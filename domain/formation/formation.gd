extends RefCounted
class_name Formation
## 陣形スキル（純ロジック・Node非依存）。配置レシピの検出とダメージ計算。
## 発動＝プレイヤーの明示操作／参加ユニットは行動完了（適用は BattleState.resolve_formation）。
## Combat と同じく非破壊（盤は書き換えない）＝検出・威力の計算だけを担う。
## 詳細 → doc/gdd/formations.md, doc/gdd/combat.md §2
##
## スライスA: フレームワーク＋①三重詠唱（effect="area"）。②③はレシピ定義のみで、
## 効果解決は B(single)/C(buff) で解禁する（IMPLEMENTED_EFFECTS でメニュー提示を絞る）。
##
## 【暫定の戦闘セマンティクス（数値チューニングは formations.md §未決）】
## - 威力＝参加者の実効攻撃力の合算（各自の兵数×攻撃力×経験×包囲×地形）。間接扱い＝melee=false で支援は乗らない。
## - 防御側は包囲が乗る（surround_factor）。貫通は発動者(leader)の性質を使う（①魔法兵0.5／③聖職0）。
## - 対象は敵のみ（味方は巻き込まない）。参加者は経験値+1（撃破が1体でもあれば+2・空撃ちは0）＝適用は BattleState.resolve_formation。

## レシピ定義（当面ハードコード。将来 CSV/JSON 化）。
## leader_types＝発動者になれる type ／ member_types＝残りの参加者の type。
## shape: "triangle"（count 体が相互隣接）／"cluster"（count 体以上の隣接クラスタ）。
## effect: "area"（中心＋周囲6の7hex）／"single"／"buff"。
## range_from: "any"（参加者のどれからでも射程判定）／"leader"（発動者から）。
const RECIPES := {
	"trinity": {
		"name": "三重詠唱",
		"leader_types": ["wizard", "witch"],
		"member_types": ["wizard", "witch"],
		"shape": "triangle",
		"count": 3,
		"effect": "area",
		"radius": 1,
		"range": 5,
		"range_from": "any",
	},
	"divine_judgment": {
		"name": "神の裁き",
		"leader_types": ["paladin"],
		"member_types": ["cleric", "priest", "bishop"],
		"shape": "triangle",
		"count": 3,
		"effect": "single",
		"range": 10,
		"range_from": "leader",
	},
	"holy_aria": {
		"name": "ホーリーアリア",
		"leader_types": ["cleric", "priest", "bishop"],
		"member_types": ["cleric", "priest", "bishop"],
		"shape": "cluster",
		"count": 5,
		"effect": "buff",
		"buff_mult": 1.3,
		"duration_turns": 2,
	},
}

## スライスAで適用まで実装済みの効果。未対応はメニューに出さない（B/Cで解禁）。
const IMPLEMENTED_EFFECTS := ["area"]

## 選択中 unit が発動できる、盤上で成立済みのレシピ選択肢一覧（読み取りのみ・非破壊）。
## 各要素＝ _option の dict（recipe/participants/needs_target/range 等）。
static func available_for(state: BattleState, unit: Unit) -> Array:
	var out: Array = []
	if unit == null or state.is_done(unit.id):
		return out
	for rid in RECIPES:
		var r: Dictionary = RECIPES[rid]
		if not (r["effect"] in IMPLEMENTED_EFFECTS):
			continue
		if not (unit.type_id in r["leader_types"]):
			continue
		match String(r["shape"]):
			"triangle":
				for members in _triangle_sets(state, unit, r):
					out.append(_option(rid, r, [unit, members[0], members[1]]))
			"cluster":
				pass  # スライスC
	return out

## target を着弾中心としたときの効果プレビュー（純ロジック・非破壊）。
## 対象ごとの hit 内訳（Combat.hit_from_breakdowns 形式＋target_id）を返す。適用は resolve_formation。
static func preview(state: BattleState, option: Dictionary, target: Vector2i) -> Dictionary:
	var hits: Array = []
	var team := _leader_team(state, option)
	match String(option["effect"]):
		"area":
			for hx in Hex.within_range(target, int(option["radius"])):
				var victim := state.unit_at(hx)
				if victim != null and victim.team != team:
					hits.append(_formation_hit(state, option, victim))
		"single":
			var victim := state.unit_at(target)
			if victim != null and victim.team != team:
				hits.append(_formation_hit(state, option, victim))
	return {"recipe": option["recipe"], "hits": hits}

## target が発動条件の射程内か（"any"＝参加者のどれか／"leader"＝発動者から）。
static func can_target(state: BattleState, option: Dictionary, target: Vector2i) -> bool:
	if not bool(option["needs_target"]):
		return true
	var rng := int(option["range"])
	if String(option["range_from"]) == "any":
		for pid in option["participants"]:
			var p := state.unit_by_id(int(pid))
			if p != null and Hex.distance(p.pos, target) <= rng:
				return true
		return false
	var leader := state.unit_by_id(int(option["leader_id"]))
	return leader != null and Hex.distance(leader.pos, target) <= rng

# --- 内部 ---

## leader に隣接する member_type の候補（同陣営・未行動）から、互いに隣接する2体組を全列挙。
static func _triangle_sets(state: BattleState, leader: Unit, r: Dictionary) -> Array:
	var cand: Array[Unit] = []
	for u in state.units():
		if u.id == leader.id or u.team != leader.team or state.is_done(u.id):
			continue
		if not (u.type_id in r["member_types"]):
			continue
		if Hex.distance(u.pos, leader.pos) == 1:
			cand.append(u)
	var sets: Array = []
	for i in cand.size():
		for j in range(i + 1, cand.size()):
			if Hex.distance(cand[i].pos, cand[j].pos) == 1:
				sets.append([cand[i], cand[j]])
	return sets

## 参加ユニット配列（先頭＝発動者）から選択肢 dict を組む。
static func _option(rid: String, r: Dictionary, participants: Array) -> Dictionary:
	var ids: Array[int] = []
	for u in participants:
		ids.append(u.id)
	var effect := String(r["effect"])
	return {
		"recipe": rid,
		"name": String(r["name"]),
		"leader_id": participants[0].id,
		"participants": ids,
		"effect": effect,
		"needs_target": effect in ["area", "single"],
		"range": int(r.get("range", 0)),
		"range_from": String(r.get("range_from", "leader")),
		"radius": int(r.get("radius", 0)),
	}

## victim 1体への陣形ダメージ内訳（合算攻撃力・間接扱い）。非破壊。
static func _formation_hit(state: BattleState, option: Dictionary, victim: Unit) -> Dictionary:
	var leader := state.unit_by_id(int(option["leader_id"]))
	var atk_total := 0.0
	for pid in option["participants"]:
		var p := state.unit_by_id(int(pid))
		if p == null:
			continue
		# 間接扱い＝melee=false（支援は乗らない）。各参加者の実効攻撃力を合算。
		atk_total += float(Combat.attack_breakdown(state, p, victim, false)["total"])
	var synth_atk := {"kind": "attack", "total": atk_total}
	# 防御側: 包囲は乗る（victim の surround が defense_breakdown に入る）／貫通は発動者の性質／支援なし。
	var df := Combat.defense_breakdown(state, victim, leader, false)
	var hit := Combat.hit_from_breakdowns(synth_atk, df, victim.troops)
	hit["target_id"] = victim.id
	return hit

static func _leader_team(state: BattleState, option: Dictionary) -> int:
	var leader := state.unit_by_id(int(option["leader_id"]))
	return leader.team if leader != null else -99
