extends RefCounted
class_name UnitSnapshot
## 戦闘前に固めた駒の姿（純データ・Node非依存）。撃破で盤から消えても、演出とレポートが名前・兵数・
## 足元の地形を出せるよう値を写す。作るのは BattleState.unit_snapshot。
## troops_after は戦闘（または発動）の後に呼び出し側が入れる＝兵数が動かないスキルでは troops_before と同じ。
## 詳細 → doc/tech/combat_scene.md

var id: int
var type_id: String
var skin_id: String
var team: int
var level: int          ## 戦闘前のレベル（加算前）
var troops_before: int
var troops_after: int
var max_troops: int
var terrain: String     ## 足元の地形id
var pos: Vector2i       ## 盤の位置（演出シーンが地面のスキンを引くのに要る）
var statuses: Array = []  ## この時点で効いている状態補正エントリ（StatusMod の辞書）の一覧

## 失った兵数。
func lost() -> int:
	return troops_before - troops_after

## この戦闘で撃破されたか（兵数が0になった）。
func is_killed() -> bool:
	return troops_after <= 0
