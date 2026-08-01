extends Control
class_name MapEditorBoard
## マップエディタの盤面キャンバス（tools 専用）。
## MapEditorDoc の内容を flat-top ヘックス（本体と同じ odd-q オフセット＝Hex.gd）で描画し、
## セル単位のマウス操作をシグナルで通知する。
##
## 見た目は実機と同じ画像を貼る（地形＝TerrainSkinCatalog / 駒＝SkinCatalog の autowire 規約）。
## 画像が無いスキンは色と文字のプレースホルダで描く。編集に要る情報（地形の文字・部隊番号・id・
## 拠点リング）は画像の上に重ねる。真上から見た平面表示＝段差や傾きは出ない（実機の絵は本体で見る）。

signal cell_pressed(col: int, row: int, button: int)
signal cell_dragged(col: int, row: int, button: int)
signal cell_released(col: int, row: int, button: int)
signal zoom_requested(step: int)  ## Ctrl＋ホイール（+1=拡大 / -1=縮小）

const SQRT3 := 1.7320508075688772
const MARGIN := 22.0  ## 盤の余白（列/行番号の表示領域を兼ねる）

## 描画領域の外を表す番兵。外周(margin)があると (-1,-1) は正当なセルなので、負値では判別できない。
const OUTSIDE := Vector2i(-9999, -9999)
const MARGIN_DIM := 0.45  ## 外周のセルの描画の薄さ（盤との区別）。盤外＝駒を置けないことを見た目で示す
const COLOR_BOARD_EDGE := Color(1, 1, 1, 0.55)  ## 盤と外周の境界線

## 駒の立ち絵（384四方のキャンバス）をヘックス何個分の高さで描くか。
## 実機は 3.75（doc/art/units.md §3.1）だが、真上から見るエディタでは隣のマスを覆うので小さめにする。
const UNIT_CANVAS_HEXES := 2.6
const UNIT_FOOT := 0.5  ## 立ち絵の足元（キャンバス下端）をヘックス中心からどれだけ下へ置くか

## 拠点タイルの陣営別画像 assets/terrain/{skin_id}_team{N}.png の N（StageLoader と同じ番号）。
const TEAM_INDEX := { "player": 0, "enemy": 1 }

## 画像が無いスキンのプレースホルダ色（区別が付けばよい）。
const TERRAIN_COLORS := {
	"road": Color(0.78, 0.70, 0.52),
	"plain": Color(0.62, 0.75, 0.42),
	"plateau": Color(0.76, 0.66, 0.40),
	"wasteland": Color(0.71, 0.63, 0.52),
	"forest": Color(0.30, 0.48, 0.23),
	"bush": Color(0.48, 0.63, 0.31),
	"mountain": Color(0.54, 0.50, 0.46),
	"fence": Color(0.63, 0.55, 0.35),
	"trap": Color(0.69, 0.42, 0.35),
	"rampart": Color(0.60, 0.64, 0.69),
	"cliff": Color(0.44, 0.48, 0.53),
	"wall": Color(0.25, 0.25, 0.28),
	"fort": Color(0.75, 0.47, 0.25),
}
const TEAM_COLORS := {
	"player": Color(0.25, 0.45, 0.85),
	"enemy": Color(0.82, 0.28, 0.28),
	"neutral": Color(0.55, 0.55, 0.55),
}

var doc: MapEditorDoc
var scroll: ScrollContainer  ## 中ボタンドラッグでパンする先（親のスクロール。main が設定）
var hex_size := 26.0:
	set(v):
		hex_size = v
		refresh()
var hover := OUTSIDE
var selected := OUTSIDE

var _drag_button := -1
var _last_cell := OUTSIDE
var _panning := false

var _unit_skins := {}   # SkinCatalog の索引（画像パスは autowire 済み＝実機と同じ絵になる）
var _tex_cache := {}    # "画像パス@幅" -> Texture2D|null（縮小済み）
var _variants := {}     # 基本パス -> Array[String]（基本＋連番 variant のパス。ResourceLoader の探索は1回だけ）


func _ready() -> void:
	_unit_skins = SkinCatalog.load_standard()
	mouse_exited.connect(func() -> void:
		hover = OUTSIDE
		queue_redraw())


## doc の変更後に呼ぶ（サイズ再計算＋再描画）。外周(margin)ぶんも描くので領域を広げる。
func refresh() -> void:
	if doc == null:
		return
	var m := doc.margin()
	custom_minimum_size = Vector2(
		hex_size * (1.5 * (doc.cols() + m * 2 - 1) + 2.0) + MARGIN * 2.0,
		hex_size * SQRT3 * (doc.rows() + m * 2 + 0.5) + MARGIN * 2.0)
	queue_redraw()


## 盤の (0,0) の中心。外周ぶんだけ内側へずらす＝外周のセル（負の col/row）も領域に収まる。
## ずらし量は描画範囲の左上端から出す。to_pixel は col=-m で x 最小、row=-m かつ偶数列で y 最小
## （奇数列は odd-q の食い違いで半ヘックス下がる）＝ずらし量は (1.5m, √3m) ヘックス。
func _origin() -> Vector2:
	var m := float(doc.margin()) if doc != null else 0.0
	return Vector2(hex_size * (1.0 + 1.5 * m) + MARGIN, hex_size * SQRT3 * (0.5 + m) + MARGIN)


func cell_center(col: int, row: int) -> Vector2:
	return _origin() + Hex.to_pixel(Hex.offset_to_axial(col, row), hex_size)


## ピクセル→セル。外周も返す（描画領域の外は (-9999,-9999)）。
## 呼び出し側は doc.in_board() で「駒を置ける盤か」を判定する（外周には置けない）。
func cell_at(p: Vector2) -> Vector2i:
	var off := Hex.axial_to_offset(Hex.from_pixel(p - _origin(), hex_size))
	if not doc.in_canvas(off.x, off.y):
		return OUTSIDE
	return off


func _gui_input(event: InputEvent) -> void:
	if doc == null:
		return
	# パン＝中ボタンドラッグ / ズーム＝Ctrl＋ホイール。素のホイール/トラックパッドのスクロールは
	# accept せず ScrollContainer に流す（＝通常のスクロールでも盤を動かせる）。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.ctrl_pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom_requested.emit(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		accept_event()
		return
	if event is InputEventMouseMotion and _panning:
		if scroll != null:
			scroll.scroll_horizontal -= int(event.relative.x)
			scroll.scroll_vertical -= int(event.relative.y)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var cell := cell_at(event.position)
		if event.pressed:
			_drag_button = event.button_index
			_last_cell = cell
			if cell != OUTSIDE:
				cell_pressed.emit(cell.x, cell.y, event.button_index)
		elif event.button_index == _drag_button:
			_drag_button = -1
			if cell != OUTSIDE:
				cell_released.emit(cell.x, cell.y, event.button_index)
	elif event is InputEventMouseMotion:
		var cell := cell_at(event.position)
		if cell != hover:
			hover = cell
			queue_redraw()
		if _drag_button != -1 and cell != OUTSIDE and cell != _last_cell:
			_last_cell = cell
			cell_dragged.emit(cell.x, cell.y, _drag_button)


func _hex_points(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		pts.append(center + Vector2(cos(a), sin(a)) * size)
	return pts


func _draw() -> void:
	if doc == null:
		return
	var font := get_theme_default_font()
	# 列/行番号（JSONの col/row と突き合わせるため）
	for col in doc.cols():
		var c := cell_center(col, 0)
		draw_string(font, Vector2(c.x - hex_size, MARGIN - 8.0), str(col),
			HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, 10, Color(1, 1, 1, 0.45))
	for row in doc.rows():
		var c := cell_center(0, row)
		draw_string(font, Vector2(1.0, c.y + 4.0), str(row),
			HORIZONTAL_ALIGNMENT_LEFT, MARGIN - 2.0, 10, Color(1, 1, 1, 0.45))
	# 地形（タイル画像。無ければ色＋skin_id の文字）。外周(margin)も描くが、盤外と分かるよう薄くする。
	var skins := doc.terrain_skin_map()
	var base_teams := _base_team_map()
	var m := doc.margin()
	for row in range(-m, doc.rows() + m):
		for col in range(-m, doc.cols() + m):
			var cell := Vector2i(col, row)
			var center := cell_center(col, row)
			var ch := doc.terrain_char(col, row)
			var tid := TerrainType.char_to_id(ch)
			var skin := String(skins.get(cell, ""))
			var dim := 1.0 if doc.in_board(col, row) else MARGIN_DIM
			var tex := _terrain_texture(cell, skin, tid, int(base_teams.get(cell, -1)), skins)
			if tex != null:
				draw_texture_rect(tex, Rect2(center - Vector2(hex_size, hex_size * SQRT3 * 0.5),
					Vector2(hex_size * 2.0, hex_size * SQRT3)), false, Color(1, 1, 1, dim))
				var edge := _hex_points(center, hex_size)
				edge.append(edge[0])
				draw_polyline(edge, Color(0, 0, 0, 0.22 * dim), 1.0)
			else:
				var color: Color = TERRAIN_COLORS.get(tid, Color(0.5, 0.5, 0.5))
				draw_colored_polygon(_hex_points(center, hex_size * 0.96), Color(color, dim))
				var border := _hex_points(center, hex_size * 0.96)
				border.append(border[0])
				draw_polyline(border, Color(0, 0, 0, 0.35 * dim), 1.0)
				if skin != "":
					_text(font, center, hex_size * 0.1, skin.substr(0, 10),
						maxi(7, int(hex_size * 0.26)), Color(0.7, 0.85, 1.0, dim))
			if ch != MapEditorDoc.DEFAULT_CHAR:
				# 性能(TerrainType)は絵からは読めないので必ず重ねる。絵の邪魔をしないよう控えめに。
				_text(font, center, hex_size * -0.35, ch,
					maxi(8, int(hex_size * 0.42)), Color(1, 1, 1, 0.6 * dim))
	_draw_board_edge()
	# 拠点（リング＋種別＋控え数）
	for b in doc.data["bases"]:
		var center := cell_center(int(b.get("col", 0)), int(b.get("row", 0)))
		var color: Color = TEAM_COLORS.get(String(b.get("team", "neutral")), TEAM_COLORS["neutral"])
		draw_arc(center, hex_size * 0.74, 0.0, TAU, 32, color, 3.0)
		var label := "HQ" if String(b.get("kind", "fort")) == "hq" else "F"
		var g: Variant = b.get("garrison", [])
		var g_count := 0
		if typeof(g) == TYPE_ARRAY:
			for e in g:
				g_count += maxi(int(e.get("count", 1)), 1)
		if g_count > 0:
			label += " x%d" % g_count
		_text(font, center, hex_size * 0.9, label, maxi(8, int(hex_size * 0.36)), color.lightened(0.4))
	# ユニット（立ち絵＋台座。敵は部隊番号、明示idはボス印）
	# 上の行から描く＝立ち絵が重なったとき手前（下の行）が上に来る。
	var font_size := maxi(8, int(hex_size * 0.32))
	var pieces := []
	for u in doc.data["player"]:
		pieces.append({ "unit": u, "team": 0, "tag": "" })
	var squads: Array = doc.data["enemy"]
	for s in squads.size():
		for u in squads[s].get("units", []):
			pieces.append({ "unit": u, "team": 1, "tag": str(s) })
	pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := int(a["unit"].get("row", 0))
		var rb := int(b["unit"].get("row", 0))
		if ra != rb:
			return ra < rb
		return int(a["unit"].get("col", 0)) < int(b["unit"].get("col", 0)))
	for p in pieces:
		_draw_unit(font, p["unit"], int(p["team"]), String(p["tag"]), font_size)
	# ホバー・選択
	if hover.x >= 0:
		var pts := _hex_points(cell_center(hover.x, hover.y), hex_size * 0.96)
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.8), 2.0)
	if selected.x >= 0:
		var pts := _hex_points(cell_center(selected.x, selected.y), hex_size * 0.96)
		pts.append(pts[0])
		draw_polyline(pts, Color(1.0, 0.9, 0.2, 0.95), 2.5)


## 遊べる盤の輪郭。外周を描いていると盤の縁がどこか読めなくなるので、境界の辺だけをなぞる。
## 各辺は隣との中点を通り、辺の向きは隣への向きと直交する（正六角形なので辺の長さ＝hex_size）。
func _draw_board_edge() -> void:
	if doc.margin() <= 0:
		return
	for row in doc.rows():
		for col in doc.cols():
			var center := cell_center(col, row)
			var axial := Hex.offset_to_axial(col, row)
			for d in Hex.DIRECTIONS:
				var n := Hex.axial_to_offset(axial + d)
				if doc.in_board(n.x, n.y):
					continue  # 盤の内どうし＝境界ではない
				var delta := Hex.to_pixel(axial + d, hex_size) - Hex.to_pixel(axial, hex_size)
				var perp := Vector2(-delta.y, delta.x).normalized() * (hex_size * 0.5)
				var mid := center + delta * 0.5
				draw_line(mid - perp, mid + perp, COLOR_BOARD_EDGE, 2.0)


## 駒1体。map 画像があれば陣営色の台座＋立ち絵、無ければ丸＋スキン名で描く（画像未用意のスキンが多い）。
## 陣営はどちらの場合も色（台座／丸）で読む＝絵だけでは自軍と敵の区別が付かないため。
## 名前は絵で分かるので画像があるときは出さない（駒の詳細は「選択」モードのインスペクタ）。
func _draw_unit(font: Font, u: Dictionary, team: int, squad_tag: String, font_size: int) -> void:
	var center := cell_center(int(u.get("col", 0)), int(u.get("row", 0)))
	var color: Color = TEAM_COLORS["player"] if team == 0 else TEAM_COLORS["enemy"]
	var squad_y := -hex_size * 0.55  # プレースホルダは丸の上（絵が無いので空いている）
	var id_y := hex_size * 0.75
	var tex := _unit_texture(u, team)
	if tex != null:
		draw_colored_polygon(_ellipse(center + Vector2(0, hex_size * 0.34), hex_size * 0.44, hex_size * 0.2),
			Color(color, 0.85))
		var side := hex_size * UNIT_CANVAS_HEXES
		draw_texture_rect(tex,
			Rect2(center.x - side * 0.5, center.y + hex_size * UNIT_FOOT - side, side, side), false)
		squad_y = hex_size * 0.72  # 立ち絵の顔に被らないよう、印は足元より下へ積む
		id_y = squad_y + font_size * 1.05
	else:
		draw_circle(center, hex_size * 0.5, color)
		draw_arc(center, hex_size * 0.5, 0.0, TAU, 24, color.darkened(0.4), 1.5)
		_text(font, center, font_size * 0.4, String(u.get("skin", u.get("type", "?"))).substr(0, 8),
			font_size, Color.WHITE)
	if squad_tag != "":
		_text(font, center, squad_y, "部" + squad_tag, font_size, Color(1, 0.85, 0.5))
	if u.has("id"):
		_text(font, center, id_y, "id" + str(int(u["id"])), font_size, Color(1, 0.9, 0.2))
	if u.has("passengers") and typeof(u["passengers"]) == TYPE_ARRAY and not u["passengers"].is_empty():
		_text(font, center, id_y, "乗%d" % u["passengers"].size(), font_size, Color(0.8, 1, 0.8))


# --- 画像（実機と同じ規約で引く） ---


## セルに敷くタイル画像。skin 未指定は地形タイプの既定スキン、拠点は陣営別の絵があればそちら。
## 変種（_2/_3）の選び方も線地形（connect）の繋がり方も本体と同じ＝エディタと実機で同じ絵が出る。
func _terrain_texture(cell: Vector2i, skin_id: String, type_id: String, team: int,
		skins: Dictionary) -> Texture2D:
	var skin := TerrainSkinCatalog.resolve(skin_id, type_id)
	if skin == null:
		return null
	var base := skin.image_path()
	var by_team := false
	if team >= 0:
		var p := "res://assets/terrain/%s_team%d.png" % [skin.skin_id, team]
		if ResourceLoader.exists(p):
			base = p
			by_team = true
	if not by_team and skin.connects():
		var cp := skin.connected_image_path(_connected_dirs(cell, skin, skins))
		if ResourceLoader.exists(cp):
			base = cp
	var paths := _variant_paths(base)
	if paths.is_empty():
		return null
	var axial := Hex.offset_to_axial(cell.x, cell.y)  # 本体の variant 選択は軸座標のハッシュ
	return _scaled(String(paths[absi(hash(axial)) % paths.size()]),
		ceili(hex_size * 2.0), ceili(hex_size * SQRT3))


## cell の6近傍が同じスキンか（Hex.DIRECTIONS 順）。盤の縁の扱いは本体と同じ3段
## （→ presentation/board/hex_board_3d.gd の _connected_dirs）＝エディタと実機で同じ絵が出る。
## 1) 外周(margin)が描いてあればそれを読む 2) 外周が無い面(area)は座標を盤に丸めて読む
## 3) 外周が無い線(line)は丸めず端だけ伸ばす（TerrainSkin.extend_off_board）。
func _connected_dirs(cell: Vector2i, skin: TerrainSkin, skins: Dictionary) -> Array:
	var axial := Hex.offset_to_axial(cell.x, cell.y)
	var area := skin.connects_as_area()
	var connected: Array = []
	var on_board: Array = []
	for d in Hex.DIRECTIONS:
		var c := Hex.axial_to_offset(axial + d)
		var covered := true
		var n: TerrainSkin = null
		if doc.in_board(c.x, c.y) or doc.in_canvas(c.x, c.y):
			# 盤内、または作者が描いた外周。どちらも書いてある地形をそのまま読む。
			n = TerrainSkinCatalog.resolve(String(skins.get(c, "")),
				TerrainType.char_to_id(doc.terrain_char(c.x, c.y)))
		elif area:
			var b := Vector2i(clampi(c.x, 0, doc.cols() - 1), clampi(c.y, 0, doc.rows() - 1))
			n = TerrainSkinCatalog.resolve(String(skins.get(b, "")),
				TerrainType.char_to_id(doc.terrain_char(b.x, b.y)))
		else:
			covered = false
		connected.append(n != null and n.skin_id == skin.skin_id)
		on_board.append(covered)
	if area:
		return connected
	return TerrainSkin.extend_off_board(connected, on_board)


## 駒の map 画像。skin 指定を優先し、無ければ type の既定スキン（自軍は type だけで置かれる）。
func _unit_texture(u: Dictionary, team: int) -> Texture2D:
	var skin: UnitSkin = SkinCatalog.resolve(_unit_skins,
		String(u.get("skin", "")), String(u.get("type", "")), team)
	if skin == null:
		return null
	var path := skin.image("map")
	if path == "":
		return null
	var side := ceili(hex_size * UNIT_CANVAS_HEXES)
	return _scaled(path, side, side)


## 基本パス＋連番 variant（_2/_3…）の実在するパス一覧。
func _variant_paths(base_path: String) -> Array:
	if _variants.has(base_path):
		return _variants[base_path]
	var list := []
	if ResourceLoader.exists(base_path):
		list.append(base_path)
	var stem := base_path.trim_suffix(".png")
	var n := 2
	while true:
		var p := "%s_%d.png" % [stem, n]
		if not ResourceLoader.exists(p):
			break
		list.append(p)
		n += 1
	_variants[base_path] = list
	return list


## 画像を表示サイズまで縮小したテクスチャ。素材はミップマップ無し＝そのまま縮小すると荒れるので、
## ズーム段ごとに Lanczos で作り置きする。読めなければ null（＝プレースホルダで描く合図）。
func _scaled(path: String, w: int, h: int) -> Texture2D:
	var key := "%s@%d" % [path, w]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	var src := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if src != null:
		var img := src.get_image()
		if img != null:
			img.resize(maxi(w, 1), maxi(h, 1), Image.INTERPOLATE_LANCZOS)
			tex = ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## 拠点のあるセル→陣営番号（_team{N}.png の N）。中立と拠点なしは -1。
func _base_team_map() -> Dictionary:
	var out := {}
	for b in doc.data["bases"]:
		out[Vector2i(int(b.get("col", 0)), int(b.get("row", 0)))] = \
			int(TEAM_INDEX.get(String(b.get("team", "neutral")), -1))
	return out


# --- 描画の小道具 ---


## 中央揃えの文字（影付き）。タイル画像や立ち絵の上でも読めるようにする。
func _text(font: Font, center: Vector2, offset_y: float, s: String, size: int, color: Color) -> void:
	var pos := Vector2(center.x - hex_size, center.y + offset_y)
	draw_string(font, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, size, Color(0, 0, 0, 0.7))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, size, color)


func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
