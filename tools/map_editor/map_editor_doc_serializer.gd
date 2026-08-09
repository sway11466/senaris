extends RefCounted
class_name MapEditorDocSerializer
## MapEditorDoc の stage.json 整形出力（tools 専用）。
## 既存ステージの手書きスタイルに寄せる：2スペースインデント・駒/控え/会話行は1行辞書・terrain は1行1文字列。
## MapEditorDoc.to_text() から委譲される。データ操作は持たない＝入力を文字列に変えるだけ。

## 保存時のトップレベルキーの並び（既存ステージの手書き順に合わせる）。残りは元の順で末尾。
const KEY_ORDER := ["turn_limit", "name", "cols", "rows", "margin", "terrain", "terrain_skins", "player", "enemy", "bases", "events", "victory", "defeat", "ai", "dialogue"]

## 辞書の中で「配列を段落表示する」キー（squad の units / 拠点の garrison / 輸送の passengers /
## 敗北条件の bases・actors）。1件だけなら1行に収まる＝手書きの既存ステージと同じ見た目になる。
const BLOCK_ARRAY_KEYS := ["units", "garrison", "passengers", "bases", "actors"]

## 辞書内キーの並び（既存ステージの手書き順に寄せる）。残りは元の順、BLOCK_ARRAY_KEYS は常に末尾。
const ENTITY_KEY_ORDER := ["turn", "order", "name", "ai", "speaker", "type", "skin", "actor", "text", "label", "col", "row", "team", "kind", "count", "native"]


## data と keys_in_source（読み込み時に元ファイルに存在したキーの記録）を受け取り、
## 手書きスタイルに寄せた JSON テキストを返す。
static func serialize(data: Dictionary, keys_in_source: Dictionary) -> String:
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
				and data[k].is_empty() and not keys_in_source.has(String(k)):
			continue
		parts.append("  %s: %s" % [JSON.stringify(String(k)), _emit_top(k, data[k])])
	return "{\n" + ",\n".join(parts) + "\n}\n"


## トップレベル値。terrain（文字列を1行ずつ）と terrain_skins（1件1行）だけ特別扱い。
static func _emit_top(key: String, v: Variant) -> String:
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
static func _emit_terrain_skins(v: Array) -> String:
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
static func _emit(v: Variant, ind: int) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			return _emit_dict(v, ind)
		TYPE_ARRAY:
			return _emit_array(v, ind)
		_:
			return _scalar(v)


static func _emit_dict(d: Dictionary, ind: int) -> String:
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
static func _emit_dict_block(d: Dictionary, ind: int) -> String:
	if d.is_empty():
		return "{}"
	var pad := " ".repeat(ind + 2)
	var parts: Array[String] = []
	for k in _ordered_keys(d):
		parts.append("%s%s: %s" % [pad, JSON.stringify(String(k)), _emit(d[k], ind + 2)])
	return "{\n" + ",\n".join(parts) + "\n" + " ".repeat(ind) + "}"


static func _emit_array(a: Array, ind: int) -> String:
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
static func _inline_ok(d: Dictionary) -> bool:
	for k in d:
		var t := typeof(d[k])
		if t == TYPE_DICTIONARY:
			return false
		if t == TYPE_ARRAY and not d[k].is_empty():
			return false
	return true


static func _inline_dict(d: Dictionary) -> String:
	var parts: Array[String] = []
	for k in _ordered_keys(d):
		var v: Variant = d[k]
		var vs := "[]" if typeof(v) == TYPE_ARRAY else _scalar(v)
		parts.append("%s: %s" % [JSON.stringify(String(k)), vs])
	return "{ " + ", ".join(parts) + " }"


## ENTITY_KEY_ORDER → 残りは元の順 → BLOCK_ARRAY_KEYS は末尾。
static func _ordered_keys(d: Dictionary) -> Array:
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
static func _scalar(v: Variant) -> String:
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
