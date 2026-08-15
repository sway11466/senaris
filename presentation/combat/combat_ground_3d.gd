extends SubViewportContainer
class_name CombatGround3D
## 戦闘演出シーンの地面（3D）。盤と同じ地形タイルPNGを床に寝かせ、俯瞰カメラで撮った絵を
## 演出窓の背景にする。立ち絵とエフェクトは2Dのまま上に重なる。仕様 → doc/tech/combat_scene.md
##
## 地面は盤の並びを写さず、地形（スキン）ごとのレシピで組む＝同じ地形なら毎回同じ構図になり読める。
## レシピは terrain_skin.csv の2列（combat_ground＝下地スキン／combat_layout＝自分の絵の置き方）:
##   fill   … そのスキンで一面に敷き詰める（既定＝表に書かないスキンは全部これ）
##   line   … 下地を敷き、両隊列の間を縦に横切る1列だけそのスキン（柵・道・城壁）
##   center … 下地だけをここで敷く。そのスキン自身は帯に混ぜず、地面を組んだ後に2Dで重ねる
##            （CombatStage の feature レイヤー）＝帯の縮小と靄を受けない。拠点のような
##            「立っているもの」は、帯に混ぜると奥で小さく暗くなるか手前で立ち絵に隠れるかしかない。
## 既定が敷き詰めなので、レシピの無いスキンでも必ず何かは映る（背景画像方式のような穴が開かない）。

##
## 敷き方は盤のヘックス格子ではなく、手前から奥へ「帯」を積む。帯ごとにタイルを縮めていく＝
## カメラの遠近に上乗せして奥行きを強調する（強制遠近）。ここは盤ではないのでマス目が揃っている
## 必要がなく、目盛りとして読ませないぶん、絵として奥行きが出るほうを取る。
## 帯どうしは少し重ね、手前の帯を上に置く（瓦葺き）＝大きさの違う帯の継ぎ目が見えない。

const TILE := 1.0            # 一番手前の帯の hex サイズ（奥へ行くほど BAND_SHRINK 倍で縮む）
const CAM_PITCH_DEG := 42.0  # 俯角。盤(52°)より倒して斜め上ビューを強めに出す（下げるほど遠近が強い）
const CAM_FOV := 42.0
const VIEW_COLS := 4.0       # 窓の横幅に見せる列数（小さいほど寄る）。1列＝TILE*1.5
const BAND_SHRINK := 0.93    # 1帯奥へ行くごとのタイル倍率（1.0＝縮めない＝カメラの遠近だけ）
## 帯の送り量（ヘックスの縦幅に対する比）。帯ごとに大きさが変わると列の位相がずれるので、
## 0.5 以下まで重ねないと噛み合わせの谷が埋まらず穴が開く（0.5＝位相に関係なく必ず塞がる境目）。
const BAND_OVERLAP := 0.45
const BAND_MAX := 32         # 帯数の上限（縮むほど枚数が増えるので歯止め）
const BAND_MIN_SIZE := 0.18  # これより小さい帯は敷かない（奥は靄に沈む）
const BAND_LIFT := 0.004     # 手前の帯をわずかに持ち上げる量（同一平面の Z ファイティング回避）
const BG_COLOR := Color(0.10, 0.11, 0.12)  # タイルの外側（通常は見えない）
const SQRT3 := 1.7320508075688772

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
## center のスキン自身はここでは敷かない（地面を組んだ後に2Dで重ねる＝クラス冒頭の説明）。
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
	var placement := skin.combat_placement()
	# line は画面の中央を縦に走る列＝両隊列の間。center は帯に混ぜない（重ねる側で出す）。
	var feat_col := 0 if placement == "line" else 9999
	var bands := _bands()
	for i in bands.size():
		_add_band(i, bands[i], skin, ground, placement, feat_col)

## 手前から奥への帯の並び（それぞれの奥行き z とタイルの大きさ）。
## 奥へ行くほどタイルを縮め、送り幅もそのぶん詰める＝カメラの遠近に強制遠近を上乗せする。
func _bands() -> Array:
	var out := []
	var z := _near_z()
	var far := _far_z()
	var tile := TILE
	for _i in BAND_MAX:
		if tile < BAND_MIN_SIZE or z < far:
			break
		out.append({ "z": z, "tile": tile })
		z -= SQRT3 * tile * BAND_OVERLAP
		tile *= BAND_SHRINK
	return out

## 帯1本（同じ大きさのタイルを横一列）。flat-top なので、列ごとに半マスぶん奥へずらして噛み合わせる。
## 手前の帯ほど y を高く置く＝重なった部分は手前が勝つ（瓦葺き＝大きさの違う帯の継ぎ目が見えない）。
func _add_band(band: int, info: Dictionary, skin: TerrainSkin, ground: TerrainSkin,
		placement: String, feat_col: int) -> void:
	var z: float = info["z"]
	var tile: float = info["tile"]
	var pitch := tile * 1.5
	var n := int(ceil((_half_width_at(z) + tile) / pitch))
	var y := float(BAND_MAX - band) * BAND_LIFT
	for col in range(-n, n + 1):
		var cell := Vector2i(col, band)
		var is_feature := col == feat_col
		var s := skin if is_feature else ground
		var pos := Vector3(col * pitch, y, z + (SQRT3 * 0.5 * tile if col % 2 != 0 else 0.0))
		_add_tile(cell, pos, tile, s, placement if is_feature else "")

func _add_tile(cell: Vector2i, pos: Vector3, tile: float, skin: TerrainSkin, placement: String) -> void:
	var texs := TerrainTiles.variants(_image_path(skin, placement))
	if texs.is_empty():
		return  # 絵が無いスキンは敷かない（窓の地形色が透ける＝どこが未整備か分かる）
	var tex: Texture2D = texs[TerrainTiles.variant_index(cell, texs.size())]
	# 地面を絵に焼き込んでいないスキン（map_ground＝柵など）は、盤と同じく下地を敷いてから重ねる。
	var ground_id := skin.map_ground_id()
	if not ground_id.is_empty():
		var g := TerrainSkinCatalog.resolve(ground_id, "")
		if g != null:
			var gt := TerrainTiles.variants(g.image_path())
			if not gt.is_empty():
				tex = TerrainTiles.composited(gt[TerrainTiles.variant_index(cell, gt.size())], tex)
	var mi := MeshInstance3D.new()
	mi.mesh = TerrainTiles.hex_mesh(tile)
	mi.material_override = TerrainTiles.material(tex)
	mi.position = pos
	if skin.orients():
		TerrainTiles.orient(mi, cell, skin.rotates(), skin.flips_vertically())
	_tiles.add_child(mi)

## 敷くPNG。line で置く線地形（柵・道）は、上下の帯へ繋がる直線の接続タイルを選ぶ。
## 帯ごとにタイルが縮むので、線も奥へ行くほど細くなる＝1本の道/柵が遠ざかって見える。
func _image_path(skin: TerrainSkin, placement: String) -> String:
	if skin.connects() and placement == "line":
		# Hex.DIRECTIONS の index 2 と 5 が縦の隣＝この2方向だけ繋がった直線タイル。
		var connected := [false, false, true, false, false, true]
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

## 一番手前に敷く帯の奥行き（窓の下辺より少し手前＝縁で地面が切れない）。
func _near_z() -> float:
	var vp := Vector2(_vp.size)
	var p := _plane_point(Vector2(vp.x * 0.5, vp.y))
	return (p.z if p.is_finite() else 2.0) + TILE

## 敷き止める奥行き（窓の上辺より少し奥）。地平が映る画角では手前から一定量で打ち切る。
func _far_z() -> float:
	var p := _plane_point(Vector2(Vector2(_vp.size).x * 0.5, 0.0))
	return (p.z if p.is_finite() else _near_z() - 12.0) - TILE

## その奥行きで窓に映る横幅の半分（カメラからの距離に比例）。帯ごとの枚数を決めるのに使う。
func _half_width_at(z: float) -> float:
	var vp := Vector2(_vp.size)
	if vp.y <= 0.0:
		return TILE
	var fwd := -_cam.position.normalized()  # 原点を見ているので視線＝カメラ位置の逆向き
	var d := maxf((Vector3(0.0, 0.0, z) - _cam.position).dot(fwd), 0.1)
	return tan(deg_to_rad(CAM_FOV) * 0.5) * (vp.x / vp.y) * d

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
