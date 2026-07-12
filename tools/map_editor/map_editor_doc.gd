extends RefCounted
class_name MapEditorDoc
## マップエディタ（tools/map_editor/map_editor.tscn）のドキュメントモデル。
## stage.json の辞書をそのまま正本として持ち、編集操作とテキスト入出力（読込/保存）を提供する。
## 編集対象外のキー（dialogue / terrain_skins / 未知キー）は読み込んだまま温存して書き戻す。
## 純ロジック（Godotノード非依存）＝テスト対象（tests/unit/test_map_editor_doc.gd）。
## スキーマの解釈は StageLoader（application/stage_loader.gd）に合わせる。

const DEFAULT_CHAR := "."  ## 既定地形（plain）のASCII文字

## 保存時のトップレベルキーの並び（既存ステージの手書き順に合わせる）。残りは元の順で末尾。
const KEY_ORDER := ["turn_limit", "name", "cols", "rows", "terrain", "terrain_skins", "player", "enemy", "bases", "victory", "ai", "dialogue"]

## 辞書の中で「配列を段落表示する」キー（squad の units / 拠点の garrison / 輸送の passengers）。
const BLOCK_ARRAY_KEYS := ["units", "garrison", "passengers"]

## 辞書内キーの並び（既存ステージの手書き順に寄せる）。残りは元の順、BLOCK_ARRAY_KEYS は常に末尾。
const ENTITY_KEY_ORDER := ["id", "name", "ai", "speaker", "type", "skin", "text", "col", "row", "team", "kind", "count", "native", "unit_id"]

var data: Dictionary = {}
var _keys_in_source := {}  ## 読み込んだファイルに元からあったキー（空でも書き戻すための記録）


## 新規ステージ（平地のみ・駒なし）。
static func new_stage(cols: int = 12, rows: int = 8) -> MapEditorDoc:
	var doc := MapEditorDoc.new()
	doc.data = { "turn_limit": 30, "name": "", "cols": cols, "rows": rows, "terrain": [], "player": [], "enemy": [], "bases": [] }
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
	doc._normalize_terrain()
	return doc


func cols() -> int:
	return int(data.get("cols", 12))


func rows() -> int:
	return int(data.get("rows", 8))


# --- 地形 ---


## terrain 配列を rows()行 × cols()桁 に整える（不足は既定地形で埋め、超過は切る）。
func _normalize_terrain() -> void:
	var grid: Variant = data.get("terrain", [])
	var lines: Array = grid if typeof(grid) == TYPE_ARRAY else []
	var out := []
	for row in rows():
		var line := String(lines[row]) if row < lines.size() else ""
		if line.length() < cols():
			line += DEFAULT_CHAR.repeat(cols() - line.length())
		out.append(line.substr(0, cols()))
	data["terrain"] = out


func terrain_char(col: int, row: int) -> String:
	var lines: Array = data.get("terrain", [])
	if row < 0 or row >= lines.size():
		return DEFAULT_CHAR
	var line := String(lines[row])
	return line[col] if col >= 0 and col < line.length() else DEFAULT_CHAR


func set_terrain_char(col: int, row: int, ch: String) -> void:
	if col < 0 or col >= cols() or row < 0 or row >= rows():
		return
	var lines: Array = data["terrain"]
	var line := String(lines[row])
	lines[row] = line.substr(0, col) + ch + line.substr(col + 1)


## 盤サイズ変更。範囲外になった駒・拠点は削除し、その数を返す。
func resize(new_cols: int, new_rows: int) -> int:
	data["cols"] = new_cols
	data["rows"] = new_rows
	_normalize_terrain()
	var dropped := 0
	dropped += _drop_out_of_range(data["player"])
	for sq in data["enemy"]:
		dropped += _drop_out_of_range(sq.get("units", []))
	dropped += _drop_out_of_range(data["bases"])
	return dropped


func _drop_out_of_range(list: Array) -> int:
	var dropped := 0
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		if int(e.get("col", 0)) >= cols() or int(e.get("row", 0)) >= rows():
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
		return true
	return false


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
		if String(k) in ["bases", "victory", "terrain_skins"] and typeof(data[k]) == TYPE_ARRAY \
				and data[k].is_empty() and not _keys_in_source.has(String(k)):
			continue
		parts.append("  %s: %s" % [JSON.stringify(String(k)), _emit_top(k, data[k])])
	return "{\n" + ",\n".join(parts) + "\n}\n"


## トップレベル値。terrain だけ「文字列を1行ずつ」の特別扱い。
func _emit_top(key: String, v: Variant) -> String:
	if key == "terrain" and typeof(v) == TYPE_ARRAY:
		if v.is_empty():
			return "[]"
		var lines: Array[String] = []
		for line in v:
			lines.append("    " + JSON.stringify(String(line)))
		return "[\n" + ",\n".join(lines) + "\n  ]"
	return _emit(v, 2)


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
