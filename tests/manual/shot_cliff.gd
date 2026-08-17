extends SceneTree
## 使い捨て：崖（cliff）が盤上でどう見えるかを撮る。全景と寄りの2枚。
## 実行: godot --path . -s res://tests/manual/shot_cliff.gd -- <出力ディレクトリの絶対パス>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const STAGE := "res://data/stages/tutorial3-dragon-hunt/st3.json"
const NEAR_HEX := Vector2i(4, 9)   # 崖の帯と台地の境目（offset col,row）
## 崖の高さの上書き（第2引数）。負＝穴。省略時は CSV のまま。
## CSV の検証は elevation>=0 を要求するので、負の検討はここで実行時に差し替える。

var _main: Node
var _dir := ""
var _tag := ""
var _elev := INF
var _frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	if args.size() >= 2:
		_elev = float(args[1])
		_tag = "_%s" % args[1]
	root.size = Vector2i(1280, 720)
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		_main._title.close()
		_main._select.close()
		if _elev != INF:
			TerrainSkinCatalog.skin_by_id("cliff").elevation = _elev
		_main.load_stage(STAGE)
	if _frames == 50:
		_save("cliff_full")
	if _frames == 55:
		_zoom_in()
	if _frames == 80:
		_save("cliff_near")
		return true
	return false

func _zoom_in() -> void:
	var board: Node = _main.get_node("HexBoard")
	var cam: BoardCamera = board._board_cam
	cam.target = board._hex_world(Hex.offset_to_axial(NEAR_HEX.x, NEAR_HEX.y))
	cam.dist = 7.0
	cam.update_rig()

func _save(name: String) -> void:
	var out := "%s/%s%s.png" % [_dir, name, _tag]
	root.get_texture().get_image().save_png(out)
	print("saved: ", out)
