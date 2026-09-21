extends ChronicleCardChapter
class_name ChronicleUnitsChapter
## クロニクルのユニット章。仕様 → doc/gdd/chronicle.md ユニット
##
## カテゴリごとに羊皮紙のカードを格子に並べ、押すと拡大カードが手前に開く。格子の1枚に載るのは
## 盤の絵と名前。格子・紙・拡大カードの開閉は ChronicleCardChapter。

const NONE_TEXT := "—"

## カテゴリごとに羊皮紙のカードを格子に並べる。カテゴリの出現順と各スキンの並び順は
## SkinCatalog の __by_id__ 辞書の挿入順（＝CSV の行順）に従う。
func _build() -> void:
	if _store == null:
		return
	var encountered := _store.skins()  # 出会った skin_id の並び
	var card_size := _card_size()
	for cat_entry in _ordered_skins():
		var category: String = cat_entry["category"]
		var skins: Array = cat_entry["skins"]
		var found := 0
		var cards: Array = []
		for s in skins:
			var known: bool = encountered.has(s.skin_id)
			if known:
				found += 1
			cards.append(_unit_card(s, known, card_size))
		_add_group(tr("unit_group.%s.name" % category), found, cards)

## SkinCatalog の __by_id__ からカテゴリ順にまとめた配列を返す。
## on_board == false のスキン（会話専用）はクロニクルに並べない。
## [{ "category": String, "skins": [UnitSkin, ...] }, ...]
func _ordered_skins() -> Array:
	var by_id: Dictionary = _skins.get(SkinCatalog.BY_ID_KEY, {})
	var categories: Array = []  # [{ category, skins }]
	var cat_map := {}  # category -> index in categories
	for skin_id in by_id:
		var s: UnitSkin = by_id[skin_id]
		if not s.on_board:
			continue
		if not cat_map.has(s.category):
			cat_map[s.category] = categories.size()
			categories.append({ "category": s.category, "skins": [] })
		categories[cat_map[s.category]]["skins"].append(s)
	return categories

## 格子の1枚。盤の絵と名前（紙を先に出し、絵はあとから載せる）。未解放は黒いシルエットと「？」。
## 絵は盤と同じ大小関係で載せる（ChronicleFigureFace）＝切り抜かないので crop=false。
func _unit_card(skin: UnitSkin, known: bool, card_size: Vector2) -> Control:
	var sid := skin.skin_id
	var name_text := tr("unit.%s.name" % sid) if known else tr("ui.chronicle.unknown")
	var card := _paper_card(hash(sid), known, card_size, null, func() -> void: _open_unit_card(sid), name_text)
	_defer_face(card, [skin.image("map")], func() -> Control: return _skin_figure(skin, not known), false)
	return card

# ---------------------------------------------------------------------------
# 拡大カード
# ---------------------------------------------------------------------------

## 盤の絵と戦闘の絵を並べ、名前・兵種・説明文・性能・ユニットスキルを載せる。
func _open_unit_card(skin_id: String) -> void:
	var skin := SkinCatalog.skin_by_id(_skins, skin_id)
	if skin == null:
		return
	_open_expanded(_expanded_sheet(skin))

func _expanded_sheet(skin: UnitSkin) -> Control:
	var col := _sheet_col()

	# 絵＝盤の絵と戦闘の絵を並べる
	col.add_child(_art_row([_skin_art(skin, "map", false), _skin_art(skin, "combat", false)]))

	# 見出し＝ユニット名（兵種）
	col.add_child(_sheet_title(_unit_title(skin)))

	# 説明文（chronicle.csv に unit.<skin_id>.desc があれば）
	var desc := _desc_label("unit.%s.desc" % skin.skin_id)
	if desc != null:
		col.add_child(desc)

	# 性能の数値
	col.add_child(_pairs_grid(_stat_rows(skin.type_id)))
	var traits := _trait_text(skin.type_id)
	if not traits.is_empty():
		col.add_child(_ink_line("%s  %s" % [tr("ui.info.trait"), traits], TavernTheme.INK))

	# ユニットスキル（撃てるものを性能の一部として載せる。doc/gdd/skills.md）
	for rid in _unit_skill_ids(skin):
		col.add_child(_ink_line("%s  %s" % [tr("ui.info.skill"), tr("skill.%s.name" % rid)], TavernTheme.INK))
		var skill_desc := tr("skill.%s.desc" % rid)
		if skill_desc != "skill.%s.desc" % rid:
			col.add_child(_ink_line(skill_desc, TavernTheme.INK_SOFT))
	return _paper_sheet(hash(skin.skin_id), col)

## 見出しの文字列＝ユニット名（兵種）。兵種を添えるのは味方だけ。
## 敵の分類は素性（ゴブリン・アンデッド…）で兵種ではなく、格子の章見出しと同じ語になる＝
## 括弧に入れても何も足さない。兵種そのものを出すのはリスキン元が透けるので避ける
## （情報パネルと同じ線 → doc/gdd/uiux.md 見出し）。
func _unit_title(skin: UnitSkin) -> String:
	var name_text := tr("unit.%s.name" % skin.skin_id)
	if skin.side != "ally" or skin.category.is_empty():
		return name_text
	return tr("ui.chronicle.name_category") % [name_text, tr("unit_group.%s.name" % skin.category)]

## 性能の数値＝盤の状況で変わらない値だけ。項目と語は情報パネルの能力タブと揃える。
## [[項目, 値], ...]。持たない駒に出しても意味のない項目（搭乗・シールド）は持つ駒だけ。
func _stat_rows(type_id: String) -> Array:
	var t: UnitType = _types.get(type_id, null) as UnitType
	if t == null:
		return []
	var rows: Array = []
	rows.append([tr("ui.info.atk_ground"), str(t.atk_ground)])
	rows.append([tr("ui.info.atk_air"), str(t.atk_air) if t.atk_air > 0 else NONE_TEXT])
	rows.append([tr("ui.info.defense"), str(t.defense)])
	rows.append([tr("ui.info.range"), str(t.attack_range) if t.min_range == t.attack_range \
		else "%d-%d" % [t.min_range, t.attack_range]])
	rows.append([tr("ui.info.move"), str(t.move)])
	rows.append([tr("ui.info.move_type"), tr("movement.%s.name" % t.move_type)])
	rows.append([tr("ui.info.strength"), str(t.max_troops)])
	if t.capacity > 0:
		rows.append([tr("ui.chronicle.capacity"), str(t.capacity)])
	if t.shield > 0:
		rows.append([tr("ui.info.shield"), str(t.shield)])
	return rows

## 特性＝他の行を見ても分からないことだけ（情報パネルと同じ線引き）。
func _trait_text(type_id: String) -> String:
	var t: UnitType = _types.get(type_id, null) as UnitType
	if t == null:
		return ""
	var traits: Array[String] = []
	if t.pierce > 0.0:
		traits.append(tr("ui.info.trait_pierce") % roundi(t.pierce * 100.0))
	if t.can_capture:
		traits.append(tr("ui.info.trait_capture"))
	if t.move_after_attack:
		traits.append(tr("ui.info.trait_move_after_attack"))
	return "   /   ".join(traits)

## その駒が撃てるユニットスキル（単独発動＝shape "solo"）のレシピid。
## 照合は skin_id だけ＝Formation._matches が盤で使う鍵と同じ（クロニクルの枠は必ず
## skin_id を持つ）。type_id でも拾うと、性能を借りているだけの別スキンに撃てない
## スキルが載る（ゴーストはピクシー性能だがピクシーダストは撃てない）。
func _unit_skill_ids(skin: UnitSkin) -> Array:
	var out: Array = []
	for rid in Formation.SKILLS:
		var skill_def: Dictionary = Formation.SKILLS[rid]
		if not Formation.is_unit_skill(rid):
			continue
		if (skill_def.get("leader_skins", []) as Array).has(skin.skin_id):
			out.append(rid)
	return out
