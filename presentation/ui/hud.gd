extends Control
class_name Hud
## 常時表示の HUD（ターン終了ボタン＋システムメニュー）。操作モデル → doc/gdd/uiux.md。
## Presentation の永続UI（dev/ ではない＝製品でも使う）。盤のクリックを邪魔しないよう自身は素通し。
## 進行そのものは持たず、押下をシグナルで main（＝MatchController の所有者）へ委ねる。
##
## 配置は「ビューポート寸法から絶対座標で左下に置く」方式（Node2D 下の Control でアンカーが
## 効かず見えなくなるのを避ける）。ウィンドウリサイズ時は size_changed で置き直す。

signal end_turn_requested        # ターン終了ボタン
signal restart_requested         # システムメニュー: リスタート（現ステージ再読込）
signal stage_select_requested    # システムメニュー: ステージセレクトを開く

var _end_btn: Button
var _gear: Button
var _menu: PopupMenu
enum { SYS_RESTART, SYS_SELECT, SYS_SAVE, SYS_LOAD, SYS_SETTINGS, SYS_CLOSE }

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 盤のクリックを通す（ボタンだけ拾う）

	_gear = Button.new()
	_gear.text = "⚙ メニュー"
	_gear.focus_mode = Control.FOCUS_NONE  # フォーカスを取らない＝Enter(手番終了)で誤発火しない
	_gear.size = Vector2(110, 40)
	_gear.pressed.connect(open_system_menu)
	add_child(_gear)

	_end_btn = Button.new()
	_end_btn.text = "ターン終了"
	_end_btn.focus_mode = Control.FOCUS_NONE
	_end_btn.size = Vector2(140, 40)
	_end_btn.pressed.connect(func() -> void: end_turn_requested.emit())
	add_child(_end_btn)

	_menu = PopupMenu.new()
	_menu.add_item("リスタート", SYS_RESTART)
	_menu.add_item("ステージセレクト", SYS_SELECT)
	_menu.add_separator()
	_menu.add_item("セーブ", SYS_SAVE)
	_menu.add_item("ロード", SYS_LOAD)
	_menu.add_item("設定", SYS_SETTINGS)
	for id in [SYS_SAVE, SYS_LOAD, SYS_SETTINGS]:  # 今後のフェーズで実装（今は無効表示）
		_menu.set_item_disabled(_menu.get_item_index(id), true)
	_menu.add_separator()
	_menu.add_item("閉じる", SYS_CLOSE)
	_menu.id_pressed.connect(_on_sys_id)
	add_child(_menu)

	_reposition()
	get_viewport().size_changed.connect(_reposition)

## ボタンをビューポート左下へ置き直す（起動時・リサイズ時）。
func _reposition() -> void:
	var vp := get_viewport_rect().size
	var y := vp.y - 52.0
	_gear.position = Vector2(16.0, y)
	_end_btn.position = Vector2(134.0, y)  # 歯車(幅110)の右に隙間8

## ターン終了ボタンの有効/無効（自手番のみ有効・AI手番/決着後は無効）。
func set_player_turn(enabled: bool) -> void:
	_end_btn.disabled = not enabled

## システムメニューを開く（歯車ボタン／盤の最上位 Esc から）。
func open_system_menu() -> void:
	_menu.reset_size()
	_menu.position = Vector2i(get_viewport().get_mouse_position())
	_menu.popup()

func _on_sys_id(id: int) -> void:
	match id:
		SYS_RESTART:
			restart_requested.emit()
		SYS_SELECT:
			stage_select_requested.emit()
		SYS_CLOSE:
			pass  # 閉じるだけ（popup は自動で閉じる）
