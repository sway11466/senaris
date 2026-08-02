extends RefCounted
class_name TerrainTiles
## 地形タイルを3Dに敷くための共有ヘルパー（メッシュ・材質・変種読み込み）。
## 盤（hex_board_3d）と戦闘演出の地面（combat_ground_3d）が、同じPNGを同じ発色・同じ敷き分けで
## 使うための土台。どのPNGを引くか（拠点のチーム別絵・線地形の接続タイル）は用途で違うので、
## パス解決は呼び出し側が持つ。キャッシュは static＝盤と演出で共有する。

static var _mesh := {}      # 半径(float) -> ArrayMesh
static var _mat := {}       # Texture2D -> StandardMaterial3D
static var _variants := {}  # 基本パス(String) -> Array[Texture2D]
static var _composed := {}  # "下地の id@重ね絵の id" -> Texture2D（合成結果）

## UV の縦の係数。PNG はヘックスの外接矩形（256×222＝2R × √3R）で切ってあるので、
## 縦は横と同じ 0.5 ではなく 1/√3。0.5 は外接「正方形」（2R × 2R）用の値で、これを使うと
## 絵が縦に 2/√3＝1.155倍 引き伸ばされ、上下端の6.7%が六角形の外に出て描かれない。
## 自然テクスチャでは気付けないが、絵の中に位置の約束を持つ地形（柵・道の接続タイル＝腕の先が
## 辺の中点に来る）は斜めの継ぎ目でずれる。詳細 → doc/art/terrain.md §1
const UV_V := 0.5773502691896258

## 床(XZ)に寝かせたフラットトップ六角メッシュ（中心ファン）。UVはテクスチャの外接矩形。
static func hex_mesh(size: float) -> ArrayMesh:
	if _mesh.has(size):
		return _mesh[size]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var a0 := deg_to_rad(60.0 * i)
		var a1 := deg_to_rad(60.0 * (i + 1))
		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * UV_V)); st.add_vertex(Vector3(cos(a0) * size, 0.0, sin(a0) * size))
		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * UV_V)); st.add_vertex(Vector3(cos(a1) * size, 0.0, sin(a1) * size))
	var m := st.commit()
	_mesh[size] = m
	return m

## タイル材質（アンライト＝2D canvas と同じ発色）。テクスチャごとにキャッシュ。
static func material(tex: Texture2D) -> StandardMaterial3D:
	if _mat.has(tex):
		return _mat[tex]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # 左右反転タイル（scale.x=-1）でも描けるように
	_mat[tex] = m
	return m

## 地形タイルを読む。基本 {name}.png ＋連番 variant（_2, _3 …）。無ければ空配列。
static func variants(base_path: String) -> Array:
	if _variants.has(base_path):
		return _variants[base_path]
	var texs: Array = []
	var base := load(base_path) as Texture2D if ResourceLoader.exists(base_path) else null
	if base != null:
		texs.append(base)
	var stem := base_path.trim_suffix(".png")
	var n := 2
	while true:
		var p := "%s_%d.png" % [stem, n]
		if not ResourceLoader.exists(p):
			break
		var t := load(p) as Texture2D
		if t != null:
			texs.append(t)
		n += 1
	_variants[base_path] = texs
	return texs

## 下地の上に重ね絵を合成した1枚を返す（terrain_skin.csv の map_ground / map_overlay）。
## 地面を絵に焼き込まないための仕組み。同じ絵を別の地面の上に置くたびに64枚を焼き直さずに済み、
## 下地側の variant 敷き分けもそのまま効く。合成は (下地, 重ね絵) の組ごとに1回でキャッシュする。
## どちらか欠けていれば在るほうをそのまま返す。詳細 → doc/art/terrain.md §3.6
static func composited(ground: Texture2D, overlay: Texture2D) -> Texture2D:
	if ground == null:
		return overlay
	if overlay == null:
		return ground
	var key := "%d@%d" % [ground.get_instance_id(), overlay.get_instance_id()]
	if _composed.has(key):
		return _composed[key]
	var under := _rgba(ground)
	var over := _rgba(overlay)
	var tex: Texture2D = null
	if under != null and over != null:
		if over.get_size() != under.get_size():
			over.resize(under.get_width(), under.get_height(), Image.INTERPOLATE_LANCZOS)
		under.blend_rect(over, Rect2i(Vector2i.ZERO, over.get_size()), Vector2i.ZERO)
		tex = ImageTexture.create_from_image(under)
	_composed[key] = tex
	return tex

## テクスチャを編集できる RGBA8 の Image にする（インポート済みは圧縮されていることがある）。
static func _rgba(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate()  # キャッシュ済みの Image を書き換えない
	if img.is_compressed():
		if img.decompress() != OK:
			return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img

## ヘックス座標から決定的に variant を選ぶ（作り直しても同じ絵＝ちらつかない）。
static func variant_index(hex: Vector2i, count: int) -> int:
	if count <= 1:
		return 0
	return absi(hash(hex)) % count

## 向きの無い自然地形を、座標ハッシュで60°回転＋左右反転する（反復対策）。決定的。
## orientable なスキンにだけ適用する（道・柵・拠点は向きが意味を持つので回さない）。
static func orient(mi: MeshInstance3D, hex: Vector2i) -> void:
	var o := absi(hash(Vector2i(hex.y, hex.x)))
	mi.rotation.y = float(o % 6) * (PI / 3.0)
	if (o / 6) % 2 == 1:
		mi.scale = Vector3(-1.0, 1.0, 1.0)  # cull無効なので裏面でも描ける
