extends GutTest
## CombatEffectCatalog（攻撃エフェクト表JSON → effect_id 索引）の読込テスト。仕様 → doc/tech/combat_scene.md

# --- 実データの読込と引き ---

func test_by_id_resolves_real_data() -> void:
	var e := CombatEffectCatalog.by_id("slash_m")
	assert_not_null(e, "収録エフェクトが引ける")
	assert_eq(e.name, "斬撃（中）")
	assert_eq(e.kind, CombatEffect.KIND_IMPACT)
	assert_true(CombatEffectCatalog.by_id("arrow").is_projectile(), "矢は飛翔")

func test_by_id_unknown_or_empty_returns_null() -> void:
	assert_null(CombatEffectCatalog.by_id("no_such_effect"), "未定義は null（演出側は既定のスパーク）")
	assert_null(CombatEffectCatalog.by_id(""), "空文字も null")

func test_all_effects_are_well_formed() -> void:
	var effects := CombatEffectCatalog.all_effects()
	assert_true(effects.size() > 0, "収録エフェクトが空でない")
	var seen := {}
	for e: CombatEffect in effects:
		assert_ne(e.effect_id, "", "effect_id が空でない")
		assert_false(seen.has(e.effect_id), "effect_id が重複しない: %s" % e.effect_id)
		seen[e.effect_id] = true
		assert_true(CombatEffect.KINDS.has(e.kind), "kind は既知の値: %s" % e.effect_id)
		assert_true(e.scale > 0.0, "scale は正: %s" % e.effect_id)

func test_image_path_follows_convention() -> void:
	assert_eq(CombatEffectCatalog.by_id("slash_m").image_path(), "res://assets/effects/slash_m.png")

# --- from_dict：不正値の倒し方 ---

func test_from_dict_falls_back_on_bad_values() -> void:
	var e := CombatEffect.from_dict({ "effect_id": "x", "kind": "unknown", "scale": -1 })
	assert_eq(e.kind, CombatEffect.KIND_IMPACT, "未知の kind は重ねる側へ倒す")
	assert_eq(e.scale, 1.0, "不正な scale は 1.0")
	assert_eq(CombatEffect.from_dict({}).effect_id, "", "effect_id 欠けは空文字")
	assert_eq(CombatEffect.from_dict({}).image_path(), "", "effect_id 無しの絵パスは空文字")
