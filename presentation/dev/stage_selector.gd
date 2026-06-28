extends Control
## 【DEV / デモ専用・後で破棄可】ステージ切替UI。
## 製品では冒険譚（campaign）の進行・ステージ選択画面に置き換える。
## その際このファイル（presentation/dev/）と main 側の "DEV" ブロックを削除すればよい。
## main.load_stage(path) は本物のAPIなので残す（進行管理がそれを駆動する）。

signal stage_selected(path: String)

## stages = [{ "label": 表示名, "path": "res://.../x.json" }, ...]
func setup(stages: Array) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 盤のクリックを邪魔しない（ボタンだけ拾う）
	var box := HBoxContainer.new()
	box.position = Vector2(340, 10)
	add_child(box)
	var label := Label.new()
	label.text = "DEMO STAGE:"
	box.add_child(label)
	for s in stages:
		var btn := Button.new()
		btn.text = String(s["label"])
		btn.focus_mode = Control.FOCUS_NONE  # フォーカスを取らない＝Enter(手番終了)で誤発火しない
		btn.pressed.connect(_on_pressed.bind(String(s["path"])))
		box.add_child(btn)

func _on_pressed(path: String) -> void:
	stage_selected.emit(path)
