extends RefCounted
class_name FormationResolver
## 陣形スキル・ユニットスキルの発動を盤に適用する（純ロジック・Node非依存）。state を引数に取る static ヘルパー。
## 検出と威力の計算は Formation（非破壊）が担い、盤を書き換えるのはここだけ。
## 呼び手は MatchController.execute_formation（とテスト）。BattleState は呼ばない＝盤を書き換える側はここだけ。
## 詳細 → doc/gdd/formations.md, doc/gdd/skills.md

## 陣形スキルを解決して盤に適用する。option＝Formation.available_for の1要素。
## target＝着弾中心（buff では無視）。参加ユニットは行動完了。詳細 → doc/gdd/formations.md
## origin＝発動者がこのターン移動を始めたマス。着弾後に発動者を戻すレシピ（バックスタブ＝
## return_to_origin）だけが読む。移動していなければ渡さない＝その場に留まる（呼び手＝MatchController が覚えている）。
## 成功なら SkillResult（着弾ごとの損害・光らせる面・発動者のスナップショット）、
## 不正（ターン違い・行動済み・射程外）なら null。
static func resolve(state: BattleState, option: FormationOption, target: Vector2i,
		origin := Formation.NO_HEX) -> SkillResult:
	# 妥当性: 参加者が現ターン・生存していること、まだ行動を使い切っていないこと（待機・攻撃済み
	# でない）、target が射程内であること。行ける先が無いだけの駒は参加できる＝発動に移動先も
	# 攻撃相手も要らない（Formation.available_for と同じ資格）。
	for pid in option.participants:
		var p := state.unit_by_handle(pid)
		if p == null or p.team != state.current_team:
			return null
		if not state.has_action_left(pid):
			return null
	if not Formation.can_target(state, option, target):
		return null
	var out := SkillResult.new()
	out.skill = option.skill
	out.caster_id = option.caster_id
	out.participants = option.participants.duplicate()
	out.center = target
	# 効果対象が1体のユニットスキルは演出シーンに乗る（→ doc/tech/combat_scene.md）。
	# 兵数が動かない＝着弾も撃破も起きないので、内訳は hits ではなく専用の1件（cast）で渡す。
	# 発動前に撮る＝戦闘の結果（戦闘前スナップショット）と同じ流儀。
	var skill_scope := option.scope == FormationOption.Scope.UNIT
	var cast := _skill_cast(state, option, target) if skill_scope else null
	var spawn_cells: Array[Vector2i] = []  # 分裂で出た位置（cells に載せて盤で光らせる）
	# レポートの見出し・攻撃列に出す発動者（発動前に固める＝attack のスナップショットと同じ流儀。
	# 兵数は動かないので troops_after は troops_before のまま）。詳細 → doc/tech/combat_scene.md
	var caster := state.unit_by_handle(option.caster_id)
	if caster != null:
		out.caster = state.unit_snapshot(caster)
	match option.effect:
		# バフ系（グレイス）は着弾ではなく状態補正エントリを積む（ダメージ処理は空回り＝hits空）。
		# 損害の出ないレシピの効果表示用に、積んだエントリを result にも載せる（レポートが読む）。
		FormationOption.Effect.BUFF:
			var entry := _buff_entry(state, option, target)
			state.add_status_mod(entry)
			out.status = entry
			if cast != null:
				cast.op = String(entry.get("op", "mul"))
				cast.value = float(entry.get("value", 0.0))
				cast.buff_target = String(entry.get("target", "both"))
				cast.kind = String(entry.get("kind", StatusMod.KIND_BUFF))
		# ピュリファイは積むのではなく落とす。同じく着弾は起きない＝hits空。
		FormationOption.Effect.CLEANSE:
			var cleansed := state.unit_at(target)  # can_target が味方の存在を保証済み
			if cleansed != null:
				var dropped := state.clear_debuffs(cleansed)
				if cast != null:
					cast.cleansed = dropped
		# スライムスプリットは隣接する空きマスへ発動者の複製を1体置く。
		# 着弾・兵数変化は起きない。分裂で出た位置は cells で盤に返す＝光らせる。詳細 → doc/gdd/skills.md
		FormationOption.Effect.SPAWN:
			var spawned := state.spawn_unit(option.caster_id)
			if spawned != null:
				spawn_cells.append(spawned.pos)
		# ポイズンスティングは補正値を積むのではなく、持続の間ターン開始に兵数を減らすエントリを
		# 置く。掛けた瞬間には減らない＝最初に減るのは次の対象ターン開始。詳細 → doc/gdd/skills.md
		FormationOption.Effect.DOT:
			var dot := _dot_entry(state, option, target)
			state.add_status_mod(dot)
			out.status = dot
			if cast != null:
				cast.dot_troops = int(dot.get("value", 0))
				cast.kind = String(dot.get("kind", StatusMod.KIND_DEBUFF))
	# 着弾内訳は戦闘前の盤で確定（決定的＝attack と同じ流儀）。
	var pv := Formation.preview(state, option, target)
	for hit: HitDetail in pv["hits"]:
		var victim := state.unit_by_handle(hit.target_id)
		if victim == null:
			continue
		var h := SkillHit.new()
		h.target_id = victim.handle
		h.hex = victim.pos  # 撃破すると盤から外れる＝消える前に控える（演出が当たった場所を出す）
		h.victim = state.unit_snapshot(victim)  # 撃破で盤から消えてもレポートに名前と兵数を出せるよう固める
		h.loss = hit.loss
		h.detail = hit
		victim.take_loss(hit.loss)  # シールドから先に減る（兵数が減る唯一の入口）。詳細 → doc/gdd/combat.md
		h.killed = victim.troops <= 0
		h.victim.troops_after = victim.troops
		h.victim.shield_after = victim.shield
		state.mark_engaged(victim.handle)  # 被弾＝起動トリガー（待ち伏せAIが立つ）
		if h.killed:
			state.remove_unit(victim.handle)
		out.hits.append(h)
	# レベル: attack と同じ「戦ったら+1・倒したらさらに+1」を陣形1発の単位で（面で複数撃破でも+2止まり）。
	# 対象に1体も当たらなかった空撃ちは0（戦っていない＝上がらない）。
	var any_killed := false
	for h in out.hits:
		if h.killed:
			any_killed = true
			break
	var exp_gain := 0
	if not out.hits.is_empty():
		exp_gain = 1 + (1 if any_killed else 0)
	elif skill_scope:
		# ユニットスキルは撃破が起きないので前半（戦ったら+1）だけが乗る。詳細 → doc/gdd/skills.md
		exp_gain = 1
	# 参加者は行動完了（1体は1ターンに1つの陣形スキルにのみ参加）＋レベル加算。
	for pid in option.participants:
		var p := state.unit_by_handle(pid)
		if p != null:
			p.gain_level(exp_gain)
		state.set_done(pid)
		state.mark_engaged(pid)
	# チャージが必要なレシピは発動後に 0 に戻す（→ doc/gdd/skills.md 共通ルール）。
	if option.charge_turns > 0:
		state.set_charge(option.caster_id, option.skill, 0)
	# 演出が要る情報を添える（→ doc/gdd/formations.md 発動の演出）。着弾中心と面は駒の有無に
	# よらない＝空hexも光らせて面の広さを見せるため、hits ではなくレシピの形から出す。
	# 扇（ドラゴンブレス）は発動者の位置で向きが決まる＝発動前に控えた caster を渡す（撃破されない＝盤に居る）。
	out.cells = Formation.blast_cells(option, target, caster.pos if caster != null else Formation.NO_HEX)
	out.cells.append_array(spawn_cells)  # 分裂で出た位置も光らせる（→ doc/gdd/skills.md スライムスプリット）
	out.cast = cast
	# バックスタブ＝着弾を済ませてから発動者をこのターンの移動開始位置へ戻す（刺して消える）。
	# 威力・支援・地形は戻す前の位置（刺した位置）で確定している＝順番はここで最後。
	# 戻りは経路・移動コスト・足止めを問わない＝盤の位置だけを書き換える。占領は起きない
	# （そのマスにはこのターンの頭から立っていた）。詳細 → doc/gdd/formations.md バックスタブ
	if option.return_to_origin and origin != Formation.NO_HEX and caster != null:
		caster.pos = origin
		out.caster_returned_to = origin
	return out

## 効果対象が1体のユニットスキルの演出用内訳（発動前に撮る）。発動者と対象のスナップショットに、
## レシピの情報（表示名・エフェクトID）を添える。乗った補正の値は呼び出し側が足す。
## 兵数は動かないので troops_after は troops_before のまま＝戦闘の結果と器を揃える。
## 詳細 → doc/tech/combat_scene.md ユニットスキルの演出
static func _skill_cast(state: BattleState, option: FormationOption, target: Vector2i) -> SkillCast:
	var c := SkillCast.new()
	c.skill = option.skill
	c.name = option.name
	c.effect = option.effect_id()
	c.combat_effect = option.combat_effect
	var caster := state.unit_by_handle(option.caster_id)
	var victim := state.unit_at(target)
	if caster != null:
		c.caster = state.unit_snapshot(caster)
	if victim != null:
		c.target = state.unit_snapshot(victim)
	return c

## 継続ダメージ（ポイズンスティング）の状態補正エントリを組む。値は「1ターンに減る兵数」で、
## 攻防の補正チェーンには参加しない（op が "dot"＝StatusMod.aggregate が読み飛ばす）。持続の数え方と
## ピュリファイでの解除は他の弱体と同じ器に相乗りする。詳細 → doc/gdd/skills.md
static func _dot_entry(state: BattleState, option: FormationOption, target: Vector2i) -> Dictionary:
	var u := state.unit_at(target)  # can_target が対象の存在と陣営を保証済み
	return {
		"scope": "unit",
		"handle": u.handle if u != null else -1,
		"owner_team": state.current_team,
		"op": StatusMod.OP_DOT,
		"value": option.dot_troops,
		"remaining": option.duration_turns,
		"skill": option.skill,  # 表示名は読む側が skill.<id>.name を引く（domain は表示文字列を持たない）
		"fx": option.buff_fx,
		"kind": option.buff_kind,
	}

## バフ系レシピの状態補正エントリを組む。掛かる範囲は4通り＝陣営全体（グレイス）／参加者だけ
## （シールドウォール＝列に並んだ駒・カウンター＝隣り合う2体）／対象1体（ユニットスキル＝scope UNIT・target のhexに居る駒。
## 味方＝ピクシーダスト／敵＝ドレッドタッチ）／地帯（マジックシールド＝発動者を中心とした結界）。
## 詳細 → doc/gdd/formations.md, doc/gdd/skills.md
static func _buff_entry(state: BattleState, option: FormationOption, target: Vector2i) -> Dictionary:
	# 発動者の兵1人あたりで効くレシピ（ピクシーダスト・ドレッドタッチ）は、発動時の残兵数を掛けて
	# 値を焼き込む。以後は発動者と切り離される＝掛けた側が損耗しても倒されても補正は変わらない。
	# 弱体は負値（ドレッドタッチ＝-10/兵）なので、0 以外かどうかで判定する。
	var value := option.buff_value
	if not is_zero_approx(option.buff_value_per_troop):
		var caster := state.unit_by_handle(option.caster_id)
		value = option.buff_value_per_troop * float(caster.troops if caster != null else 0)
	# 参加人数で伸びるレシピ（グレイス・シールドウォール）は、基準人数（min_count）を超えた
	# 参加者1体ごとに加算する。グレイス＝5体 ×1.30／6体 ×1.35／8体 ×1.45、シールドウォール＝3体 ×1.15／4体 ×1.20。
	# 発動時の人数で焼き込む＝以後クラスタや列が崩れても変わらない。
	if not is_zero_approx(option.buff_value_per_extra):
		var extra := option.participants.size() - option.min_count
		value += option.buff_value_per_extra * float(maxi(extra, 0))
	var e := {
		"owner_team": state.current_team,
		"op": option.buff_op,
		"target": option.buff_target,
		"value": value,
		"remaining": option.duration_turns,
		"skill": option.skill,  # 表示名は読む側が skill.<id>.name を引く（domain は表示文字列を持たない）
		"fx": option.buff_fx,  # 盤の見た目（presentation が読む。空＝見た目なし）
		# 強化か弱体か。ピュリファイが落とす対象と盤の見た目をこれで決める＝値の符号から推測しない。
		"kind": option.buff_kind,
	}
	if option.scope == FormationOption.Scope.UNIT:
		var u := state.unit_at(target)  # can_target が対象の存在と陣営を保証済み
		e["scope"] = "unit"
		e["handle"] = u.handle if u != null else -1
	elif option.scope == FormationOption.Scope.ZONE:
		# マジックシールド＝発動者を中心とした結界。ここだけは効く相手を発動時に固めない
		# ＝そのとき中に居る味方に効く（入れば効き、出れば切れる）。固めるのは中心と値だけで、
		# 中心は発動者の位置＝発動者がこのあと動いても結界は動かない。
		var c := state.unit_by_handle(option.caster_id)
		var center := c.pos if c != null else target
		e["scope"] = "zone"
		e["team"] = state.current_team
		e["q"] = center.x
		e["r"] = center.y
		e["radius"] = option.zone_radius
		# 貫通無効は攻防の値ではない＝集計の外で combat の貫通の段が読む。
		if option.pierce_immune:
			e["pierce_immune"] = true
	elif option.scope == FormationOption.Scope.PARTICIPANTS:
		# シールドウォール＝列に並んだ参加者だけ／カウンター＝組んだ2体だけ。発動時の顔ぶれで
		# 固める＝このあと列や組が崩れても、掛かった相手も値も変わらない（人数で伸びる値の焼き込みと同じ流儀）。
		e["scope"] = "participants"
		e["handles"] = option.participants.duplicate()
	else:
		e["scope"] = "team"
		e["team"] = state.current_team
	return e
