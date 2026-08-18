extends SceneTree
## 使い捨て：盤の基準高さ（行＋列）の見え方を撮る。ステージJSONを触らず、実行時に注入する。
## 実行: godot --path . -s res://tests/manual/shot_board_height.gd -- <出力ディレクトリの絶対パス>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const STAGE := "res://data/stages/debug-skins/terrain.json"
const STEP := 0.30   # 1行/1列あたりの上がり幅（ワールド・TILE=1）

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
		_measure_pick(_main.get_node("HexBoard"))
		_verify_pick(_main.get_node("HexBoard"))
		_save("height_flat")
	if _frames == 45:
		_apply(true, false)   # 奥へ向かって上がる
	if _frames == 65:
		_measure_pick(_main.get_node("HexBoard"))
		_verify_pick(_main.get_node("HexBoard"))
		_save("height_rows")
	if _frames == 70:
		_apply(true, true)    # 行＋列＝左上から右下へ流れる
	if _frames == 90:
		_measure_pick(_main.get_node("HexBoard"))
		_verify_pick(_main.get_node("HexBoard"))
		_save("height_diagonal")
		return true
	return false

## 行・列の基準高さを注入して盤を組み直す。
func _apply(use_rows: bool, use_cols: bool) -> void:
	var board: Node = _main.get_node("HexBoard")
	var tr: BoardTerrainRenderer = board._terrain_renderer
	var state = board.state
	var rows: Array = []
	var cols: Array = []
	if use_rows:
		for r in state.rows:
			rows.append(float(state.rows - 1 - r) * STEP)  # 奥（row0）ほど高い
	if use_cols:
		for c in state.cols:
			cols.append(float(c) * STEP)
	tr._board_height = { "row": rows, "col": cols }
	tr.build_tiles()
	board._sync()
	board.fit_to_view()

func _save(name: String) -> void:
	var out := "%s/%s.png" % [_dir, name]
	root.get_texture().get_image().save_png(out)
	print("saved: ", out)

## 当たり判定のコスト。高さの種類が増えると総当たりが伸びるので実測する。
func _measure_pick(board: Node) -> void:
	var levels: Array = board._terrain_renderer.elev_levels()
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		board._hex_at_mouse()
	var us := (Time.get_ticks_usec() - t0) / 1000.0
	print("pick: 高さの種類=%d / 1回あたり %.1f us" % [levels.size(), us])

## 当たり判定の往復チェック：各マスの中心（そのマスの高さ）を画面へ投影し、
## その画面座標から引いたヘックスが元のマスに戻るか。段差があっても指したマスが取れることの確認。
func _verify_pick(board: Node) -> void:
	var state = board.state
	var cam: BoardCamera = board._board_cam
	var ok := 0
	var ng := 0
	for col in state.cols:
		for row in state.rows:
			var hex := Hex.offset_to_axial(col, row)
			var w: Vector3 = board._hex_world(hex)
			if cam.camera.is_position_behind(w):
				continue
			var got: Vector2i = board._hex_at_screen(cam.camera.unproject_position(w))
			if got == hex:
				ok += 1
			else:
				ng += 1
				if ng <= 3:
					print("  ずれ: %s -> %s" % [hex, got])
	print("pick往復: 一致 %d / ずれ %d" % [ok, ng])
