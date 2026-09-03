extends Control
class_name Hud
## 常時表示の HUD（ターン終了ボタン＋システムメニュー）。操作モデル → doc/gdd/uiux.md。
## Presentation の永続UI（dev/ ではない＝製品でも使う）。盤のクリックを邪魔しないよう自身は素通し。
## 進行そのものは持たず、押下をシグナルで main（＝MatchController の所有者）へ委ねる。
##
## 配置は「ビューポート寸法から絶対座標で左下に置く」方式（Node2D 下の Control でアンカーが
## 効かず見えなくなるのを避ける）。ウィンドウリサイズ時は size_changed で置き直す。

signal end_turn_requested        # ターン終了ボタン
signal info_panel_toggle_requested  # 情報板ボタン＝右の情報板を畳む／開く
signal info_panel_reset_requested   # システムメニュー: 情報板の位置を戻す
signal restart_requested         # システムメニュー: リスタート（現ステージ再読込）
signal stage_select_requested    # システムメニュー: ステージセレクトを開く
signal save_requested            # システムメニュー: 中断セーブ
signal load_requested            # システムメニュー: 中断セーブから再開
signal settings_requested        # システムメニュー: 設定画面を盤の上に開く
signal zoom_in_requested         # システムメニュー: ズームイン（1段階）
signal zoom_out_requested        # システムメニュー: ズームアウト（1段階）
signal wipe_enemies_requested    # デバッグメニュー: 盤上の敵を殲滅（デバッグビルドのみ出る項目）
signal debug_event_requested(index: int)  # デバッグメニュー: 未発生イベントを起こす（一覧の何番目か）

## ボタンの絵。`{id}.png` が在れば文字の左に出し、無ければ文字だけ（特性アイコンと同じ規約）。
## 記号を文字（⚙）で置かない＝UI のフォントを決めていないので OS の代替フォントで形が変わる。作りは doc/art/icons.md
const ICON_DIR := "res://assets/icons/hud/"
const ICON_SIZE := 24  # 板の高さ40から上下の余白6ずつを引いた中身28に収める

var _end_btn: Button
var _info_btn: Button
var _gear: Button
var _menu: PopupMenu
var _dbg_events: PopupMenu = null  # デバッグ区画のサブメニュー（製品ビルドでは作らない＝null）
enum { SYS_RESTART, SYS_SELECT, SYS_ZOOM_IN, SYS_ZOOM_OUT, SYS_INFO_RESET, SYS_SAVE, SYS_LOAD, SYS_SETTINGS, SYS_CLOSE, DBG_WIPE, DBG_EVENTS }

## デバッグ: 未発生イベントの表示名を返す Callable（main が挿す）。一覧は起こすたびに減るので
## 作り置きせず、メニューを開くたびに聞き直す。空を返せば「イベントを起こす」は無効表示。
var debug_events_provider: Callable

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 盤のクリックを通す（ボタンだけ拾う）

	# wood_button は focus_mode=NONE 済み（＝Enter(ターン終了)で誤発火しない）
	_gear = _button("ui.hud.menu", "menu", 110.0)
	_gear.pressed.connect(open_system_menu)
	add_child(_gear)

	_end_btn = _button("ui.hud.end_turn", "end_turn", 140.0)
	_end_btn.pressed.connect(func() -> void: end_turn_requested.emit())
	add_child(_end_btn)

	# 情報板の畳む／開く。左下のメニューの右。仕様 → doc/gdd/uiux.md ターン終了・システムメニュー
	_info_btn = _button("ui.hud.info_panel", "info_panel", 110.0)
	_info_btn.pressed.connect(func() -> void: info_panel_toggle_requested.emit())
	add_child(_info_btn)

	_menu = PopupMenu.new()
	_menu.add_item(tr("ui.hud.restart"), SYS_RESTART)
	_menu.add_item(tr("ui.hud.stage_select"), SYS_SELECT)
	_menu.add_separator()
	# ズームはラベルの括弧書きで本来の操作（Ctrl＋ホイール）も周知する。仕様 → doc/gdd/uiux.md
	_menu.add_item(tr("ui.hud.zoom_in"), SYS_ZOOM_IN)
	_menu.add_item(tr("ui.hud.zoom_out"), SYS_ZOOM_OUT)
	_menu.add_item(tr("ui.hud.info_panel_reset"), SYS_INFO_RESET)  # 動かした情報板を既定の場所へ
	_menu.add_separator()
	_menu.add_item(tr("ui.hud.save"), SYS_SAVE)
	_menu.add_item(tr("ui.hud.load"), SYS_LOAD)
	_menu.add_item(tr("ui.hud.settings"), SYS_SETTINGS)  # タイトルと同じ設定画面を盤の上に開く（doc/gdd/settings.md）
	_menu.set_item_disabled(_menu.get_item_index(SYS_LOAD), true)  # ロードは中断セーブが在るときだけ有効（main が切替）
	_menu.add_separator()
	_menu.add_item(tr("ui.hud.close"), SYS_CLOSE)
	# デバッグ区画は末尾＝製品ビルドには出ない（デバッグ冒険譚の表示と同じゲート）。仕様 → doc/gdd/uiux.md
	# ここだけ直書きのままなのは、配布ビルドに出ない＝プレイヤーが読まないため（doc/tech/i18n.md）。
	if OS.is_debug_build():
		_menu.add_separator("デバッグ")
		_menu.add_item("敵を殲滅", DBG_WIPE)
		_dbg_events = PopupMenu.new()
		_dbg_events.id_pressed.connect(func(i: int) -> void: debug_event_requested.emit(i))
		_menu.add_submenu_node_item("イベントを起こす", _dbg_events, DBG_EVENTS)
	_menu.id_pressed.connect(_on_sys_id)
	add_child(_menu)

	_reposition()
	get_viewport().size_changed.connect(_reposition)

## 木の板ボタンを作る。絵（ICON_DIR/{icon_id}.png）が在れば文字の左に載せる。
## 幅は文字が収まる目安で、実幅は最小サイズで広がりうる（_reposition は実幅で並べる）。
func _button(key: String, icon_id: String, width: float) -> Button:
	var b := TavernTheme.wood_button(tr(key))
	b.size = Vector2(width, 40)
	var path := ICON_DIR + icon_id + ".png"
	if ResourceLoader.exists(path):
		b.icon = load(path)
		b.add_theme_constant_override("icon_max_width", ICON_SIZE)
		b.add_theme_constant_override("h_separation", 6)
	return b

## ボタンを置き直す（起動時・リサイズ時）。左下にメニューと情報板、盤エリアの右下にターン終了。
## ターン終了を単独にするのは、毎ターン押すぶん押し間違いのダメージが大きく、距離で守るため
## （doc/gdd/uiux.md ボタンの左右・ターン終了）。
## 言語が変わったので文言を貼り直す（doc/tech/i18n.md 言語の切り替え）。
## HUD は起動時に1度だけ作ってセッション中生き続けるので、作り直さずに文字だけ差し替える
## （作り直すとターンの可否・ロードの可否を持ち直すことになる）。
func refresh_labels() -> void:
	_gear.text = tr("ui.hud.menu")
	_end_btn.text = tr("ui.hud.end_turn")
	_info_btn.text = tr("ui.hud.info_panel")
	for pair in [[SYS_RESTART, "ui.hud.restart"], [SYS_SELECT, "ui.hud.stage_select"],
			[SYS_ZOOM_IN, "ui.hud.zoom_in"], [SYS_ZOOM_OUT, "ui.hud.zoom_out"],
			[SYS_INFO_RESET, "ui.hud.info_panel_reset"],
			[SYS_SAVE, "ui.hud.save"], [SYS_LOAD, "ui.hud.load"],
			[SYS_SETTINGS, "ui.hud.settings"], [SYS_CLOSE, "ui.hud.close"]]:
		_menu.set_item_text(_menu.get_item_index(int(pair[0])), tr(String(pair[1])))

func _reposition() -> void:
	var vp := get_viewport_rect().size
	var y := vp.y - 52.0
	_gear.position = Vector2(16.0, y)
	_info_btn.position = Vector2(16.0 + _gear.size.x + 8.0, y)  # 歯車の実幅（最小サイズで広がりうる）の右に隙間8
	_end_btn.position = Vector2(UiLayout.board_area(vp).end.x - 16.0 - _end_btn.size.x, y)

## ターン終了ボタンの有効/無効（自ターンのみ有効・AIターン/決着後は無効）。
func set_player_turn(enabled: bool) -> void:
	_end_btn.disabled = not enabled

## 「ロード」項目の有効/無効（中断セーブが在るときだけ有効）。main が保存有無で切り替える。
func set_load_available(available: bool) -> void:
	_menu.set_item_disabled(_menu.get_item_index(SYS_LOAD), not available)

## システムメニューを開く（歯車ボタン／盤の最上位 Esc から）。
func open_system_menu() -> void:
	_refresh_debug_events()
	_menu.reset_size()
	_menu.position = Vector2i(get_viewport().get_mouse_position())
	_menu.popup()

## デバッグ: サブメニューへ未発生イベントの一覧を貼り直す（開くたび）。
## 起こせるものが無ければ親の項目を無効表示にする＝押しても何も起きない項目を残さない。
func _refresh_debug_events() -> void:
	if _dbg_events == null:
		return
	var labels := PackedStringArray()
	if debug_events_provider.is_valid():
		labels = debug_events_provider.call()
	_dbg_events.clear()
	for i in labels.size():
		_dbg_events.add_item(labels[i], i)
	_dbg_events.reset_size()
	_menu.set_item_disabled(_menu.get_item_index(DBG_EVENTS), labels.is_empty())

func _on_sys_id(id: int) -> void:
	match id:
		SYS_RESTART:
			restart_requested.emit()
		SYS_SELECT:
			stage_select_requested.emit()
		SYS_SAVE:
			save_requested.emit()
		SYS_LOAD:
			load_requested.emit()
		SYS_SETTINGS:
			settings_requested.emit()
		SYS_ZOOM_IN:
			zoom_in_requested.emit()
		SYS_ZOOM_OUT:
			zoom_out_requested.emit()
		SYS_INFO_RESET:
			info_panel_reset_requested.emit()
		SYS_CLOSE:
			pass  # 閉じるだけ（popup は自動で閉じる）
		DBG_WIPE:
			wipe_enemies_requested.emit()  # 確認は挟まない（デバッグビルド限定の項目）
