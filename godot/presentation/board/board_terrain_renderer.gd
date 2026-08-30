extends Node3D
class_name BoardTerrainRenderer
## 地形タイル構築（タイル・グリッド線・スカート・下地）を担う。
## HexBoard3D が子ノードとして持ち、タイルテクスチャの解決・標高キャッシュ・
## ジオラマの外周スカートまでの地形描画を委譲する。
## 盤のゲーム状態には直接依存しない＝呼び出し側が setup で注入する。

# HexBoard3D.TILE と同値。盤全体で共有する「ヘックスの大きさ」の定数。
const TILE := 1.0
const SKIRT_DEPTH := TILE * 0.45   # 盤外周の側面（ジオラマの島の厚み）
## 見た目の高さ（elevation）と駒の足元の高さ（floor）はスキン側のデータ＝terrain_skin.csv。
## 高さは段差辺に側面スカートを生やす（崖は台地より高い＝登れる高台と登れない絶壁を序列で見せる）。
## floor が動かすのは立ち絵だけ（影・兵数バー・リングは上面のまま）＝盤の読み取りは従来どおり。
## floor < elevation で駒が地形に沈む（森＝木々の間の地面）、> で浮く（水面の上を飛ぶ）。
const SKIRT_DARKEN := 0.55         # 側面の暗さ（タイル平均色をこの割合で darkened）
## 立ち絵PNGの「キャンバス高さ」が何タイルぶんに当たるか。BoardUnitRenderer.UNIT_CANVAS_TILES と同値
## ＝キャンバスの刻みは駒と共通（1タイル＝384px/3.75）。大小の差はキャンバスに焼き込んだ余白が持つ
## ＝オブジェクトの大きさ(terrain_skin.csv の map_scale)は絵の書き出しだけが読む。ただし物差しは駒と
## 別で、駒＝背丈がファイターの何倍か、オブジェクト＝絵の幅がヘックスの幅(2タイル)の何倍か
## （→ doc/art/terrain.md）。盤の読みは「マスからはみ出さないか」で決まるので、幅を基準にする。
const CANVAS_TILES := 3.75
## 立ち絵の足元をヘックス中心から手前（下辺寄り）へずらす量はスキン側のデータ＝object_foot_z。
## 駒（+0.6）と同じ向きで、駒より小さくしておけば同じマスでも駒が手前に立つ。
## ずらすのは、立ち絵が足元から上へ伸びる＝盤の俯角のぶん体が奥のマスに乗って見えるため。
const COLOR_LINE := Color(0.78, 0.83, 0.90, 0.45)

# --- 状態（setup で注入）---
var _state: BattleState
var _terrain_skins := {}   # Vector2i -> skin_id（ステージの見た目差分。盤外＝外周のセルも書ける）
## Vector2i -> terrain_id（外周＝盤の外側1周ぶんの地形。作者が描いたもの）。
## 描かないし駒も入らない＝接続タイル（柵・道）が「盤の外に何があるか」を引くためだけのデータ。
## 空＝外周なしで、そのときだけ縁の推測（面は丸め込み／線は腕を伸ばす）に落ちる。
var _margin_terrain := {}
## 盤の基準高さ（見た目のみ）。{ "row": [行数ぶん], "col": [列数ぶん] }。空＝その軸は平ら。
## あるマスの高さ ＝ 行の基準 ＋ 列の基準 ＋ スキンの elevation（→ doc/gdd/terrain.md 盤の高さ）。
## 盤の高さを無視するスキン（ignore_board_height）は基準を足さない＝elevation / floor が絶対高さ。
## マスごとの高さ上書きがあるマスは、この計算をせず上書き値をそのまま使う。
var _board_height := { "row": [], "col": [] }
## Vector2i -> { "elevation": float, "floor": float }（マスごとの高さ上書き。書いてあればそれが最終の高さ）。
var _height_overrides := {}

# --- キャッシュ ---
var _terrain_tex := {}     # base_path(String) -> Array[Texture2D]（基本＋連番 variant）
var _side_tex := {}        # skin_id -> Texture2D|null（側面画像。置いていなければ null）
var _fence_tex := {}       # res://パス -> Texture2D|null（柵の面に貼る帯）
var _tile_nodes := {}      # Vector2i -> MeshInstance3D（占領で拠点タイルを貼り替えるため）
var _standee_nodes := {}   # Vector2i -> Sprite3D（占領で拠点の立ち絵を貼り替えるため）
var _elev_cache := {}      # Vector2i -> float（スキン解決の結果。build_tiles で捨てる）
var _elev_levels_cache: Array = []  # 盤に実在する標高レベル（高い順）
var _avg_color := {}       # Texture2D -> Color（タイル平均色キャッシュ＝スカートの断面色）
var _art_height := {}      # Texture2D -> float（立ち絵の絵の実体の高さ。キャンバスの余白を除く）

# --- メッシュ（_ready で生成）---
var _hex_mesh: ArrayMesh          # 床に寝かせたヘックス（タイル用・UVは外接矩形）
var _skirt_tex: ImageTexture      # スカートの粒状ノイズ（べた塗り回避。_ready で1回生成）

func _ready() -> void:
	_hex_mesh = BoardMeshFactory.make_hex_mesh(TILE)
	_skirt_tex = BoardMeshFactory.make_skirt_texture()

func setup(state: BattleState, terrain_skins: Dictionary, margin_terrain: Dictionary,
		board_height: Dictionary = { "row": [], "col": [] }, height_overrides: Dictionary = {}) -> void:
	_state = state
	_terrain_skins = terrain_skins
	_margin_terrain = margin_terrain
	_board_height = board_height
	_height_overrides = height_overrides

# =========================================================================
# Public API
# =========================================================================

## 地形タイル・グリッド線・下地。bind（ステージ確定）ごとに作り直す。
func build_tiles() -> void:
	_clear_children()
	_tile_nodes.clear()
	_standee_nodes.clear()
	_elev_cache.clear()
	_elev_levels_cache.clear()
	if _state == null:
		return
	for col in _state.cols:
		for row in _state.rows:
			var hex := Hex.offset_to_axial(col, row)
			_add_tile(hex)
	_add_objects()
	_add_grid()
	_add_skirt()
	_add_ground()

## 拠点を現在の所有チームの絵に貼り替える。占領で色が変わるので _sync_bases から毎回呼ぶ。
## 拠点がオブジェクト（fort＝立ち絵）のマスは立ち絵を貼り替える。平面タイルは足場のままで触らない
## （_tile_texture を貼ると立ち絵の絵が地面にも合成され、二重に描かれる）。
func refresh_base_tiles() -> void:
	if _state == null:
		return
	for b in _state.bases():
		var skin := _skin_at(b.hex)
		if _is_object(skin):
			var spr: Sprite3D = _standee_nodes.get(b.hex)
			if spr != null:
				_apply_standee_texture(spr, skin, b.hex)
			continue
		var mi: MeshInstance3D = _tile_nodes.get(b.hex)
		if mi == null:
			continue
		var tex := _tile_texture(b.hex)
		if tex != null:
			mi.material_override = BoardMeshFactory.terrain_material(tex)

## そのヘックスの読み取り面の標高（スキン別・既定0）。ピッキング/配置/グリッド/オーバーレイで使う。
## 水平の板（橋）のマスだけ floor＝板の高さ。elevation はそのマスでは足場（水）の高さで、
## タイル敷きとスカートが使う（→ _footing_elev）。
## 毎フレームのピッキングから何度も引かれるので、盤を組み直すまでキャッシュする。
func elev(hex: Vector2i) -> float:
	if _elev_cache.has(hex):
		return _elev_cache[hex]
	var key := "floor" if _is_flat(_skin_at(hex)) else "elevation"
	var e := _skin_height(hex, key)
	_elev_cache[hex] = e
	return e

## スキン由来の高さ（elevation / floor）を1本の規則で解決する。
## マスに高さ上書きがあれば、その値がそのまま最終の高さ＝盤の高さ（行＋列の基準）もスキンの値も見ない。
## 上書きの無いマスは、盤の高さを無視フラグの無いスキンだけに足す（→ doc/gdd/terrain.md 盤の高さ）。
func _skin_height(hex: Vector2i, key: String) -> float:
	var skin := _skin_at(hex)
	if skin == null:
		return _base_height(hex)
	var ov: Variant = _height_overrides.get(hex)
	if typeof(ov) == TYPE_DICTIONARY:
		return float(ov[key])
	var v: float = skin.elevation if key == "elevation" else skin.floor
	return v if skin.ignore_board_height else v + _base_height(hex)

## 盤の基準高さ（行＋列）。ステージが書いていなければ0＝平ら。盤の外のセルは縁の値に丸める
## （外周のスカートが盤の縁と地続きに見えるように）。
func _base_height(hex: Vector2i) -> float:
	var row: Array = _board_height.get("row", [])
	var col: Array = _board_height.get("col", [])
	if row.is_empty() and col.is_empty():
		return 0.0
	var o := Hex.axial_to_offset(hex)
	var h := 0.0
	if not row.is_empty():
		h += float(row[clampi(o.y, 0, row.size() - 1)])
	if not col.is_empty():
		h += float(col[clampi(o.x, 0, col.size() - 1)])
	return h

## 駒の足元の高さ（floor・既定＝上面と同じ）。立ち絵だけがこの高さに立つ。
## elevation より低ければ地形に沈み（森）、高ければ浮く（水面の上を飛ぶ）。
func unit_floor(hex: Vector2i) -> float:
	return _skin_height(hex, "floor")

## 水平の板（橋）のスキンか。オブジェクトの高さは2列で受け持ちが分かれる＝elevation の高さに
## 足場（map_ground）を敷き、floor の高さに板を置く（→ doc/gdd/terrain.md）。
func _is_flat(skin: TerrainSkin) -> bool:
	return skin != null and skin.placement == TerrainSkin.PLACE_FLAT

## 足場（タイル）を敷く高さ＝スキンの elevation。通常のマスでは elev()（読み取り面）と同じ値で、
## 水平の板（橋）のマスだけ違う＝elevation は下の水の高さ・読み取り面（板）は floor に浮く。
## マスごとの高さ上書きにもそのまま乗る＝ペアが「水位と板の高さ」になる。
func _footing_elev(hex: Vector2i) -> float:
	return _skin_height(hex, "elevation")

## 盤に存在する標高レベルを高い順で（ピッキングで上のタイルを先に判定）。0 を必ず含む。
## スキンはセルごとに違いうるので、定数表ではなく実際に敷かれた高さから集める。
func elev_levels() -> Array:
	if not _elev_levels_cache.is_empty():
		return _elev_levels_cache
	var s := { 0.0: true }
	if _state != null:
		for col in _state.cols:
			for row in _state.rows:
				s[elev(Hex.offset_to_axial(col, row))] = true
	var arr := s.keys()
	arr.sort()
	arr.reverse()
	_elev_levels_cache = arr
	return arr

# =========================================================================
# Private
# =========================================================================

## そのヘックスの見た目のスキン（ステージの差分指定を優先・無ければ地形の既定）。無ければ null。
func _skin_at(hex: Vector2i) -> TerrainSkin:
	if _state == null:
		return null
	return TerrainSkinCatalog.resolve(_terrain_skins.get(hex, ""), _state.terrain_at(hex))

## スキンの側面画像（置いてあれば）。無ければ null＝既定の粒ノイズ＋断面色。スキン単位でキャッシュ。
func _side_texture(skin: TerrainSkin) -> Texture2D:
	if skin == null:
		return null
	if _side_tex.has(skin.skin_id):
		return _side_tex[skin.skin_id]
	var p := skin.side_image_path()
	var tex := load(p) as Texture2D if ResourceLoader.exists(p) else null
	_side_tex[skin.skin_id] = tex
	return tex

## hex が盤の中か。
func _on_board(hex: Vector2i) -> bool:
	if _state == null:
		return false
	var o := Hex.axial_to_offset(hex)
	return o.x >= 0 and o.x < _state.cols and o.y >= 0 and o.y < _state.rows

## hex が盤の矩形（offset col/row）の中にあるか。
func _in_board(hex: Vector2i) -> bool:
	if _state == null:
		return false
	var c := Hex.axial_to_offset(hex)
	return c.x >= 0 and c.x < _state.cols and c.y >= 0 and c.y < _state.rows

## 盤の矩形（offset col/row）へ丸め込む。盤内はそのまま返る。
func _clamp_to_board(hex: Vector2i) -> Vector2i:
	if _state == null:
		return hex
	var c := Hex.axial_to_offset(hex)
	return Hex.offset_to_axial(clampi(c.x, 0, _state.cols - 1), clampi(c.y, 0, _state.rows - 1))

## そのヘックスにある拠点の所属チーム。拠点でない/中立なら -1。拠点は数個なので線形で足りる。
func _base_team_at(hex: Vector2i) -> int:
	if _state == null:
		return -1
	for b in _state.bases():
		if b.hex == hex:
			return b.team
	return -1

## hex の地形タイルのテクスチャ（skin 解決＋variant 敷き分け＋キャッシュ）。無ければ null。
## map_ground を持つ足場スキン（橋＝川の上に石畳）は、下地を敷いてから重ねる。
## 下地の variant もこのヘックスで選ぶので、橋のマスだけ川が固定される、ということにならない。
## オブジェクトのマスの上面はここではなく _surface_texture（足場だけ）で引く。
func _tile_texture(hex: Vector2i) -> Texture2D:
	var skin := _skin_at(hex)
	if skin == null:
		return null
	var over := _variant_texture(_tile_image_path(skin, hex), hex)
	var ground_id := skin.map_ground_id()
	if ground_id.is_empty():
		return over
	var ground := TerrainSkinCatalog.resolve(ground_id, "")
	if ground == null:
		return over
	# 下地も接続タイルを引く。橋のマスに敷く川は、そのマスの向きに合った1枚でなければ繋がらない。
	return TerrainTiles.composited(_variant_texture(_tile_image_path(ground, hex), hex), over)

## パスの variant を読み、このヘックスぶんの1枚を返す（読み込みはパスごとに1回）。
func _variant_texture(path: String, hex: Vector2i) -> Texture2D:
	var variants: Array = _terrain_tex.get(path, [])
	if variants.is_empty() and not _terrain_tex.has(path):
		variants = _load_terrain_variants(path)
		_terrain_tex[path] = variants
	if variants.is_empty():
		return null
	return variants[_terrain_variant(hex, variants.size())]

## そのヘックスに敷く画像の基準パス。占領されている拠点は、所有チーム別の絵があればそれを使う。
## assets/terrain/{skin_id}_team{N}.png を置けば切り替わり、置かなければ中立の絵のまま（コード不変）。
## 線地形（connect＝柵・道）は、隣り合う同スキンの向きの組み合わせで絵を選ぶ。
func _tile_image_path(skin: TerrainSkin, hex: Vector2i) -> String:
	var team := _base_team_at(hex)
	if team >= 0:
		var p := "res://assets/terrain/%s_team%d.png" % [skin.skin_id, team]
		if ResourceLoader.exists(p):
			return p
	if skin.connects():
		var cp := skin.connected_image_path(_connected_dirs(skin, hex))
		if ResourceLoader.exists(cp):
			return cp
	return skin.image_path()

## hex の6近傍が同じスキンか（Hex.DIRECTIONS 順）。盤外の隣をどう埋めるかを3段で決める。
## 1) 外周(margin)が描いてあれば、そのマスの地形をそのまま読む＝作者の指定が最優先。線も面も同じ扱い
##    で、on_board も真にする＝腕を伸ばす補正は効かせない（描いてある以上、推測する必要がない）。
## 2) 外周が無い面(area＝道)は「縁のマスがそのまま続いている」として引く＝座標を盤に丸めて読む。
##    縁で帯が輪郭付きの蓋にならず、まっすぐ盤の外へ抜ける。
## 3) 外周が無い線(line＝柵)は丸めない。端が縁に来たときだけ、その先へ腕を伸ばす（extend_off_board）。
## 6近傍だけでは出せない絵（縁の2マス先の事情で変わる形）があるので、1) を用意している。
func _connected_dirs(skin: TerrainSkin, hex: Vector2i) -> Array:
	var area := skin.connects_as_area()
	var connected: Array = []
	var on_board: Array = []
	for d in Hex.DIRECTIONS:
		var n := hex + d
		var s: TerrainSkin = null
		var covered := true
		if _in_board(n):
			s = _skin_at(n)
		elif _margin_terrain.has(n):
			# 外周のセル。見た目差分(terrain_skins)は盤外の座標でも書けるので盤内と同じ引き方をする。
			s = TerrainSkinCatalog.resolve(_terrain_skins.get(n, ""), String(_margin_terrain[n]))
		elif area:
			s = _skin_at(_clamp_to_board(n))
		else:
			covered = false
		connected.append(skin.connects_with(s))
		on_board.append(covered)
	if area:
		return connected
	return TerrainSkin.extend_off_board(connected, on_board)

## タイルの平均色（中央付近を5点サンプル・透過は除外）。スカートの断面色に使う。
func _tile_avg_color(tex: Texture2D) -> Color:
	if _avg_color.has(tex):
		return _avg_color[tex]
	var col := Color(0.35, 0.30, 0.22)  # 読めない場合のフォールバック（土色）
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		var sum := Vector3.ZERO
		var cnt := 0
		for off: Vector2 in [Vector2(0.5, 0.5), Vector2(0.3, 0.35), Vector2(0.7, 0.35), Vector2(0.3, 0.65), Vector2(0.7, 0.65)]:
			var c := img.get_pixel(int(w * off.x), int(h * off.y))
			if c.a > 0.5:
				sum += Vector3(c.r, c.g, c.b)
				cnt += 1
		if cnt > 0:
			col = Color(sum.x / cnt, sum.y / cnt, sum.z / cnt)
	_avg_color[tex] = col
	return col

func _add_tile(hex: Vector2i) -> void:
	var skin := _skin_at(hex)
	var tex := _surface_texture(hex)
	if tex == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _hex_mesh
	mi.material_override = BoardMeshFactory.terrain_material(tex)
	var p := Hex.to_pixel(hex, TILE)
	# タイルは足場の高さ（elevation）に敷く。水平の板（橋）のマスだけ読み取り面（elev＝floor の板）
	# と違う高さになり、板の下に水が残る。他のマスでは elev() と同じ値。
	mi.position = Vector3(p.x, _footing_elev(hex), p.y)
	if skin != null and skin.orients():
		TerrainTiles.orient(mi, hex, skin.rotates(), skin.flips_horizontally(), skin.flips_vertically())  # 向きは座標ハッシュから決定的に選ぶ＝盤は毎回同じ
	_tile_nodes[hex] = mi  # 占領でタイルを貼り替えるため、ヘックスから引けるようにしておく
	add_child(mi)

## マスの上面（平面タイル）に敷く絵。オブジェクトのマスは足場だけを敷く（物そのものは
## _add_objects が立てる）。タイル敷きとスカートの断面色が同じ解決を使う。
func _surface_texture(hex: Vector2i) -> Texture2D:
	var skin := _skin_at(hex)
	return _ground_texture(hex, skin) if _is_object(skin) else _tile_texture(hex)

## そのスキンがオブジェクト（足場の上に置くもの）か。→ doc/gdd/terrain.md
func _is_object(skin: TerrainSkin) -> bool:
	return skin != null and TerrainType.layer(skin.terrain_type) == "object"

## オブジェクトのマスに敷く足場のテクスチャ（map_ground）。書いていなければ null。
func _ground_texture(hex: Vector2i, skin: TerrainSkin) -> Texture2D:
	if skin == null:
		return null
	var ground := TerrainSkinCatalog.resolve(skin.map_ground_id(), "")
	if ground == null:
		return null
	return _variant_texture(_tile_image_path(ground, hex), hex)

## オブジェクトを置く。置き方はスキンの placement（→ doc/gdd/terrain.md）＝辺に沿って立てた板
## （柵）／水平の板（橋）／カメラに正対する立ち絵1枚（既定）。立てた板は絵ごとに1メッシュへまとめる。
func _add_objects() -> void:
	var boxes := {}  # Texture2D -> SurfaceTool（柵の箱組み。絵ごとに1メッシュへまとめる）
	for col in _state.cols:
		for row in _state.rows:
			var hex := Hex.offset_to_axial(col, row)
			var skin := _skin_at(hex)
			if not _is_object(skin):
				continue
			match skin.placement:
				TerrainSkin.PLACE_PANEL:
					_add_fence_boxes(boxes, skin, hex)
				TerrainSkin.PLACE_FLAT:
					_add_object_flat(skin, hex)
				_:
					_add_object_standee(skin, hex)
	for tex: Texture2D in boxes:
		var mi := MeshInstance3D.new()
		mi.mesh = boxes[tex].commit()
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED  # 面数が少なく、巻き順を固定する価値がない
		mi.material_override = m
		add_child(mi)

## 柵（placement=panel）。板1枚ではなく、柱と横木の直方体を立体で組む（橋・段差の側面と同じ
## 「形は3D・絵は2D」の分担 → doc/gdd/terrain.md）。柱はヘックス中心と繋がる辺の中点に立ち、
## 横木2本がその間を渡る。辺の柱は隣のマスと同じ位置になるので1本に見える＝板版の鏡写しトリックが要らない。
## 面にはスキンごとの帯（assets/terrain/{skin_id}_{面}.png・→ _fence_face_texture）を貼る。
## 寸法はここの定数＝柵スキンが全部同じプロポーションのうちは絵もデータも寸法を持たない。
const FENCE_POST_H := 0.62      # 柱の高さ（TILE）
const FENCE_POST_HW := 0.09     # 柱の半幅
const FENCE_RAIL_HH := 0.08     # 横木の半分の高さ
const FENCE_RAIL_HD := 0.05     # 横木の半分の奥行き
const FENCE_RAIL_TOP_Y := 0.50  # 上の横木の中心高さ
const FENCE_RAIL_LOW_Y := 0.26  # 下の横木の中心高さ

## 柵の面の帯（assets/terrain/{skin_id}_{face}.png）。無ければ声を上げて null。
func _fence_face_texture(skin: TerrainSkin, face: String) -> Texture2D:
	var path := "res://assets/terrain/%s_%s.png" % [skin.skin_id, face]
	if _fence_tex.has(path):
		return _fence_tex[path]
	var tex := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if tex == null:
		push_error("BoardTerrainRenderer: 柵の帯が無い %s" % path)
	_fence_tex[path] = tex
	return tex

func _add_fence_boxes(boxes: Dictionary, skin: TerrainSkin, hex: Vector2i) -> void:
	var p := Hex.to_pixel(hex, TILE)
	var y := elev(hex)
	var a := Vector3(p.x, y, p.y)
	var conn := _connected_dirs(skin, hex)
	var any := false
	for i in 6:
		if not bool(conn[i]):
			continue
		any = true
		var q := Hex.to_pixel(hex + Hex.DIRECTIONS[i], TILE)
		var mid := Vector3((p.x + q.x) * 0.5, y, (p.y + q.y) * 0.5)
		var dirv := (mid - a).normalized()
		var half_len := a.distance_to(mid) * 0.5
		for cy in [FENCE_RAIL_TOP_Y, FENCE_RAIL_LOW_Y]:
			_fbox_add(boxes, skin, (a + mid) * 0.5 + Vector3(0, cy, 0), dirv,
				half_len, FENCE_RAIL_HD, FENCE_RAIL_HH, "rail_front", "rail_top")
		# 辺の柱。隣も同じ位置に描くと面が重なってちらつくので、方向 0..2 のときだけ描く
		#（同じ辺は相手から見ると方向 3..5）。盤外へ伸びた腕の先は相手がいないので常に描く。
		if i < 3 or not _in_board(hex + Hex.DIRECTIONS[i]):
			_fbox_add(boxes, skin, mid + Vector3(0, FENCE_POST_H * 0.5, 0), dirv,
				FENCE_POST_HW, FENCE_POST_HW, FENCE_POST_H * 0.5, "post_side", "post_top")
	if any:
		_fbox_add(boxes, skin, a + Vector3(0, FENCE_POST_H * 0.5, 0), Vector3.RIGHT,
			FENCE_POST_HW, FENCE_POST_HW, FENCE_POST_H * 0.5, "post_side", "post_top")

## 直方体1個を SurfaceTool へ足す。c=中心 / axis=長さ方向（水平の単位ベクトル）/
## hl=半長 / hd=半奥行 / hh=半高。側面と端面に side、上下面に top の帯を貼る。
func _fbox_add(boxes: Dictionary, skin: TerrainSkin, c: Vector3, axis: Vector3,
		hl: float, hd: float, hh: float, side: String, top: String) -> void:
	var d := Vector3(-axis.z, 0.0, axis.x)
	var u := axis * hl
	var v := d * hd
	var h := Vector3(0.0, hh, 0.0)
	var side_tex := _fence_face_texture(skin, side)
	var top_tex := _fence_face_texture(skin, top)
	if side_tex == null or top_tex == null:
		return
	_fbox_quad(boxes, side_tex, c - u + v + h, c + u + v + h, c + u + v - h, c - u + v - h)
	_fbox_quad(boxes, side_tex, c + u - v + h, c - u - v + h, c - u - v - h, c + u - v - h)
	_fbox_quad(boxes, side_tex, c + u + v + h, c + u - v + h, c + u - v - h, c + u + v - h)
	_fbox_quad(boxes, side_tex, c - u - v + h, c - u + v + h, c - u + v - h, c - u - v - h)
	_fbox_quad(boxes, top_tex, c - u - v + h, c + u - v + h, c + u + v + h, c - u + v + h)
	_fbox_quad(boxes, top_tex, c - u + v - h, c + u + v - h, c + u - v - h, c - u - v - h)

func _fbox_quad(boxes: Dictionary, tex: Texture2D,
		p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3) -> void:
	var st: SurfaceTool = boxes.get(tex)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		boxes[tex] = st
	st.set_uv(Vector2(0, 0)); st.add_vertex(p1)
	st.set_uv(Vector2(1, 0)); st.add_vertex(p2)
	st.set_uv(Vector2(1, 1)); st.add_vertex(p3)
	st.set_uv(Vector2(0, 0)); st.add_vertex(p1)
	st.set_uv(Vector2(1, 1)); st.add_vertex(p3)
	st.set_uv(Vector2(0, 1)); st.add_vertex(p4)

## 水平の板（橋）。自分のタイル絵をヘックス形の板として floor の高さ（＝elev。盤の読み取り面で、
## 駒もここに立つ）に敷く。足場（map_ground＝川）は _add_tile が elevation の高さに敷くので、
## 板の下を水がくぐる。
func _add_object_flat(skin: TerrainSkin, hex: Vector2i) -> void:
	var tex := _variant_texture(_tile_image_path(skin, hex), hex)
	if tex == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _hex_mesh
	# 透過を描く材質で敷く。通常のタイル材質は不透明描画なので、床の帯の外（絵の透過部分）が
	# 塗りつぶされて下の水が見えなくなる。
	mi.material_override = TerrainTiles.cutout_material(tex)
	var p := Hex.to_pixel(hex, TILE)
	mi.position = Vector3(p.x, elev(hex), p.y)
	add_child(mi)

## 繋がらないオブジェクト（岩・建物・砦）。立ち絵1枚を、スキンが指すぶんマス中心より手前に立てる。
func _add_object_standee(skin: TerrainSkin, hex: Vector2i) -> void:
	var spr := Sprite3D.new()
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	if not _apply_standee_texture(spr, skin, hex):
		spr.free()
		return
	var p := Hex.to_pixel(hex, TILE)
	spr.position = Vector3(p.x, elev(hex) + 0.02, p.y + skin.object_foot_z)
	_standee_nodes[hex] = spr
	add_child(spr)

## 立ち絵の絵を貼る（チーム別の絵の解決込み＝占領で貼り替わる）。倍率と原点は絵の寸法に
## 依存するので、絵と一緒にここで合わせる。絵が引けなければ false。
## 左右反転は絵の向きの話なのでここで掛ける。立ち絵が取れるのは flip_x まで（回すと足元が
## 地面から外れ、上下反転は逆さに立つ）＝ orient は呼ばず flips_h_at だけを引く。
func _apply_standee_texture(spr: Sprite3D, skin: TerrainSkin, hex: Vector2i) -> bool:
	var tex := _variant_texture(_tile_image_path(skin, hex), hex)
	if tex == null:
		return false
	spr.texture = tex
	spr.pixel_size = (CANVAS_TILES * TILE) / float(tex.get_height())
	spr.offset = Vector2(0, tex.get_height() * 0.5)  # 原点＝足元
	spr.flip_h = skin.flips_horizontally() and TerrainTiles.flips_h_at(hex)
	return true

## 立ち絵の天辺（ワールド座標）。立ち絵はカメラに正対するので、画面で頭の上に来る点は、足元から
## カメラの上方向へ絵の高さぶん進んだところ。立ち絵の無いマスは null（拠点の控え数の置き場に使う）。
func standee_top(hex: Vector2i, up: Vector3) -> Variant:
	var spr: Sprite3D = _standee_nodes.get(hex)
	if spr == null or spr.texture == null:
		return null
	return spr.position + up * _standee_art_height(spr)

## 立ち絵の「絵の実体」の高さ（ワールド）。キャンバスは下端揃えで上に余白があるので、テクスチャの
## 高さをそのまま使うと頭上が余白のぶん高くなる。画像を読むのは重いのでテクスチャごとに覚える。
func _standee_art_height(spr: Sprite3D) -> float:
	var tex := spr.texture
	if not _art_height.has(tex):
		var img := tex.get_image()
		if img == null:
			return 0.0
		if img.is_compressed():
			img.decompress()
		_art_height[tex] = float(img.get_used_rect().size.y)
	return _art_height[tex] * spr.pixel_size

## ヘックスの輪郭線（セルの読み取り用）。全マスまとめて1メッシュ。
## スキンが grid=false のマスは引かない＝駒が入れない地形が枠で刻まれず、一つの塊として読める。
func _add_grid() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for col in _state.cols:
		for row in _state.rows:
			var hex := Hex.offset_to_axial(col, row)
			var skin := _skin_at(hex)
			if skin != null and not skin.grid:
				continue
			var p := Hex.to_pixel(hex, TILE)
			var gy := elev(hex) + 0.01
			for i in 6:
				var a0 := deg_to_rad(60.0 * i)
				var a1 := deg_to_rad(60.0 * (i + 1))
				im.surface_add_vertex(Vector3(p.x + cos(a0) * TILE, gy, p.y + sin(a0) * TILE))
				im.surface_add_vertex(Vector3(p.x + cos(a1) * TILE, gy, p.y + sin(a1) * TILE))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = COLOR_LINE
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	add_child(mi)

## 盤外周の側面（スカート）。盤外に接する辺だけ下へ伸ばし、ジオラマの「島」に見せる。
## 側面画像（assets/terrain/{skin_id}_side.png）を持つスキンは、その画像を貼った別メッシュにまとめる。
## 画像ごとにマテリアルが要るので、テクスチャ単位でメッシュを分ける（アンライトなので法線は不問）。
func _add_skirt() -> void:
	# 辺 i（コーナー i→i+1・辺中点の方位 60i+30°）に対応する隣接方向（フラットトップ axial）。
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
	]
	var tools := {}  # Texture2D|null -> SurfaceTool（null＝既定の粒ノイズ＋断面色）
	for col in _state.cols:
		for row in _state.rows:
			var hex := Hex.offset_to_axial(col, row)
			var p := Hex.to_pixel(hex, TILE)
			var side := _side_texture(_skin_at(hex))
			var top_c: Color
			var bot_c: Color
			if side != null:
				# 側面画像はそれ自体が岩肌＝タイルの平均色で染めない。上端→下端の減光だけ掛ける。
				top_c = Color(1, 1, 1)
				bot_c = Color(0.8, 0.8, 0.8)
			else:
				# 断面色＝そのタイルの平均色（草の下は緑土・砂の下は砂色＝地続きに見える）。
				# べた塗り回避: 上端は明るめ→下端ほど暗い頂点グラデ＋粒状ノイズテクスチャを重ねる。
				var tex := _surface_texture(hex)
				var base := _tile_avg_color(tex) if tex != null else Color(0.35, 0.30, 0.22)
				top_c = base.darkened(SKIRT_DARKEN - 0.20)
				bot_c = base.darkened(SKIRT_DARKEN + 0.20)
			var st: SurfaceTool = tools.get(side)
			if st == null:
				st = SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[side] = st
			# スカートは足場の高さ（elevation）で数える。水平の板（橋）のマスは水面の高さになる
			# ＝板の縁は堰堤にならず、岸の壁が橋の下の水まで下りる。
			var top := _footing_elev(hex)
			for i in 6:
				var nb := hex + dirs[i]
				var bottom: float
				if not _on_board(nb):
					bottom = -SKIRT_DEPTH         # 盤外＝ジオラマの縁（島の厚み）
				elif _footing_elev(nb) < top - 0.001:
					bottom = _footing_elev(nb)   # 低い隣接＝台地の崖面（段差ぶんだけ下ろす）
				else:
					continue                      # 同高 or 高い隣にはスカート不要
				var a0 := deg_to_rad(60.0 * i)
				var a1 := deg_to_rad(60.0 * (i + 1))
				var c0 := Vector3(p.x + cos(a0) * TILE, top, p.y + sin(a0) * TILE)
				var c1 := Vector3(p.x + cos(a1) * TILE, top, p.y + sin(a1) * TILE)
				var d0 := Vector3(c0.x, bottom, c0.z)
				var d1 := Vector3(c1.x, bottom, c1.z)
				# UVのuはコーナーのワールド座標から取る＝隣り合う辺と連続（継ぎ目が出ない）。
				var u0 := (c0.x * 0.31 + c0.z * 0.53) * 0.8
				var u1 := (c1.x * 0.31 + c1.z * 0.53) * 0.8
				st.set_color(top_c); st.set_uv(Vector2(u0, 0.05)); st.set_normal(Vector3.UP); st.add_vertex(c0)
				st.set_color(top_c); st.set_uv(Vector2(u1, 0.05)); st.set_normal(Vector3.UP); st.add_vertex(c1)
				st.set_color(bot_c); st.set_uv(Vector2(u0, 0.95)); st.set_normal(Vector3.UP); st.add_vertex(d0)
				st.set_color(bot_c); st.set_uv(Vector2(u1, 0.95)); st.set_normal(Vector3.UP); st.add_vertex(d1)
				st.set_color(bot_c); st.set_uv(Vector2(u0, 0.95)); st.set_normal(Vector3.UP); st.add_vertex(d0)
				st.set_color(top_c); st.set_uv(Vector2(u1, 0.05)); st.set_normal(Vector3.UP); st.add_vertex(c1)
	for side in tools:
		var mi := MeshInstance3D.new()
		mi.mesh = tools[side].commit()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true  # 断面色/減光（頂点カラー）× テクスチャの積
		m.albedo_texture = side if side != null else _skirt_tex
		m.cull_mode = BaseMaterial3D.CULL_DISABLED  # 三角形の向きを気にしない（内外どちらからも見える）
		mi.material_override = m
		add_child(mi)

## 盤の下地（虚空に浮かないための大きな平面）。スカートの下端より深くに置き、盤を「島」として浮かせる。
func _add_ground() -> void:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for col in _state.cols:
		for row in _state.rows:
			var p := Hex.to_pixel(Hex.offset_to_axial(col, row), TILE)
			mn = mn.min(p)
			mx = mx.max(p)
	var c := (mn + mx) * 0.5
	var pm := PlaneMesh.new()
	pm.size = (mx - mn) + Vector2(60.0, 60.0)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.22, 0.24, 0.18)  # 盤より暗く＝盤が浮き立つ
	mi.material_override = m
	mi.position = Vector3(c.x, -SKIRT_DEPTH - 0.35, c.y)
	add_child(mi)

## 地形タイルを読む。基本 {name}.png ＋連番 variant。
func _load_terrain_variants(base_path: String) -> Array:
	return TerrainTiles.variants(base_path)

## ヘックス座標から決定的に variant を選ぶ（盤の再構築でも不変）。
func _terrain_variant(hex: Vector2i, count: int) -> int:
	return TerrainTiles.variant_index(hex, count)

func _clear_children() -> void:
	for c in get_children():
		remove_child(c)
		c.free()
