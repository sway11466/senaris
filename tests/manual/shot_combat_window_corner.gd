extends SceneTree
## 使い捨て：戦闘窓の角の形（斜めカット→角丸）を撮る。全景と左上の角の拡大。
## 実行: godot --path . -s res://tests/manual/shot_combat_window_corner.gd -- <出力ディレクトリの絶対パス> <接尾辞>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const L := { "team": 0, "type_id": "fighter", "skin_id": "fighter", "terrain": "plain", "troops_before": 8 }
const R := { "team": 1, "type_id": "fighter", "skin_id": "orc", "terrain": "plain", "troops_before": 8 }

var _stage: CombatScene
var _dir := ""
var _tag := "before"
var _frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	if args.size() > 1:
		_tag = String(args[1])
	root.size = Vector2i(1280, 720)
	_stage = CombatScene.new()
	root.add_child(_stage)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_stage.bind(SkinCatalog.load_standard())
		_stage._open(R, "R", L)
		_stage._render_side("L", L, 8)
		_stage._render_side("R", R, 8)
	if _frames == 40:  # 幕開けのワイプが開ききってから撮る
		var img := root.get_texture().get_image()
		img.save_png("%s/window_corner_%s.png" % [_dir, _tag])
		# 左上の角を切り出して4倍に拡大＝斜めか丸かを目で確かめられる大きさにする
		var crop := img.get_region(Rect2i(_corner_origin(), Vector2i(120, 120)))
		crop.resize(480, 480, Image.INTERPOLATE_NEAREST)
		crop.save_png("%s/window_corner_%s_zoom.png" % [_dir, _tag])
		print("saved: ", _dir, "/window_corner_", _tag, ".png")
		return true
	return false

## 窓の左上の角の画面座標（CombatStage のレイアウトと同じ計算）。
func _corner_origin() -> Vector2i:
	var board := UiLayout.board_area(Vector2(1280, 720))
	var area := Vector2(min(board.size.x * 0.90, 740.0), min(board.size.y * 0.62, 520.0))
	return Vector2i((board.position + (board.size - area) * 0.5).round()) - Vector2i(10, 10)
