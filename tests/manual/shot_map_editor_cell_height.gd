extends SceneTree
## 使い捨て：マップエディタの盤で、マス個別の高さ上書き（elevation）が地形記号の下に出るか撮る。
## 実行: godot --path . -s res://tests/manual/shot_map_editor_cell_height.gd -- <出力ディレクトリの絶対パス>

const STAGE := "res://data/stages/debug-skins/height.json"

var _editor: Node
var _dir := ""
var _frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	_editor = load("res://tools/map_editor/map_editor.tscn").instantiate()
	root.add_child(_editor)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		_editor._on_open_file(ProjectSettings.globalize_path(STAGE))
	if _frames == 30:
		var doc: MapEditorDoc = _editor._doc
		print("overrides: ", doc.elevation_override_map())
	if _frames == 40:
		_save("map_editor_cell_elevation")
	if _frames == 45:
		# 拡大して、地形記号あり／なし・整数／小数／負の値の見え方を並べる
		var doc: MapEditorDoc = _editor._doc
		doc.set_terrain_char(1, 1, "森")
		doc.set_terrain_skin(1, 1, "forest", { "elevation": 2.0, "floor": 2.0 })
		doc.set_terrain_skin(2, 2, "plain", { "elevation": -1.5, "floor": -1.5 })
		doc.set_terrain_char(3, 1, "岩")
		doc.set_terrain_skin(3, 1, "rock", { "elevation": 10.25, "floor": 0.0 })
		_editor._board.hex_size = 48.0
	if _frames == 60:
		_save("map_editor_cell_elevation_zoom")
		return true
	return false

func _save(name: String) -> void:
	var out := "%s/%s.png" % [_dir, name]
	root.get_texture().get_image().save_png(out)
	print("saved: ", out)
