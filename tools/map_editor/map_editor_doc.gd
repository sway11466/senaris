extends RefCounted
class_name MapEditorDoc
## マップエディタ（tools/map_editor/map_editor.tscn）のドキュメントモデル。
## stage.json の辞書をそのまま正本として持ち、編集操作とテキスト入出力（読込/保存）を提供する。
## 編集対象外のキー（dialogue / 未知キー）は読み込んだまま温存して書き戻す。
## 純ロジック（Godotノード非依存）＝テスト対象（tests/unit/test_map_editor_doc.gd）。
## スキーマの解釈は StageLoader（application/stage_loader.gd）に合わせる。

const DEFAULT_CHAR := "."  ## 既定地形（plain）のASCII文字

var data: Dictionary = {}
var _keys_in_source := {}  ## 読み込んだファイルに元からあったキー（空でも書き戻すための記録）
var _terrain_undo := {}    ## 直前の地形操作より前の状態（terrain / terrain_skins）。空＝戻せない


## 新規ステージ（平地のみ・駒なし）。
static func new_stage(cols: int = 12, rows: int = 8, margin: int = 0) -> MapEditorDoc:
	var doc := MapEditorDoc.new()
	doc.data = { "turn_limit": 30, "name": "", "cols": cols, "rows": rows, "margin": margin, "terrain": [], "player": [], "enemy": [], "bases": [] }
	doc._normalize_terrain()
	return doc


## JSONテキストから読み込む。不正なら null。
## JSON.parse_string はパース失敗時にエンジンエラーを出すため、静かな JSON.parse を使う。
static func from_text(text: String) -> MapEditorDoc:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var doc := MapEditorDoc.new()
	doc.data = parsed
	for key in parsed:
		doc._keys_in_source[String(key)] = true
	for key in ["player", "enemy", "bases"]:  # 編集対象の配列はキー欠落を補う
		if typeof(doc.data.get(key)) != TYPE_ARRAY:
			doc.data[key] = []
	if not doc.data.has("margin"):
		doc.data["margin"] = 0  # 既定値に頼らず必ず書き出す（保存でキーが増える＝意図した挙動）
	doc._normalize_terrain()
	return doc


func cols() -> int:
	return int(data.get("cols", 12))


func rows() -> int:
	return int(data.get("rows", 8))


## 外周（盤の外側に何マスぶん地形を描くか）。0＝外周なし。詳細 → doc/gdd/map.md
## cols()/rows() は遊べる盤のままで、terrain だけがこのぶん大きい。駒・拠点は外周に置けない。
func margin() -> int:
	return maxi(int(data.get("margin", 0)), 0)


## 外周まで含めた描画領域に col/row が入っているか（-margin .. cols+margin-1）。
func in_canvas(col: int, row: int) -> bool:
	var m := margin()
	return col >= -m and col < cols() + m and row >= -m and row < rows() + m


## 遊べる盤の中か（駒・拠点を置ける範囲）。外周は含まない。
func in_board(col: int, row: int) -> bool:
	return col >= 0 and col < cols() and row >= 0 and row < rows()


# --- 地形 ---


## terrain 配列を (rows()+2*margin)行 × (cols()+2*margin)桁 に整える
## （不足は既定地形で埋め、超過は切る）。margin ぶんずれた位置に盤が入る。
func _normalize_terrain() -> void:
	var grid: Variant = data.get("terrain", [])
	var lines: Array = grid if typeof(grid) == TYPE_ARRAY else []
	var m := margin()
	var width := cols() + m * 2
	var out := []
	for i in rows() + m * 2:
		var line := String(lines[i]) if i < lines.size() else ""
		if line.length() < width:
			line += DEFAULT_CHAR.repeat(width - line.length())
		out.append(line.substr(0, width))
	data["terrain"] = out


## セルの地形文字。col/row は盤の0起点（外周は負値・cols()以上）。範囲外は既定地形。
func terrain_char(col: int, row: int) -> String:
	var m := margin()
	var lines: Array = data.get("terrain", [])
	var i := row + m
	if i < 0 or i >= lines.size():
		return DEFAULT_CHAR
	var line := String(lines[i])
	var j := col + m
	return line[j] if j >= 0 and j < line.length() else DEFAULT_CHAR


## セルの地形文字を書き換える。外周（margin の内側）も塗れる＝盤の縁の繋がりを作者が決められる。
func set_terrain_char(col: int, row: int, ch: String) -> void:
	if not in_canvas(col, row):
		return
	var m := margin()
	var lines: Array = data["terrain"]
	var i := row + m
	var j := col + m
	var line := String(lines[i])
	lines[i] = line.substr(0, j) + ch + line.substr(j + 1)


## 外周の厚みを変える（グリッドを描き直す）。減らすと外に出た地形・skin 指定は捨てられる。
## グリッドは盤の座標で読み直してから敷き直す＝厚みが変わっても盤の中身がずれない
## （_normalize_terrain は末尾を足し引きするだけなので、これを挟まないと全体が1マスずれる）。
func set_margin(new_margin: int) -> void:
	var m := maxi(new_margin, 0)
	var old := margin()
	if m == old:
		return
	var keep := {}  # 盤の0起点の座標 → 地形の文字（旧グリッドから読む）
	for row in range(-m, rows() + m):
		for col in range(-m, cols() + m):
			keep[Vector2i(col, row)] = terrain_char(col, row)  # 旧グリッドの外は既定地形
	data["margin"] = m
	_normalize_terrain()
	for cell in keep:
		set_terrain_char(cell.x, cell.y, String(keep[cell]))
	_terrain_undo = {}  # 旧サイズのスナップショットは戻せない（グリッドとズレる）
	if typeof(data.get("terrain_skins")) == TYPE_ARRAY:
		_drop_outside_canvas(data["terrain_skins"])


# --- ベタ塗り（連結領域） ---


## クリックしたマスと地続きのマスを返す。同じ見た目＝地形の文字・skin_id・高さ上書きの全部が
## 一致するマスだけを辿る（同じ平地でも既定スキンと plain_cave1 は別領域。同じ水でも高さ違いは別領域）。
## 高さの比較はエントリのデータ同士＝行・列の基準高さは見ない（傾斜盤でも同じ塗りは1領域）。
## 隣接は六方向（Hex と同じ定義）。
## 盤と外周は跨がない＝盤で始めた塗りが外周へ漏れず、外周で始めた塗りが盤を塗り潰さない。
func connected_cells(col: int, row: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not in_canvas(col, row):
		return out
	var on_board := in_board(col, row)
	var skins := terrain_skin_map()
	var ovs := _override_keys()
	var target_char := terrain_char(col, row)
	var start := Vector2i(col, row)
	var target_skin := String(skins.get(start, ""))
	var target_ov := String(ovs.get(start, ""))
	var seen := { start: true }
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		out.append(cell)
		for dir in 6:
			var n := Hex.axial_to_offset(Hex.neighbor(Hex.offset_to_axial(cell.x, cell.y), dir))
			if not in_canvas(n.x, n.y) or in_board(n.x, n.y) != on_board:
				continue  # 描画領域の外／盤と外周の境は跨がない
			if seen.has(n):
				continue
			if terrain_char(n.x, n.y) != target_char:
				continue
			if String(skins.get(n, "")) != target_skin:
				continue
			if String(ovs.get(n, "")) != target_ov:
				continue
			seen[n] = true
			stack.append(n)
	return out


## 座標→高さ上書きの比較キー（"elevation|floor" の文字列）。連結判定用＝データそのままの比較。
## 文字列にするのは null と数値の混在を安全に比べるため（型違い Variant の == は実行時エラー）。
func _override_keys() -> Dictionary:
	var out := {}
	for e in _skin_entries():
		out[Vector2i(int(e.get("col", -1)), int(e.get("row", -1)))] = \
			"%s|%s" % [str(e.get("elevation")), str(e.get("floor"))]
	return out


## 連結領域をまとめて塗る（性能＝地形の文字、見た目＝skin_id。"" は差分なし＝type の既定）。
## ov＝マスごとの高さ上書き（{ elevation, floor }。空＝上書きなし）。塗ったマス数を返す。
func fill_terrain(col: int, row: int, ch: String, skin_id: String, ov: Dictionary = {}) -> int:
	var cells := connected_cells(col, row)
	for cell in cells:
		set_terrain_char(cell.x, cell.y, ch)
		set_terrain_skin(cell.x, cell.y, skin_id, ov)
	return cells.size()


# --- 地形の取り消し（直前の1操作だけ） ---


## 地形を書き換える直前に呼ぶ（1手だけ保持＝古いスナップショットは捨てる）。
func push_terrain_undo() -> void:
	var skins: Variant = data.get("terrain_skins")
	_terrain_undo = {
		"terrain": data["terrain"].duplicate(true),
		"terrain_skins": skins.duplicate(true) if typeof(skins) == TYPE_ARRAY else null,
	}


func can_undo_terrain() -> bool:
	return not _terrain_undo.is_empty()


## 直前の地形操作を取り消す。戻せるものが無ければ false。
func undo_terrain() -> bool:
	if _terrain_undo.is_empty():
		return false
	data["terrain"] = _terrain_undo["terrain"]
	if typeof(_terrain_undo["terrain_skins"]) == TYPE_ARRAY:
		data["terrain_skins"] = _terrain_undo["terrain_skins"]
	else:
		data.erase("terrain_skins")  # 操作前は差分自体が無かった＝キーごと消す
	_terrain_undo = {}
	return true


# --- 盤の高さ（height＝{row:[..], col:[..]}。見た目だけ＝ルールに入らない。→ doc/gdd/terrain.md 盤の高さ） ---


## 行 index の基準高さ。キーが無い・配列が短い・数値でないところは 0。
func row_height(index: int) -> float:
	return _axis_height("row", index)


## 列 index の基準高さ。
func col_height(index: int) -> float:
	return _axis_height("col", index)


func _axis_height(key: String, index: int) -> float:
	var h: Variant = data.get("height")
	if typeof(h) != TYPE_DICTIONARY:
		return 0.0
	var arr: Variant = (h as Dictionary).get(key)
	if typeof(arr) != TYPE_ARRAY or index < 0 or index >= (arr as Array).size():
		return 0.0
	var v: Variant = arr[index]
	return float(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 0.0


func set_row_height(index: int, v: float) -> void:
	_set_axis_height("row", index, rows(), v)


func set_col_height(index: int, v: float) -> void:
	_set_axis_height("col", index, cols(), v)


## 書くときに配列を盤の長さに整える（StageLoader は長さ違いを弾く＝正しい長さでしか書かない）。
func _set_axis_height(key: String, index: int, want: int, v: float) -> void:
	if index < 0 or index >= want:
		return
	if typeof(data.get("height")) != TYPE_DICTIONARY:
		data["height"] = {}  # 書くときだけキーを作る（読むだけで生やさない）
	var h: Dictionary = data["height"]
	var arr: Array = h[key] if typeof(h.get(key)) == TYPE_ARRAY else []
	while arr.size() < want:
		arr.append(0.0)
	arr.resize(want)
	arr[index] = v
	h[key] = arr


## height を保存できる形に整える。配列は盤の行数・列数に合わせ（伸びた分0・はみ出しは切る）、
## 全部0なら省略と同義（doc/gdd/terrain.md）なのでキーごと消す。
## ただし元ファイルにあったキーは温存＝開いて保存しただけでは内容を変えない。
func _normalize_height() -> void:
	var h: Variant = data.get("height")
	if typeof(h) != TYPE_DICTIONARY:
		return
	var flat := true
	for pair: Array in [["row", rows()], ["col", cols()]]:
		var key := String(pair[0])
		var arr: Variant = (h as Dictionary).get(key)
		if typeof(arr) != TYPE_ARRAY:
			continue
		var out: Array = []
		for i in int(pair[1]):
			var v: Variant = (arr as Array)[i] if i < (arr as Array).size() else 0.0
			var f := float(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 0.0
			if f != 0.0:
				flat = false
			out.append(f)
		h[key] = out
	if flat and not _keys_in_source.has("height"):
		data.erase("height")


## 高さの1軸を delta ぶん送る（shift 用）。押し出された端は捨て、空いた端は 0。
static func _shift_height_axis(h: Dictionary, key: String, delta: int, want: int) -> void:
	var arr: Variant = h.get(key)
	if typeof(arr) != TYPE_ARRAY:
		return
	var out: Array = []
	out.resize(want)
	out.fill(0.0)
	for i in mini((arr as Array).size(), want):
		var ni := i + delta
		if ni >= 0 and ni < want:
			out[ni] = arr[i]
	h[key] = out


## 1軸で、送ると盤の外へ出る 0 以外の値の数（shift_losses 用）。
static func _height_axis_losses(h: Variant, key: String, delta: int, want: int) -> int:
	if typeof(h) != TYPE_DICTIONARY:
		return 0
	var arr: Variant = (h as Dictionary).get(key)
	if typeof(arr) != TYPE_ARRAY:
		return 0
	var lost := 0
	for i in mini((arr as Array).size(), want):
		var v: Variant = arr[i]
		var f := float(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 0.0
		if f != 0.0 and (i + delta < 0 or i + delta >= want):
			lost += 1
	return lost


# --- 見た目レイヤー（terrain_skins＝座標→skin_id の差分列挙。未指定セルは type の既定スキン） ---


## セルの skin_id。指定が無ければ ""（＝type の既定スキン）。
func terrain_skin(col: int, row: int) -> String:
	for e in _skin_entries():
		if int(e.get("col", -1)) == col and int(e.get("row", -1)) == row:
			return String(e.get("skin", ""))
	return ""


## 座標→skin_id の辞書（盤の描画用。1回の描画で引き直さないためのまとめ取り）。
func terrain_skin_map() -> Dictionary:
	var out := {}
	for e in _skin_entries():
		out[Vector2i(int(e.get("col", -1)), int(e.get("row", -1)))] = String(e.get("skin", ""))
	return out


## 座標→高さ上書きの elevation（float）。ペアが揃っているマスだけ載る。盤の表示用。
func elevation_override_map() -> Dictionary:
	var out := {}
	for e in _skin_entries():
		var ev: Variant = e.get("elevation")
		var fl: Variant = e.get("floor")
		if typeof(ev) in [TYPE_INT, TYPE_FLOAT] and typeof(fl) in [TYPE_INT, TYPE_FLOAT]:
			out[Vector2i(int(e.get("col", -1)), int(e.get("row", -1)))] = float(ev)
	return out


## セルの skin_id を設定する。"" は指定の削除＝type の既定スキンに戻す。
## 外周のセル（負の col/row・cols()以上）にも書ける＝盤外の座標がそのまま載る。
## ov＝マスごとの高さ上書き（{ elevation, floor }。空＝上書きなし＝キーを消す）。上書きはスキンの
## エントリにしか持てない＝塗り直しでエントリが消えれば上書きも消える（見えない上書きを残さない）。
func set_terrain_skin(col: int, row: int, skin_id: String, ov: Dictionary = {}) -> void:
	if not in_canvas(col, row):
		return
	if typeof(data.get("terrain_skins")) != TYPE_ARRAY:
		if skin_id == "":
			return
		data["terrain_skins"] = []  # 追加するときだけキーを作る（読むだけで生やさない）
	var list: Array = data["terrain_skins"]  # 実体を直接いじる（_skin_entries は複製＝削除が効かない）
	for i in list.size():
		var e: Variant = list[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if int(e.get("col", -1)) == col and int(e.get("row", -1)) == row:
			if skin_id == "":
				list.remove_at(i)
			else:
				e["skin"] = skin_id
				_apply_override(e, ov)
			return
	if skin_id != "":
		var entry := { "col": col, "row": row, "skin": skin_id }
		_apply_override(entry, ov)
		list.append(entry)


## エントリへ高さ上書きを書く/消す。ペア（elevation・floor）でだけ書く＝片方だけの状態を作らない。
static func _apply_override(e: Dictionary, ov: Dictionary) -> void:
	if ov.has("elevation") and ov.has("floor"):
		e["elevation"] = float(ov["elevation"])
		e["floor"] = float(ov["floor"])
	else:
		e.erase("elevation")
		e.erase("floor")


## セルの高さ上書き（{ elevation, floor }）。無ければ空辞書（ペアが揃っていないものも無い扱い）。
func height_override(col: int, row: int) -> Dictionary:
	for e in _skin_entries():
		if int(e.get("col", -1)) == col and int(e.get("row", -1)) == row:
			var ev: Variant = e.get("elevation")
			var fl: Variant = e.get("floor")
			if typeof(ev) in [TYPE_INT, TYPE_FLOAT] and typeof(fl) in [TYPE_INT, TYPE_FLOAT]:
				return { "elevation": float(ev), "floor": float(fl) }
			return {}
	return {}


## terrain_skins の要素（辞書のみ）。キーが無い/不正なら空配列。
func _skin_entries() -> Array:
	var v: Variant = data.get("terrain_skins", [])
	if typeof(v) != TYPE_ARRAY:
		return []
	var out := []
	for e in v:
		if typeof(e) == TYPE_DICTIONARY:
			out.append(e)
	return out


## 盤サイズ変更。範囲外になった駒・拠点・skin 指定は削除し、その数を返す。
## 高さの配列は盤の長さに合わせ直す（伸びた分0・はみ出しは切る＝地形の行と同じ黙った扱い）。
func resize(new_cols: int, new_rows: int) -> int:
	data["cols"] = new_cols
	data["rows"] = new_rows
	_normalize_terrain()
	_normalize_height()
	_terrain_undo = {}  # 旧サイズのスナップショットは戻せない（盤とズレる）
	var dropped := 0
	dropped += _drop_out_of_range(data["player"])
	for sq in data["enemy"]:
		dropped += _drop_out_of_range(sq.get("units", []))
	dropped += _drop_out_of_range(data["bases"])
	if typeof(data.get("terrain_skins")) == TYPE_ARRAY:
		dropped += _drop_outside_canvas(data["terrain_skins"])  # skin は外周にも書ける
	return dropped


## 盤の外に出た要素（駒・拠点）を落とす。外周には置けないので基準は盤そのもの。
func _drop_out_of_range(list: Array) -> int:
	var dropped := 0
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		if int(e.get("col", 0)) >= cols() or int(e.get("row", 0)) >= rows():
			list.remove_at(i)
			dropped += 1
	return dropped


## 描画領域（盤＋外周）の外に出た要素を落とす。skin 指定は外周にも載るのでこちらを使う。
func _drop_outside_canvas(list: Array) -> int:
	var dropped := 0
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		if not in_canvas(int(e.get("col", 0)), int(e.get("row", 0))):
			list.remove_at(i)
			dropped += 1
	return dropped


# --- 全体の平行移動（盤の中身をまとめてずらす） ---


## その列送りが平行移動になるか（偶数のみ）。盤は odd-q＝奇数列だけ半マス下げて敷くので、
## 奇数列ぶん送ると列の偶奇が入れ替わり、隣接の噛み合わせが変わる＝描いた形が崩れる。
## 例: 離れている (0,0) と (1,1) は、1列送ると (1,0) と (2,1) ＝隣同士になる。2列なら形は保たれる。
static func is_shiftable_dcol(dcol: int) -> bool:
	return dcol % 2 == 0


## 平行移動で描画領域・盤の外へ出てしまう中身の数（キー: terrain / skins / units / bases）。
## 空の辞書＝そのまま動かせる。地形は既定地形でないマスだけ数える（空白が外へ出るのは失っていない）。
func shift_losses(dcol: int, drow: int) -> Dictionary:
	var out := {}
	var m := margin()
	var terrain_lost := 0
	for row in range(-m, rows() + m):
		for col in range(-m, cols() + m):
			if terrain_char(col, row) == DEFAULT_CHAR:
				continue
			if not in_canvas(col + dcol, row + drow):
				terrain_lost += 1
	if terrain_lost > 0:
		out["terrain"] = terrain_lost
	var skins_lost := 0
	for e in _skin_entries():
		if not in_canvas(int(e.get("col", 0)) + dcol, int(e.get("row", 0)) + drow):
			skins_lost += 1
	if skins_lost > 0:
		out["skins"] = skins_lost
	var units_lost := 0
	for u in placed_units():
		if not in_board(int(u.get("col", 0)) + dcol, int(u.get("row", 0)) + drow):
			units_lost += 1
	if units_lost > 0:
		out["units"] = units_lost
	var bases_lost := 0
	for b in data.get("bases", []):
		if typeof(b) != TYPE_DICTIONARY:
			continue
		if not in_board(int(b.get("col", 0)) + dcol, int(b.get("row", 0)) + drow):
			bases_lost += 1
	if bases_lost > 0:
		out["bases"] = bases_lost
	# 高さは行・列に付く値＝中身と一緒に送る。0以外が端からこぼれるなら失うものに数える。
	var height_lost := _height_axis_losses(data.get("height"), "row", drow, rows()) \
		+ _height_axis_losses(data.get("height"), "col", dcol, cols())
	if height_lost > 0:
		out["height"] = height_lost
	return out


## 盤の中身（地形・見た目スキン・駒・拠点・防衛対象）をまとめてずらす。動かせたら true。
## dcol は偶数のみ（is_shiftable_dcol）。何かが外へ出るなら1つも動かさない
## ＝逆向きに押せば必ず元へ戻せる（この操作は Ctrl+Z の対象外）。
func shift(dcol: int, drow: int) -> bool:
	if not is_shiftable_dcol(dcol) or (dcol == 0 and drow == 0):
		return false
	if not shift_losses(dcol, drow).is_empty():
		return false
	var m := margin()
	var keep := {}  # 盤の0起点の座標 → 地形の文字（敷き直す前に読み切る）
	for row in range(-m, rows() + m):
		for col in range(-m, cols() + m):
			keep[Vector2i(col, row)] = terrain_char(col, row)
	var blank := []
	for _i in rows() + m * 2:
		blank.append(DEFAULT_CHAR.repeat(cols() + m * 2))
	data["terrain"] = blank
	for cell in keep:
		set_terrain_char(cell.x + dcol, cell.y + drow, String(keep[cell]))
	for e in _skin_entries():
		e["col"] = int(e.get("col", 0)) + dcol
		e["row"] = int(e.get("row", 0)) + drow
	for u in placed_units():
		u["col"] = int(u.get("col", 0)) + dcol
		u["row"] = int(u.get("row", 0)) + drow
	for b in data.get("bases", []):
		if typeof(b) == TYPE_DICTIONARY:
			b["col"] = int(b.get("col", 0)) + dcol
			b["row"] = int(b.get("row", 0)) + drow
	for c in defeat_list():  # 拠点を名指しする防衛対象も連れて動く＝指す先が消えたことにしない
		for t in lose_base_targets(c):
			if typeof(t) == TYPE_DICTIONARY:
				t["col"] = int(t.get("col", 0)) + dcol
				t["row"] = int(t.get("row", 0)) + drow
	if typeof(data.get("height")) == TYPE_DICTIONARY:  # 高さも中身と一緒に送る（置き去りにしない）
		_shift_height_axis(data["height"], "row", drow, rows())
		_shift_height_axis(data["height"], "col", dcol, cols())
	_terrain_undo = {}  # 駒ごと動いた後に地形だけ戻すと辻褄が合わない
	return true


## 盤に座標を持つ駒すべて（自軍・敵部隊・増援イベント）。実体を返す＝書き換えがそのまま効く。
## 拠点の控え(garrison)と搭載駒(passengers)は座標を持たない（出撃時に決まる）ので含めない。
func placed_units() -> Array:
	var out := []
	for u in data.get("player", []):
		if typeof(u) == TYPE_DICTIONARY:
			out.append(u)
	for sq in data.get("enemy", []):
		if typeof(sq) != TYPE_DICTIONARY:
			continue
		for u in (sq as Dictionary).get("units", []):
			if typeof(u) == TYPE_DICTIONARY:
				out.append(u)
	for ev in event_list():
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		for u in (ev as Dictionary).get("units", []):
			if typeof(u) == TYPE_DICTIONARY:
				out.append(u)
	return out


# --- ユニット・拠点 ---


## セルの駒を返す。無ければ空辞書。
## あれば { "squad": 部隊index（自軍は -1）, "index": 配列内index, "unit": 駒辞書 }。
func unit_at(col: int, row: int) -> Dictionary:
	var units: Array = data["player"]
	for i in units.size():
		if int(units[i].get("col", 0)) == col and int(units[i].get("row", 0)) == row:
			return { "squad": -1, "index": i, "unit": units[i] }
	var squads: Array = data["enemy"]
	for s in squads.size():
		var su: Array = squads[s].get("units", [])
		for i in su.size():
			if int(su[i].get("col", 0)) == col and int(su[i].get("row", 0)) == row:
				return { "squad": s, "index": i, "unit": su[i] }
	return {}


## セルの拠点を返す。無ければ空辞書。あれば { "index": 配列内index, "base": 拠点辞書 }。
func base_at(col: int, row: int) -> Dictionary:
	var bases: Array = data["bases"]
	for i in bases.size():
		if int(bases[i].get("col", 0)) == col and int(bases[i].get("row", 0)) == row:
			return { "index": i, "base": bases[i] }
	return {}


## 拠点の控え（garrison）に眠っている駒の総数。1行＝skin×count で、count 省略は1体。
## 盤のラベルもパネルの表示もこれを通す＝数え方が2箇所で食い違わない。
static func garrison_count(base: Variant) -> int:
	if typeof(base) != TYPE_DICTIONARY:
		return 0
	var g: Variant = (base as Dictionary).get("garrison", [])
	if typeof(g) != TYPE_ARRAY:
		return 0
	var n := 0
	for e in g as Array:
		if typeof(e) == TYPE_DICTIONARY:
			n += maxi(int((e as Dictionary).get("count", 1)), 1)
	return n


## 自軍の駒を置く（既に駒があれば false）。
func add_player(type_id: String, col: int, row: int) -> bool:
	if not unit_at(col, row).is_empty():
		return false
	data["player"].append({ "type": type_id, "col": col, "row": row })
	return true


## 敵の駒を部隊 squad_idx に置く（既に駒があれば false）。
func add_enemy(squad_idx: int, skin_id: String, col: int, row: int) -> bool:
	if not unit_at(col, row).is_empty():
		return false
	if squad_idx < 0 or squad_idx >= data["enemy"].size():
		return false
	var sq: Dictionary = data["enemy"][squad_idx]
	if typeof(sq.get("units")) != TYPE_ARRAY:
		sq["units"] = []
	sq["units"].append({ "skin": skin_id, "col": col, "row": row })
	return true


## 敵部隊を追加して index を返す。行動順 order は既存の最大＋1（doc/gdd/ai.md 行動順）。
func add_squad(ai: String, name: String = "") -> int:
	var sq := {}
	sq["order"] = max_order() + 1
	if name != "":
		sq["name"] = name
	sq["ai"] = ai
	sq["units"] = []
	data["enemy"].append(sq)
	return data["enemy"].size() - 1


## ステージで使われている行動順 order の最大値（部隊＋AI出撃する拠点。無ければ 0）。
func max_order() -> int:
	var best := 0
	for sq in data["enemy"]:
		best = maxi(best, _order_value(sq))
	for b in data.get("bases", []):
		if typeof(b) == TYPE_DICTIONARY and (b as Dictionary).has("ai"):
			best = maxi(best, _order_value(b))
	return best


func _order_value(holder: Variant) -> int:
	if typeof(holder) != TYPE_DICTIONARY:
		return 0
	var v: Variant = (holder as Dictionary).get("order")
	return int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 0


## 敵部隊を削除（所属ユニットごと）。
func remove_squad(squad_idx: int) -> void:
	if squad_idx >= 0 and squad_idx < data["enemy"].size():
		data["enemy"].remove_at(squad_idx)


## 拠点を置く（既に拠点があれば false）。ai は空文字＝AI出撃なし（キー自体を書かない）。
func add_base(col: int, row: int, team: String, kind: String, ai: String = "") -> bool:
	if not base_at(col, row).is_empty():
		return false
	var b := { "col": col, "row": row, "team": team, "kind": kind }
	if ai != "":
		b["ai"] = ai
	b["garrison"] = []
	data["bases"].append(b)
	return true


## 拠点を別のマスへ動かす。外周・盤外や、既に拠点があるマスへは動かせない。
## 名指ししていた敗北条件(lose_base)の座標も連れて動く＝指す先が消えたことにしない。
func move_base_at(from_col: int, from_row: int, to_col: int, to_row: int) -> bool:
	if not in_board(to_col, to_row):
		return false
	var hit := base_at(from_col, from_row)
	if hit.is_empty() or not base_at(to_col, to_row).is_empty():
		return false
	hit["base"]["col"] = to_col
	hit["base"]["row"] = to_row
	for c in defeat_list():
		for t in lose_base_targets(c):
			if _is_target_at(t, from_col, from_row):
				t["col"] = to_col
				t["row"] = to_row
	return true


## 駒を別のマスへ動かす（拠点は動かさない）。外周・盤外や、既に駒がいるマスへは動かせない。
func move_unit_at(from_col: int, from_row: int, to_col: int, to_row: int) -> bool:
	if not in_board(to_col, to_row):
		return false
	var hit := unit_at(from_col, from_row)
	if hit.is_empty() or not unit_at(to_col, to_row).is_empty():
		return false
	hit["unit"]["col"] = to_col
	hit["unit"]["row"] = to_row
	return true


## 敵の駒を別の部隊へ移す（位置はそのまま）。移したら true。
func move_unit_to_squad(from_squad: int, index: int, to_squad: int) -> bool:
	var squads: Array = data["enemy"]
	if from_squad == to_squad:
		return false
	if from_squad < 0 or from_squad >= squads.size() or to_squad < 0 or to_squad >= squads.size():
		return false
	var units: Array = squads[from_squad].get("units", [])
	if index < 0 or index >= units.size():
		return false
	var unit: Variant = units[index]
	units.remove_at(index)
	if typeof(squads[to_squad].get("units")) != TYPE_ARRAY:
		squads[to_squad]["units"] = []
	squads[to_squad]["units"].append(unit)
	return true


func remove_unit_at(col: int, row: int) -> bool:
	var hit := unit_at(col, row)
	if hit.is_empty():
		return false
	if int(hit["squad"]) < 0:
		data["player"].remove_at(hit["index"])
	else:
		data["enemy"][hit["squad"]]["units"].remove_at(hit["index"])
	return true


func remove_base_at(col: int, row: int) -> bool:
	var hit := base_at(col, row)
	if hit.is_empty():
		return false
	data["bases"].remove_at(hit["index"])
	_drop_lose_base(col, row)  # 消えた拠点を指す敗北条件を残さない
	return true


## 指定マスを指す防衛対象を取り除く（拠点の削除に追随）。対象が空になった条件ごと消す。
func _drop_lose_base(col: int, row: int) -> void:
	var d := defeat_list()
	for i in range(d.size() - 1, -1, -1):
		if not is_lose_base(d[i]):
			continue
		var targets := lose_base_targets(d[i])
		for j in range(targets.size() - 1, -1, -1):
			if _is_target_at(targets[j], col, row):
				targets.remove_at(j)
		if targets.is_empty():
			d.remove_at(i)
	if d.is_empty() and data.has("defeat"):
		data.erase("defeat")


static func is_lose_base(c: Variant) -> bool:
	return typeof(c) == TYPE_DICTIONARY and String(c.get("type", "")) == "lose_base"


static func is_lose_unit(c: Variant) -> bool:
	return typeof(c) == TYPE_DICTIONARY and String(c.get("type", "")) == "lose_unit"


## lose_unit 条件が持つ名指しの配列。実体を返す＝呼び出し側の追加・削除がそのまま効く。
static func lose_unit_actors(c: Variant) -> Array:
	if not is_lose_unit(c):
		return []
	var a: Variant = c.get("actors", [])
	return a if typeof(a) == TYPE_ARRAY else []


## lose_base 条件が持つ対象の配列。実体を返す＝呼び出し側の追加・削除がそのまま効く。
static func lose_base_targets(c: Variant) -> Array:
	if not is_lose_base(c):
		return []
	var b: Variant = c.get("bases", [])
	return b if typeof(b) == TYPE_ARRAY else []


static func _is_target_at(t: Variant, col: int, row: int) -> bool:
	return typeof(t) == TYPE_DICTIONARY and int(t.get("col", -1)) == col and int(t.get("row", -1)) == row


# --- 名指し(actor)・勝利条件 ---


## ステージで使われている actor の集合（盤の駒・部隊の駒・拠点の控え）。重複しない名前を作るのに使う。
func used_actors() -> Dictionary:
	var out := {}
	for u in data["player"]:
		_collect_actor(out, u)
	for sq in data["enemy"]:
		for u in sq.get("units", []):
			_collect_actor(out, u)
	for b in data.get("bases", []):
		if typeof(b) != TYPE_DICTIONARY:
			continue
		for g in b.get("garrison", []):
			_collect_actor(out, g)
	return out


func _collect_actor(out: Dictionary, unit: Variant) -> void:
	if typeof(unit) != TYPE_DICTIONARY:
		return
	var a := String((unit as Dictionary).get("actor", ""))
	if a != "":
		out[a] = true
	for p in (unit as Dictionary).get("passengers", []):
		_collect_actor(out, p)


## base を土台に、ステージ内で重複しない actor 名を作る（"necromancer" → "necromancer2" …）。
func free_actor(base: String) -> String:
	var stem := base if base != "" else "actor"
	var used := used_actors()
	if not used.has(stem):
		return stem
	var n := 2
	while used.has("%s%d" % [stem, n]):
		n += 1
	return "%s%d" % [stem, n]


## 駒の名指し(actor)を書き換える。空文字なら名前を外す。
## 駒を指す手段は actor 一本＝数値 id はデータに書かない（doc/gdd/map.md 名前つきの駒）。
## 元の名前を指していた勝敗条件は一緒に付け替える（拠点を動かすと lose_base が追随するのと同じ）。
## 指す先が無くなった条件は消す＝「対象なし＝成立しない」条件を黙って残さない。
func set_actor(unit: Dictionary, name: String) -> void:
	var old := String(unit.get("actor", ""))
	if old == name:
		return
	if name == "":
		unit.erase("actor")
		unit.erase("supply")  # 名簿との突き合わせは名前つきの駒だけの話（doc/gdd/map.md 配置）
	else:
		unit["actor"] = name
	if old != "":
		_rename_actor_refs(old, name)


## 勝敗条件の中の actor 名を付け替える（new が空なら、その名指しを取り除く）。
func _rename_actor_refs(old: String, new: String) -> void:
	var v := victory_list()
	for i in range(v.size() - 1, -1, -1):
		if String(v[i].get("type", "")) != "defeat_unit" or String(v[i].get("actor", "")) != old:
			continue
		if new == "":
			v.remove_at(i)
		else:
			v[i]["actor"] = new
	if v.is_empty() and data.has("victory"):
		data.erase("victory")
	var d := defeat_list()
	for i in range(d.size() - 1, -1, -1):
		if String(d[i].get("type", "")) != "lose_unit":
			continue
		var actors: Variant = d[i].get("actors", [])
		if typeof(actors) != TYPE_ARRAY:
			continue
		for j in range((actors as Array).size() - 1, -1, -1):
			if String(actors[j]) != old:
				continue
			if new == "":
				(actors as Array).remove_at(j)
			else:
				actors[j] = new
		if (actors as Array).is_empty():
			d.remove_at(i)
	if d.is_empty() and data.has("defeat"):
		data.erase("defeat")


## BGM の指定（bgm: { main }）。無ければ空の辞書。値はトラックID。詳細 → doc/audio/bgm.md
func bgm() -> Dictionary:
	var v: Variant = data.get("bgm", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


## BGM スロットを決める。空文字＝そのスロットを外す（冒険譚の既定→全体既定へフォールバックさせる）。
## スロットが全部空になったら bgm キーごと消す＝空の欄を書き出さない。
func set_bgm(slot: String, track_id: String) -> void:
	var b := bgm()
	if track_id == "":
		b.erase(slot)
	else:
		b[slot] = track_id
	if b.is_empty():
		data.erase("bgm")
	else:
		data["bgm"] = b


func victory_list() -> Array:
	var v: Variant = data.get("victory", [])
	return v if typeof(v) == TYPE_ARRAY else []


## 勝利条件を1件足す（キーが無ければ作る）。中身の妥当性は呼び出し側が見る。
func add_victory(cond: Dictionary) -> void:
	if typeof(data.get("victory")) != TYPE_ARRAY:
		data["victory"] = []
	data["victory"].append(cond)


func remove_victory(index: int) -> void:
	var v := victory_list()
	if index >= 0 and index < v.size():
		v.remove_at(index)
	if v.is_empty() and data.has("victory"):
		data.erase("victory")  # 空の victory キーは書き出さない


# --- イベント（時限発生＝増援）。盤に描くものではないのでリストとして持つ。詳細 → doc/gdd/map.md イベント ---

func event_list() -> Array:
	var e: Variant = data.get("events", [])
	return e if typeof(e) == TYPE_ARRAY else []


## 増援を1件足す（キーが無ければ作る）。駒は空で始め、パネル側で足す。
func add_event(turn: int, team: String) -> void:
	if typeof(data.get("events")) != TYPE_ARRAY:
		data["events"] = []
	data["events"].append({ "turn": maxi(turn, 1), "type": "reinforce", "team": team, "units": [] })


func remove_event(index: int) -> void:
	var e := event_list()
	if index >= 0 and index < e.size():
		e.remove_at(index)
	if e.is_empty() and data.has("events"):
		data.erase("events")  # 空の events キーは書き出さない


## index のイベントの駒リスト（無ければ作って返す＝そのまま編集できる）。範囲外は空。
func event_units(index: int) -> Array:
	var e := event_list()
	if index < 0 or index >= e.size():
		return []
	var ev: Dictionary = e[index]
	if typeof(ev.get("units")) != TYPE_ARRAY:
		ev["units"] = []
	return ev["units"]


func defeat_list() -> Array:
	var d: Variant = data.get("defeat", [])
	return d if typeof(d) == TYPE_ARRAY else []


## 拠点(col,row)を防衛対象にする＝奪われたら敗北。既に指定済みなら何もしない。
## 拠点の無いマスは受け付けない（作者の指定ミスを保存前に弾く）。
## group=false: 単独の条件として足す＝他の条件とOR（どれか1つ失えば敗北）。
## group=true: 直近の lose_base 条件に相乗り＝同じ条件内はAND（すべて失って初めて敗北）。
func add_defeat_lose_base(col: int, row: int, group: bool = false) -> bool:
	if base_at(col, row).is_empty():
		return false
	if has_defeat_lose_base(col, row):
		return true  # 既に指定済み
	if typeof(data.get("defeat")) != TYPE_ARRAY:
		data["defeat"] = []
	var target := { "col": col, "row": row }
	var d: Array = data["defeat"]
	if group:
		for i in range(d.size() - 1, -1, -1):
			if not is_lose_base(d[i]):
				continue
			if typeof(d[i].get("bases")) != TYPE_ARRAY:
				d[i]["bases"] = []
			d[i]["bases"].append(target)
			return true
	d.append({ "type": "lose_base", "bases": [target] })
	return true


## そのマスが既にどこかの lose_base 条件の対象になっているか。
func has_defeat_lose_base(col: int, row: int) -> bool:
	for c in defeat_list():
		for t in lose_base_targets(c):
			if _is_target_at(t, col, row):
				return true
	return false


## 敗北条件を1件足す（キーが無ければ作る）。中身の妥当性は呼び出し側が見る。
func add_defeat(cond: Dictionary) -> void:
	if typeof(data.get("defeat")) != TYPE_ARRAY:
		data["defeat"] = []
	data["defeat"].append(cond)


func remove_defeat(index: int) -> void:
	var d := defeat_list()
	if index >= 0 and index < d.size():
		d.remove_at(index)
	if d.is_empty() and data.has("defeat"):
		data.erase("defeat")  # 空の defeat キーは書き出さない


# --- 保存（テキスト化） ---


func to_text() -> String:
	_normalize_terrain()
	_normalize_height()
	return MapEditorDocSerializer.serialize(data, _keys_in_source)
