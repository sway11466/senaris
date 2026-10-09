extends AiTrait
class_name TraitAbomination
## abomination（暴走する古代兵器）の行動ルール。第1部ボス（魔人の失敗作）専用＝チャージスポットで溜め、
## ランページで寄り、マナリークを吐き、ランページで戻る。通常攻撃・通常移動の行は持たない＝自分からは
## 殴らず、反撃だけ。汎用の特性ではないので、スキルは mana_leak / rampage を名指しで使う。詳細 → doc/gdd/ai.md abomination
## 1 マナリークが溜まっていて、今の位置からの着弾先に敵が入る → 敵の数が最大の着弾先にマナリーク
## 2 マナリークが溜まっている → ランページの止まる位置のうち、そこからマナリークに入る敵の数が最大の位置へ突進
##   （どこからも入らなければ、盤上距離が最小の敵へ最も近づく位置へ。近づけなければ動かない）
## 3 マナリークが溜まっていない → 盤上距離が最小のチャージスポットへ最も近づく止まる位置へ突進
##   （スポットの上の駒は轢く）
## どの行も成立しなければ待機。

const LEAK := "mana_leak"  ## 吐く面（doc/gdd/skills.md マナリーク）
const DASH := "rampage"    ## 寄る・戻る突進（doc/gdd/skills.md ランページ）

func id() -> String:
	return "abomination"

func action(state: BattleState, u: Unit) -> AiAction:
	var leak := _skill(state, u, LEAK)  # 溜まっていなければ null（available_for がチャージで絞る）
	var dash := _skill(state, u, DASH)
	if leak != null:
		# 1 今の位置から吐ける
		var best := _best_blast_at(state, u, leak, u.pos)
		if not best.is_empty():
			return AiAction.skill(u.handle, leak, best["cell"])
		# 2 寄る
		if dash != null:
			var to := _dash_toward_blast(state, u, dash, leak)
			if to != AiPick.NO_HEX:
				return AiAction.skill(u.handle, dash, to)
		return null
	# 3 戻る
	if dash != null and _has_skill(u, LEAK):
		var to := _dash_toward_spot(state, u, dash)
		if to != AiPick.NO_HEX:
			return AiAction.skill(u.handle, dash, to)
	return null

# --- スキルの引き方 ---

## いま撃てるスキル rid の選択肢。撃てなければ null（チャージ切れ・行動済み・持っていない）。
func _skill(state: BattleState, u: Unit, rid: String) -> FormationOption:
	for option in Formation.available_for(state, u):
		if option.skill == rid:
			return option
	return null

## スキル rid を持つ駒か（溜まっているかは問わない）＝戻る行の資格。
func _has_skill(u: Unit, rid: String) -> bool:
	return Formation.can_cast_skin(u, Formation.SKILLS[rid])

# --- 行の中身 ---

## pos に居るものとして option（面スキル）を撃ったとき、範囲に入る敵の数が最大の着弾先。
## 戻り＝{ cell, n, d }（d＝範囲に入る敵のうち pos に最も近いものの盤上距離）。敵が1体も入る着弾先が無ければ空。
## 同数は d が小さい方 → 着弾先の col → row の若い方（AiRows._best_blast と同じ物差し）。
func _best_blast_at(state: BattleState, u: Unit, option: FormationOption, pos: Vector2i) -> Dictionary:
	var best := {}
	for cell in Formation.targetable_cells(state, option, pos):
		var n := 0
		var d := BattleState.UNREACHABLE
		for h in Formation.blast_cells(option, cell, pos):
			var v := state.unit_at(h)
			if v == null or v.team == u.team:
				continue
			n += 1
			d = mini(d, Hex.distance(pos, v.pos))
		if n == 0:
			continue
		if best.is_empty() or n > best["n"] or (n == best["n"] and (d < best["d"] \
				or (d == best["d"] and AiPick.is_younger_hex(cell, best["cell"])))):
			best = {"cell": cell, "n": n, "d": d}
	return best

## 寄る行＝突進の止まる位置のうち、そこから leak を撃ったとき範囲に入る敵の数が最大の位置へ。
## どの止まる位置からも敵が入らなければ、盤上距離が最小の敵へ最も近づく位置へ（近づけなければ NO_HEX）。
## 同じ止まる位置なら、駒にぶつかる選び方（轢く）を先に採る。戻り＝突進の着弾先（止まる位置ではない）。
func _dash_toward_blast(state: BattleState, u: Unit, dash: FormationOption, leak: FormationOption) -> Vector2i:
	var best_to := AiPick.NO_HEX
	var best_key: Array = []
	var nearest := _nearest_enemy(state, u)
	var cur_d := Hex.distance(u.pos, nearest.pos) if nearest != null else 0
	for to in Formation.targetable_cells(state, dash):
		var plan := Formation.dash_plan(state, dash, to)
		if plan.is_empty():
			continue
		var stop: Vector2i = plan["stop"]
		var bumps := 0 if plan["victim"] != null else 1
		var blast := _best_blast_at(state, u, leak, stop)
		var key: Array
		if not blast.is_empty():
			key = [0, -int(blast["n"]), int(blast["d"]), bumps]
		else:
			if nearest == null:
				continue
			var d := Hex.distance(stop, nearest.pos)
			if d >= cur_d and plan["victim"] == null:
				continue  # 近づけない止まる位置は採らない（轢ける向きは別）
			key = [1, d, 0, bumps]
		if best_to == AiPick.NO_HEX or _key_better(key, stop, best_key, best_stop_of(state, dash, best_to)):
			best_to = to
			best_key = key
	return best_to

## 戻る行＝盤上距離が最小のチャージスポットへ最も近づく止まる位置へ。スポットの上に駒が居れば轢く
## （その駒へぶつかる着弾先を採る）。近づけず轢けもしなければ NO_HEX。戻り＝突進の着弾先。
func _dash_toward_spot(state: BattleState, u: Unit, dash: FormationOption) -> Vector2i:
	var spot := _nearest_spot(state, u)
	if spot == AiPick.NO_HEX:
		return AiPick.NO_HEX
	var cur_d := Hex.distance(u.pos, spot)
	var best_to := AiPick.NO_HEX
	var best_key: Array = []
	for to in Formation.targetable_cells(state, dash):
		var plan := Formation.dash_plan(state, dash, to)
		if plan.is_empty():
			continue
		var stop: Vector2i = plan["stop"]
		var victim: Unit = plan["victim"]
		var rams_spot := victim != null and victim.pos == spot
		var d := Hex.distance(stop, spot)
		if d >= cur_d and not rams_spot:
			continue
		var key: Array = [0 if rams_spot else 1, d, 0 if victim != null else 1]
		if best_to == AiPick.NO_HEX or _key_better(key, stop, best_key, best_stop_of(state, dash, best_to)):
			best_to = to
			best_key = key
	return best_to

## 比べる順に並べた鍵（小さいほど良い）。同値は止まる位置の col → row の若い方。
func _key_better(key: Array, stop: Vector2i, best_key: Array, best_stop: Vector2i) -> bool:
	for i in key.size():
		if key[i] != best_key[i]:
			return key[i] < best_key[i]
	return AiPick.is_younger_hex(stop, best_stop)

## 着弾先 to を選んだときの止まる位置。
func best_stop_of(state: BattleState, dash: FormationOption, to: Vector2i) -> Vector2i:
	var plan := Formation.dash_plan(state, dash, to)
	return plan["stop"] if not plan.is_empty() else AiPick.NO_HEX

## 盤上距離が最小の敵（同値は col → row の若い方）。居なければ null。
func _nearest_enemy(state: BattleState, u: Unit) -> Unit:
	var enemies: Array[Unit] = []
	for other in state.units():
		if other.team != u.team:
			enemies.append(other)
	if enemies.is_empty():
		return null  # 敵の居ない盤＝寄る先が無い
	return pick.nearest_unit_by_board(u.pos, enemies)

## 盤上距離が最小のチャージスポットのマス（同値は col → row の若い方）。無ければ NO_HEX。
func _nearest_spot(state: BattleState, u: Unit) -> Vector2i:
	var cells: Array[Vector2i] = []
	for g in state.gimmicks():
		if GimmickKinds.is_charge_spot(g):
			cells.append(g.hex)
	if cells.is_empty():
		return AiPick.NO_HEX  # スポットの無い盤＝戻る行は成立しない
	return pick.nearest_hex_by_board(u.pos, cells)
