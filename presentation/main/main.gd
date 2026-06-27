extends Node2D
## Presentation 層のエントリポイント。
## 戦闘状態(BattleState)と進行役(MatchController)を組み立て、盤(HexBoard)に渡す。
## 配置などはデモ用の仮。将来はステージデータ(data/)から構築する。

func _ready() -> void:
	print("Senaris booted.")

	var state := BattleState.new(12, 8)
	state.add_unit(Unit.new(1, 0, Hex.offset_to_axial(3, 3), 4))
	state.add_unit(Unit.new(2, 0, Hex.offset_to_axial(4, 5), 3))
	state.add_unit(Unit.new(3, 1, Hex.offset_to_axial(8, 2), 4))
	state.add_unit(Unit.new(4, 1, Hex.offset_to_axial(7, 5), 3))

	var controller := MatchController.new()
	controller.name = "MatchController"
	controller.setup(state)
	add_child(controller)

	$HexBoard.bind(state, controller)

	controller.turn_changed.connect(_on_turn_changed)
	_update_turn_label(state.current_team, state.turn_number)

func _on_turn_changed(team: int, turn_number: int) -> void:
	_update_turn_label(team, turn_number)

func _update_turn_label(team: int, turn_number: int) -> void:
	var who := "自軍" if team == 0 else "敵軍"
	$Title.text = "Senaris — Turn %d / %s（Enter で手番終了）" % [turn_number, who]
