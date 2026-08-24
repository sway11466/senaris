extends CombatStage
class_name SkillScene
## ユニットスキルの進行。舞台（窓・地面・隊列・立ち絵・兵量バー・エフェクト）は CombatStage が持ち、
## ここは「ため→発動→幕引き」の順番だけを組む。仕様 → doc/tech/combat_scene.md ユニットスキルの演出
## 起きることは攻撃とほぼ同じで、違うのは兵数が減らず補正が乗る点だけ。反撃は無い。
## detail は BattleState.resolve_formation の "skill"。

const OUTRO := 0.7  # 発動が終わってから幕を引くまで（秒）。戦闘の幕引きと同じ間
const LABEL_OUTLINE := Color(0.16, 0.18, 0.24)  # 補正量の縁。損害数（赤）と混ぜない
const LABEL_TOP := 0.14  # 補正量の出だし（窓内寸に対する比）。損害数（1行）より上＝2行が隊列に被らない
## 補正の掛かる先（状態補正エントリの target）→ 表示する行の見出し（翻訳キー。表示時に tr() する）。
const TARGET_ROWS := {
	"both": ["ui.combat.attack", "ui.combat.defense"],
	"attack": ["ui.combat.attack"], "defense": ["ui.combat.defense"],
}

## ユニットスキルの発動を演出する。detail が空・発動者か対象が欠けていれば何もしない。
func play(detail: Dictionary) -> void:
	if detail == null or detail.is_empty():
		return
	var caster: Dictionary = detail.get("caster", {})
	var victim: Dictionary = detail.get("target", {})
	if caster.is_empty() or victim.is_empty():
		return
	_build()  # 未生成なら組む（結線タイミングに依存しない）

	# 陣営が違えば戦闘と同じ左右（team0=左／team1=右）。同陣営どうしは陣営で決まらないので
	# 発動者を左・対象を右に置く。立ち絵の反転は舞台側（_face_mirror）が引き受ける。
	var cast_side := "L"
	if int(caster["team"]) != int(victim["team"]):
		cast_side = "L" if int(caster["team"]) == 0 else "R"
	var to_side := _other_side(cast_side)

	_open(victim, to_side, caster)  # 地面は左右それぞれの駒の地形。重ね絵は掛けられる側
	var gen := _gen
	_render_side(cast_side, caster, _troops_of(caster))
	_render_side(to_side, victim, _troops_of(victim))

	# ため：まず両者を見せてから放つ（突入直後に即着弾しない）。兵量バーは動かないので、
	# 幕引きまでの長さは「放ってから最後の1発が届く」時間だけで決まる。
	var eff := _skill_effect(detail, caster)
	var shots := clampi(_troops_of(caster), 1, POS.size())
	var reach := float(shots - 1) * STAGGER + (FLIGHT if eff != null and eff.is_projectile() else 0.0)
	_tween = create_tween()
	_tween.tween_interval(LEAD_IN)
	_tween.tween_callback(func() -> void:
		if gen == _gen:
			_cast(cast_side, to_side, victim, eff, shots, detail, gen))
	_tween.tween_interval(OUTRO + reach)
	_tween.tween_callback(func() -> void:
		if gen == _gen:
			_dismiss())

## 発動の一撃。エフェクトを発動者の兵量ぶん出し、対象の隊列スロットへ配る。
## 効果量が残兵数で決まる（buff_value_per_troop）ので、発数＝残兵数にすると絵と数字が一致する。
func _cast(cast_side: String, to_side: String, victim: Dictionary, eff: CombatEffect, shots: int, detail: Dictionary, gen: int) -> void:
	# 発動音。1発ずつではなく発動につき1回（8体並ぶと8連射になって潰れる）。
	# 素材はレシピIDの規約解決（assets/sfx/{recipe_id}.ogg）＝陣形スキルと同じ引き方。
	# 無ければ無音で進む。詳細 → doc/audio/sfx.md
	SfxPlayer.play_sfx(String(detail.get("recipe", "")))
	var targets := _troops_of(victim)
	var fly := eff != null and eff.is_projectile()
	for i in shots:
		var to := _slot_pos(to_side, POS[i % targets])
		var delay := float(i) * STAGGER
		if fly:
			_spawn_fly(_slot_pos(cast_side, POS[i]), to, eff, delay, gen)
		else:
			_spawn_burst(to, to_side == "L", eff, delay, gen)
	var tw := create_tween()
	tw.tween_interval(float(shots - 1) * STAGGER + (FLIGHT if fly else 0.0))
	tw.tween_callback(func() -> void:
		if gen != _gen:
			return  # スキップで閉じた後に飛来物が届いても何もしない
		_shake()
		_flash(to_side)
		var text := _effect_text(detail)
		if text != "":
			_float_label(to_side, text, LABEL_OUTLINE, LABEL_TOP))

## 使うエフェクト。レシピの combat_effect を優先し、空なら発動者スキンの combat_effect へ落ちる。
## 詳細 → doc/gdd/skills.md 実装方針
func _skill_effect(detail: Dictionary, caster: Dictionary) -> CombatEffect:
	var id := String(detail.get("combat_effect", ""))
	if id != "":
		return CombatEffectCatalog.by_id(id)
	return _effect_of(caster)

## 対象に何が起きたかの表示。損害数の代わりに、乗った補正（または落とした件数）を出す。
func _effect_text(detail: Dictionary) -> String:
	# 継続ダメージ（ポイズンスティング）は掛けた瞬間には減らない＝兵量バーが動かない。
	# その代わり、毎ターン何人減るかをここに出す。詳細 → doc/gdd/skills.md
	if String(detail.get("effect", "")) == "dot":
		var per_turn := int(detail.get("dot_troops", 0))
		return tr("ui.combat.poison") % per_turn if per_turn > 0 else ""
	if String(detail.get("effect", "")) == "cleanse":
		var n := int(detail.get("cleansed", 0))
		return tr("ui.combat.cleansed") % n if n > 0 else ""
	var rows: Array = TARGET_ROWS.get(String(detail.get("buff_target", "both")), [])
	if rows.is_empty():
		return ""
	var v := float(detail.get("value", 0.0))
	var body := ("×%.2f" % v) if String(detail.get("op", "mul")) == "mul" else ("%+d" % int(round(v)))
	var lines: Array[String] = []
	for r in rows:
		lines.append("%s %s" % [tr(r), body])
	return "\n".join(lines)
