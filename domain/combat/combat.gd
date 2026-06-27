extends RefCounted
class_name Combat
## 戦闘解決（純ロジック・決定的＝乱数なし）。詳細 → doc/gdd/combat.md
##
## 実効攻撃力 A ＝ 兵数 × ユニット攻撃力 × 経験 × 包囲 × 地形(攻) ＋ 支援(攻)
## 実効防御力 D ＝ 兵数 × ユニット防御力 × 経験 × 包囲 × 地形(防) ＋ 支援(防)
## 失う兵数 ＝ clamp( round( k × 相手兵数 × A^p/(A^p+D^p) ), 0, 相手兵数 )
##
## 補正（経験・包囲・地形・支援）は当面すべて中立。今後 effective_* に差し込む。

const K := 1.0  ## 殺傷力（全体の削り量。チューニング用）
const P := 2.0  ## 決定力（戦力差の効き。互角は常に0.5、差だけ鋭くなる）

## 包囲補正係数（被包囲で 0.5、それ以外 1.0）。攻防の両方に乗る。
static func surround_factor(state: BattleState, u: Unit) -> float:
	return 0.5 if Surround.is_surrounded(state, u) else 1.0

## 実効攻撃力。TODO: × 経験 × 地形(攻) ＋ 支援(攻)
static func effective_attack(state: BattleState, u: Unit) -> float:
	return float(u.troops) * float(u.unit_attack) * surround_factor(state, u)

## 実効防御力。TODO: × 経験 × 地形(防) ＋ 支援(防)
static func effective_defense(state: BattleState, u: Unit) -> float:
	return float(u.troops) * float(u.unit_defense) * surround_factor(state, u)

## attacker が defender に与える失う兵数（0〜defender.troops）。
static func casualties(state: BattleState, attacker: Unit, defender: Unit) -> int:
	var a := effective_attack(state, attacker)
	var d := effective_defense(state, defender)
	if a <= 0.0:
		return 0
	var ap := pow(a, P)
	var frac := ap / (ap + pow(d, P))
	var loss := int(round(K * float(defender.troops) * frac))
	if loss < 1 and a >= d:  # 膠着回避（暫定）: 攻撃力が相手以上なら最低1
		loss = 1
	return clampi(loss, 0, defender.troops)
