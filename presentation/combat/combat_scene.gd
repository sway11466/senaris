extends CombatStage
class_name CombatScene
## 戦闘の進行。舞台（窓・地面・隊列・立ち絵・兵量バー・エフェクト）は CombatStage が持ち、
## ここは「ため→着弾→反撃→幕引き」の順番だけを組む。仕様 → doc/tech/combat_scene.md
## MatchController.combat_resolved(detail) を受け、プレイヤー左／敵右で隊列を並べ、
## シェイク＋フラッシュ＋損害数を出す。detail は BattleState.attack の "detail"。

const COUNTER_GAP := 0.1  # 攻撃側の着弾から反撃までの間（秒）
const DAMAGE_OUTLINE := Color(0.47, 0.12, 0.12)  # 損害数の縁（赤＝減った）

## 戦闘結果 detail を演出する。detail が空なら何もしない。
func play(detail: Dictionary) -> void:
	if detail == null or detail.is_empty():
		return
	_build()  # 未生成なら組む（結線タイミングに依存しない）
	var a: Dictionary = detail["attacker"]
	var t: Dictionary = detail["defender"]
	var counter: bool = detail.get("to_attacker") != null

	# 陣営で左右を固定（team0=左／team1=右）。攻撃側/防御側では入れ替えない。
	var L: Dictionary = a if int(a["team"]) == 0 else t
	var R: Dictionary = t if int(a["team"]) == 0 else a
	var atk_side := "L" if int(a["team"]) == 0 else "R"
	var def_side := "R" if int(a["team"]) == 0 else "L"

	_open(t, def_side)  # 地面は守り手の地形（攻撃側の地形は使わない）
	var gen := _gen
	_render_side("L", L, int(L["troops_before"]))
	_render_side("R", R, int(R["troops_before"]))

	var def_dmg := int(t["troops_before"]) - int(t["troops_after"])
	var atk_dmg := int(a["troops_before"]) - int(a["troops_after"])
	var def_comb: Dictionary = R if def_side == "R" else L
	var atk_comb: Dictionary = L if atk_side == "L" else R
	var def_after := int(t["troops_after"])
	var atk_after := int(a["troops_after"])

	# ため：まず隊列を見せてから斬りかかる（突入直後に即着弾しない）。
	# 一撃は放ってから着弾するまで時間がかかる（飛翔＋発数ぶんの時差）。この遅れを後続にも
	# 足して、「攻撃側が着弾 → 反撃 → 幕引き」の順番が入れ替わらないようにする。
	_tween = create_tween()
	_tween.tween_interval(LEAD_IN)
	_tween.tween_callback(func() -> void:
		if gen == _gen:
			_strike_side(def_side, def_dmg, def_after, def_comb, atk_comb, gen))
	if counter:
		_tween.tween_interval(COUNTER_GAP + _strike_time(atk_comb, int(a["troops_before"])))
		_tween.tween_callback(func() -> void:
			if gen == _gen:
				_strike_side(atk_side, atk_dmg, atk_after, atk_comb, def_comb, gen))
		_tween.tween_interval(0.7 + _strike_time(def_comb, def_after))
	else:
		_tween.tween_interval(0.7 + _strike_time(atk_comb, int(a["troops_before"])))
	_tween.tween_callback(func() -> void:
		if gen == _gen:
			_dismiss())

## 片側への一撃。side＝被弾側、comb＝被弾側の駒、by＝殴った側の駒（エフェクトの持ち主）。
## エフェクトは殴った側の兵量ぶん出し、被弾側の隊列スロットへ配る（1発が1体に当たって見える）。
## 殴った側のほうが多いときはスロットを先頭から巡回する＝誰も居ない場所を斬らない。
## シェイク・フラッシュ・損害数・兵量バーは最後の1発が届いた時点に揃える。
func _strike_side(side: String, dmg: int, after: int, comb: Dictionary, by: Dictionary, gen: int) -> void:
	var eff := _effect_of(by)
	# 命中音。1発ずつではなく一撃につき鳴らす＝8体並ぶと8連射になって潰れる。
	# 近接は1音（ここだけ）。遠距離は発射をここで鳴らし、着弾は最後の1発が届く時点に回す。
	# 素材はエフェクトIDの規約解決（assets/sfx/{effect_id}.ogg）。無ければ無音で進む。
	if eff != null:
		if eff.is_projectile():
			SfxPlayer.play_sfx(eff.effect_id)  # 発射。損害によらず武器固有
		else:
			SfxPlayer.play_sfx(SFX_DEFLECT if dmg <= 0 else eff.effect_id)
	# 発数は「いま殴った側に並んでいる数」。反撃では既に減った後の隊列が振るので、
	# detail の戦闘前の兵量を使うと、2体しか居ないのに5発斬るような絵になる。
	var shots := clampi(int(_shown.get(_other_side(side), 1)), 1, POS.size())
	var targets := _troops_of(comb)
	var fly := eff != null and eff.is_projectile()
	for i in shots:
		var to := _slot_pos(side, POS[i % targets])
		var delay := float(i) * STAGGER
		if fly:
			_spawn_fly(_slot_pos(_other_side(side), POS[i]), to, eff, delay, gen)
		else:
			_spawn_burst(to, side == "L", eff, delay, gen)
	var tw := create_tween()
	tw.tween_interval(_strike_time(by, shots))
	tw.tween_callback(func() -> void:
		if gen != _gen:
			return  # スキップで閉じた後に飛来物が届いても何もしない
		if eff != null and eff.is_projectile():
			SfxPlayer.play_sfx(SFX_DEFLECT if dmg <= 0 else "%s_hit" % eff.effect_id)
		_shake()
		_render_side(side, comb, after, true)
		_flash(side)
		if dmg > 0:
			_float_label(side, "-%d" % dmg, DAMAGE_OUTLINE))

## その一撃が「放ってから最後の1発が届く」までの時間。飛翔＋発数ぶんの時差。
## shots は殴る時点で並んでいる数（反撃は減った後の数）＝play が先に見積もって幕引きを合わせる。
func _strike_time(by: Dictionary, shots: int) -> float:
	var stagger := float(clampi(shots, 1, POS.size()) - 1) * STAGGER
	return stagger + (FLIGHT if _is_projectile(by) else 0.0)
