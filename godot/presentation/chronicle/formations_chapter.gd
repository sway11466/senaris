extends ChronicleCardChapter
class_name ChronicleFormationsChapter
## クロニクルの陣形スキル章。仕様 → doc/gdd/chronicle.md 陣形スキル
##
## 表A（doc/gdd/formations.md）の分類ごとに羊皮紙のカードを格子に並べる。解放済みの面はカットインの絵と
## スキル名、未解放の面は要るユニットの黒塗りを人数ぶん＝ヒント（誰が要るかまで。名前は「？」で伏せ、
## 形と位置は解放後の拡大カードだけ）。
## 分類と並びは Formation.SKILLS の category と挿入順（表Aの写し）。
## 並ぶのは陣形スキル（shape != "solo"）だけ＝単独発動のユニットスキルはユニット章の拡大カードに載る
## （doc/gdd/skills.md）。

const NONE_TEXT := "—"
const HINT_GAP := 4  # 黒塗りの駒の間

## カットインの絵（1200×896）を面いっぱいに載せる横長のカード。
func _card_columns() -> int:
	return 4

func _card_aspect() -> float:
	return 0.75

func _build() -> void:
	if _store == null:
		return
	var encountered := _store.skills()  # 見た skill_id の並び
	var card_size := _card_size()
	for group in _grouped_skills():
		var category: String = group["category"]
		var ids: Array = group["skills"]
		var found := 0
		var cards: Array = []
		for rid in ids:
			var known: bool = encountered.has(rid)
			if known:
				found += 1
			cards.append(_skill_card(rid, known, card_size))
		_add_group(tr("skill_group.%s.name" % category), found, cards)

## Formation.SKILLS から陣形スキル（shape != "solo"）を分類ごとにまとめる。分類の並びは初めて
## 現れた順、分類のなかは挿入順＝表Aの行順。[{ "category": String, "skills": [id, ...] }, ...]
func _grouped_skills() -> Array:
	var groups: Array = []
	var index := {}  # category -> index in groups
	for rid in Formation.SKILLS:
		if Formation.is_unit_skill(rid):
			continue
		var r: Dictionary = Formation.SKILLS[rid]
		var category := String(r.get("category", ""))
		if not index.has(category):
			index[category] = groups.size()
			groups.append({ "category": category, "skills": [] })
		groups[index[category]]["skills"].append(rid)
	return groups

## 格子の1枚。解放済みはカットインの絵と名前、未解放は黒塗りの顔ぶれと「？」（紙を先に出し、絵はあとから載せる）。
func _skill_card(skill_id: String, known: bool, card_size: Vector2) -> Control:
	var rid := skill_id
	var name_text := tr("skill.%s.name" % rid) if known else tr("ui.chronicle.unknown")
	var card := _paper_card(hash(rid), known, card_size, null, func() -> void: _open_skill_card(rid), name_text)
	if known:
		_defer_face(card, [FormationCutin.card_art_path(rid)],
			func() -> Control: return _cutin_art(rid), false)
	else:
		_defer_face(card, _skin_paths(_figure_skins(rid)), func() -> Control: return _hint_face(rid))
	return card

## カットインの絵。発動者ごとに絵が分かれるスキルは先頭のスキンの絵。未用意ならプレースホルダの文字。
func _cutin_art(skill_id: String) -> Control:
	var tex := FormationCutin.load_card_art(skill_id)
	if tex == null:
		return _art_placeholder(tr("skill.%s.name" % skill_id))
	return _art_rect(tex, false)

## 未解放の面＝要るユニットの盤の絵を黒塗りで人数ぶん横に並べる。切り抜いて枠に収める＝
## 5人並ぶ紙でも重ならず、ユニット章の格子のような大小関係は付けない（doc/gdd/chronicle.md 陣形スキル）。
func _hint_face(skill_id: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", HINT_GAP)
	for skin in _figure_skins(skill_id):
		var art := _skin_art(skin, "map", true)
		art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(art)
	return row

## 図と黒塗りに使う顔ぶれ＝人数ぶんの UnitSkin。先頭が発動者（発動者になれる駒の先頭で代表）、
## 残りは参加者の先頭で代表する（doc/gdd/formations.md 一覧）。
func _figure_skins(skill_id: String) -> Array:
	var r: Dictionary = Formation.SKILLS[skill_id]
	var casters: Array = r.get("caster_skins", [])
	var members: Array = r.get("member_skins", [])
	var count: int = r.get("count", 1)
	var out: Array = []
	for i in count:
		var pool: Array = casters if i == 0 else members
		var skin := SkinCatalog.skin_by_id(_skins, String(pool[0]))
		if skin != null:
			out.append(skin)
	return out

# ---------------------------------------------------------------------------
# 拡大カード
# ---------------------------------------------------------------------------

## カットインの絵とレシピの図を並べ、名前（分類）・説明文・効果の表・候補を載せる。
func _open_skill_card(skill_id: String) -> void:
	if not Formation.SKILLS.has(skill_id):
		return
	_open_expanded(_expanded_sheet(skill_id))

func _expanded_sheet(skill_id: String) -> Control:
	var r: Dictionary = Formation.SKILLS[skill_id]
	var col := _sheet_col()

	# 絵＝カットインとレシピの図
	var figure := ChronicleRecipeFigure.new()
	var textures: Array = []
	for skin in _figure_skins(skill_id):
		textures.append(_skin_texture(skin, "map"))
	# 対象を取る形の敵ヘクスには敵の代表＝ゴブリンの駒を置く（doc/gdd/chronicle.md 陣形スキル）。
	var goblin := SkinCatalog.skin_by_id(_skins, "goblin")
	var target: Texture2D = null if goblin == null else _skin_texture(goblin, "map")
	figure.setup(String(r.get("shape", "")), textures, target)
	col.add_child(_art_row([_cutin_art(skill_id), figure]))

	# 見出し＝名前（分類）
	var category := String(r.get("category", ""))
	col.add_child(_sheet_title(tr("ui.chronicle.name_category") % [
		tr("skill.%s.name" % skill_id), tr("skill_group.%s.name" % category)]))

	# 説明文（skills.csv の skill.<id>.desc。情報パネルと共通）
	var desc := _desc_label("skill.%s.desc" % skill_id)
	if desc != null:
		col.add_child(desc)

	# 効果・射程・持続・人数・発動できる駒。値に文が入る（持続・効果）ので1行2対に留める
	col.add_child(_pairs_grid(_skill_rows(r), 2))

	# 発動者と参加者の候補（図は代表1体なので、候補が複数あることはここで分かる）
	col.add_child(_ink_line("%s  %s" % [tr("ui.chronicle.skill_caster"),
		_skin_names_text(r.get("caster_skins", []))], TavernTheme.INK))
	col.add_child(_ink_line("%s  %s" % [tr("ui.chronicle.skill_members"),
		_skin_names_text(r.get("member_skins", []))], TavernTheme.INK))

	return _paper_sheet(hash(skill_id), col)

## 効果の表＝[[項目, 値], ...]。
func _skill_rows(r: Dictionary) -> Array:
	var rows: Array = []
	rows.append([tr("ui.chronicle.skill_effect"), _effect_text(r)])
	rows.append([tr("ui.info.range"), _range_text(r)])
	rows.append([tr("ui.chronicle.skill_duration"), _duration_text(r)])
	var count: int = r.get("count", 1)
	rows.append([tr("ui.chronicle.skill_count"),
		tr("ui.chronicle.skill_count_min") % count if r.get("shape", "") == "cluster" else str(count)])
	rows.append([tr("ui.chronicle.skill_from"),
		tr("ui.chronicle.skill_from_caster") if r.get("range_from", "") == "caster" \
		else tr("ui.chronicle.skill_from_any")])
	return rows

## レシピの効果を翻訳済みテキストにする。
func _effect_text(r: Dictionary) -> String:
	match String(r.get("effect", "")):
		"area":
			return tr("ui.chronicle.skill_effect_area") % int(r.get("radius", 1))
		"single":
			return tr("ui.chronicle.skill_effect_single")
		"buff":
			return tr("ui.chronicle.skill_effect_buff")
	return ""

## 射程。固定値があればその数、性能から引くレシピは説明文、どちらも無ければ「—」。
func _range_text(r: Dictionary) -> String:
	var range_val: int = r.get("range", 0)
	if range_val > 0:
		return str(range_val)
	match String(r.get("range_from_stats", "")):
		"caster":
			return tr("ui.chronicle.skill_range_caster")
		"max_plus":
			var plus: int = int(r.get("range_plus", 0))
			if plus > 0:
				return tr("ui.chronicle.skill_range_max_plus") % plus
			elif plus < 0:
				return tr("ui.chronicle.skill_range_max_minus") % absi(plus)
			else:
				return tr("ui.chronicle.skill_range_max")
	return NONE_TEXT

## 持続。ダメージ系は即時、補正は次の自軍ターン開始まで（doc/gdd/formations.md 表B）。
func _duration_text(r: Dictionary) -> String:
	if not r.has("duration_turns"):
		return tr("ui.chronicle.skill_instant")
	var turns: int = r["duration_turns"]
	if turns == 1:
		return tr("ui.chronicle.skill_until_next_turn")
	return tr("ui.chronicle.skill_turns") % turns

## スキン id の配列を翻訳済み名前のカンマ区切りに変換する（重複は除く）。
func _skin_names_text(skin_ids: Array) -> String:
	var unique: Array = []
	for sid in skin_ids:
		var n := tr("unit.%s.name" % sid)
		if not unique.has(n):
			unique.append(n)
	return ", ".join(unique)
