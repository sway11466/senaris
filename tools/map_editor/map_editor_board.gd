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
signal height_edited(axis: String, index: int, value: float)  ## 番号帯の高さ入力欄で確定（axis="row"/"col"）

const SQRT3 := 1.7320508075688772
const MARGIN := 22.0    ## 盤の右・下の余白
const HEADER_H := 36.0  ## 上の帯（列番号＋列の基準高さ。→ doc/gdd/terrain.md 盤の高さ）
const HEADER_W := 56.0  ## 左の帯（行番号＋行の基準高さ）
const HEIGHT_RANGE := 99.0  ## 基準高さの入力範囲（±）
## 基準高さの文字色。0は薄く（分布が読める程度）、ホバーで明るく＝クリックできる合図。
const COLOR_HEIGHT := Color(1.0, 0.82, 0.4, 0.9)
const COLOR_HEIGHT_ZERO := Color(1.0, 0.82, 0.4, 0.35)
const COLOR_HEIGHT_HOVER := Color(1.0, 0.95, 0.7, 1.0)

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
const TERRAIN_COLORS := {  # terrain_type.csv の id と同順・全型
	"road": Color(0.78, 0.70, 0.52),
	"plain": Color(0.62, 0.75, 0.42),
	"wasteland": Color(0.71, 0.63, 0.52),
	"rampart": Color(0.60, 0.64, 0.69),
	"river": Color(0.45, 0.62, 0.78),
	"wall": Color(0.25, 0.25, 0.28),
	"plateau": Color(0.76, 0.66, 0.40),
	"forest": Color(0.30, 0.48, 0.23),
	"bush": Color(0.48, 0.63, 0.31),
	"bedrock": Color(0.54, 0.50, 0.46),
	"fence": Color(0.63, 0.55, 0.35),
	"trap": Color(0.69, 0.42, 0.35),
	"prop": Color(0.62, 0.54, 0.60),
	"rubble": Color(0.58, 0.55, 0.48),
	"rock": Color(0.44, 0.48, 0.53),
	"building": Color(0.70, 0.52, 0.40),
	"fort": Color(0.75, 0.47, 0.25),
	"bridge": Color(0.66, 0.62, 0.55),
	"keepout": Color(0.35, 0.32, 0.36),
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

var _hover_header := {}          # ホバー中の番号帯 { axis, index }。空＝帯の外
var _height_edit: LineEdit = null  # 開いている高さ入力欄（null＝なし）
var _height_edit_axis := ""
var _height_edit_index := -1


func _ready() -> void:
	_unit_skins = SkinCatalog.load_standard()
	mouse_exited.connect(func() -> void:
		hover = OUTSIDE
		queue_redraw())


## doc の変更後に呼ぶ（サイズ再計算＋再描画）。外周(margin)ぶんも描くので領域を広げる。
## ズームや盤サイズが変わると入力欄の位置がずれるので、開いていたら閉じる。
func refresh() -> void:
	if doc == null:
		return
	_close_height_editor()
	var m := doc.margin()
	custom_minimum_size = Vector2(
		hex_size * (1.5 * (doc.cols() + m * 2 - 1) + 2.0) + HEADER_W + MARGIN,
		hex_size * SQRT3 * (doc.rows() + m * 2 + 0.5) + HEADER_H + MARGIN)
	queue_redraw()


## 盤の (0,0) の中心。外周ぶんだけ内側へずらす＝外周のセル（負の col/row）も領域に収まる。
## ずらし量は描画範囲の左上端から出す。to_pixel は col=-m で x 最小、row=-m かつ偶数列で y 最小
## （奇数列は odd-q の食い違いで半ヘックス下がる）＝ずらし量は (1.5m, √3m) ヘックス。
func _origin() -> Vector2:
	var m := float(doc.margin()) if doc != null else 0.0
	return Vector2(hex_size * (1.0 + 1.5 * m) + HEADER_W, hex_size * SQRT3 * (0.5 + m) + HEADER_H)


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
		if event.pressed:
			_close_height_editor()  # 入力欄の外をクリック＝取り消して閉じる
			if event.button_index == MOUSE_BUTTON_LEFT:
				var hh := _header_at(event.position)
				if not hh.is_empty():  # 番号帯の高さ表示をクリック＝その場で入力欄を開く
					_open_height_editor(String(hh["axis"]), int(hh["index"]))
					accept_event()
					return
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
		var hh := _header_at(event.position)
		if hh != _hover_header:
			_hover_header = hh
			# 手のカーソルで「クリックできる」を示す（帯の外では通常の矢印に戻す）。
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not hh.is_empty() \
				else Control.CURSOR_ARROW
			queue_redraw()
		var cell := cell_at(event.position)
		if cell != hover:
			hover = cell
			queue_redraw()
		if _drag_button != -1 and cell != OUTSIDE and cell != _last_cell:
			_last_cell = cell
			cell_dragged.emit(cell.x, cell.y, _drag_button)


# --- 盤の高さ（番号帯の常時表示とその場の入力欄）。値の意味 → doc/gdd/terrain.md 盤の高さ ---


## 番号帯のどの行/列の上か。上の帯＝列・左の帯＝行。どちらでもなければ空辞書。
## 帯は盤の行・列だけが対象（外周は高さを持たない＝height 配列は盤のサイズ基準）。
func _header_at(p: Vector2) -> Dictionary:
	if doc == null:
		return {}
	if p.y >= 0.0 and p.y < HEADER_H:
		for col in doc.cols():
			if absf(p.x - cell_center(col, 0).x) <= hex_size * 0.75:
				return { "axis": "col", "index": col }
	if p.x >= 0.0 and p.x < HEADER_W:
		for row in doc.rows():
			if absf(p.y - cell_center(0, row).y) <= hex_size * SQRT3 * 0.5:
				return { "axis": "row", "index": row }
	return {}


## クリックした番号の位置に入力欄を開く。Enter＝確定（height_edited を発火）、
## Esc・外クリック＝取り消し。値の書き込みは main（doc を持つ側）に任せる。
func _open_height_editor(axis: String, index: int) -> void:
	_close_height_editor()
	var e := LineEdit.new()
	e.text = _fmt_height(doc.col_height(index) if axis == "col" else doc.row_height(index))
	if axis == "col":
		e.position = Vector2(cell_center(index, 0).x - 30.0, HEADER_H - 26.0)
		e.size = Vector2(60.0, 24.0)
	else:
		e.position = Vector2(2.0, cell_center(0, index).y - 12.0)
		e.size = Vector2(HEADER_W - 4.0, 24.0)
	e.text_submitted.connect(_commit_height)
	e.focus_exited.connect(_close_height_editor)  # Esc は LineEdit がフォーカスを手放す＝ここに来る
	add_child(e)
	_height_edit = e
	_height_edit_axis = axis
	_height_edit_index = index
	e.grab_focus()
	e.select_all()


## 入力欄の確定。数値として読めない入力は捨てる（元の値のまま）。
func _commit_height(text: String) -> void:
	var axis := _height_edit_axis
	var index := _height_edit_index
	_close_height_editor()
	var s := text.strip_edges()
	if not s.is_valid_float():
		return
	height_edited.emit(axis, index, clampf(s.to_float(), -HEIGHT_RANGE, HEIGHT_RANGE))


func _close_height_editor() -> void:
	if _height_edit == null:
		return
	var e := _height_edit
	_height_edit = null
	# 解放時に遅れて飛ぶ focus_exited を切る＝入れ替えで開いた次の入力欄を巻き込んで閉じない。
	e.focus_exited.disconnect(_close_height_editor)
	e.queue_free()


## 基準高さの表示文字。整数値は整数で（保存時の _scalar と同じ見た目）。
static func _fmt_height(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(v)


static func _height_color(v: float, hovered: bool) -> Color:
	if hovered:
		return COLOR_HEIGHT_HOVER
	return COLOR_HEIGHT if v != 0.0 else COLOR_HEIGHT_ZERO


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
	# 列/行番号（JSONの col/row と突き合わせるため）と基準高さ（全マス分の常時表示＝クリックの受け皿。
	# 番号は薄い白・高さは琥珀色で、座標と高さを読み違えないようにする）。
	var hover_axis := String(_hover_header.get("axis", ""))
	var hover_index := int(_hover_header.get("index", -1))
	for col in doc.cols():
		var c := cell_center(col, 0)
		draw_string(font, Vector2(c.x - hex_size, HEADER_H - 22.0), str(col),
			HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, 10, Color(1, 1, 1, 0.45))
		draw_string(font, Vector2(c.x - hex_size, HEADER_H - 8.0), _fmt_height(doc.col_height(col)),
			HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, 10,
			_height_color(doc.col_height(col), hover_axis == "col" and hover_index == col))
	for row in doc.rows():
		var c := cell_center(0, row)
		draw_string(font, Vector2(2.0, c.y + 4.0), str(row),
			HORIZONTAL_ALIGNMENT_LEFT, 18.0, 10, Color(1, 1, 1, 0.45))
		draw_string(font, Vector2(22.0, c.y + 4.0), _fmt_height(doc.row_height(row)),
			HORIZONTAL_ALIGNMENT_LEFT, HEADER_W - 26.0, 10,
			_height_color(doc.row_height(row), hover_axis == "row" and hover_index == row))
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
		var g_count := MapEditorDoc.garrison_count(b)
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
	if not by_team:
		base = _connected_path(cell, skin, skins)
	var w := ceili(hex_size * 2.0)
	var h := ceili(hex_size * SQRT3)
	var axial := Hex.offset_to_axial(cell.x, cell.y)  # 本体の variant 選択は軸座標のハッシュ
	var over := _variant_texture(base, axial, w, h)
	# 地面を絵に焼き込んでいないスキン（map_ground）は、本体と同じく下地を敷いてから重ねる。
	var ground_id := skin.map_ground_id()
	if not ground_id.is_empty() and not by_team:
		var ground := TerrainSkinCatalog.resolve(ground_id, "")
		if ground != null:
			# 下地も接続タイルを引く（本体と同じ）。橋のマスの川は向きが合っていないと繋がらない。
			var gp := _connected_path(cell, ground, skins)
			return TerrainTiles.composited(_variant_texture(gp, axial, w, h), over)
	return over


## skin がそのセルで引く画像パス。繋がる地形なら向きの組み合わせ別タイル、無ければ基本の1枚。
func _connected_path(cell: Vector2i, skin: TerrainSkin, skins: Dictionary) -> String:
	if skin.connects():
		var cp := skin.connected_image_path(_connected_dirs(cell, skin, skins))
		if ResourceLoader.exists(cp):
			return cp
	return skin.image_path()


## 基本パスの variant を1枚選び、盤の表示サイズに縮めて返す。
func _variant_texture(base_path: String, axial: Vector2i, w: int, h: int) -> Texture2D:
	var paths := _variant_paths(base_path)
	if paths.is_empty():
		return null
	return _scaled(String(paths[absi(hash(axial)) % paths.size()]), w, h)


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
		connected.append(skin.connects_with(n))
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
