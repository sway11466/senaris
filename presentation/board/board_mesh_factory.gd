extends RefCounted
class_name BoardMeshFactory
## 盤面で使うメッシュ・材質の生成ヘルパー（純関数 + 色キャッシュ）。
## hex_board_3d.gd から切り出した。TerrainTiles と同じ流儀＝static 関数・状態なし。

# --- キャッシュ ---
static var _overlay_mat := {}  # Color -> StandardMaterial3D
static var _bill_mat := {}     # Color -> StandardMaterial3D

# =========================================================================
# メッシュ生成
# =========================================================================

## 床(XZ)に寝かせたフラットトップ六角メッシュ。TerrainTiles と共有。
static func make_hex_mesh(tile_size: float) -> ArrayMesh:
	return TerrainTiles.hex_mesh(tile_size)

## 拠点の縁取り＝六角の枠メッシュ（タイルの外側に張り出す帯）。
## 内側へ食い込ませるとタイルの絵を隠す（町スキンは六角いっぱいに描かれている）。
## 帯をヘックスの外へ出し、隣のタイルの上に乗せることで、絵を欠かさず所属を示す。
static func make_hexring_mesh(tile_size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_out := tile_size * 1.10
	var r_in := tile_size * 1.00
	for i in 6:
		var a0 := deg_to_rad(60.0 * i)
		var a1 := deg_to_rad(60.0 * (i + 1))
		var o0 := Vector3(cos(a0) * r_out, 0.0, sin(a0) * r_out)
		var o1 := Vector3(cos(a1) * r_out, 0.0, sin(a1) * r_out)
		var i0 := Vector3(cos(a0) * r_in, 0.0, sin(a0) * r_in)
		var i1 := Vector3(cos(a1) * r_in, 0.0, sin(a1) * r_in)
		st.set_normal(Vector3.UP); st.add_vertex(o0)
		st.set_normal(Vector3.UP); st.add_vertex(o1)
		st.set_normal(Vector3.UP); st.add_vertex(i0)
		st.set_normal(Vector3.UP); st.add_vertex(i1)
		st.set_normal(Vector3.UP); st.add_vertex(i0)
		st.set_normal(Vector3.UP); st.add_vertex(o1)
	return st.commit()

## 床(XZ)の楕円メッシュ（ブロブシャドウ用。z_ratio でつぶす）。24分割。
static func make_disc_mesh(radius: float, z_ratio: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		st.set_normal(Vector3.UP); st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP); st.add_vertex(Vector3(cos(a0) * radius, 0.0, sin(a0) * radius * z_ratio))
		st.set_normal(Vector3.UP); st.add_vertex(Vector3(cos(a1) * radius, 0.0, sin(a1) * radius * z_ratio))
	return st.commit()

## 床(XZ)の円環メッシュ（32分割の帯）。選択/攻撃/閲覧/包囲リング用。
static func make_ring_mesh(radius: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	var r0 := radius - width * 0.5
	var r1 := radius + width * 0.5
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var o0 := Vector3(cos(a0) * r1, 0.0, sin(a0) * r1)
		var o1 := Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
		var i0 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var i1 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
		st.set_normal(Vector3.UP); st.add_vertex(o0)
		st.set_normal(Vector3.UP); st.add_vertex(o1)
		st.set_normal(Vector3.UP); st.add_vertex(i0)
		st.set_normal(Vector3.UP); st.add_vertex(i1)
		st.set_normal(Vector3.UP); st.add_vertex(i0)
		st.set_normal(Vector3.UP); st.add_vertex(o1)
	return st.commit()

## 足元の光の円盤。中心が不透明・外周が透明の頂点カラーを持つ。32分割。
static func make_glow_mesh(radius: float, z_ratio: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		st.set_color(Color(1, 1, 1, 1)); st.set_normal(Vector3.UP); st.add_vertex(Vector3.ZERO)
		st.set_color(Color(1, 1, 1, 0)); st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cos(a0) * radius, 0.0, sin(a0) * radius * z_ratio))
		st.set_color(Color(1, 1, 1, 0)); st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cos(a1) * radius, 0.0, sin(a1) * radius * z_ratio))
	return st.commit()

## 足元の光の輪。内周と外周が透明・その中間が不透明の帯。32分割×2段。
## 塗りの外側に置くので、弱体の塗りと強化の輪が同じ足元に出ても互いを潰さない。
static func make_glow_ring_mesh(r_in: float, r_out: float, z_ratio: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	var r_mid := (r_in + r_out) * 0.5
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		# 内周→中間→外周の2段の帯。中間だけ不透明にして、両端へなだらかに消す。
		for band in [[r_in, 0.0, r_mid, 1.0], [r_mid, 1.0, r_out, 0.0]]:
			var ri: float = band[0]
			var ai: float = band[1]
			var ro: float = band[2]
			var ao: float = band[3]
			var p0 := Vector3(cos(a0) * ri, 0.0, sin(a0) * ri * z_ratio)
			var p1 := Vector3(cos(a1) * ri, 0.0, sin(a1) * ri * z_ratio)
			var q0 := Vector3(cos(a0) * ro, 0.0, sin(a0) * ro * z_ratio)
			var q1 := Vector3(cos(a1) * ro, 0.0, sin(a1) * ro * z_ratio)
			st.set_color(Color(1, 1, 1, ai)); st.set_normal(Vector3.UP); st.add_vertex(p0)
			st.set_color(Color(1, 1, 1, ai)); st.set_normal(Vector3.UP); st.add_vertex(p1)
			st.set_color(Color(1, 1, 1, ao)); st.set_normal(Vector3.UP); st.add_vertex(q0)
			st.set_color(Color(1, 1, 1, ao)); st.set_normal(Vector3.UP); st.add_vertex(q0)
			st.set_color(Color(1, 1, 1, ai)); st.set_normal(Vector3.UP); st.add_vertex(p1)
			st.set_color(Color(1, 1, 1, ao)); st.set_normal(Vector3.UP); st.add_vertex(q1)
	return st.commit()

## スカート用の粒状ノイズ（グレースケール・シームレス）。頂点カラーに乗算されて土の質感になる。
## 変化幅は控えめ（0.78〜1.0倍）＝べた塗り感だけ消し、色は頂点グラデに任せる。
static func make_skirt_texture() -> ImageTexture:
	var fn := FastNoiseLite.new()
	fn.seed = 7  # 決定的（毎回同じ見た目）
	fn.frequency = 0.05
	fn.fractal_octaves = 4
	var img := fn.get_seamless_image(256, 256)
	for y in 256:
		for x in 256:
			var v := img.get_pixel(x, y).r          # ノイズ値 0..1
			var g := 0.78 + v * 0.22                 # 控えめな明暗に圧縮
			img.set_pixel(x, y, Color(g, g, g))
	return ImageTexture.create_from_image(img)

# =========================================================================
# 三角メッシュ（攻撃対象マーカー）
# =========================================================================

## 下向き三角の頂点（XY平面・原点＝下の先端）。ビルボード材質と組んで頭上マーカーにする。
static func tri_points(w: float, h: float) -> Array[Vector2]:
	return [Vector2(-w * 0.5, h), Vector2(0.0, 0.0), Vector2(w * 0.5, h)]

## 三角形の3辺すべてを外へ e だけ等距離に押し出した三角形（＝縁取りの下敷き）。
## 幅と高さを増やしただけの相似形では、上辺と斜辺で張り出しが2倍ちがう（上辺0.045に対し
## 斜辺0.022＝実測）ので、輪郭ではなく上辺の帽子に見える。内接円の半径が r→r+e に増えた
## 相似形＝内心を中心に (r+e)/r 倍すれば、どの辺からも距離 e で揃う。
static func outset_tri(p: Array[Vector2], e: float) -> Array[Vector2]:
	var a := p[1].distance_to(p[2])  # 各頂点の対辺の長さ（内心の重み）
	var b := p[2].distance_to(p[0])
	var c := p[0].distance_to(p[1])
	var per := a + b + c
	var area := absf((p[1] - p[0]).cross(p[2] - p[0])) * 0.5
	if per <= 0.0 or area <= 0.0:
		return p
	var incenter := (p[0] * a + p[1] * b + p[2] * c) / per
	var r := area / (per * 0.5)  # 内接円の半径
	var k := (r + e) / r
	return [
		incenter + (p[0] - incenter) * k,
		incenter + (p[1] - incenter) * k,
		incenter + (p[2] - incenter) * k,
	]

## 頂点3つ（XY平面）を三角のメッシュにする。裏面も描く前提で巻き順は問わない。
static func make_tri_mesh(p: Array[Vector2]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in p:
		st.set_normal(Vector3.BACK); st.add_vertex(Vector3(v.x, v.y, 0.0))
	return st.commit()

# =========================================================================
# 材質生成
# =========================================================================

## ユニットスキル中の足元の光の材質（加算 or 通常合成）。明滅は共有の1材質を _process が
## 書き換える＝掛かっている駒が同じ位相で光る。
static func make_glow_material(color: Color, additive: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true  # 中心→外周のアルファ落ちは頂点カラーで作る
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## 頭上マーカーの材質。深度判定を切って常に最前面に描く＝地形にも他の駒にも隠れない。
## 重なり順は render_priority だけで決まるので、縁取り→本体の順に上げる。
static func make_mark_material(color: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = priority
	return m

## タイル材質（アンライト＝2D canvas と同じ発色）。TerrainTiles と共有。
static func terrain_material(tex: Texture2D) -> StandardMaterial3D:
	return TerrainTiles.material(tex)

## オーバーレイ材質（半透明・アンライト）。色ごとにキャッシュ。
static func overlay_material(color: Color) -> StandardMaterial3D:
	if _overlay_mat.has(color):
		return _overlay_mat[color]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay_mat[color] = m
	return m

## ビルボード材質（兵数バー用・アンライト・半透明可）。色ごとにキャッシュ。
static func bill_material(color: Color) -> StandardMaterial3D:
	if _bill_mat.has(color):
		return _bill_mat[color]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	_bill_mat[color] = m
	return m
