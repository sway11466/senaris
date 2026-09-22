extends RefCounted
class_name ManualToc
## ゲーム内マニュアルの目次＝章・節・ブロックの並び。仕様 → doc/gdd/manual.md
##
## 本文そのものは持たない。持つのは「どんな順で何が並ぶか」だけで、文字列は翻訳CSV
## （data/i18n/manual.csv）から翻訳キーで引く（doc/tech/i18n.md）。構造をコードに置くのは、
## 章立てが1つしか無く、ステージのように同じ形が多数あるデータではないため
## ＝JSON とローダーとスキーマ検証を新設しても受益が無い。
##
## キーは manual.<章id>.<節id>.<要素> の規約で組み立てる（下記 key）。構造が参照するキーが
## CSV に揃っているか、CSV 側に構造から参照されないキーが無いかは tests/unit/test_manual.gd が見る。
##
## ブロックの型（"t"）:
##   p     段落1つ。"e"＝要素名
##   h     節の中の小見出し。"e"＝要素名
##   dl    用語と説明の並び。"e"＝要素名の配列。各要素が .term と .desc を持つ
##   rules 敵AIの行動ルール表。"n"＝行数。各行が rule<N>.cond と rule<N>.act を持つ
##   cols  段組み。"left"／"right"＝それぞれに積むブロックの並び（中身は下の型と同じ）
##   img   絵1枚。"e"＝要素名（キーは <要素>.img）。値は絵のパスで、翻訳CSVが言語ごとに持つ
##         ＝文字の写った絵（情報板）は言語ぶん撮って別のパスを書き、言語で変わらない絵は同じパスを書く
##   table 表。"e"＝要素名・"n"＝見出しを除く行数。キーは <要素>.head と <要素>.r1..rN で、
##         1行が1キー。セルは | 区切りで、列数は見出し行のセル数が決める
##   fig   図。"e"＝図の名前。描くものはコードが持ち、翻訳キーを持たない（文字を入れない＝言語で変わらない）
##
## 節が2つ以上ある章は、目次でその章の下に節が開く（いまは敵AIだけ）。
## 節が1つの章は章を選べばそのまま本文が出る。
##
## 節は本文（"blocks"）を持つか、タブ（"tabs"）を持つかのどちらか。タブは本文ペインの上に
## 横並びで出す切り替えで、いまは敵AIの「特性ごとの行動」だけが持つ。タブは節と同じ
## キー空間に居る＝要素キーは manual.<章id>.<タブid>.<要素> になり、節idと重複させない。

const KEY_PREFIX := "manual"

## 章の並び。並び順がそのまま目次の並び順になる。
const CHAPTERS: Array = [
	{ "id": "unit", "sections": [
		{ "id": "main", "blocks": [
			# 能力値＝どの駒も持つもの。特性＝持つ駒にだけ板が行を出すもので、板のラベル
			# （ui.info.trait）と同じ語でくくる。項目の並びは情報板の能力タブと同じ順
			# （doc/gdd/uiux.md）＝板を見ながら上から順に引ける。
			# 兵種は板の見出しに出る（能力タブに行が無い）ので並びの先頭に置く。
			{ "t": "p", "e": "intro" },
			{ "t": "h", "e": "stats" },
			{ "t": "p", "e": "stats1" },
			{ "t": "cols", "left": [
				{ "t": "dl", "e": [
					"category", "troops", "level", "atk_ground", "atk_air", "defense", "move",
					"move_type", "range",
				] },
			], "right": [
				{ "t": "img", "e": "panel_fighter" },
				{ "t": "img", "e": "panel_witch" },
				{ "t": "img", "e": "panel_thief" },
			] },
			{ "t": "h", "e": "traits" },
			{ "t": "p", "e": "traits1" },
			{ "t": "p", "e": "traits2" },
			{ "t": "cols", "left": [
				{ "t": "dl", "e": ["pierce", "can_capture", "move_after_attack", "capacity"] },
			], "right": [
				{ "t": "img", "e": "panel_cleric" },
			] },
		] },
	] },
	{ "id": "combat", "sections": [
		{ "id": "main", "blocks": [
			{ "t": "img", "e": "window" },
			{ "t": "p", "e": "intro" },
			{ "t": "h", "e": "simultaneous" },
			{ "t": "p", "e": "sim1" },
			{ "t": "p", "e": "sim2" },
			# 補正から先は戦闘レポートと突き合わせて読む＝板を横に並べる。
			{ "t": "h", "e": "mods" },
			{ "t": "cols", "left": [
				# 並びはレポートのサマリータブの行と同じ順（combat_report_view）＝板を見ながら上から順に
				# 引ける。レベルはサマリーでは名前の行に混ざっているが、真っ先に目に入るので先頭に置く。
				# 総攻撃・総防御は補正そのものではなく積み上がった結果だが、以降の項目が何に効くのかを
				# 先に示す＝式をここで1回だけ出す。防御貫通だけは板の順から外して末尾に置く
				# ＝補正をすべて済ませたあとに掛かるので、並びが適用の順のままになる。
				{ "t": "dl", "e": ["level", "total", "terrain", "surround", "support", "status", "pierce"] },
				{ "t": "h", "e": "damage" },
				{ "t": "p", "e": "damage1" },
				{ "t": "p", "e": "damage2" },
			], "right": [
				{ "t": "img", "e": "report_summary" },
				{ "t": "img", "e": "report_attack" },
				{ "t": "img", "e": "report_counter" },
			] },
		] },
	] },
	# 包囲は補正の1つだが、深さで係数が変わる＝形と数字を見せないと「2体以上で成立」までしか
	# 読めない。図と表を持つぶん戦闘の章に収まらないので、章として立てる。戦闘の補正の並びには
	# 短い説明だけ残し、詳しくはこの章を見に来させる。
	{ "id": "surround", "sections": [
		{ "id": "main", "blocks": [
			{ "t": "p", "e": "intro" },
			{ "t": "h", "e": "count" },
			{ "t": "fig", "e": "surround" },
			{ "t": "p", "e": "fig_note" },
			{ "t": "p", "e": "count1" },
			{ "t": "h", "e": "depth" },
			{ "t": "table", "e": "rate", "n": 5 },
			{ "t": "p", "e": "heads" },
		] },
	] },
	{ "id": "terrain", "sections": [
		{ "id": "main", "blocks": [
			{ "t": "p", "e": "intro" },
			# 攻防から先は情報板と突き合わせて読む＝板を横に並べる（戦闘の章と同じ形）。
			# 板は空きマスを選んだときの表示で、平地（足場・補正なし）と町（オブジェクト・攻守で
			# 逆に振れる）の2枚＝係数の違いと層の違いを、同じ形の板を並べて見せる。
			{ "t": "cols", "left": [
				{ "t": "h", "e": "stats" },
				{ "t": "p", "e": "stats1" },
				{ "t": "h", "e": "layer" },
				{ "t": "p", "e": "layer1" },
				{ "t": "h", "e": "height" },
				{ "t": "p", "e": "height1" },
			], "right": [
				{ "t": "img", "e": "panel_plain" },
				{ "t": "img", "e": "panel_town" },
			] },
		] },
	] },
	{ "id": "move", "sections": [
		{ "id": "main", "blocks": [
			{ "t": "p", "e": "intro" },
			{ "t": "h", "e": "cost" },
			{ "t": "p", "e": "cost1" },
			{ "t": "p", "e": "cost2" },
			{ "t": "h", "e": "zoc" },
			{ "t": "p", "e": "zoc1" },
			{ "t": "p", "e": "zoc2" },
			{ "t": "h", "e": "after" },
			{ "t": "p", "e": "after1" },
			{ "t": "h", "e": "transport" },
			{ "t": "p", "e": "tr1" },
			{ "t": "p", "e": "tr2" },
			{ "t": "p", "e": "tr3" },
		] },
	] },
	{ "id": "skill", "sections": [
		{ "id": "main", "blocks": [
			{ "t": "p", "e": "intro" },
			{ "t": "h", "e": "recipe" },
			{ "t": "p", "e": "recipe1" },
			{ "t": "p", "e": "recipe2" },
			{ "t": "h", "e": "cost" },
			{ "t": "p", "e": "cost1" },
			{ "t": "p", "e": "cost2" },
			{ "t": "h", "e": "kinds" },
			{ "t": "p", "e": "kinds1" },
			{ "t": "p", "e": "kinds2" },
			{ "t": "p", "e": "kinds3" },
			{ "t": "h", "e": "stack" },
			{ "t": "p", "e": "stack1" },
			{ "t": "p", "e": "stack2" },
			{ "t": "p", "e": "stack3" },
		] },
	] },
	{ "id": "ai", "sections": [
		{ "id": "common", "blocks": [
			{ "t": "p", "e": "intro" },
			{ "t": "p", "e": "read" },
			{ "t": "h", "e": "rules" },
			{ "t": "p", "e": "rules1" },
			{ "t": "p", "e": "rules2" },
			{ "t": "h", "e": "start" },
			{ "t": "p", "e": "start1" },
			{ "t": "p", "e": "start2" },
			{ "t": "h", "e": "squad" },
			{ "t": "p", "e": "squad1" },
			{ "t": "p", "e": "squad2" },
			{ "t": "h", "e": "order" },
			{ "t": "p", "e": "order1" },
			{ "t": "h", "e": "deploy" },
			{ "t": "p", "e": "deploy1" },
			{ "t": "p", "e": "deploy2" },
		] },
		{ "id": "terms", "blocks": [
			{ "t": "p", "e": "intro" },
			{ "t": "h", "e": "distance" },
			{ "t": "dl", "e": [
				"dist_board", "dist_move", "dist_terrain", "dist_detour", "dist_sight",
				"unmeasurable",
			] },
			{ "t": "h", "e": "moving" },
			{ "t": "dl", "e": ["reach", "advance", "keep_range", "threat", "spacing"] },
			{ "t": "h", "e": "targets" },
			{ "t": "dl", "e": [
				"no_counter", "wounded", "prey", "air_target", "blocker", "lethal",
				"gain", "encircle_ok", "loss", "ride",
			] },
			{ "t": "h", "e": "params" },
			{ "t": "dl", "e": ["sight", "retreat", "stack_cond"] },
		] },
		{ "id": "traits", "tabs": [
			{ "id": "charge", "blocks": [
				{ "t": "p", "e": "desc" },
				{ "t": "h", "e": "start" },
				{ "t": "p", "e": "start1" },
				{ "t": "h", "e": "rules" },
				{ "t": "rules", "n": 7 },
				{ "t": "p", "e": "note1" },
				{ "t": "p", "e": "note2" },
			] },
			{ "id": "ambush", "blocks": [
				{ "t": "p", "e": "desc" },
				{ "t": "h", "e": "start" },
				{ "t": "p", "e": "start1" },
				{ "t": "h", "e": "rules" },
				{ "t": "rules", "n": 7 },
				{ "t": "p", "e": "note1" },
			] },
			{ "id": "raid", "blocks": [
				{ "t": "p", "e": "desc" },
				{ "t": "h", "e": "start" },
				{ "t": "p", "e": "start1" },
				{ "t": "h", "e": "rules" },
				{ "t": "rules", "n": 13 },
				{ "t": "p", "e": "note1" },
				{ "t": "p", "e": "note2" },
				{ "t": "p", "e": "note3" },
			] },
			{ "id": "predator", "blocks": [
				{ "t": "p", "e": "desc" },
				{ "t": "h", "e": "start" },
				{ "t": "p", "e": "start1" },
				{ "t": "h", "e": "rules" },
				{ "t": "rules", "n": 9 },
				{ "t": "p", "e": "note1" },
				{ "t": "p", "e": "note2" },
			] },
			{ "id": "swarm", "blocks": [
				{ "t": "p", "e": "desc" },
				{ "t": "h", "e": "start" },
				{ "t": "p", "e": "start1" },
				{ "t": "h", "e": "rules" },
				{ "t": "rules", "n": 11 },
				{ "t": "p", "e": "note1" },
				{ "t": "p", "e": "note2" },
			] },
			{ "id": "flee", "blocks": [
				{ "t": "p", "e": "desc" },
				{ "t": "h", "e": "start" },
				{ "t": "p", "e": "start1" },
				{ "t": "h", "e": "rules" },
				{ "t": "rules", "n": 4 },
				{ "t": "p", "e": "note1" },
				{ "t": "p", "e": "note2" },
			] },
			{ "id": "withdraw", "blocks": [
				{ "t": "p", "e": "desc" },
				{ "t": "h", "e": "start" },
				{ "t": "p", "e": "start1" },
				{ "t": "h", "e": "rules" },
				{ "t": "rules", "n": 12 },
				{ "t": "p", "e": "note1" },
				{ "t": "p", "e": "note2" },
			] },
			{ "id": "standoff", "blocks": [
				{ "t": "p", "e": "desc" },
				{ "t": "h", "e": "start" },
				{ "t": "p", "e": "start1" },
				{ "t": "h", "e": "rules" },
				{ "t": "rules", "n": 9 },
				{ "t": "p", "e": "note1" },
				{ "t": "p", "e": "note2" },
			] },
		] },
		{ "id": "transport", "blocks": [
			{ "t": "p", "e": "desc" },
			{ "t": "p", "e": "note1" },
			{ "t": "p", "e": "note2" },
		] },
	] },
	{ "id": "base", "sections": [
		{ "id": "main", "blocks": [
			{ "t": "p", "e": "intro" },
			{ "t": "h", "e": "capture" },
			{ "t": "p", "e": "capture1" },
			{ "t": "p", "e": "capture2" },
			{ "t": "h", "e": "deploy" },
			{ "t": "p", "e": "deploy1" },
			{ "t": "p", "e": "deploy2" },
			{ "t": "h", "e": "recover" },
			{ "t": "p", "e": "recover1" },
			{ "t": "p", "e": "recover2" },
			{ "t": "h", "e": "neutral" },
			{ "t": "p", "e": "neutral1" },
			{ "t": "h", "e": "hq" },
			{ "t": "p", "e": "hq1" },
		] },
	] },
	{ "id": "rank", "sections": [
		{ "id": "main", "blocks": [
			{ "t": "p", "e": "intro" },
			{ "t": "h", "e": "axis" },
			{ "t": "p", "e": "axis1" },
			{ "t": "p", "e": "axis2" },
			{ "t": "p", "e": "axis3" },
			{ "t": "h", "e": "record" },
			{ "t": "p", "e": "record1" },
		] },
	] },
]

## 翻訳キーを組み立てる。要素名を継ぎ足す（例: key("ai", "charge", "rule1.cond")）。
static func key(chapter_id: String, section_id: String, element: String) -> String:
	return "%s.%s.%s.%s" % [KEY_PREFIX, chapter_id, section_id, element]

## 章の見出しのキー。
static func chapter_title_key(chapter_id: String) -> String:
	return "%s.%s.title" % [KEY_PREFIX, chapter_id]

## 節の見出しのキー。
static func section_title_key(chapter_id: String, section_id: String) -> String:
	return "%s.%s.%s.title" % [KEY_PREFIX, chapter_id, section_id]

## ブロック1つが参照するキー。ブロックの型ごとに要素名の展開の仕方が違う。
static func block_keys(chapter_id: String, section_id: String, block: Dictionary) -> Array:
	var keys: Array = []
	match String(block.get("t", "")):
		"p", "h":
			keys.append(key(chapter_id, section_id, String(block["e"])))
		"dl":
			for e in block["e"]:
				keys.append(key(chapter_id, section_id, "%s.term" % String(e)))
				keys.append(key(chapter_id, section_id, "%s.desc" % String(e)))
		"rules":
			for i in range(1, int(block["n"]) + 1):
				keys.append(key(chapter_id, section_id, "rule%d.cond" % i))
				keys.append(key(chapter_id, section_id, "rule%d.act" % i))
		"img":
			keys.append(key(chapter_id, section_id, "%s.img" % String(block["e"])))
		"table":
			keys.append(key(chapter_id, section_id, "%s.head" % String(block["e"])))
			for i in range(1, int(block["n"]) + 1):
				keys.append(key(chapter_id, section_id, "%s.r%d" % [String(block["e"]), i]))
		"fig":
			pass  # 図は文字を持たない＝引くキーが無い
		"cols":
			for side in ["left", "right"]:
				for b: Dictionary in block[side]:
					keys.append_array(block_keys(chapter_id, section_id, b))
		_:
			push_error("ManualToc: 未知のブロック型: %s" % str(block))
	return keys

## 構造が参照する全キー（見出しを含む）。CSV との突き合わせに使う。
static func all_keys() -> Array:
	var keys: Array = []
	for chapter in CHAPTERS:
		var chapter_id := String(chapter["id"])
		keys.append(chapter_title_key(chapter_id))
		for section in chapter["sections"]:
			var section_id := String(section["id"])
			keys.append(section_title_key(chapter_id, section_id))
			for holder in leaves(section):
				var leaf_id := String(holder["id"])
				if leaf_id != section_id:
					keys.append(section_title_key(chapter_id, leaf_id))  # タブの見出し
				for block in holder["blocks"]:
					keys.append_array(block_keys(chapter_id, leaf_id, block))
	return keys

## 節の中で本文を持つもの＝節そのもの（"blocks"）か、その節のタブ（"tabs"）の並び。
static func leaves(section: Dictionary) -> Array:
	return section["tabs"] if section.has("tabs") else [section]

## 節がタブを持つか。
static func has_tabs(section: Dictionary) -> bool:
	return section.has("tabs")

## 章を id で引く（見つからなければ空の辞書）。
static func chapter(chapter_id: String) -> Dictionary:
	for c in CHAPTERS:
		if String(c["id"]) == chapter_id:
			return c
	return {}
