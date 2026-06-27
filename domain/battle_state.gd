extends RefCounted
class_name BattleState
## 戦闘全体の状態 ＝ 中断セーブの本体（唯一の真実）。
## Godot ノード非依存（extends RefCounted）。見た目の状態はここに含めない。
## 詳細 → doc/design/architecture.md, doc/gamesystem/save.md

# TODO: ユニット配置・マップ状態・ターン情報をここに集約していく。
