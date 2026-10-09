extends RefCounted
class_name SkillResult
## 陣形スキル／ユニットスキルの発動結果（純データ・Node非依存）。作るのは FormationResolver.resolve だけ。
## 着弾ごとの損害（hits）・盤で光らせる面（cells）・発動者のスナップショット・積んだ状態補正エントリ・
## 効果対象が1体のときの演出用内訳（cast）を持つ。
## 盤の着弾演出（BoardImpactRenderer）・スキルレポート（SkillReportView）・演出シーン（SkillScene）が読む。
## 詳細 → doc/gdd/formations.md 発動の演出, doc/tech/combat_scene.md

var skill: String                  ## スキルID
var caster_id: int                 ## 発動者の駒番号
var caster: UnitSnapshot           ## 発動者（発動前に固める。兵数は動かないので troops_after＝troops_before）
## 参加した駒（先頭＝発動者）。着弾の無いレシピが「誰に効いたのか」を盤で見せるのに読む
## （シールドウォール＝参加者に発動の印を出す）。詳細 → doc/gdd/formations.md 発動の演出
var participants: Array[int] = []
var center: Vector2i               ## 着弾中心（対象を取らないレシピでは呼び手が渡した値のまま）
var cells: Array[Vector2i] = []    ## 光らせる面（駒の有無によらない）＋分裂で出た位置
var hits: Array[SkillHit] = []     ## 着弾した対象ごとの損害（着弾の無いレシピは空）
var status: Dictionary = {}        ## 積んだ状態補正エントリ（バフ・毒）。無ければ空
var cast: SkillCast                ## 効果対象が1体のユニットスキルの演出用内訳。それ以外は null
## 着弾後に発動者を戻したマス（バックスタブ＝このターンの移動開始位置）。戻していなければ
## Formation.NO_HEX。盤の演出が「刺してから跳んで帰る」の帰り先に読む。
## 詳細 → doc/gdd/formations.md バックスタブ
var caster_returned_to: Vector2i = Formation.NO_HEX
## 罠発見（detect）が調べた範囲＝発動者から視線の届いたヘックス（発動者のマスを含む）。盤が「光が広がって
## スキャンする」演出を出す範囲。見つけた罠のマスは cells に、仕掛けの id は detected に載る。
## 詳細 → doc/gdd/skills.md 罠発見
var scanned: Array[Vector2i] = []
var detected: Array[String] = []
## 突進（ランページ＝効果 move）で発動者が止まった位置。動いていなければ Formation.NO_HEX（隣の駒を
## 殴っただけ）。dash_path＝通ったマス（出発を含まず止まった位置を含む）。盤が駒を直線に滑らせるのに読む。
## 詳細 → doc/gdd/skills.md ランページ
var caster_moved_to: Vector2i = Formation.NO_HEX
var dash_path: Array[Vector2i] = []

## 盤に見せる着弾があるか（被弾した駒か光らせる面がある）。無いもの（陣営全体のバフ・解除）は
## 盤を揺らさず作り直すだけ。罠発見は何も見つからなくても調べた範囲を見せる。
func has_impact() -> bool:
	return not hits.is_empty() or not cells.is_empty() or not scanned.is_empty() 		or caster_moved_to != Formation.NO_HEX

## 突進の一撃を戦闘の結果の器（AttackResult）に写す＝演出シーンが攻撃と同じ画（2体が対峙する画）で
## 反撃なしの一撃として見せる。attacker＝止まった位置の発動者のスナップショット（呼び手が盤から撮る）。
## ぶつかっていなければ null。詳細 → doc/gdd/skills.md ランページ
func dash_as_attack(attacker: UnitSnapshot) -> AttackResult:
	if hits.is_empty() or attacker == null:
		return null
	var hit := hits[0]
	var r := AttackResult.new()
	r.attacker = attacker
	r.defender = hit.victim
	r.to_defender = hit.detail
	r.to_attacker = null  # 反撃なし
	r.melee = Hex.distance(attacker.pos, hit.victim.pos) == 1
	return r
