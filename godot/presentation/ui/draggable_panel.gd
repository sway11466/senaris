extends Panel
class_name DraggablePanel
## 右の箱に出る板（情報板・会話板）の共通部分＝掴んで動かす。
## プレイヤーから見て板は1枚（中身が駒の情報か会話かは板の状態と無関係）なので、
## 動かし方はここに1つだけ持ち、どちらの板も同じ手つきで動く。位置を1つに揃えるのは main
## （moved を受けてもう一方へ写す）。仕様 → doc/gdd/uiux.md 移動
##
## 木の地の左ボタンが板の移動。ここへ届くのはボタン以外＝ボタンは自分で押下を止め、
## ラベルと中身の器は素通しなので、板の地だけが残る（子の mouse_filter は各板が守る）。
## 引きずり中の motion は、押した Control に届き続ける（Viewport のマウスフォーカス）＝板の外へ
## 速く振っても追従が切れない。動ける範囲は決めない＝画面からはみ出してよい。

signal moved(pos: Vector2)  # 掴んで動かし、離した（板の左上。main が設定に書き、もう一方の板へ写す）

var _dragging := false   # 木の地を掴んで引きずっている
var _drag_grip := Vector2.ZERO  # 掴んだ点の、板の左上からのずれ（引きずり中は板がこの点に追従する）
var _drag_from := Vector2.ZERO  # 掴んだときの板の位置（動いていなければ離しても設定を書かない）

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_dragging = true
			_drag_grip = mb.global_position - global_position
			_drag_from = position
		elif _dragging:
			_dragging = false
			if position != _drag_from:
				moved.emit(position)  # 押して離しただけ（動いていない）では設定を書かない
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		# 位置は event から取る（実カーソルを読むと、タッチや合成イベントで追従しない）。
		global_position = (event as InputEventMouseMotion).global_position - _drag_grip
		accept_event()

## 既定の場所（UiLayout.RIGHT_BOX）へ戻す。設定の消し込みは呼ぶ側（main）が行う。
## 仕様 → doc/gdd/uiux.md ターン終了・システムメニュー
func reset_position() -> void:
	_dragging = false
	position = UiLayout.RIGHT_BOX.position
