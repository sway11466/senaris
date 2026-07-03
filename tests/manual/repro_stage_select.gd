extends SceneTree
## 【使い捨て】ステージセレクトのカード押下→出撃をヘッドレスで再現するスクリプト。
## 実行: godot --headless --path . -s res://tests/manual/repro_stage_select.gd

var _frames := 0
var _main: Node = null

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _find_select(node: Node) -> Node:
	for c in node.get_children():
		if c is StageSelect:
			return c
		var hit := _find_select(c)
		if hit != null:
			return hit
	return null

## セレクト画面のカード（Button）を押下シグナル経由でクリックする。
func _press_card(index: int) -> void:
	var select := _find_select(_main)
	var cards: Array[Node] = []
	for b in _walk_buttons(select, cards):
		pass
	print("repro: press card [%s]" % cards[index].text.replace("\n", " / "))
	cards[index].pressed.emit()

func _walk_buttons(node: Node, out: Array[Node]) -> Array[Node]:
	for c in node.get_children():
		if c is Button and c.custom_minimum_size != Vector2.ZERO:  # カードだけ（戻る等を除く）
			out.append(c)
		_walk_buttons(c, out)
	return out

func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		5:
			_press_card(0)   # 冒険譚カード（tutorial）→ ステージ一覧へ
		10:
			_press_card(0)   # ステージカード（st1）→ ブリーフィング
		15:
			print("repro: confirm sortie")
			_find_select(_main)._briefing.confirmed.emit()  # 「出撃」ボタン相当
		20:
			print("repro: done without crash")
			return true
	return false
