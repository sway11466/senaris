extends CanvasLayer
class_name TitleScreen
## 起動時のタイトル画面。閉じた酒場の扉を外から見せ、入力で扉が開いて店内へ入る動画に切り替え
## （再生中の入力でスキップ）、入り終わった店内の絵の上にメニューを出す。
## 画面の設計 → doc/gdd/title.md ／ 絵と動画の素材仕様 → doc/art/menu.md §5
##
## 静止画は動画のコマそのものなので、動画と静止画が入れ替わっても画は動かない
## （開始＝1コマ目 door.png／メニュー＝最終コマ room.png）。
## 動画には扉の軋みと焚き火が入っている＝扉の音を別に鳴らす必要はない。
##
## メニューは左の卓を人物ごと不透明の板で覆って載せる（下が透けると文字が読めない）。
## 板とボタンはセレクト画面と同じ材質（TavernTheme）＝店の中の設えとして地続きに見せる。
##
## 素材が置かれていなければ絵を諦めてメニューだけ出す（起動が止まるより無いまま進むほうがよい）。

signal door_opening        # 扉が開き始めた。main が BGM のこもりを解く合図（下記 OPEN_SEC 秒かけて）
signal menu_shown          # メニューを出した。main が menu 曲へクロスフェードする合図
signal continue_requested  # 冒険の続き＝中断セーブから盤へ直行
signal new_game_requested  # 新しい冒険譚＝セレクトへ
signal quit_requested      # おわる

const STILL_PATH := "res://assets/menu/door.png"  # 動画の1コマ目＝始まりの画
const ROOM_PATH := "res://assets/menu/room.png"   # 動画の最終コマ＝メニューの背景
const VIDEO_PATH := "res://assets/menu/door_open.ogv"

## 動画のどこで扉が開くか。実測値（画面の明るさが底から50%に達するのが2.29秒、90%が3.04秒）。
## こもりを解き始める時刻と、解き切るまでの秒数。
const OPEN_AT := 1.3
const OPEN_SEC := 1.9

## メニューが浮かび上がる時間（秒）。動画が止まった瞬間に板が現れると唐突なので一拍かける。
const MENU_FADE_SEC := 0.5

## メニュー板の置き場（画面比・左上と右下）。画面の上下中央、かつ左半分の左右中央に置く
## ＝板の中心は (0.25, 0.5)。画面比で持つので、窓の大きさが変わっても絵に対する位置が動かない。
## 板を収める枠（画面比）。左半分の中で上下に余白をとり、その中に板を絵の縦横比のまま
## 目一杯収めて中央に置く＝板の中心は画面の上下中央・左半分の左右中央 (0.25, 0.5)。
const PANEL_AREA_RIGHT := 0.5
const PANEL_AREA_TOP := 0.10
const PANEL_AREA_BOTTOM := 0.90

## 板の絵が無いときの縦横比（幅÷高さ）。絵が在ればその寸法から取る。
const PANEL_FALLBACK_RATIO := 0.56

## 板の内側の余白（px）。四隅の金具にボタンが掛からない幅をとる。
const PANEL_PAD_X := 52
const PANEL_PAD_Y := 52

const BUTTON_HEIGHT := 52
const BUTTON_GAP := 18
const BUTTON_FONT_SIZE := 20

var _root: Control
var _still: TextureRect
var _video: VideoStreamPlayer
var _menu: Control = null
var _has_save := false   ## 中断セーブが在る＝「冒険の続き」を出す（main から play で受け取る）
var _playing := false    ## 動画を再生中＝入力はスキップになる
var _opened := false     ## door_opening を出し終えた（1回だけ）
var _menu_open := false  ## メニューを出した＝以後の入力は板のボタンが受ける

func _ready() -> void:
	layer = 70  # 勝利イラスト(60)より前面＝起動直後の最前面
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # 後ろ（セレクト・盤）へ触らせない
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)
	_still = TextureRect.new()
	_still.set_anchors_preset(Control.PRESET_FULL_RECT)
	_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_still)
	_video = VideoStreamPlayer.new()
	_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.bus = "SFX"  # 扉の軋み・焚き火は効果音。曲（Music）とは別に絞れるようにする
	# Control の既定（STOP）のままだと再生中のクリックを動画が飲み込み、_root へ届かない
	# ＝キーでしか飛ばせなくなる。絵と同じく素通しにして、入力は _root が受ける。
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.visible = false
	_video.finished.connect(_show_menu)
	_root.add_child(_video)
	visible = false

## タイトルを出す。閉じた扉を外から見せて入力を待ち、扉が開く動画をはさんでメニューへ渡す。
## has_save＝中断セーブの有無（「冒険の続き」を出すかどうか）。
func play(has_save: bool) -> void:
	_has_save = has_save
	visible = true
	var still := ResourceLoader.load(STILL_PATH) as Texture2D
	if still == null:
		print("TitleScreen: 扉の絵が無い＝待たずに動画から始める: %s" % STILL_PATH)
		_start_video()
		return
	_still.texture = still  # ここで入力を待つ（_advance が扉を開ける）

## タイトルを畳む（項目を選んで次の場面へ移るとき。場面の切り替えは main が持つ）。
func close() -> void:
	visible = false

## 動画を始める。読めなければ絵を出したままメニューへ進む。
func _start_video() -> void:
	var stream := ResourceLoader.load(VIDEO_PATH) as VideoStream
	if stream == null:
		print("TitleScreen: 扉の動画が無い＝メニューだけ出す: %s" % VIDEO_PATH)
		_show_menu()
		return
	_playing = true
	_video.stream = stream
	_video.visible = true
	_video.play()

func _process(_delta: float) -> void:
	if not _playing or _opened:
		return
	if _video.stream_position >= OPEN_AT:
		_opened = true
		door_opening.emit()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_advance()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _menu_open:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not event.is_echo():
		_advance()
		get_viewport().set_input_as_handled()

## 1回目の入力＝扉を開ける（動画を始める）。再生中の入力＝動画を飛ばしてメニューへ。
## メニューが出た後は板のボタンが受けるので、板の外を押しても何も起きない。
func _advance() -> void:
	if _menu_open:
		return
	if _playing:
		_show_menu()
	else:
		_start_video()

## 動画を止め、店内の絵に差し替えてメニューを出す。動画を最後まで見ても、途中で飛ばしても同じ画になる。
func _show_menu() -> void:
	if _menu_open:
		return
	_menu_open = true
	_playing = false
	_video.stop()
	_video.visible = false
	var room := ResourceLoader.load(ROOM_PATH) as Texture2D
	if room == null:
		print("TitleScreen: 店内の絵が無い＝扉の絵のままメニューを出す: %s" % ROOM_PATH)
	else:
		_still.texture = room
	if _menu == null:
		_menu = _build_menu()
		_root.add_child(_menu)
	_menu.modulate.a = 0.0
	create_tween().tween_property(_menu, "modulate:a", 1.0, MENU_FADE_SEC)
	menu_shown.emit()

## メニュー板。不透明の板を敷き、木の板ボタンを縦に並べる。
## 板は1枚絵をそのまま伸縮させる（ナインパッチにしない）ので、絵の縦横比を保つ枠に収めて歪ませない。
## 項目は常に同じ並びで出し、いま選べないもの（行き先が未実装・中断セーブが無い）は押せない見た目にする
## ＝起動のたびに並びが動かず、この画面から何ができるのかも分かる。
func _build_menu() -> Control:
	var area := AspectRatioContainer.new()
	area.anchor_left = 0.0
	area.anchor_top = PANEL_AREA_TOP
	area.anchor_right = PANEL_AREA_RIGHT
	area.anchor_bottom = PANEL_AREA_BOTTOM
	area.offset_left = 0.0
	area.offset_top = 0.0
	area.offset_right = 0.0
	area.offset_bottom = 0.0
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.stretch_mode = AspectRatioContainer.STRETCH_FIT
	area.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	area.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	var tex := TavernTheme.title_board_texture()
	area.ratio = PANEL_FALLBACK_RATIO if tex == null else float(tex.get_width()) / float(tex.get_height())
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", TavernTheme.title_board_stylebox())
	area.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = PANEL_PAD_X
	box.offset_top = PANEL_PAD_Y
	box.offset_right = -PANEL_PAD_X
	box.offset_bottom = -PANEL_PAD_Y
	box.alignment = BoxContainer.ALIGNMENT_CENTER  # 項目数が変わっても（続きの有無）板の中で釣り合う
	box.add_theme_constant_override("separation", BUTTON_GAP)
	# 中断セーブが無いときも項目は出す（押せないだけ）＝並びが変わらず、何が在るかも分かる
	box.add_child(_menu_button("冒険の続き", continue_requested if _has_save else null))
	box.add_child(_menu_button("新しい冒険譚", new_game_requested))
	box.add_child(_menu_button("設定", null))      # 受け口が無い（doc/backlog.md feature-47）
	box.add_child(_menu_button("マニュアル", null))  # 同上（feature-52）
	box.add_child(_menu_button("クレジット", null))  # 同上（feature-46）
	box.add_child(_menu_button("おわる", quit_requested))
	return area

## 板ボタン1つ。sig が null＝いま選べない項目で、押せない見た目にして並びだけ残す。
func _menu_button(text: String, sig: Variant) -> Button:
	var b := TavernTheme.wood_button(text)
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	if sig == null:
		b.disabled = true
	else:
		b.pressed.connect(func() -> void: (sig as Signal).emit())
	return b
