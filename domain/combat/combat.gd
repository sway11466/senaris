extends RefCounted
class_name Combat
## 戦闘解決（純ロジック・決定的＝乱数なし）。詳細 → doc/gdd/combat.md
##
## 実効攻撃力 A ＝ 兵数 × ユニット攻撃力 × 経験 × 包囲 × 地形(攻) ＋ 支援(攻)
## 実効防御力 D ＝ 兵数 × ユニット防御力 × 経験 × 包囲 × 地形(防) ＋ 支援(防)
## 失う兵数 ＝ clamp( round( k × 相手兵数 × A^p/(A^p+D^p) ), 0, 相手兵数 )
##
## 補正のうち 包囲・支援・経験・地形 は実装済み（地形は平地・台地の2種から順次追加）。

const K := 1.0  ## 殺傷力（全体の削り量。チューニング用）
const P := 2.0  ## 決定力（戦力差の効き。互角は常に0.5、差だけ鋭くなる）

const SUPPORT_RATE := 0.25       ## 支援は味方の素ステータスの25%
const DEFENSE_SUPPORT_CAP := 2.0 ## 支援後の防御は支援前の2倍まで

## 経験値補正（Lv1〜8 → 倍率。経験 ＝ 1 ＋ %）。Lv1＝×1.0（補正なし）、攻防共通。
## index = level - 1。生き残るほど上がり、上昇幅も加速する。詳細 → combat.md
const EXPERIENCE := [1.00, 1.05, 1.10, 1.15, 1.25, 1.40, 1.65, 2.00]

## 包囲補正係数（段階式・1.0＝影響なし）。攻防の両方に乗る。詳細は Surround。
static func surround_factor(state: BattleState, u: Unit) -> float:
	return Surround.factor(state, u)

## u の経験（レベル）補正倍率。攻撃力・防御力の両方に乗る。Lv1＝×1.0。
static func experience_factor(u: Unit) -> float:
	return float(EXPERIENCE[clampi(u.level, 1, Unit.MAX_LEVEL) - 1])

## u が enemy を攻撃するときの実効攻撃力。地形(攻) ＝ u の足元の地形係数。
## 支援(攻) ＝ enemy に隣接する u の味方からの加算（地形・経験は乗らない素の値）。
static func effective_attack(state: BattleState, u: Unit, enemy: Unit) -> float:
	var terrain := Terrain.attack_factor(state.terrain_at(u.pos))
	var base := float(u.troops) * float(u.unit_attack) * experience_factor(u) * surround_factor(state, u) * terrain
	return base + _support(state, u, enemy, true)

## u が enemy に攻撃されるときの実効防御力。地形(防) ＝ u の足元の地形係数。
## 支援(防) ＝ enemy に隣接する u の味方からの加算。支援後は支援前の2倍が上限。
static func effective_defense(state: BattleState, u: Unit, enemy: Unit) -> float:
	var terrain := Terrain.defense_factor(state.terrain_at(u.pos))
	var base := float(u.troops) * float(u.unit_defense) * experience_factor(u) * surround_factor(state, u) * terrain
	var supported := base + _support(state, u, enemy, false)
	return minf(supported, base * DEFENSE_SUPPORT_CAP)

## u の味方（u自身を除く）で enemy に隣接しているものからの支援合計。
## is_attack=true で攻撃支援（味方のユニット攻撃力）、false で防御支援（味方のユニット防御力）。
## 支援量は味方の素の値（兵数 × ステータス × 0.5）。経験・包囲などの補正は含めない。
static func _support(state: BattleState, u: Unit, enemy: Unit, is_attack: bool) -> float:
	var total := 0.0
	for ally in state.units():
		if ally.team != u.team or ally.id == u.id:
			continue
		if Hex.distance(ally.pos, enemy.pos) != 1:
			continue
		var stat := ally.unit_attack if is_attack else ally.unit_defense
		total += float(ally.troops) * float(stat) * SUPPORT_RATE
	return total

## attacker が defender に与える失う兵数（0〜defender.troops）。
static func casualties(state: BattleState, attacker: Unit, defender: Unit) -> int:
	var a := effective_attack(state, attacker, defender)
	var d := effective_defense(state, defender, attacker)
	if a <= 0.0:
		return 0
	var ap := pow(a, P)
	var frac := ap / (ap + pow(d, P))
	var loss := int(round(K * float(defender.troops) * frac))
	return clampi(loss, 0, defender.troops)
