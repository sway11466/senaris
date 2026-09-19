extends GutTest
## presentation/formation/formation_cutin.gd の絵の規約解決。
## レシピの cutin_per_caster で名前が分かれ、無い名前はもう一方に落ちないことを見る。
## 仕様 → doc/gdd/formations.md 発動の演出／doc/art/keyvisual.md §3

# --- 名前の決め方 ---

func test_stem_per_caster_uses_skill_and_skin() -> void:
	assert_eq(FormationCutin.art_stem("trick_shot", "archer"), "trick_shot_archer",
		"発動者ごとのレシピは {skill_id}_{skin}")

func test_stem_per_caster_changes_with_skin() -> void:
	assert_eq(FormationCutin.art_stem("trick_shot", "elf"), "trick_shot_elf", "射手が変われば名前も変わる")

func test_stem_per_caster_without_skin_is_empty() -> void:
	assert_eq(FormationCutin.art_stem("trick_shot", ""), "",
		"発動者ごとのレシピでスキンが無ければ決められない＝スキルだけの名前に落とさない")

func test_stem_shared_ignores_skin() -> void:
	assert_eq(FormationCutin.art_stem("trinity_nova", "wizard"), "trinity_nova",
		"設定値の無いレシピは渡されたスキンを使わない")

func test_stem_shared_without_skin() -> void:
	assert_eq(FormationCutin.art_stem("trinity_nova", ""), "trinity_nova", "スキンが空でもスキルの名前で引ける")

func test_stem_empty_skill_is_empty() -> void:
	assert_eq(FormationCutin.art_stem("", "archer"), "", "スキルIDが空なら決められない")

func test_stem_unknown_skill_falls_to_skill_id() -> void:
	assert_eq(FormationCutin.art_stem("no_such_skill", "archer"), "no_such_skill",
		"レシピに無いIDは設定値が無い扱い（絵は無いので結局飛ぶ）")

func test_only_trick_shot_is_per_caster() -> void:
	var per: Array[String] = []
	for rid in Formation.SKILLS:
		if Formation.SKILLS[rid].get("cutin_per_caster", false):
			per.append(rid)
	assert_eq(per, ["trick_shot"] as Array[String], "発動者ごとに絵を分けるのは④だけ")

# --- 読み込み（置いてある絵と無い絵） ---

func test_load_shared_art_exists() -> void:
	assert_not_null(FormationCutin.load_art("trinity_nova", "wizard"), "①の絵は置いてある")

func test_load_unknown_skill_is_null() -> void:
	assert_null(FormationCutin.load_art("no_such_skill", "archer"), "無い名前は null")

func test_load_per_caster_without_skin_is_null() -> void:
	assert_null(FormationCutin.load_art("trick_shot", ""), "スキン無しでは trick_shot.png を探さない")

func test_card_art_uses_first_leader_skin() -> void:
	# カードは先頭スキン（アーチャー）で引く＝load_art("trick_shot", "archer") と同じ結果。
	assert_eq(FormationCutin.load_card_art("trick_shot"), FormationCutin.load_art("trick_shot", "archer"),
		"クロニクルのカードは発動者になれる駒の先頭で引く")

func test_card_art_shared_skill() -> void:
	assert_eq(FormationCutin.load_card_art("trinity_nova"), FormationCutin.load_art("trinity_nova", "wizard"),
		"設定値の無いレシピはスキルの絵")
