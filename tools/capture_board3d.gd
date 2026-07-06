extends Node3D
## 【使い捨て・実験】盤を「傾けた Camera3D＋床に寝かせたヘックス＋立てた Sprite3D」で描く 3D プローブ。
## image1 タイプ（見た目は2D絵のまま／カメラだけ傾ける）の見え方を素早く確認するための検証シーン。
## 地形テクスチャ・ユニット絵は既存アセットをそのまま流用（描き直し無し）。
## 実行: godot --path . res://tools/capture_board3d.tscn -- <出力PNGの絶対パス>
## リポジトリの本流には残さない前提（実験ブランチのプローブ）。

const TILE := 1.0  # ワールドでの hex サイズ（中心〜頂点）

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var out := "board3d.png"
	var uargs := OS.get_cmdline_user_args()
	if uargs.size() > 0:
		out = uargs[0]

	var path := "res://data/stages/debug/debug.json"
	var skins := SkinCatalog.load_standard()
	var tskins := StageLoader.load_terrain_skins(path)
	var state := StageLoader.load_file(path)
	if state == null:
		push_error("capture3d: ステージを読めない: %s" % path)
		get_tree().quit(1)
		return

	# --- 環境・ライト ---
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.16, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.80, 0.83, 0.88)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_energy = 1.0
	add_child(sun)

	# --- タイル（床に寝かせたヘックスメッシュ＋地形テクスチャ）---
	var hex_mesh := _make_hex_mesh()
	var centers: Array[Vector3] = []
	for col in state.cols:
		for row in state.rows:
			var hex := Hex.offset_to_axial(col, row)
			var p := Hex.to_pixel(hex, TILE)
			var wpos := Vector3(p.x, 0.0, p.y)
			centers.append(wpos)
			_add_tile(hex_mesh, hex, wpos, state, tskins)

	# --- ユニット（立てた Sprite3D ビルボード）---
	for u in state.units():
		var p := Hex.to_pixel(u.pos, TILE)
		_add_unit(u, Vector3(p.x, 0.0, p.y), skins)

	# --- 盤中心と広がり ---
	var c := Vector3.ZERO
	for w in centers:
		c += w
	c /= float(maxi(centers.size(), 1))
	var maxr := 1.0
	for w in centers:
		maxr = maxf(maxr, (w - c).length())

	# --- 地面（盤が虚空に浮かないよう下地）---
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(maxr * 6.0 + 20.0, maxr * 6.0 + 20.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.40, 0.27)
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.material_override = gm
	ground.position = c + Vector3(0, -0.02, 0)
	add_child(ground)

	# --- カメラ（俯角 ~52°）---
	var cam := Camera3D.new()
	cam.fov = 42.0
	var pitch := deg_to_rad(52.0)
	var dist := maxr * 1.9 + 4.0
	cam.position = c + Vector3(0.0, sin(pitch) * dist, cos(pitch) * dist)
	add_child(cam)        # look_at はツリー内でないと使えない
	cam.look_at(c, Vector3.UP)
	cam.make_current()

	# 地形テクスチャ・シェーダのウォームアップに数フレーム回す。
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	print("CAPTURE_SAVED err=", img.save_png(out), " path=", out)
	get_tree().quit(0)

## 床(XZ)に寝かせたフラットトップ六角メッシュ（中心ファン）。UVはテクスチャの外接に合わせる。
func _make_hex_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		verts.append(Vector3(cos(a) * TILE, 0.0, sin(a) * TILE))
	for i in 6:
		var a0 := deg_to_rad(60.0 * i)
		var a1 := deg_to_rad(60.0 * (i + 1))
		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5)); st.add_vertex(verts[i])
		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5)); st.add_vertex(verts[(i + 1) % 6])
	return st.commit()

func _add_tile(hex_mesh: ArrayMesh, hex: Vector2i, wpos: Vector3, state, tskins: Dictionary) -> void:
	var skin := TerrainSkinCatalog.resolve(tskins.get(hex, ""), state.terrain_at(hex))
	if skin == null:
		return
	var tex := load(skin.image_path()) as Texture2D
	if tex == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = hex_mesh
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # 2D canvas と同じ＝テクスチャ本来の色（露出で飛ばさない）
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.position = wpos
	add_child(mi)

func _add_unit(u, wpos: Vector3, skins: Dictionary) -> void:
	var s := SkinCatalog.resolve(skins, u.skin_id, u.type_id, u.team)
	if s == null:
		return
	var p: String = s.image("map")
	if p == "":
		return
	var tex := load(p) as Texture2D
	if tex == null:
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # 常にカメラへ正対＝全身の立ち姿のまま（俯瞰でも潰れない）
	spr.shaded = false
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD    # 透過はカット（半透明ソート回避で常に手前/奥が正しい）
	spr.pixel_size = (2.5 * TILE) / float(tex.get_height())  # 高さ ~2.5 タイル
	spr.offset = Vector2(0, tex.get_height() * 0.5)     # 絵を上へ寄せ、ノード原点＝足元に（回転軸を足に）
	spr.position = wpos + Vector3(0, 0.02, 0)           # 足を地面へ接地（微上げでZファイト回避）
	add_child(spr)
