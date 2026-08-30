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
##
## 節が2つ以上ある章は、目次で1段潜って節の一覧になる（いまは敵AIだけ）。
## 節が1つの章は章を選べばそのまま本文が出る。

const KEY_PREFIX := "manual"

## 章の並び。並び順がそのまま目次の並び順になる。
const CHAPTERS: Array = [
	{ "id": "unit", "sections": [
		{ "id": "main", "blocks": [
			{ "t": "p", "e": "intro" },
			{ "t": "dl", "e": [
				"troops", "atk_ground", "atk_air", "defense", "pierce", "range",
				"move", "move_type", "move_after_attack", "can_capture", "capacity",
				"level", "category",
			] },
		] },
	] },
	{ "id": "combat", "sections": [
		{ "id": "main", "blocks": [
			{ "t": "p", "e": "intro" },
			{ "t": "h", "e": "simultaneous" },
			{ "t": "p", "e": "sim1" },
			{ "t": "p", "e": "sim2" },
			{ "t": "h", "e": "chain" },
			{ "t": "p", "e": "chain1" },
			{ "t": "p", "e": "chain2" },
			{ "t": "p", "e": "chain3" },
			{ "t": "h", "e": "mods" },
			{ "t": "dl", "e": ["level", "surround", "support", "terrain", "pierce", "status"] },
			{ "t": "p", "e": "mods_note" },
			{ "t": "h", "e": "damage" },
			{ "t": "p", "e": "damage1" },
			{ "t": "p", "e": "damage2" },
		] },
	] },
	{ "id": "terrain", "sections": [
		{ "id": "main", "blocks": [
			{ "t": "p", "e": "intro" },
			{ "t": "h", "e": "stats" },
			{ "t": "p", "e": "stats1" },
			{ "t": "h", "e": "sight" },
			{ "t": "p", "e": "sight1" },
			{ "t": "p", "e": "sight2" },
			{ "t": "h", "e": "layer" },
			{ "t": "p", "e": "layer1" },
			{ "t": "h", "e": "height" },
			{ "t": "p", "e": "height1" },
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
			{ "t": "h", "e": "sortie" },
			{ "t": "p", "e": "sortie1" },
			{ "t": "p", "e": "sortie2" },
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
			for block in section["blocks"]:
				keys.append_array(block_keys(chapter_id, section_id, block))
	return keys

## 章を id で引く（見つからなければ空の辞書）。
static func chapter(chapter_id: String) -> Dictionary:
	for c in CHAPTERS:
		if String(c["id"]) == chapter_id:
			return c
	return {}
