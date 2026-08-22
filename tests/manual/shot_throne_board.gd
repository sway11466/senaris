extends SceneTree
## 使い捨て：玉座 (plain_cave1_fence_throne1) の盤上の見え方を撮る。
## 洞窟のボス部屋を模した使い捨てステージで、ゴブリンロードが玉座のマスに立つ。
## 実行: godot --path . -s res://tests/manual/shot_throne_board.gd -- <出力ディレクトリの絶対パス>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const STAGE := "res://tests/manual/_shots/throne_stage.json"

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
	if _frames == 80:
		var img := root.get_texture().get_image()
		img.save_png("%s/throne_board.png" % _dir)
		var crop := img.get_region(Rect2i(560, 180, 560, 360))
		crop.resize(1120, 720, Image.INTERPOLATE_NEAREST)
		crop.save_png("%s/throne_board_zoom.png" % _dir)
		print("saved: %s/throne_board.png" % _dir)
		return true
	return false
