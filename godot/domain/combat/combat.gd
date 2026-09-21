extends RefCounted
class_name Combat
## 戦闘解決（純ロジック・決定的＝乱数なし）。詳細 → doc/gdd/combat.md
##
## 実効攻撃力 A ＝ 兵数 × ユニット攻撃力 × レベル × 包囲 × 地形(攻) ＋ 支援(攻)
## 実効防御力 D ＝ ( 兵数 × ユニット防御力 × レベル × 包囲 × 地形(防) ＋ 支援(防) ) ×(1 − 攻撃側pierce)
##   ＝ 支援・2倍上限・下限0を適用した後に攻撃側の防御貫通を掛ける（魔法兵0.5＝防御半減／物理0＝据え置き）。
## 失う兵数 ＝ clamp( round( k × 相手兵数 × A^p/(A^p+D^p) ), 0, 相手兵数 )
##
## 補正のうち 包囲・支援・レベル・地形・貫通(pierce) は実装済み（地形は平地・台地の2種から順次追加）。

const K := 1.0  ## 殺傷力（全体の削り量。チューニング用）
const P := 2.0  ## 決定力（戦力差の効き。互角は常に0.5、差だけ鋭くなる）

const SUPPORT_RATE := 0.25       ## 支援は味方の素ステータスの25%
const DEFENSE_SUPPORT_CAP := 2.0 ## 支援後の防御は支援前の2倍まで

## レベル補正（Lv1〜99）: 1レベルごとに +1%。Lv1＝×1.0（補正なし）、Lv99＝×1.98。攻防共通。
## 攻防回数が多くレベルが速く上がる前提なので、1段を薄く長く伸ばす線形カーブ。詳細 → combat.md
const FACTOR_PER_LEVEL := 0.01

## 包囲補正係数（段階式・1.0＝影響なし）。攻防の両方に乗る。詳細は Surround。
static func surround_factor(state: BattleState, u: Unit) -> float:
	return Surround.factor(state, u)

## u のレベル補正倍率。攻撃力・防御力の両方に乗る。Lv1＝×1.0。
static func level_factor(u: Unit) -> float:
	return level_factor_at(u.level)

## level（1〜MAX_LEVEL）→ レベル補正倍率。Unit を介さず level 値から直接引く（明示計算・ツール用）。
static func level_factor_at(level: int) -> float:
	return 1.0 + FACTOR_PER_LEVEL * float(clampi(level, 1, Unit.MAX_LEVEL) - 1)

## 実効攻撃力の内訳（StatBreakdown）。**式の本体はここだけ**＝total を各係数から組み立てる。
## 表示も戦闘解決もこの内訳から導くので、画面の数字と実処理が必ず一致する。
## 相手が飛行なら対空、地上なら対地（attack_against）。対空0で飛行を狙うと stat=0＝total0。
## 包囲・支援は常時（近接/間接を問わない）。支援(攻・加算)は防御ユニット(enemy)の周りに立つ自軍から集める。
## ここは「標準の係数の集め方」＝通常戦闘用。別の流儀（陣形スキル等）は呼び出し元が
## 係数を選んで attack_breakdown_from を直接呼ぶ（例外のフラグをここに足さない）。
static func attack_breakdown(state: BattleState, u: Unit, enemy: Unit) -> StatBreakdown:
	var sf := state.status_aggregate(u, "attack")  # 状態補正（バフ/デバフ）の合成 {mul, add}
	var b := attack_breakdown_from(
		u.troops,
		u.attack_against(enemy),
		level_factor(u),
		surround_factor(state, u),
		TerrainType.attack_factor(state.terrain_at(u.pos)),
		support_around(state, enemy.pos, u.team, u.handle, true),
		float(sf["mul"]), float(sf["add"]))
	b.vs_aerial = enemy.is_aerial()
	return b

## 明示係数から実効攻撃力の内訳を組む（式の本体）。盤ベースの attack_breakdown も
## 開発ツール（tools/combat_sim）も、攻撃力の total 計算はここに集約する＝式を二重に持たない。
static func attack_breakdown_from(troops: int, stat: int, lv: float, surround: float, terrain: float, support: float, status_mul := 1.0, status_add := 0.0) -> StatBreakdown:
	var b := StatBreakdown.new()
	b.kind = StatBreakdown.Kind.ATTACK
	b.troops = troops
	b.stat = stat
	b.level = lv
	b.surround = surround
	b.terrain = terrain
	b.support = support
	b.status_mul = status_mul
	b.status_add = status_add
	b.total = b.base() * status_mul + support + status_add
	return b

## 実効防御力の内訳（StatBreakdown）。包囲・支援は常時（近接/間接を問わない）。支援(防・加算)は
## 防御ユニット自身(u)の周りに立つ自軍から集める。支援後は素の2倍が上限。
## 最後に攻撃側(enemy)の防御貫通を掛ける: D' = D ×(1 − enemy.pierce)（魔法兵0.5＝防御半減）。
## 防御は単一値なので、対地・対空どちらの相手にも同じく効く。判定順は支援・上限の後（test_pierce.gd で固定）。
## 結界（マジックシールド）の中に居る駒は貫通を受けない＝攻撃側の貫通を 0 として渡す。
static func defense_breakdown(state: BattleState, u: Unit, enemy: Unit) -> StatBreakdown:
	var sf := state.status_aggregate(u, "defense")  # 状態補正（バフ/デバフ）の合成 {mul, add}
	var b := defense_breakdown_from(
		u.troops,
		u.unit_defense,
		level_factor(u),
		surround_factor(state, u),
		TerrainType.defense_factor(state.terrain_at(u.pos)),
		support_around(state, u.pos, u.team, u.handle, false),
		0.0 if state.pierce_immune(u) else float(enemy.pierce),
		float(sf["mul"]), float(sf["add"]))
	return b

## 明示係数から実効防御力の内訳を組む（式の本体）。支援後に2倍上限と下限0、最後に攻撃側の貫通を掛ける。
## 盤ベースの defense_breakdown も開発ツールも、防御力の total 計算はここに集約する。
static func defense_breakdown_from(troops: int, stat: int, lv: float, surround: float, terrain: float, support: float, pierce: float, status_mul := 1.0, status_add := 0.0) -> StatBreakdown:
	var b := StatBreakdown.new()
	b.kind = StatBreakdown.Kind.DEFENSE
	b.troops = troops
	b.stat = stat
	b.level = lv
	b.surround = surround
	b.terrain = terrain
	b.support = support
	b.status_mul = status_mul
	b.status_add = status_add
	var pre := b.base() * status_mul
	var supported := pre + support + status_add  # 加算群（支援・状態add）は素の2倍上限の対象
	var capped := minf(supported, pre * DEFENSE_SUPPORT_CAP)  # 支援は素の2倍まで
	var floored := maxf(capped, 0.0)  # 減算デバフで負なら0＝素通し（損害式は防²＝負が正に化けて逆に硬くなるため）
	b.capped = supported > capped  # 支援2倍上限が効いたか（貫通適用前で判定）
	b.pierce = 1.0 - pierce  # 貫通後係数（1.0=貫通なし・0.5=防御半減）
	b.total = floored * b.pierce
	return b

## 支援の合計。どちらの支援も**防御ユニット（着弾した駒）の周り**で数える＝center の隣接6hex に
## 立つ team の駒から 兵数 × ステータス × SUPPORT_RATE（0.25）を積む。攻撃距離では変わらない。
## exclude_handle（攻撃者自身・防御ユニット自身）は数に入れない。
## is_attack=true で攻撃支援（駒のユニット攻撃力）、false で防御支援（駒のユニット防御力）。
## 支援量は駒の素の値＝レベル・包囲などの補正は含めない。詳細 → doc/gdd/combat.md 支援効果
static func support_around(state: BattleState, center: Vector2i, team: int,
		exclude_handle: int, is_attack: bool) -> float:
	var total := 0.0
	for ally in state.units():
		if ally.team != team or ally.handle == exclude_handle:
			continue
		if Hex.distance(ally.pos, center) != 1:
			continue
		var stat := ally.unit_attack if is_attack else ally.unit_defense
		total += float(ally.troops) * float(stat) * SUPPORT_RATE
	return total

## 1回の打撃の解決（HitDetail）。attacker→defender の実効攻防・割合・失う兵を**1か所で確定**。
## 戦闘解決（兵数の適用）も画面表示も、この同じ内訳を使う＝式を二重に持たない。
static func hit_detail(state: BattleState, attacker: Unit, defender: Unit) -> HitDetail:
	var atk := attack_breakdown(state, attacker, defender)
	var df := defense_breakdown(state, defender, attacker)
	return hit_from_breakdowns(atk, df, defender.troops)

## 攻撃側の内訳・防御側の内訳・防御側の兵数から、割合と失う兵を確定する（式の本体）。
## fraction/loss はここ1か所だけ。盤の戦闘解決も開発ツールもこれを通す＝画面と実処理が一致する。
static func hit_from_breakdowns(atk: StatBreakdown, df: StatBreakdown, defender_troops: int) -> HitDetail:
	var h := HitDetail.new()
	h.attack = atk
	h.defense = df
	if atk.total > 0.0:
		var ap := pow(atk.total, P)
		h.fraction = ap / (ap + pow(df.total, P))  # 割合＝攻²/(攻²+防²)。互角0.5、差で鋭く。
		h.loss = clampi(int(round(K * float(defender_troops) * h.fraction)), 0, defender_troops)
	return h

## attacker が defender に与える失う兵数（hit_detail の loss）。0〜defender.troops。
static func casualties(state: BattleState, attacker: Unit, defender: Unit) -> int:
	return hit_detail(state, attacker, defender).loss
