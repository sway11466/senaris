extends CanvasLayer
class_name TitleScreen
## 起動時のタイトル画面。閉じた酒場の扉を見せ、入力で扉が開く動画に切り替え、
## 扉をくぐったところでセレクト画面へ渡す。絵と動画の仕様 → doc/art/menu.md §5
##
## 画（静止画）は動画の1コマ目そのものなので、動画へ切り替わっても画は動かない。
## 動画には扉の軋みと焚き火が入っている＝扉の音を別に鳴らす必要はない。
##
## 素材が置かれていなければ即 finished を出す（起動が止まるより無いまま進むほうがよい）。

signal door_opening  # 扉が開き始めた。main が BGM のこもりを解く合図（下記 OPEN_SEC 秒かけて）
signal finished      # 扉をくぐり終えた or スキップされた。main がセレクトを開く合図

const STILL_PATH := "res://assets/menu/door.png"
const VIDEO_PATH := "res://assets/menu/door_open.ogv"

## 動画のどこで扉が開くか。実測値（画面の明るさが底から50%に達するのが2.29秒、90%が3.04秒）。
## こもりを解き始める時刻と、解き切るまでの秒数。
const OPEN_AT := 1.3
const OPEN_SEC := 1.9

var _root: Control
var _still: TextureRect
var _video: VideoStreamPlayer
var _playing := false   ## 動画を再生中＝次の入力はスキップになる
var _opened := false    ## door_opening を出し終えた（1回だけ）
var _done := false

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
	_video.visible = false
	_video.finished.connect(_finish)
	_root.add_child(_video)
	visible = false

## タイトルを出す。素材が読めなければ何もせず finished（呼び出し側は即セレクトへ）。
func play() -> void:
	var still := ResourceLoader.load(STILL_PATH) as Texture2D
	if still == null:
		print("TitleScreen: 扉の絵が無い＝タイトルを飛ばす: %s" % STILL_PATH)
		_finish()
		return
	_still.texture = still
	visible = true

## 動画を始める。読めなければそのまま終了扱い（絵だけ見せて次へ渡す）。
func _start_video() -> void:
	var stream := ResourceLoader.load(VIDEO_PATH) as VideoStream
	if stream == null:
		print("TitleScreen: 扉の動画が無い＝そのままセレクトへ: %s" % VIDEO_PATH)
		_finish()
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
	if not visible or _done:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not event.is_echo():
		_advance()
		get_viewport().set_input_as_handled()

## 1回目の入力＝扉を開ける。2回目（再生中）＝スキップしてセレクトへ。
func _advance() -> void:
	if _done:
		return
	if _playing:
		_finish()
	else:
		_start_video()

func _finish() -> void:
	if _done:
		return
	_done = true
	_playing = false
	_video.stop()
	visible = false
	finished.emit()
