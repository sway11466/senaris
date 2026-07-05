extends SceneTree
## 【使い捨て】セレクト画面のカード押下→ステージ選択→出撃をヘッドレスで再現するスクリプト。
## 分割後の構成: SelectScreen（コーディネーター）＞ CampaignSelect / StageSelect。
## 実行: godot --headless --path . -s res://tests/manual/repro_stage_select.gd

var _frames := 0
var _main: Node = null

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _find(node: Node, klass: String) -> Node:
	for c in node.get_children():
		if c.is_class("Node") and c.get_script() != null and c.get_script().get_global_name() == klass:
			return c
		var hit := _find(c, klass)
		if hit != null:
			return hit
	return null

## 見えているカード/リスト行を押下シグナル経由でクリックする。
func _press_visible(index: int) -> void:
	var buttons: Array[Node] = []
	_walk_buttons(_main, buttons)
	print("repro: press [%s]" % buttons[index].text.replace("\n", " / "))
	buttons[index].pressed.emit()

func _walk_buttons(node: Node, out: Array[Node]) -> Array[Node]:
	for c in node.get_children():
		# 見えているカード/リスト行だけ（戻るボタン・非表示ビューの残骸を除く）
		if c is Button and c.custom_minimum_size != Vector2.ZERO and c.is_visible_in_tree():
			out.append(c)
		_walk_buttons(c, out)
	return out

func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		5:
			_press_visible(0)   # キャンペーンカード → ステージ一覧へ
		10:
			_press_visible(0)   # ステージ行 → ブリーフィング
		15:
			print("repro: confirm sortie")
			_find(_main, "StageSelect")._briefing.confirmed.emit()  # 「出撃」ボタン相当
		20:
			print("repro: done without crash")
			return true
	return false
