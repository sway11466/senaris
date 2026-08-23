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

## ボタンを置く領域（画面比）。左半分の中央に縦一列で並べる＝列の中心は (0.25, 0.5)。
const MENU_AREA_RIGHT := 0.5

## 暗幕の右端（画面比）と色。ボタンの帯を絵から分けるためだけの膜で、文字はボタン（不透明）に載る。
## 木ではなく中立の暗色にする＝操作の道具は酒場の物ではない（キャンペーンセレクトの
## カルーセルUIが灰色なのと同じ考え。campaign_select.gd の DOT_COLOR）。
const SCRIM_RIGHT := 0.56
const SCRIM_COLOR := Color(0.04, 0.03, 0.03)
const SCRIM_ALPHA_EDGE := 0.80   # 画面左端
const SCRIM_ALPHA_HOLD := 0.74   # ボタンの列を覆う範囲。ここから右へ抜けていく
const SCRIM_HOLD_AT := 0.55      # 抜け始める位置（暗幕の幅に対する比）

## ビルドの刻印（左下）。読めるだけでよく、絵の邪魔をしないところまで沈める。
const STAMP_MARGIN := 12
const STAMP_FONT_SIZE := 12
const STAMP_COLOR := Color(1, 1, 1, 0.35)

const BUTTON_WIDTH := 260
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

## メニューへ戻る（セレクトから）。扉と動画はもう見せず、店内の絵とメニューだけを出し直す。
## 項目は作り直す＝遊んでいる間に中断セーブが増減していても「冒険の続き」の可否が合う。
func reopen(has_save: bool) -> void:
	_has_save = has_save
	if _menu != null:
		_menu.queue_free()
		_menu = null
	_menu_open = false
	visible = true
	_show_menu()

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

## メニュー。左半分に暗幕を敷き、その中央に木の板ボタンを縦に並べる。
## 酒場の物（木の板を敷く等）にはしない＝設定・マニュアル・おわる は作中の誰の行為でもなく、
## 操作の道具だから絵から浮かせる。キャンペーンセレクトのカルーセルUIを灰色にしたのと同じ判断。
## 項目は常に同じ並びで出し、いま選べないもの（行き先が未実装・中断セーブが無い）は押せない見た目にする
## ＝起動のたびに並びが動かず、この画面から何ができるのかも分かる。
func _build_menu() -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_scrim())
	var center := CenterContainer.new()  # 左半分のちょうど真ん中に列を置く
	center.anchor_left = 0.0
	center.anchor_top = 0.0
	center.anchor_right = MENU_AREA_RIGHT
	center.anchor_bottom = 1.0
	center.offset_left = 0.0
	center.offset_top = 0.0
	center.offset_right = 0.0
	center.offset_bottom = 0.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var box := VBoxContainer.new()
	center.add_child(box)
	box.add_theme_constant_override("separation", BUTTON_GAP)
	# 中断セーブが無いときも項目は出す（押せないだけ）＝並びが変わらず、何が在るかも分かる
	box.add_child(_menu_button(tr("ui.title.continue"), continue_requested if _has_save else null))
	box.add_child(_menu_button(tr("ui.title.new_adventure"), new_game_requested))
	box.add_child(_menu_button(tr("ui.title.settings"), null))  # 受け口が無い（doc/backlog.md feature-47）
	box.add_child(_menu_button(tr("ui.title.manual"), null))    # 同上（feature-52）
	box.add_child(_menu_button(tr("ui.title.credits"), null))   # 同上（feature-46）
	box.add_child(_menu_button(tr("ui.title.quit"), quit_requested))
	layer.add_child(_stamp())
	return layer

## ビルドの刻印（例: windows-itch-demo-0.1.0）。左下の隅に小さく置く。
## サポートで版が特定できないとバグ報告を再現できないため、戻ってこられる画面に常時出す
## （扉と動画は一瞬で飛ばせるので載せない。仕様 → doc/tech/build.md）。
## メニューの列には混ぜない＝項目に見えると操作対象と誤解される。
func _stamp() -> Control:
	var label := Label.new()
	label.text = BuildInfo.stamp()
	label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	label.grow_horizontal = Control.GROW_DIRECTION_END
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_left = STAMP_MARGIN
	label.offset_bottom = -STAMP_MARGIN
	label.add_theme_font_size_override("font_size", STAMP_FONT_SIZE)
	label.add_theme_color_override("font_color", STAMP_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## ボタンの帯を絵から分ける暗幕。左端から右へ抜ける横グラデーション1枚。
func _scrim() -> Control:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, SCRIM_HOLD_AT, 1.0])
	grad.colors = PackedColorArray([
		Color(SCRIM_COLOR, SCRIM_ALPHA_EDGE),
		Color(SCRIM_COLOR, SCRIM_ALPHA_HOLD),
		Color(SCRIM_COLOR, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 1
	tex.fill_from = Vector2(0.0, 0.0)  # 左から右へ（縦は一様）
	tex.fill_to = Vector2(1.0, 0.0)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_left = 0.0
	rect.anchor_top = 0.0
	rect.anchor_right = SCRIM_RIGHT
	rect.anchor_bottom = 1.0
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	return rect

## 板ボタン1つ。sig が null＝いま選べない項目で、沈んだ見た目にして並びだけ残す。
## disabled にはしない＝入力を受け取らないと拒否音を鳴らせないため（セレクトの未解放ステージと同じ）。
func _menu_button(text: String, sig: Variant) -> Button:
	var b := TavernTheme.wood_button(text)
	b.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	b.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	if sig == null:
		TavernTheme.dim_wood_button(b)
		b.pressed.connect(func() -> void: SfxPlayer.play_event("menu_locked"))
	else:
		b.pressed.connect(func() -> void:
			SfxPlayer.play_event("menu_command")
			(sig as Signal).emit())
	return b
