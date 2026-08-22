extends SceneTree
## 使い捨て：奥の背景 sky_clear を、町 road_fort_town1 をゴブリンが守る戦闘で撮る（720p / 1080p）。
## 実行: godot --path . -s res://tests/manual/shot_sky_clear_combat.gd -- <出力ディレクトリの絶対パス>

const L := { "team": 0, "type_id": "fighter", "skin_id": "fighter", "terrain": "plain", "pos": Vector2i(5, 3), "troops_before": 8 }
const R := { "team": 1, "type_id": "fighter", "skin_id": "goblin", "terrain": "fort", "pos": Vector2i(6, 3), "troops_before": 8 }

var _stage: CombatScene
var _dir := ""
var _frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	_stage = CombatScene.new()
	root.add_child(_stage)
	_stage.bind(SkinCatalog.load_standard())
	_stage.bind_terrain_skins({ L.pos: "plain", R.pos: "road_fort_town1" })
	_stage.bind_state(BattleState.new())
	_stage.bind_backdrop("sky_clear")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_open()
	if _frames == 40:
		_save("720p")
		root.size = Vector2i(1920, 1080)
		_open()
	if _frames == 80:
		_save("1080p")
		return true
	return false

func _open() -> void:
	_stage._open(R, "R", L)
	_stage._render_side("L", L, 8)
	_stage._render_side("R", R, 8)

func _save(what: String) -> void:
	var path := "%s/sky_clear_%s.png" % [_dir, what]
	root.get_texture().get_image().save_png(path)
	print("saved: ", path)
