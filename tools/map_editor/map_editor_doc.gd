extends RefCounted
class_name MapEditorDoc
## マップエディタ（tools/map_editor/map_editor.tscn）のドキュメントモデル。
## stage.json の辞書をそのまま正本として持ち、編集操作とテキスト入出力（読込/保存）を提供する。
## 編集対象外のキー（dialogue / 未知キー）は読み込んだまま温存して書き戻す。
## 純ロジック（Godotノード非依存）＝テスト対象（tests/unit/test_map_editor_doc.gd）。
## スキーマの解釈は StageLoader（application/stage_loader.gd）に合わせる。

const DEFAULT_CHAR := "."  ## 既定地形（plain）のASCII文字

## 保存時のトップレベルキーの並び（既存ステージの手書き順に合わせる）。残りは元の順で末尾。
const KEY_ORDER := ["turn_limit", "name", "cols", "rows", "margin", "terrain", "terrain_skins", "player", "enemy", "bases", "victory", "defeat", "ai", "dialogue"]

## 辞書の中で「配列を段落表示する」キー（squad の units / 拠点の garrison / 輸送の passengers）。
const BLOCK_ARRAY_KEYS := ["units", "garrison", "passengers"]

## 辞書内キーの並び（既存ステージの手書き順に寄せる）。残りは元の順、BLOCK_ARRAY_KEYS は常に末尾。
const ENTITY_KEY_ORDER := ["id", "name", "ai", "speaker", "type", "skin", "text", "col", "row", "team", "kind", "count", "native", "unit_id"]

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


## クリックしたマスと地続きのマスを返す。同じ見た目＝地形の文字と skin_id の両方が一致するマス
## だけを辿る（同じ平地でも既定スキンと plain_cave1 は別領域）。隣接は六方向（Hex と同じ定義）。
## 盤と外周は跨がない＝盤で始めた塗りが外周へ漏れず、外周で始めた塗りが盤を塗り潰さない。
func connected_cells(col: int, row: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not in_canvas(col, row):
		return out
	var on_board := in_board(col, row)
	var skins := terrain_skin_map()
	var target_char := terrain_char(col, row)
	var target_skin := String(skins.get(Vector2i(col, row), ""))
	var start := Vector2i(col, row)
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
			seen[n] = true
			stack.append(n)
	return out


## 連結領域をまとめて塗る（性能＝地形の文字、見た目＝skin_id。"" は差分なし＝type の既定）。
## 塗ったマス数を返す。
func fill_terrain(col: int, row: int, ch: String, skin_id: String) -> int:
	var cells := connected_cells(col, row)
	for cell in cells:
		set_terrain_char(cell.x, cell.y, ch)
		set_terrain_skin(cell.x, cell.y, skin_id)
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


## セルの skin_id を設定する。"" は指定の削除＝type の既定スキンに戻す。
## 外周のセル（負の col/row・cols()以上）にも書ける＝盤外の座標がそのまま載る。
func set_terrain_skin(col: int, row: int, skin_id: String) -> void:
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
			return
	if skin_id != "":
		list.append({ "col": col, "row": row, "skin": skin_id })


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
func resize(new_cols: int, new_rows: int) -> int:
	data["cols"] = new_cols
	data["rows"] = new_rows
	_normalize_terrain()
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


## 敵部隊を追加して index を返す。
func add_squad(ai: String, name: String = "") -> int:
	var sq := {}
	if name != "":
		sq["name"] = name
	sq["ai"] = ai
	sq["units"] = []
	data["enemy"].append(sq)
	return data["enemy"].size() - 1


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


## 駒（優先）または拠点を移動。移動先に同種が居れば false。
func move(from_col: int, from_row: int, to_col: int, to_row: int) -> bool:
	if to_col < 0 or to_col >= cols() or to_row < 0 or to_row >= rows():
		return false
	var hit := unit_at(from_col, from_row)
	if not hit.is_empty():
		if not unit_at(to_col, to_row).is_empty():
			return false
		hit["unit"]["col"] = to_col
		hit["unit"]["row"] = to_row
		return true
	var bh := base_at(from_col, from_row)
	if not bh.is_empty():
		if not base_at(to_col, to_row).is_empty():
			return false
		bh["base"]["col"] = to_col
		bh["base"]["row"] = to_row
		_move_lose_base(from_col, from_row, to_col, to_row)  # 敗北条件の座標も連れて動く
		return true
	return false


## 防衛対象の指定を外す（拠点自体は残す）。
func remove_defeat_lose_base(col: int, row: int) -> void:
	_drop_lose_base(col, row)


## 指定マスを指す lose_base 条件を取り除く（拠点の削除に追随）。
func _drop_lose_base(col: int, row: int) -> void:
	var d := defeat_list()
	for i in range(d.size() - 1, -1, -1):
		if _is_lose_base_at(d[i], col, row):
			d.remove_at(i)
	if d.is_empty() and data.has("defeat"):
		data.erase("defeat")


## 指定マスを指す lose_base 条件の座標を付け替える（拠点の移動に追随）。
func _move_lose_base(from_col: int, from_row: int, to_col: int, to_row: int) -> void:
	for c in defeat_list():
		if _is_lose_base_at(c, from_col, from_row):
			c["col"] = to_col
			c["row"] = to_row


static func _is_lose_base_at(c: Variant, col: int, row: int) -> bool:
	return typeof(c) == TYPE_DICTIONARY and String(c.get("type", "")) == "lose_base" \
		and int(c.get("col", -1)) == col and int(c.get("row", -1)) == row


# --- id・勝利条件 ---


## StageLoader と同じ規則で駒の id を求める（表示用）。
## 採番は player 順 → 各部隊の units 順。明示 "id" があってもカウンタは進む。passengers もカウンタを消費。
## 返り値: { "p:<i>": id, "e:<s>:<i>": id }
func computed_ids() -> Dictionary:
	var out := {}
	var counter := 1
	var units: Array = data["player"]
	for i in units.size():
		out["p:%d" % i] = int(units[i].get("id", counter))
		counter += 1
		counter += _passenger_count(units[i])
	var squads: Array = data["enemy"]
	for s in squads.size():
		var su: Array = squads[s].get("units", [])
		for i in su.size():
			out["e:%d:%d" % [s, i]] = int(su[i].get("id", counter))
			counter += 1
			counter += _passenger_count(su[i])
	return out


func _passenger_count(unit: Dictionary) -> int:
	var p: Variant = unit.get("passengers", [])
	return p.size() if typeof(p) == TYPE_ARRAY else 0


## 駒をボス指定＝明示 id を振り、勝利条件 defeat_unit を追加。振った id を返す。
## id は 99 から下りで空きを使う（既存ステージの慣習）。既に明示 id 持ちならそれを使う。
func set_boss(squad_idx: int, unit_idx: int) -> int:
	var unit: Dictionary = data["enemy"][squad_idx]["units"][unit_idx]
	var id: int
	if unit.has("id"):
		id = int(unit["id"])
	else:
		var used := {}
		for v in computed_ids().values():
			used[int(v)] = true
		id = 99
		while used.has(id):
			id -= 1
		unit["id"] = id
	if typeof(data.get("victory")) != TYPE_ARRAY:
		data["victory"] = []
	for c in data["victory"]:
		if String(c.get("type", "")) == "defeat_unit" and int(c.get("unit_id", -1)) == id:
			return id  # 既に条件あり
	data["victory"].append({ "type": "defeat_unit", "unit_id": id })
	return id


func victory_list() -> Array:
	var v: Variant = data.get("victory", [])
	return v if typeof(v) == TYPE_ARRAY else []


func remove_victory(index: int) -> void:
	var v := victory_list()
	if index >= 0 and index < v.size():
		v.remove_at(index)
	if v.is_empty() and data.has("victory"):
		data.erase("victory")  # 空の victory キーは書き出さない


func defeat_list() -> Array:
	var d: Variant = data.get("defeat", [])
	return d if typeof(d) == TYPE_ARRAY else []


## 拠点(col,row)を防衛対象にする＝奪われたら敗北。既に指定済みなら何もしない。
## 拠点の無いマスは受け付けない（作者の指定ミスを保存前に弾く）。
func add_defeat_lose_base(col: int, row: int) -> bool:
	if base_at(col, row).is_empty():
		return false
	if typeof(data.get("defeat")) != TYPE_ARRAY:
		data["defeat"] = []
	for c in data["defeat"]:
		if String(c.get("type", "")) == "lose_base" \
				and int(c.get("col", -1)) == col and int(c.get("row", -1)) == row:
			return true  # 既に条件あり
	data["defeat"].append({ "type": "lose_base", "col": col, "row": row })
	return true


func remove_defeat(index: int) -> void:
	var d := defeat_list()
	if index >= 0 and index < d.size():
		d.remove_at(index)
	if d.is_empty() and data.has("defeat"):
		data.erase("defeat")  # 空の defeat キーは書き出さない


# --- 保存（テキスト化） ---
# 既存ステージの手書きスタイルに寄せる：2スペースインデント・駒/控え/会話行は1行辞書・terrain は1行1文字列。


func to_text() -> String:
	_normalize_terrain()
	var keys := []
	for k in KEY_ORDER:
		if data.has(k):
			keys.append(k)
	for k in data:
		if not keys.has(k):
			keys.append(k)
	var parts: Array[String] = []
	for k in keys:
		# 任意キー（bases/victory/terrain_skins）は空なら書かない（読み込み時の補完でキーを増やさない）。
		# ただし元ファイルに書いてあったキーはそのまま残す（往復で内容を変えない）。
		if String(k) in ["bases", "victory", "defeat", "terrain_skins"] and typeof(data[k]) == TYPE_ARRAY \
				and data[k].is_empty() and not _keys_in_source.has(String(k)):
			continue
		parts.append("  %s: %s" % [JSON.stringify(String(k)), _emit_top(k, data[k])])
	return "{\n" + ",\n".join(parts) + "\n}\n"


## トップレベル値。terrain（文字列を1行ずつ）と terrain_skins（1件1行）だけ特別扱い。
func _emit_top(key: String, v: Variant) -> String:
	if key == "terrain" and typeof(v) == TYPE_ARRAY:
		if v.is_empty():
			return "[]"
		var lines: Array[String] = []
		for line in v:
			lines.append("    " + JSON.stringify(String(line)))
		return "[\n" + ",\n".join(lines) + "\n  ]"
	if key == "terrain_skins" and typeof(v) == TYPE_ARRAY and not v.is_empty():
		return _emit_terrain_skins(v)
	return _emit(v, 2)


## terrain_skins：1件1行・キーは col, row, skin の順（手書きの既存ステージに合わせる）。
## 並びは row→col ＝ terrain グリッドと同じ順にして、diff で盤と突き合わせられるようにする。
func _emit_terrain_skins(v: Array) -> String:
	var entries := []
	for e in v:
		if typeof(e) != TYPE_DICTIONARY:
			return _emit(v, 2)  # 想定外の中身は汎用整形に任せる（内容を落とさない）
		entries.append(e)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("row", 0)) != int(b.get("row", 0)):
			return int(a.get("row", 0)) < int(b.get("row", 0))
		return int(a.get("col", 0)) < int(b.get("col", 0)))
	var lines: Array[String] = []
	for e in entries:
		var parts: Array[String] = []
		for k in ["col", "row", "skin"]:
			if e.has(k):
				parts.append("%s: %s" % [JSON.stringify(k), _scalar(e[k])])
		for k in e:  # 未知キーは後ろに温存
			if not (String(k) in ["col", "row", "skin"]):
				parts.append("%s: %s" % [JSON.stringify(String(k)), _emit(e[k], 4)])
		lines.append("    { " + ", ".join(parts) + " }")
	return "[\n" + ",\n".join(lines) + "\n  ]"


## 汎用の値→テキスト。ind は現在のインデント（スペース数）。
func _emit(v: Variant, ind: int) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			return _emit_dict(v, ind)
		TYPE_ARRAY:
			return _emit_array(v, ind)
		_:
			return _scalar(v)


func _emit_dict(d: Dictionary, ind: int) -> String:
	var block_keys := []  # 段落表示する配列キー（units/garrison/passengers で中身あり）
	for k in d:
		if String(k) in BLOCK_ARRAY_KEYS and typeof(d[k]) == TYPE_ARRAY and not d[k].is_empty():
			block_keys.append(k)
	if block_keys.is_empty():
		if _inline_ok(d):
			return _inline_dict(d)
		return _emit_dict_block(d, ind)
	# エンティティ形式：スカラー類を先頭行に、units 等の配列を段落で
	var head: Array[String] = []
	for k in _ordered_keys(d):
		if not (k in block_keys):
			head.append("%s: %s" % [JSON.stringify(String(k)), _emit(d[k], ind + 2)])
	var pad := " ".repeat(ind + 2)
	var lines: Array[String] = []
	if not head.is_empty():
		lines.append(", ".join(head))
	for k in block_keys:
		var arr: Array = d[k]
		if arr.size() == 1 and typeof(arr[0]) == TYPE_DICTIONARY and _inline_ok(arr[0]):
			lines.append("%s%s: [ %s ]" % [pad, JSON.stringify(String(k)), _inline_dict(arr[0])])
		else:
			lines.append("%s%s: %s" % [pad, JSON.stringify(String(k)), _emit_array(arr, ind + 2)])
	return "{ " + ",\n".join(lines) + " }"


## 段落表示の辞書（dialogue など）：キーごとに1行。
func _emit_dict_block(d: Dictionary, ind: int) -> String:
	if d.is_empty():
		return "{}"
	var pad := " ".repeat(ind + 2)
	var parts: Array[String] = []
	for k in _ordered_keys(d):
		parts.append("%s%s: %s" % [pad, JSON.stringify(String(k)), _emit(d[k], ind + 2)])
	return "{\n" + ",\n".join(parts) + "\n" + " ".repeat(ind) + "}"


func _emit_array(a: Array, ind: int) -> String:
	if a.is_empty():
		return "[]"
	var all_scalar := true
	for e in a:
		if typeof(e) in [TYPE_DICTIONARY, TYPE_ARRAY]:
			all_scalar = false
			break
	if all_scalar:
		var vals: Array[String] = []
		for e in a:
			vals.append(_scalar(e))
		return "[" + ", ".join(vals) + "]"
	var pad := " ".repeat(ind + 2)
	var parts: Array[String] = []
	for e in a:
		parts.append(pad + _emit(e, ind + 2))
	return "[\n" + ",\n".join(parts) + "\n" + " ".repeat(ind) + "]"


## 1行に収めてよい辞書か（値がすべてスカラー or 空配列）。
func _inline_ok(d: Dictionary) -> bool:
	for k in d:
		var t := typeof(d[k])
		if t == TYPE_DICTIONARY:
			return false
		if t == TYPE_ARRAY and not d[k].is_empty():
			return false
	return true


func _inline_dict(d: Dictionary) -> String:
	var parts: Array[String] = []
	for k in _ordered_keys(d):
		var v: Variant = d[k]
		var vs := "[]" if typeof(v) == TYPE_ARRAY else _scalar(v)
		parts.append("%s: %s" % [JSON.stringify(String(k)), vs])
	return "{ " + ", ".join(parts) + " }"


## ENTITY_KEY_ORDER → 残りは元の順 → BLOCK_ARRAY_KEYS は末尾。
func _ordered_keys(d: Dictionary) -> Array:
	var out := []
	for k in ENTITY_KEY_ORDER:
		if d.has(k):
			out.append(k)
	for k in d:
		if not out.has(k) and not (String(k) in BLOCK_ARRAY_KEYS):
			out.append(k)
	for k in BLOCK_ARRAY_KEYS:
		if d.has(k) and not out.has(k):
			out.append(k)
	return out


## スカラー値のJSON表記。JSONパース由来の float は整数値なら整数で書く（"30.0"→"30"）。
func _scalar(v: Variant) -> String:
	match typeof(v):
		TYPE_STRING:
			return JSON.stringify(v)
		TYPE_FLOAT:
			return str(int(v)) if v == floorf(v) else str(v)
		TYPE_INT:
			return str(v)
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_NIL:
			return "null"
		_:
			return JSON.stringify(v)
