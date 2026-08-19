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
## ＝駒とオブジェクトで物差しを1本にする（背丈を「駒の何倍か」で読める）。大小の差はキャンバスに
## 焼き込んだ余白が持つ＝倍率(terrain_skin.csv の map_scale)は絵の書き出しだけが読む。
const CANVAS_TILES := 3.75
## 立ち絵の足元をヘックス中心から奥（上辺寄り）へずらす量はスキン側のデータ＝object_foot_z。
## 駒は手前（+0.6）に立つので、同じマスなら駒が前に出る。
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
var _obj_side_tex := {}    # art_id -> Texture2D|null（繋がるオブジェクトの板の絵）
var _tile_nodes := {}      # Vector2i -> MeshInstance3D（占領で拠点タイルを貼り替えるため）
var _standee_nodes := {}   # Vector2i -> Sprite3D（占領で拠点の立ち絵を貼り替えるため）
var _elev_cache := {}      # Vector2i -> float（スキン解決の結果。build_tiles で捨てる）
var _elev_levels_cache: Array = []  # 盤に実在する標高レベル（高い順）
var _avg_color := {}       # Texture2D -> Color（タイル平均色キャッシュ＝スカートの断面色）

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

## そのヘックスの見た目の標高（スキン別・既定0）。ピッキング/配置/スカートで使う。
## 毎フレームのピッキングから何度も引かれるので、盤を組み直すまでキャッシュする。
func elev(hex: Vector2i) -> float:
	if _elev_cache.has(hex):
		return _elev_cache[hex]
	var e := _skin_height(hex, "elevation")
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
	mi.position = Vector3(p.x, elev(hex), p.y)
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

## オブジェクトを立てる。繋がるもの（柵）はワールドに向きを持った板、それ以外はカメラに
## 正対する立ち絵1枚（→ doc/gdd/terrain.md）。板は絵ごとに1メッシュへまとめる。
func _add_objects() -> void:
	var panels := {}  # Texture2D -> SurfaceTool
	for col in _state.cols:
		for row in _state.rows:
			var hex := Hex.offset_to_axial(col, row)
			var skin := _skin_at(hex)
			if not _is_object(skin):
				continue
			if skin.connects():
				_add_object_panels(panels, skin, hex)
			else:
				_add_object_standee(skin, hex)
	for tex: Texture2D in panels:
		var mi := MeshInstance3D.new()
		mi.mesh = panels[tex].commit()
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED  # 裏から見ても描く
		mi.material_override = m
		add_child(mi)

## 繋がるオブジェクト（柵）。ヘックス中心から、繋がる隣との辺の中点まで板を立てる。
## 向きは板の置き方が出すので、絵は横から見た1枚で足りる（繋がり方別に64枚を持たない）。
## 板の幅は盤の形が決めている（中心→辺の中点＝0.866タイル）ので、高さは絵の縦横比から出す。
## 絵をその幅に合わせた細長いキャンバスで書き出せば、背丈は立ち絵と同じ物差しに乗る
## （→ doc/art/terrain.md）。ここでスキンの倍率を読まないのはそのため。
func _add_object_panels(panels: Dictionary, skin: TerrainSkin, hex: Vector2i) -> void:
	var tex := _object_side_texture(skin)
	if tex == null:
		return
	var st: SurfaceTool = panels.get(tex)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		panels[tex] = st
	var p := Hex.to_pixel(hex, TILE)
	var y := elev(hex)
	var conn := _connected_dirs(skin, hex)
	var half := TILE * sqrt(3.0) * 0.5  # 中心から辺の中点まで
	var h := half * (float(tex.get_height()) / maxf(float(tex.get_width()), 1.0))
	for i in 6:
		if not bool(conn[i]):
			continue
		var q := Hex.to_pixel(hex + Hex.DIRECTIONS[i], TILE)
		var a := Vector3(p.x, y, p.y)
		var b := Vector3((p.x + q.x) * 0.5, y, (p.y + q.y) * 0.5)
		var up := Vector3(0.0, h, 0.0)
		st.set_uv(Vector2(0, 1)); st.add_vertex(a)
		st.set_uv(Vector2(1, 1)); st.add_vertex(b)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a + up)
		st.set_uv(Vector2(1, 1)); st.add_vertex(b)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b + up)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a + up)

## 繋がらないオブジェクト（岩・建物・砦）。駒と同じ立ち絵1枚を、スキンが指す奥行きぶん奥に立てる。
func _add_object_standee(skin: TerrainSkin, hex: Vector2i) -> void:
	var spr := Sprite3D.new()
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	if not _apply_standee_texture(spr, skin, hex):
		spr.free()
		return
	var p := Hex.to_pixel(hex, TILE)
	spr.position = Vector3(p.x, elev(hex) + 0.02, p.y - skin.object_foot_z)
	_standee_nodes[hex] = spr
	add_child(spr)

## 立ち絵の絵を貼る（チーム別の絵の解決込み＝占領で貼り替わる）。倍率と原点は絵の寸法に
## 依存するので、絵と一緒にここで合わせる。絵が引けなければ false。
func _apply_standee_texture(spr: Sprite3D, skin: TerrainSkin, hex: Vector2i) -> bool:
	var tex := _variant_texture(_tile_image_path(skin, hex), hex)
	if tex == null:
		return false
	spr.texture = tex
	spr.pixel_size = (CANVAS_TILES * TILE) / float(tex.get_height())
	spr.offset = Vector2(0, tex.get_height() * 0.5)  # 原点＝足元
	return true

## 繋がるオブジェクトの板の絵（assets/terrain/{art_id}_side.png）。無ければ声を上げて null。
func _object_side_texture(skin: TerrainSkin) -> Texture2D:
	var id := skin.art_id()
	if _obj_side_tex.has(id):
		return _obj_side_tex[id]
	var path := "res://assets/terrain/%s_side.png" % id
	var tex := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if tex == null:
		push_error("BoardTerrainRenderer: 板の絵が無い %s" % path)
	_obj_side_tex[id] = tex
	return tex

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
			var top := elev(hex)
			for i in 6:
				var nb := hex + dirs[i]
				var bottom: float
				if not _on_board(nb):
					bottom = -SKIRT_DEPTH         # 盤外＝ジオラマの縁（島の厚み）
				elif elev(nb) < top - 0.001:
					bottom = elev(nb)            # 低い隣接＝台地の崖面（段差ぶんだけ下ろす）
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
