extends RefCounted
class_name HitDetail
## 1回の打撃の内訳（純データ・Node非依存）。attacker→defender の実効攻防・割合・失う兵を1つに束ねる。
## 作るのは Combat.hit_from_breakdowns だけ＝fraction / loss の式はそこ1か所。
## 戦闘解決（兵数の適用）も画面表示（戦闘レポート・スキルレポート）も、この同じ内訳を使う。
## 詳細 → doc/gdd/combat.md

var attack: StatBreakdown   ## 打つ側の実効攻撃力の内訳
var defense: StatBreakdown  ## 受ける側の実効防御力の内訳
var fraction: float         ## 失う割合＝攻²/(攻²+防²)
var loss: int               ## 失う兵数（0〜受ける側の兵数）
var target_id := -1         ## 受ける側の駒番号。陣形スキルの着弾が対象ごとに載せる。通常戦闘では -1
