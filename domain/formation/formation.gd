extends RefCounted
class_name Formation
## 陣形スキル（純ロジック・Node非依存）。配置レシピの検出とダメージ計算。
## 発動＝プレイヤーの明示操作／参加ユニットは行動完了（適用は BattleState.resolve_formation）。
## Combat と同じく非破壊（盤は書き換えない）＝検出・威力の計算だけを担う。
## 詳細 → doc/gdd/formations.md, doc/gdd/combat.md §2
##
## ①トリニティスペル(area)＋③ディバインジャッジメント(single)＝ダメージ系／②ホーリーアリア(buff)＝状態補正（乗算・全体・持続）。
## 3レシピとも解禁済み（IMPLEMENTED_EFFECTS）。buff は BattleState が状態補正エントリを積む（doc/gdd/combat.md）。
##
## 【暫定の戦闘セマンティクス（数値チューニングは formations.md §未決）】
## - 威力＝発動者1体の実効攻撃力（兵数×攻撃力×レベル×包囲×地形）を面の各ヘックスに当てる。間接扱い＝melee=false で支援は乗らない。
## - 防御側は包囲が乗る（surround_factor）。貫通は発動者(leader)の性質を使う（①魔法兵0.5／③聖職0）。
## - 対象は面内の全ユニット（敵味方問わず＝フレンドリーファイア。誤爆＝配置の読み合い）。ただし発動者自身は除外（詠唱の源＝自傷しない）。
## - 参加者は Lv+1（撃破が1体でもあれば+2・空撃ちは0）＝適用は BattleState.resolve_formation。

## レシピ定義（当面ハードコード。将来 CSV/JSON 化）。
## leader_skins＝発動者になれるスキン ／ member_skins＝残りの参加者のスキン。
## 照合は skin_id（未指定なら type_id へフォールバック）＝ _matches。詳細 → doc/gdd/formations.md
## shape: "triangle"（count 体が相互隣接）／"cluster"（count 体以上の隣接クラスタ）。
## effect: "area"（中心＋周囲6の7hex）／"single"／"buff"。
## range_from: "any"（参加者のどれからでも射程判定）／"leader"（発動者から）。
const RECIPES := {
	"trinity_spell": {
		"name": "トリニティスペル",
		"leader_skins": ["wizard", "witch"],
		"member_skins": ["wizard", "witch"],
		"shape": "triangle",
		"count": 3,
		"effect": "area",
		"radius": 1,
		"range": 5,
		"range_from": "any",
	},
	"divine_judgment": {
		"name": "ディバインジャッジメント",
		"leader_skins": ["paladin"],
		"member_skins": ["cleric", "priest", "bishop"],
		"shape": "triangle",
		"count": 3,
		"effect": "single",
		"range": 10,
		"range_from": "leader",
	},
	"holy_aria": {
		"name": "ホーリーアリア",
		"leader_skins": ["cleric", "priest", "bishop"],
		"member_skins": ["cleric", "priest", "bishop"],
		"shape": "cluster",
		"count": 5,
		"effect": "buff",
		"buff_op": "mul",
		"buff_value": 1.3,
		"buff_fx": "aura",  # 盤全体の見た目（外周から差し込む金の光）。詳細 → doc/gdd/formations.md
		"duration_turns": 1,  # 自軍ターン1回＋間の敵ターン＝1ターン。詳細 → doc/gdd/map.md 用語・ターン
	},
	# ユニットスキル＝参加者が発動者だけ(shape="solo")・効果を味方1体に乗せる(buff_scope="unit")。
	# 仕組みは陣形と共通で、カタログだけ分けている。詳細 → doc/gdd/skills.md
	"pixie_dust": {
		"name": "ピクシーダスト",
		"leader_skins": ["pixie"],
		"member_skins": [],
		"shape": "solo",
		"count": 1,
		"effect": "buff",
		"buff_scope": "unit",
		"buff_op": "add",  # 実効攻防への加算（レベル・包囲・地形の補正は乗らない）
		# 発動したピクシー1兵あたりの加算量。発動時の残兵数を掛けた値を焼き込む＝以後ピクシーが
		# 損耗しても倒されても、掛かった補正は変わらない。詳細 → doc/gdd/skills.md
		"buff_value_per_troop": 10.0,
		"buff_target": "both",
		"buff_fx": "dust",  # 盤の見た目（掛かっている駒の足元を光らせる）。空＝見た目なし
		"duration_turns": 3,  # 発動側ターン3回ぶん。詳細 → doc/gdd/skills.md
		"range": 1,  # 自分(0)＋隣接(1)
		"range_from": "leader",
	},
	"purify": {
		"name": "ピュリファイ",
		"leader_skins": ["cleric", "priest", "bishop"],
		"member_skins": [],
		"shape": "solo",
		"count": 1,
		# 状態補正を積むのではなく落とす＝値を持たない。詳細 → doc/gdd/skills.md
		"effect": "cleanse",
		"buff_scope": "unit",  # 対象1体（自分＋隣接）
		"buff_side": "ally",
		"range": 1,
		"range_from": "leader",
	},
	"dread_touch": {
		"name": "ドレッドタッチ",
		"leader_skins": ["ghost"],
		"member_skins": [],
		"shape": "solo",
		"count": 1,
		"effect": "buff",
		"buff_scope": "unit",
		"buff_side": "enemy",  # 対象は敵1体（ピクシーダストは味方＝"ally"）。詳細 → doc/gdd/skills.md
		"buff_op": "add",
		# ピクシーダストと同じ形の負値＝発動時のゴーストの残兵数を掛けて焼き込む（満員8体で -80）。
		"buff_value_per_troop": -10.0,
		"buff_target": "both",
		"buff_fx": "dread",
		"buff_kind": "debuff",  # 強化か弱体か。ピュリファイが落とす対象・盤の見た目。値の符号からは判断しない
		"duration_turns": 3,  # 発動側ターン3回ぶん。詳細 → doc/gdd/skills.md
		"range": 1,
		"range_from": "leader",
	},
	"venom_fang": {
		"name": "ヴェノムファング",
		"leader_skins": ["rock_serpent"],
		"member_skins": [],
		"shape": "solo",
		"count": 1,
		"effect": "buff",
		"buff_scope": "unit",
		"buff_side": "enemy",
		"buff_op": "mul",
		# 固定係数 0.9＝1本で攻防10%減。重ねると掛け合わさる（2本で0.81・3本で0.73）。
		# ドレッドタッチの残兵依存（add）と違い、兵数に依らない。詳細 → doc/gdd/skills.md
		"buff_value": 0.9,
		"buff_target": "both",
		"buff_fx": "venom",
		"buff_kind": "debuff",
		"duration_turns": 3,  # 発動側ターン3回ぶん。詳細 → doc/gdd/skills.md
		"range": 1,
		"range_from": "leader",
	},
	"slime_split": {
		"name": "スライムスプリット",
		"leader_skins": ["slime"],
		"member_skins": [],
		"shape": "solo",
		"count": 1,
		# 駒を盤に追加する効果。状態補正ではない。対象選択なし（隣接する空きマスへ自動配置）。
		# 発動者の複製を1体生成し、兵数は発動時点の発動者の兵数を引き継ぐ。max_troops は type の既定値。
		# 詳細 → doc/gdd/skills.md
		"effect": "spawn",
		"range": 0,  # 自分の隣接に湧く＝対象選択は不要
		"range_from": "leader",
		"charge_turns": 3,  # 盤に出た直後は撃てない。3ターン溜めてから発動。詳細 → doc/gdd/skills.md
	},
}

## 適用まで実装済みの効果。未対応はメニューに出さない。
const IMPLEMENTED_EFFECTS := ["area", "single", "buff", "cleanse", "spawn"]

## 「発動者の位置を仮定しない」番兵（盤の外）。available_for / can_target / targetable_cells の
## from_hex に渡さなければこれ＝発動者は盤の上の実位置に居るものとして判定する。
const NO_HEX := Vector2i(1 << 30, 1 << 30)

## そのレシピがユニットスキル（単独発動＝shape "solo"）か。カタログ上の区別で、仕組みは共通。
## 演出・効果音の出し分けが読む（陣形はカットインあり／ユニットスキルは音だけ）。
static func is_unit_skill(recipe_id: String) -> bool:
	var r: Dictionary = RECIPES.get(recipe_id, {})
	return String(r.get("shape", "")) == "solo"

## 選択中 unit が発動できる、盤上で成立済みのレシピ選択肢一覧（読み取りのみ・非破壊）。
## 各要素＝ _option の dict（recipe/participants/needs_target/range 等）。
## from_hex＝発動者がそこに居ると仮定して成立を見る（移動を確定する前のコマンドメニュー用）。
## 発動者は移動してから発動してよい＝隣接の判定は移動先で行う。詳細 → doc/gdd/formations.md
static func available_for(state: BattleState, unit: Unit, from_hex := NO_HEX) -> Array:
	var out: Array = []
	if unit == null:
		return out
	var lead_pos := unit.pos if from_hex == NO_HEX else from_hex
	for rid in RECIPES:
		var r: Dictionary = RECIPES[rid]
		if not (r["effect"] in IMPLEMENTED_EFFECTS):
			continue
		if not _matches(unit, r["leader_skins"]):
			continue
		# 参加資格は陣形もユニットスキルも「行動を使い切っていない」（待機・攻撃済みでない）。
		# 行ける先が無いだけの駒は参加できる＝発動に移動先も攻撃相手も要らない。
		if not state.has_action_left(unit.id):
			continue
		# チャージが必要なレシピは、溜まっていなければ不成立。詳細 → doc/gdd/skills.md
		var ct := int(r.get("charge_turns", 0))
		if ct > 0 and state.get_charge(unit.id, rid) < ct:
			continue
		match String(r["shape"]):
			"triangle":
				for members in _triangle_sets(state, unit, r, lead_pos):
					out.append(_option(rid, r, [unit, members[0], members[1]]))
			"solo":
				# spawn は隣接に空きマス（盤内かつ駒が居ない）が無ければ成立しない
				if String(r["effect"]) == "spawn":
					var has_empty := false
					for nb in Hex.neighbors(lead_pos):
						if state.in_field(nb) and state.unit_at(nb) == null:
							has_empty = true
							break
					if not has_empty:
						continue
				out.append(_option(rid, r, [unit]))  # ユニットスキル＝発動者だけで成立
			"cluster":
				var members := _cluster(state, unit, r, lead_pos)
				if not members.is_empty():
					var ordered: Array = [unit]  # 発動者を先頭に（leader_id 用）
					for m in members:
						if m.id != unit.id:
							ordered.append(m)
					out.append(_option(rid, r, ordered))
	return out

## target を着弾中心としたときの効果プレビュー（純ロジック・非破壊）。
## 対象ごとの hit 内訳（Combat.hit_from_breakdowns 形式＋target_id）を返す。適用は resolve_formation。
static func preview(state: BattleState, option: Dictionary, target: Vector2i) -> Dictionary:
	var hits: Array = []
	var participants: Array = option["participants"]
	for hx in blast_cells(option, target):
		var victim := state.unit_at(hx)
		if victim != null and not (victim.id in participants):
			hits.append(_formation_hit(state, option, victim))
	return {"recipe": option["recipe"], "hits": hits}

## 着弾する面＝効果が及ぶヘックス（駒の有無によらない）。着弾の無いもの（バフ・解除）は空。
## 盤の演出が「どこに当たったか」を光らせるのに使う。詳細 → doc/gdd/formations.md 発動の演出
static func blast_cells(option: Dictionary, target: Vector2i) -> Array[Vector2i]:
	match String(option["effect"]):
		"area":
			return Hex.within_range(target, int(option.get("radius", 0)))
		"single":
			return [target] as Array[Vector2i]
	return [] as Array[Vector2i]

## target が発動条件の射程内か（"any"＝参加者のどれか／"leader"＝発動者から）。
## from_hex＝発動者がそこに居ると仮定する（移動を確定する前の判定）。省略すると盤の実位置。
static func can_target(state: BattleState, option: Dictionary, target: Vector2i, from_hex := NO_HEX) -> bool:
	if not bool(option["needs_target"]):
		return true
	var rng := int(option["range"])
	var lead_id := int(option["leader_id"])
	var leader := state.unit_by_id(lead_id)
	var within := false
	if String(option["range_from"]) == "any":
		for pid in option["participants"]:
			var p := state.unit_by_id(int(pid))
			if p == null:
				continue
			var ppos := from_hex if (from_hex != NO_HEX and p.id == lead_id) else p.pos
			if Hex.distance(ppos, target) <= rng:
				within = true
				break
	elif from_hex != NO_HEX:
		within = Hex.distance(from_hex, target) <= rng
	else:
		within = leader != null and Hex.distance(leader.pos, target) <= rng
	if not within:
		return false
	# 対象1体のスキルは駒の居るhexだけ＝空撃ちさせない。味方に掛けるもの（ピクシーダスト）は発動者
	# 自身も選べ、敵を弱らせるもの（ドレッドタッチ）は敵だけを選べる。詳細 → doc/gdd/skills.md
	if String(option.get("buff_scope", "")) == "unit":
		var u := _unit_at_assumed(state, leader, from_hex, target)
		if u == null or leader == null:
			return false
		var same_team := u.team == leader.team
		if String(option.get("buff_side", "ally")) == "enemy":
			return not same_team
		return same_team
	return true

## option の着弾中心に選べるhex（発動条件の射程内・盤上）。空＝いま撃てる先が無い＝コマンド
## メニューでは項目を無効化する（→ doc/gdd/uiux.md 「できない操作は選べない」）。
## from_hex＝発動者がそこに居ると仮定する（移動を確定する前のメニュー判定）。省略すると実位置。
## single（単体狙撃）は「参加者以外の駒が居るhex」だけ＝空撃ちさせない。area（面）は地面にも撃てる。
## 陣営の絞り込み（味方向き／敵向き）は can_target が持つ＝ここには二重に書かない。
static func targetable_cells(state: BattleState, option: Dictionary, from_hex := NO_HEX) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not bool(option["needs_target"]):
		return out
	var leader := state.unit_by_id(int(option["leader_id"]))
	var single := String(option["effect"]) == "single"
	var participants: Array = option["participants"]
	for h in _in_range_cells(state, option, from_hex):
		if not can_target(state, option, h, from_hex):
			continue
		if single:
			var u := _unit_at_assumed(state, leader, from_hex, h)
			if u == null or u.id in participants:
				continue
		out.append(h)
	return out

# --- 内部 ---

## unit がレシピの候補スキン列に当てはまるか。照合は skin_id、未指定なら type_id へフォールバック。
## 見た目が違えば別ユニット＝種別が同じでもゴブリンでホーリーアリアは成立しない。
## 詳細 → doc/gdd/formations.md
static func _matches(unit: Unit, skins: Array) -> bool:
	var key := unit.skin_id if unit.skin_id != "" else unit.type_id
	return key in skins

## from_hex に発動者が居ると仮定したときの hex の駒。移動を確定する前は盤の上の発動者がまだ
## 元のマスに立っているので、そこを空として読み替える（自分に掛けるスキルの対象判定に効く）。
static func _unit_at_assumed(state: BattleState, leader: Unit, from_hex: Vector2i, hex: Vector2i) -> Unit:
	if leader != null and from_hex != NO_HEX:
		if hex == from_hex:
			return leader
		if hex == leader.pos:
			return null
	return state.unit_at(hex)

## 射程内かつ盤上のhex（重複なし）。起点は "any" なら参加者ぜんぶ／"leader" なら発動者だけ。
static func _in_range_cells(state: BattleState, option: Dictionary, from_hex: Vector2i) -> Array[Vector2i]:
	var rng := int(option["range"])
	var lead_id := int(option["leader_id"])
	var origins: Array[Vector2i] = []
	if String(option["range_from"]) == "any":
		for pid in option["participants"]:
			var p := state.unit_by_id(int(pid))
			if p != null:
				origins.append(from_hex if (from_hex != NO_HEX and p.id == lead_id) else p.pos)
	elif from_hex != NO_HEX:
		origins.append(from_hex)
	else:
		var leader := state.unit_by_id(lead_id)
		if leader != null:
			origins.append(leader.pos)
	var seen := {}
	var out: Array[Vector2i] = []
	for o in origins:
		for h in Hex.within_range(o, rng):
			if not seen.has(h) and state.in_field(h):
				seen[h] = true
				out.append(h)
	return out

## leader（lead_pos に居るものとする）に隣接する member_skins の候補（同陣営・未行動）から、
## 互いに隣接する2体組を全列挙。lead_pos は移動先のこともある＝発動者だけ仮の位置で測る。
static func _triangle_sets(state: BattleState, leader: Unit, r: Dictionary, lead_pos: Vector2i) -> Array:
	var cand: Array[Unit] = []
	for u in state.units():
		if u.id == leader.id or u.team != leader.team or not state.has_action_left(u.id):
			continue
		if not _matches(u, r["member_skins"]):
			continue
		if Hex.distance(u.pos, lead_pos) == 1:
			cand.append(u)
	var sets: Array = []
	for i in cand.size():
		for j in range(i + 1, cand.size()):
			if Hex.distance(cand[i].pos, cand[j].pos) == 1:
				sets.append([cand[i], cand[j]])
	return sets

## leader を含む member_skins の隣接連結成分（同陣営・未行動）を返す。size < count なら空＝不成立。
## ②ホーリーアリア＝占領兵が count 体以上「固まっていれば」成立（形は不問）。参加者＝クラスタ全員。
## leader は lead_pos に居るものとする（移動先のこともある）＝探索は位置で持ち回る。
static func _cluster(state: BattleState, leader: Unit, r: Dictionary, lead_pos: Vector2i) -> Array:
	var seen := {leader.id: leader}
	var frontier: Array[Vector2i] = [lead_pos]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_back()
		for u in state.units():
			if seen.has(u.id) or u.team != leader.team or not state.has_action_left(u.id):
				continue
			if not _matches(u, r["member_skins"]):
				continue
			if Hex.distance(u.pos, cur) == 1:
				seen[u.id] = u
				frontier.append(u.pos)
	if seen.size() < int(r["count"]):
		return []
	return seen.values()

## 参加ユニット配列（先頭＝発動者）から選択肢 dict を組む。
static func _option(rid: String, r: Dictionary, participants: Array) -> Dictionary:
	var ids: Array[int] = []
	for u in participants:
		ids.append(u.id)
	var effect := String(r["effect"])
	var buff_scope := String(r.get("buff_scope", "team"))
	var opt := {
		"recipe": rid,
		"name": String(r["name"]),
		"leader_id": participants[0].id,
		"participants": ids,
		"effect": effect,
		# ユニットスキル（単独発動）と陣形スキル（複数人）の区別。表示ラベルの出し分けに使う。
		# 発動者が移動してから撃てるのは両方とも同じ＝ここでは分けない。詳細 → doc/gdd/formations.md
		"kind": "skill" if String(r["shape"]) == "solo" else "formation",
		# 対象1体のバフ（ユニットスキル）は掛ける相手を選ぶ＝陣営全体バフと違って対象指定が要る。
		"needs_target": effect in ["area", "single"] or buff_scope == "unit",
		"range": int(r.get("range", 0)),
		"range_from": String(r.get("range_from", "leader")),
		"radius": int(r.get("radius", 0)),
	}
	# 対象の絞り込みは効果の種類と独立に載せる（積む buff も落とす cleanse も同じ選び方をする）。
	opt["buff_scope"] = buff_scope
	# 対象1体のスキルが味方向きか敵向きか（can_target の絞り込み）。既定は味方。
	opt["buff_side"] = String(r.get("buff_side", "ally"))
	# ユニットスキルの演出シーンで使うエフェクトID。空＝発動者スキンの combat_effect へ落ちる
	# （presentation 側で解決）。エフェクトの単位を「誰が撃ったか」ではなく「何を撃ったか」にする列＝
	# ピュリファイはクレリックが撃ってもビショップが撃っても同じ絵になる。詳細 → doc/gdd/skills.md 実装方針
	# 陣形の盤の着弾はこれを見ない（レシピ専用の絵を規約解決する → doc/gdd/formations.md 発動の演出）。
	opt["combat_effect"] = String(r.get("combat_effect", ""))
	if effect == "buff":  # 状態補正の値を option に載せる（BattleState._buff_entry が読む）
		# 強化か弱体か（ピュリファイが落とす対象・盤の見た目）。値の符号から推測しない＝レシピが明示する。
		opt["buff_kind"] = String(r.get("buff_kind", StatusMod.KIND_BUFF))
		opt["buff_op"] = String(r.get("buff_op", "mul"))
		opt["buff_value"] = float(r.get("buff_value", 1.0))
		opt["buff_value_per_troop"] = float(r.get("buff_value_per_troop", 0.0))
		opt["buff_fx"] = String(r.get("buff_fx", ""))
		opt["buff_target"] = String(r.get("buff_target", "both"))
		opt["duration_turns"] = int(r.get("duration_turns", 1))
	return opt

## victim 1体への陣形ダメージ内訳（発動者1体の実効攻撃力・間接扱い）。非破壊。
## 威力＝発動者(leader)1体ぶんの実効攻撃力を面内の各ヘックスに当てる（合算しない）。
## 面の広さ（最大7hex）そのものが強み。合算は割合式が飽和してオーバーキルのため見送り（旧feature-11）。
## 参加3体は発動コスト＝行動完了で消費し、威力には積まない。
static func _formation_hit(state: BattleState, option: Dictionary, victim: Unit) -> Dictionary:
	var leader := state.unit_by_id(int(option["leader_id"]))
	# 間接扱い＝melee=false（支援は乗らない）。発動者の実効攻撃力（兵数×攻撃力×レベル×包囲×地形）。
	var atk := float(Combat.attack_breakdown(state, leader, victim, false)["total"])
	var synth_atk := {"kind": "attack", "total": atk}
	# 防御側: 包囲は乗る（victim の surround が defense_breakdown に入る）／貫通は発動者の性質／支援なし。
	var df := Combat.defense_breakdown(state, victim, leader, false)
	var hit := Combat.hit_from_breakdowns(synth_atk, df, victim.troops)
	hit["target_id"] = victim.id
	return hit
