extends RefCounted
class_name SkillResult
## 陣形スキル／ユニットスキルの発動結果（純データ・Node非依存）。作るのは FormationResolver.resolve だけ。
## 着弾ごとの損害（hits）・盤で光らせる面（cells）・発動者のスナップショット・積んだ状態補正エントリ・
## 効果対象が1体のときの演出用内訳（cast）を持つ。
## 盤の着弾演出（BoardImpactRenderer）・スキルレポート（SkillReportView）・演出シーン（SkillScene）が読む。
## 詳細 → doc/gdd/formations.md 発動の演出, doc/tech/combat_scene.md

var skill: String                  ## スキルID
var leader_id: int                 ## 発動者の駒番号
var caster: UnitSnapshot           ## 発動者（発動前に固める。兵数は動かないので troops_after＝troops_before）
var center: Vector2i               ## 着弾中心（対象を取らないレシピでは呼び手が渡した値のまま）
var cells: Array[Vector2i] = []    ## 光らせる面（駒の有無によらない）＋分裂で出た位置
var hits: Array[SkillHit] = []     ## 着弾した対象ごとの損害（着弾の無いレシピは空）
var status: Dictionary = {}        ## 積んだ状態補正エントリ（バフ・毒）。無ければ空
var cast: SkillCast                ## 効果対象が1体のユニットスキルの演出用内訳。それ以外は null

## 盤に見せる着弾があるか（被弾した駒か光らせる面がある）。無いもの（陣営全体のバフ・解除）は
## 盤を揺らさず作り直すだけ。
func has_impact() -> bool:
	return not hits.is_empty() or not cells.is_empty()
