extends SceneTree
## 使い捨て：盤に立った拠点「町」(road_fort_town1) を、味方／中立／敵の3つ並べて撮る。
## debug-mapops/base.json は町を3つ左から 味方・中立・敵 で置いている。
## 実行: godot --path . -s res://tests/manual/shot_fort_town1_board.gd -- <出力ディレクトリの絶対パス>

const STAGE := "res://data/stages/debug-mapops/base.json"

var _main: Node
var _dir := ""
var _frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		_main._title.close()
		_main._select.close()
		_main.load_stage(STAGE)
	if _frames == 40:
		_main._conversation._on_skip()  # 冒頭の会話を畳んで盤を明るく戻す
	if _frames == 80:
		var img := root.get_texture().get_image()
		img.save_png("%s/fort_town1_board.png" % _dir)
		var crop := img.get_region(Rect2i(40, 240, 720, 260))
		crop.resize(1440, 520, Image.INTERPOLATE_NEAREST)
		crop.save_png("%s/fort_town1_board_zoom.png" % _dir)
		print("saved: %s/fort_town1_board.png" % _dir)
		return true
	return false
