extends RefCounted
class_name Combat
## 戦闘解決（純ロジック・決定的＝乱数なし）。詳細 → doc/gdd/combat.md
##
## 実効攻撃力 A ＝ 兵数 × ユニット攻撃力 × 経験 × 包囲 × 地形(攻) ＋ 支援(攻)
## 実効防御力 D ＝ ( 兵数 × ユニット防御力 × 経験 × 包囲 × 地形(防) ＋ 支援(防) ) ×(1 − 攻撃側pierce)
##   ＝ 支援・2倍上限を適用した後に攻撃側の防御貫通を掛ける（魔法兵0.5＝防御半減／物理0＝据え置き）。
## 失う兵数 ＝ clamp( round( k × 相手兵数 × A^p/(A^p+D^p) ), 0, 相手兵数 )
##
## 補正のうち 包囲・支援・経験・地形・貫通(pierce) は実装済み（地形は平地・台地の2種から順次追加）。

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

## 実効攻撃力の内訳（dict）。**式の本体はここだけ**＝total を各係数から組み立てる。
## 表示も戦闘解決もこの内訳から導くので、画面の数字と実処理が必ず一致する。
## 相手が飛行なら対空、地上なら対地（attack_against）。対空0で飛行を狙うと stat=0＝total0。
## 包囲は常時（囲まれた側は近接/間接問わず弱る）。支援(攻・加算)は melee のときだけ。
static func attack_breakdown(state: BattleState, u: Unit, enemy: Unit, melee := true) -> Dictionary:
	var b := {
		"kind": "attack",
		"vs_aerial": enemy.is_aerial(),
		"troops": u.troops,
		"stat": u.attack_against(enemy),
		"experience": experience_factor(u),
		"surround": surround_factor(state, u),
		"terrain": TerrainType.attack_factor(state.terrain_at(u.pos)),
		"support": _support(state, u, enemy, true) if melee else 0.0,
		"melee": melee,
	}
	b["total"] = float(b["troops"]) * float(b["stat"]) * float(b["experience"]) * float(b["surround"]) * float(b["terrain"]) + float(b["support"])
	return b

## 実効防御力の内訳（dict）。包囲は常時、支援(防・加算)は melee のみ・支援後は素の2倍が上限。
## 最後に攻撃側(enemy)の防御貫通を掛ける: D' = D ×(1 − enemy.pierce)（魔法兵0.5＝防御半減）。
## 防御は単一値なので、対地・対空どちらの相手にも同じく効く。判定順は支援・上限の後（combat.md【要判断】）。
static func defense_breakdown(state: BattleState, u: Unit, enemy: Unit, melee := true) -> Dictionary:
	var support: float = _support(state, u, enemy, false) if melee else 0.0
	var pre := float(u.troops) * float(u.unit_defense) * experience_factor(u) * surround_factor(state, u) * TerrainType.defense_factor(state.terrain_at(u.pos))
	var supported := pre + support
	var capped := minf(supported, pre * DEFENSE_SUPPORT_CAP)  # 支援は素の2倍まで
	var pierce_factor := 1.0 - float(enemy.pierce)  # 貫通後係数（1.0=貫通なし・0.5=防御半減）
	return {
		"kind": "defense",
		"troops": u.troops,
		"stat": u.unit_defense,
		"experience": experience_factor(u),
		"surround": surround_factor(state, u),
		"terrain": TerrainType.defense_factor(state.terrain_at(u.pos)),
		"support": support,
		"capped": supported > capped,  # 支援2倍上限が効いたか（貫通適用前で判定）
		"pierce": pierce_factor,       # 攻撃側の貫通後係数（内訳表示用）
		"melee": melee,
		"total": capped * pierce_factor,
	}

## u が enemy を攻撃するときの実効攻撃力（内訳の total）。
static func effective_attack(state: BattleState, u: Unit, enemy: Unit, melee := true) -> float:
	return attack_breakdown(state, u, enemy, melee)["total"]

## u が enemy に攻撃されるときの実効防御力（内訳の total）。
static func effective_defense(state: BattleState, u: Unit, enemy: Unit, melee := true) -> float:
	return defense_breakdown(state, u, enemy, melee)["total"]

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

## 1回の打撃の解決（内訳つき・dict）。attacker→defender の実効攻防・割合・失う兵を**1か所で確定**。
## 戦闘解決（兵数の適用）も画面表示も、この同じ dict を使う＝式を二重に持たない。
## { attack:<攻撃側の内訳>, defense:<防御側の内訳>, fraction:割合, loss:失う兵数 }
static func hit_detail(state: BattleState, attacker: Unit, defender: Unit, melee := true) -> Dictionary:
	var atk := attack_breakdown(state, attacker, defender, melee)
	var df := defense_breakdown(state, defender, attacker, melee)
	var a: float = atk["total"]
	var d: float = df["total"]
	var fraction := 0.0
	var loss := 0
	if a > 0.0:
		var ap := pow(a, P)
		fraction = ap / (ap + pow(d, P))  # 割合＝攻²/(攻²+防²)。互角0.5、差で鋭く。
		loss = clampi(int(round(K * float(defender.troops) * fraction)), 0, defender.troops)
	return { "attack": atk, "defense": df, "fraction": fraction, "loss": loss }

## attacker が defender に与える失う兵数（hit_detail の loss）。0〜defender.troops。
static func casualties(state: BattleState, attacker: Unit, defender: Unit, melee := true) -> int:
	return hit_detail(state, attacker, defender, melee)["loss"]
