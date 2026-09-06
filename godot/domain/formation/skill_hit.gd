extends RefCounted
class_name SkillHit
## 陣形スキルの着弾1件＝対象1体の損害（純データ）。SkillResult.hits の要素。
## 撃破で盤から消えても演出とレポートが出せるよう、位置とスナップショットを固める。

var target_id: int        ## 被弾した駒番号
var hex: Vector2i         ## 被弾した位置（撃破で盤から外れる前の値）
var loss: int             ## 失った兵数
var killed: bool          ## 撃破されたか
var detail: HitDetail     ## 打撃の内訳（レポートの3列表）
var victim: UnitSnapshot  ## 被弾側（発動前の姿＋troops_after）
