extends SceneTree
## 使い捨て：柵を「上から見た絵」ではなく「ワールドに立てた板」で描いたらどう見えるかのモック。
## 実装ではない。盤を組んだあとに外から板を足し、柵タイルの絵は下地(平地)に差し替えて隠している。
## 実行: godot --path . -s res://tests/manual/mock_fence_height.gd -- <出力ディレクトリの絶対パス>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const STAGE := "res://data/stages/tutorial2-undead-rush/st4.json"
const TILE := 1.0                         # 盤と同値
const HEIGHT := 0.34                      # 柵の高さ（ワールド・TILE=1）
const NEAR_HEX := Vector2i(2, 1)          # 寄りで見る柵（offset col,row）

# 辺 i（コーナー i→i+1）に対応する隣接方向（フラットトップ axial）。スカートと同じ並び。
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
]

var _main: Node
var _dir := ""
var _panel := ""   # 仮の板テクスチャの絶対パス（第2引数）
var _frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	_panel = args[1] if args.size() >= 2 else ""
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
		_build_fences()
	if _frames == 60:
		_save("fence_height_full")
	if _frames == 65:
		_zoom_in()
	if _frames == 90:
		_save("fence_height_near")
		return true
	return false

## 柵のマスを平地に見せかけ、隣の柵へ向かって立て板を張る。
func _build_fences() -> void:
	var board: Node = _main.get_node("HexBoard")
	var tr: BoardTerrainRenderer = board._terrain_renderer
	var state = board.state
	var tex := _panel_texture()
	var ground := load("res://assets/terrain/plain.png") as Texture2D

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for col in state.cols:
		for row in state.rows:
			var hex := Hex.offset_to_axial(col, row)
			if state.terrain_at(hex) != "fence":
				continue
			# 上から見た柵の絵を消す＝下地の平地に差し替え（板だけを見せるため）
			var mi: MeshInstance3D = tr._tile_nodes.get(hex)
			if mi != null and ground != null:
				mi.material_override = BoardMeshFactory.terrain_material(ground)
			var p := Hex.to_pixel(hex, TILE)
			var y := tr.elev(hex)
			for i in 6:
				var nb := hex + DIRS[i]
				var o := Hex.axial_to_offset(nb)
				if o.x < 0 or o.x >= state.cols or o.y < 0 or o.y >= state.rows:
					continue
				if state.terrain_at(nb) != "fence":
					continue
				var q := Hex.to_pixel(nb, TILE)
				var a := Vector3(p.x, y, p.y)                              # ヘックス中心
				var b := Vector3((p.x + q.x) * 0.5, y, (p.y + q.y) * 0.5)  # 辺の中点
				_add_panel(st, a, b)

	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = m
	tr.add_child(node)

## a→b に立てた板（高さ HEIGHT）。UVは横1回・縦1回。
func _add_panel(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var up := Vector3(0, HEIGHT, 0)
	var a1 := a + up
	var b1 := b + up
	st.set_uv(Vector2(0, 1)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(b)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a1)
	st.set_uv(Vector2(1, 1)); st.add_vertex(b)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b1)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a1)

func _panel_texture() -> Texture2D:
	var img := Image.new()
	if img.load(_panel) != OK:
		push_error("板テクスチャが読めない: %s" % _panel)
		return null
	return ImageTexture.create_from_image(img)

func _zoom_in() -> void:
	var board: Node = _main.get_node("HexBoard")
	var cam: BoardCamera = board._board_cam
	cam.target = board._hex_world(Hex.offset_to_axial(NEAR_HEX.x, NEAR_HEX.y))
	cam.dist = 6.0
	cam.update_rig()

func _save(name: String) -> void:
	var out := "%s/%s.png" % [_dir, name]
	root.get_texture().get_image().save_png(out)
	print("saved: ", out)
