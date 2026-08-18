extends SceneTree
## 使い捨て：マップエディタの盤の高さ編集（番号帯の常時表示・その場の入力欄）を撮る。
## 実行: godot --path . -s res://tests/manual/shot_map_editor_height.gd -- <出力ディレクトリの絶対パス>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const STAGE := "res://data/stages/debug-skins/terrain.json"

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
		# 奥へ上がる行と、右で上がる列を入れて帯の表示を出す
		var doc: MapEditorDoc = _editor._doc
		for r in doc.rows():
			doc.set_row_height(r, snappedf(float(doc.rows() - 1 - r) * 0.18, 0.01))
		doc.set_col_height(doc.cols() - 1, -0.5)  # 負の値の表示幅も見る
		_editor._board.refresh()
	if _frames == 40:
		_save("map_editor_height_labels")
	if _frames == 45:
		_editor._board._open_height_editor("col", 3)  # 上の帯の入力欄
	if _frames == 55:
		_save("map_editor_height_edit_col")
	if _frames == 60:
		_editor._board._open_height_editor("row", 2)  # 左の帯の入力欄
	if _frames == 70:
		_save("map_editor_height_edit_row")
		return true
	return false

func _save(name: String) -> void:
	var out := "%s/%s.png" % [_dir, name]
	root.get_texture().get_image().save_png(out)
	print("saved: ", out)
