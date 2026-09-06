extends RefCounted
class_name StatBreakdown
## 実効攻撃力／実効防御力の内訳（純データ・Node非依存）。係数ごとの値と出来上がりの total を持つ。
## 式の本体は Combat.attack_breakdown_from / defense_breakdown_from＝作るのはそこだけ。
## 表示（戦闘レポートの3列表）も戦闘解決もこの同じ内訳から導く＝画面の数字と実処理が必ず一致する。
## 詳細 → doc/gdd/combat.md

enum Kind { ATTACK, DEFENSE }

var kind: Kind
var troops: int        ## 兵数
var stat: int          ## ユニット攻撃力（対地／対空のどちらか）またはユニット防御力
var level: float       ## レベル補正倍率
var surround: float    ## 包囲補正倍率
var terrain: float     ## 地形補正倍率
var support: float     ## 支援（加算）
var status_mul: float  ## 状態補正の乗算の合成
var status_add: float  ## 状態補正の加算の合成
var total: float       ## 出来上がりの実効値

# --- 攻撃だけ ---
var vs_aerial := false  ## 相手が飛行＝stat は対空攻撃力
var melee := true       ## 近接（距離1）の打撃か＝支援が乗る

# --- 防御だけ ---
var capped := false     ## 支援2倍上限が効いたか（貫通適用前で判定）
var pierce := 1.0       ## 攻撃側の貫通後係数（1.0＝貫通なし・0.5＝防御半減）

func is_attack() -> bool:
	return kind == Kind.ATTACK

## 素の値＝兵数 × ステータス × レベル × 包囲 × 地形（支援・状態補正・貫通を掛ける前）。
## 開発ツールの内訳表示が「素 → 支援 → 実効」の順で式を見せるのに使う。
func base() -> float:
	return float(troops) * float(stat) * level * surround * terrain
