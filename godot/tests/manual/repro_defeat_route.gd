extends SceneTree
## feature-104 検証用（使い捨て）: 敗北の戦果票で選んだ行き先が実際に効くか。
## 盤を出して敗北の決着を流し、(1) もう一度挑む→同じステージが読み直される
## (2) 依頼ボードへ戻る→セレクトが開く (3) 暗幕クリック→盤に戻るだけ、を順に見る。
## 実行: godot --path . -s res://tests/manual/repro_defeat_route.gd（--headless 不可）

const STAGE := "res://data/stages/debug-ai/standoff.json"
const OUT := "res://tests/manual/out/defeat_route.txt"

var _main: Node
var _log: Array = []
var _frame := 0
var _step := 0

func _initialize() -> void:
	var scene: PackedScene = load("res://presentation/main/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 10:
		return false
	if _frame % 30 != 0:
		return false
	match _step:
		0:
			_main._select.close()
			_main.load_stage(STAGE)
		1:
			_main._controller.state.turn_number = 7  # 読み直されたら1に戻る＝再挑戦が効いた印
			_main._on_battle_finished(BattleState.PLAYER_LOSS)  # 敗北の決着を流す（await で票が出る）
		2:
			_log.append("票が出た=%s / 行き先ボタン=%s" % [_main._result.visible, _main._result._choices.visible])
			_main._result._retry.emit_signal("pressed")  # もう一度挑む
		3:
			_log.append("再挑戦後: 盤のステージ=%s / ターン=%d / 票=%s / セレクト=%s" % [
				_main._current_stage_path.get_file(), _main._controller.state.turn_number, _main._result.visible, _main._select.visible])
			_main._on_battle_finished(BattleState.PLAYER_LOSS)
		4:
			_main._result._to_select.emit_signal("pressed")  # 依頼ボードへ戻る
		5:
			_log.append("セレクトへ後: セレクト=%s / 票=%s" % [_main._select.visible, _main._result.visible])
			_main._select.close()
			_main.load_stage(STAGE)
		6:
			_main._on_battle_finished(BattleState.PLAYER_LOSS)
		7:
			_main._result._dismiss()  # 暗幕クリック相当＝選ばずに閉じる
		8:
			_log.append("閉じただけ: 票=%s / セレクト=%s / 盤のステージ=%s" % [
				_main._result.visible, _main._select.visible, _main._current_stage_path.get_file()])
			FileAccess.open(OUT, FileAccess.WRITE).store_string("\n".join(_log))
			quit()
			return true
	_step += 1
	return false
