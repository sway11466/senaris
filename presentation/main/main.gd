extends Node2D
## Presentation 層のエントリポイント。
## 戦闘状態(BattleState)と進行役(MatchController)を組み立て、盤(HexBoard)に渡す。
## 配置などはデモ用の仮。将来はステージデータ(data/)から構築する。

func _ready() -> void:
	print("Senaris booted.")

	# ステージデータ(data/stages/*.json)から盤面を構築。配置・地形はデータ側で編集する。
	var state := StageLoader.load_file("res://data/stages/demo/demo.json")

	var controller := MatchController.new()
	controller.name = "MatchController"
	controller.setup(state)
	# 敵軍(team 1)を最小AIに任せる。ステージ仕様が決まれば brain を差し替える。
	controller.ai_team = 1
	controller.ai_brain = NearestAttackerBrain.new()
	add_child(controller)

	# スキン表（名前・画像）を渡す。画像未用意のうちは名前プレースホルダで描く。
	var skins := SkinCatalog.load_standard()
	$HexBoard.bind(state, controller, skins)

	# 右側の情報パネルに選択ユニットを映す。
	$InfoPanel.bind(state, skins)
	$HexBoard.selection_changed.connect($InfoPanel.show_unit)

	controller.turn_changed.connect(_on_turn_changed)
	controller.battle_finished.connect(_on_battle_finished)
	_update_turn_label(state.current_team, state.turn_number)

func _on_turn_changed(team: int, turn_number: int) -> void:
	_update_turn_label(team, turn_number)

func _update_turn_label(team: int, turn_number: int) -> void:
	var who := "自軍" if team == 0 else "敵軍"
	$Title.text = "Senaris — Turn %d / %s（Enter で手番終了）" % [turn_number, who]

func _on_battle_finished(outcome: int) -> void:
	var text := "決着"
	match outcome:
		BattleState.PLAYER_WIN:
			text = "自軍の勝利！"
		BattleState.PLAYER_LOSS:
			text = "自軍の敗北…"
	$Title.text = "Senaris — %s" % text
