extends SubViewportContainer
class_name CombatGround3D
## 戦闘演出シーンの地面（3D）。盤と同じ地形タイルPNGを床に寝かせ、俯瞰カメラで撮った絵を
## 演出窓の背景にする。立ち絵とエフェクトは2Dのまま上に重なる。仕様 → doc/tech/combat_scene.md
##
## 地面は盤の並びを写さず、地形（スキン）ごとのレシピで組む＝同じ地形なら毎回同じ構図になり読める。
## レシピは terrain_skin.csv の2列（combat_ground＝下地スキン／combat_layout＝自分の絵の置き方）:
##   fill   … そのスキンで一面に敷き詰める（既定＝表に書かないスキンは全部これ）
##   line   … 下地を敷き、両隊列の間を縦に横切る1列だけそのスキン（柵・道・城壁）
##   center … 下地を敷き、守り手側の1マスだけそのスキン（拠点・罠）
## 既定が敷き詰めなので、レシピの無いスキンでも必ず何かは映る（背景画像方式のような穴が開かない）。

const TILE := 1.0            # ワールドでの hex サイズ（盤と同じ＝タイルPNGの見え方が揃う）
const CAM_PITCH_DEG := 62.0  # 俯角。盤(52°)より立てる＝寄っても遠近が急にならず、地平も映らない
const CAM_FOV := 42.0
const VIEW_COLS := 4.0       # 窓の横幅に見せる列数（小さいほど寄る）。1列＝TILE*1.5
const LINE_HALF := 8         # line レシピで敷く縦列の長さ（中心から上下へ・画面外まで伸ばす）
const FEATURE_POS := Vector2(1.4, 0.6)  # center レシピの目標点（守り手側・地面のワールド座標。x は左側で反転）
const BG_COLOR := Color(0.10, 0.11, 0.12)  # タイルの外側（通常は見えない）

var _vp: SubViewport
var _cam: Camera3D
var _tiles: Node3D
var _built := ""  # 直前に組んだ内容のキー（スキン＋側＋窓サイズ）。同じなら組み直さない

func _init() -> void:
	stretch = true  # SubViewport のサイズをコンテナに追従させる
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true  # 盤の World3D とは分ける（盤のカメラ・ライトの影響を受けない）
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE  # 閉じている間は描かない
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG_COLOR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_vp.add_child(_cam)
	_cam.make_current()
	_tiles = Node3D.new()
	_vp.add_child(_tiles)

## 守り手の地形スキンで地面を組む。def_side は守り手が画面のどちら側か（"L"/"R"）。
## skin が null なら地面を空にする＝窓の地形色（CombatScene の下地）がそのまま出る。
func build(skin: TerrainSkin, def_side: String) -> void:
	var key := "%s|%s|%s" % [skin.skin_id if skin != null else "", def_side, str(size)]
	if key == _built:
		return  # 同じ地形の連戦では組み直さない
	_built = key
	_clear()
	_place_camera()
	if skin == null:
		return
	var ground := TerrainSkinCatalog.skin_by_id(skin.combat_ground_id())
	if ground == null:
		ground = skin
	var feature := _feature_cells(skin, def_side)
	for hex in _ground_hexes():
		var s := skin if feature.has(hex) else ground
		_add_tile(hex, s, feature)

## そのスキンの絵を置くヘックス（レシピ別）。fill は空＝全面が「自分の絵」になるので下地と一致する。
func _feature_cells(skin: TerrainSkin, def_side: String) -> Dictionary:
	var cells := {}
	match skin.combat_placement():
		"line":
			# q=0 の列＝画面を縦に横切る1本（Hex.to_pixel は q がワールドx＝画面の横）。
			# 両隊列の真ん中を柵や道が走る絵になる。
			for r in range(-LINE_HALF, LINE_HALF + 1):
				cells[Vector2i(0, r)] = true
		"center":
			cells[_defender_hex(def_side)] = true
		_:
			pass  # fill＝下地がそのまま自分の絵
	return cells

## 守り手の隊列の足元あたりのヘックス（拠点・罠を置く場所）。画面の左右どちら側かで振り分ける。
## 目標点は隊列の重心の足元＝窓の横 0.75 あたり・縦は中央より少し手前（立ち絵の足元の平均）。
## 実際に敷くのはそこに一番近いヘックス（格子にスナップする）。
func _defender_hex(def_side: String) -> Vector2i:
	var p := FEATURE_POS
	if def_side == "L":
		p.x = -p.x
	return Hex.from_pixel(p * TILE, TILE)

func _add_tile(hex: Vector2i, skin: TerrainSkin, feature: Dictionary) -> void:
	var texs := TerrainTiles.variants(_image_path(hex, skin, feature))
	if texs.is_empty():
		return  # 絵が無いスキンは敷かない（窓の地形色が透ける＝どこが未整備か分かる）
	var mi := MeshInstance3D.new()
	mi.mesh = TerrainTiles.hex_mesh(TILE)
	mi.material_override = TerrainTiles.material(texs[TerrainTiles.variant_index(hex, texs.size())])
	var p := Hex.to_pixel(hex, TILE)
	mi.position = Vector3(p.x, 0.0, p.y)  # 標高は付けない（地面は平ら・立ち絵は2Dで上に載る）
	if skin.orientable:
		TerrainTiles.orient(mi, hex)
	_tiles.add_child(mi)

## そのヘックスに敷くPNG。線地形（柵・道）は feature の並びから接続タイルを選ぶ＝盤と同じ絵で繋がる。
func _image_path(hex: Vector2i, skin: TerrainSkin, feature: Dictionary) -> String:
	if skin.connect and feature.has(hex):
		var connected: Array = []
		for d in Hex.DIRECTIONS:
			connected.append(feature.has(hex + d))
		var p := skin.connected_image_path(connected)
		if ResourceLoader.exists(p):
			return p
	return skin.image_path()

## カメラを窓のサイズに合わせて置く（俯角固定・原点を見る）。窓の横幅に VIEW_COLS 列ぶん入る距離。
func _place_camera() -> void:
	var vp := Vector2(_vp.size)
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var world_w := VIEW_COLS * TILE * 1.5  # 列の間隔は 1.5*TILE（flat-top）
	var dist := world_w / (2.0 * tan(deg_to_rad(CAM_FOV) * 0.5) * (vp.x / vp.y))
	var pitch := deg_to_rad(CAM_PITCH_DEG)
	_cam.position = Vector3(0.0, sin(pitch), cos(pitch)) * dist
	_cam.look_at(Vector3.ZERO, Vector3.UP)

## 窓に映る範囲を覆うヘックス一覧。画面4隅のレイを地面(y=0)に落とした矩形を、
## 半マス刻みで舐めて拾う（取りこぼしなく、余分も少ない）。
func _ground_hexes() -> Array:
	var vp := Vector2(_vp.size)
	if vp.x <= 0.0 or vp.y <= 0.0:
		return []
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for c: Vector2 in [Vector2(0, 0), Vector2(vp.x, 0), Vector2(0, vp.y), vp]:
		var p := _plane_point(c)
		if not p.is_finite():
			return Hex.within_range(Vector2i.ZERO, 8)  # 地平が映る画角＝広めに敷いて逃げる
		mn = mn.min(Vector2(p.x, p.z))
		mx = mx.max(Vector2(p.x, p.z))
	mn -= Vector2(TILE, TILE)  # タイルの半径ぶん外まで＝縁で欠けない
	mx += Vector2(TILE, TILE)
	var cells := {}
	var step := TILE * 0.5
	var y := mn.y
	while y <= mx.y:
		var x := mn.x
		while x <= mx.x:
			cells[Hex.from_pixel(Vector2(x, y), TILE)] = true
			x += step
		y += step
	return cells.keys()

## screen 直下の地面(y=0)上の点。交差しない（水平線より上）なら Vector3.INF。
func _plane_point(screen: Vector2) -> Vector3:
	var o := _cam.project_ray_origin(screen)
	var d := _cam.project_ray_normal(screen)
	if absf(d.y) < 1e-6:
		return Vector3.INF
	var t := (0.0 - o.y) / d.y
	if t < 0.0:
		return Vector3.INF
	return o + d * t

func _clear() -> void:
	for c in _tiles.get_children():
		_tiles.remove_child(c)
		c.free()
