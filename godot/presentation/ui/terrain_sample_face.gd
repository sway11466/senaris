extends Control
class_name TerrainSampleFace
## 情報板の地形タブ・空きマスの地形表示に出す、そのマスの地形の見本（presentation）。
## 盤と同じPNGを描く：足場のヘックス1枚と、その中心に足元を合わせて立つオブジェクト（拠点・岩山
## など）の立ち絵。大小関係は盤と同じ＝ヘックスの幅 2R に対して立ち絵のキャンバス高さは
## BoardTerrainRenderer.CANVAS_TILES（3.75R）。ヘックスは盤のカメラの俯角ぶん縦に潰し、立ち絵は
## 盤と同じく正対（潰さない）＝盤で見えている姿に寄せる。
## 立ち絵の手前寄せ（terrain_skin.csv の object_foot_z）も盤と同じだけ掛ける＝足元をマスの中心から
## 下へ沈める。盤は俯角のぶん sin を掛けた量を画面の下方向へ寄せているので、同じ式をここでも使う
## （掛けないと、盤では地面に食い込んで建つ町や拠点が、板の中では浮いて見える）。
##
## ヘックスの手前側には厚みの帯（盤のスカートと同じもの）を付ける。高さは足場の見た目の高さ
## （terrain_skin.csv の elevation）に SIDE_EXTRA を足したぶん＝高さ0の地形でも薄く厚みが出る。
## 厚みを付けるのは、上面だけだと板の中で地形が紙のように見え、盤に敷かれた立体と結び付かない
## ため。絵は盤と同じ `{skin_id}_side.png`、持たないスキンは盤と同じくタイルの平均色を暗くして塗る。
##
## ヘックスは面の下端に置く（厚みの帯の下端＝面の下端）＝立ち絵の有無・背の高さで動かない。
## 背の高い立ち絵は面の上へはみ出す（面は板の子で切り落とされない）。仕様 → doc/gdd/uiux.md タブ

const HEX_W := 96.0     # ヘックスの幅（2R）。面の幅より狭く取り、立ち絵の左右のはみ出しを面の中に収める
const SIDE_EXTRA := 0.2 # 厚みの下駄（タイル単位）。平地（elevation 0）にも見える厚みを持たせる

var _tile: Texture2D = null    # 足場のヘックス（平面タイル）。無ければ描かない
var _object: Texture2D = null  # 足場の上に立つ絵（384角キャンバス・足元が下端）。無ければ描かない
var _foot_z := 0.0             # 立ち絵の手前寄せ（タイル単位）。スキンが持つ値をそのまま受ける
var _side: Texture2D = null    # 厚みの帯の絵。無ければ断面色（タイルの平均色）で塗る
var _elevation := 0.0          # 足場の見た目の高さ（タイル単位）。帯の高さの素になる
var _side_repeats := false     # 帯の貼り方（true＝縮尺を保って縦に並べる／false＝段差いっぱいに伸ばす）

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 絵の面＝押す物ではない（掴んだら板が動く）
	resized.connect(queue_redraw)

## 見本の中身をまとめて据える。地形が変わるたびに呼び直す＝描くのに要る値はすべてここで受ける
## （既定値を持たない＝呼ぶ側が毎回すべて決める）。
func setup(tile: Texture2D, object: Texture2D, foot_z: float,
		side: Texture2D, elevation: float, side_repeats: bool) -> void:
	_tile = tile
	_object = object
	_foot_z = foot_z
	_side = side
	_elevation = elevation
	_side_repeats = side_repeats
	queue_redraw()

func has_picture() -> bool:
	return _tile != null or _object != null

func _draw() -> void:
	if not has_picture():
		return
	var pitch := deg_to_rad(BoardCamera.PITCH_DEG)
	# ヘックスの高さ＝外接矩形 2R × √3R を俯角ぶん潰す
	var hex_h := HEX_W * sqrt(3.0) * 0.5 * sin(pitch)
	# 厚みは縦に立っている＝俯角の cos ぶんが画面に出る（潰す床とは掛ける値が違う）。
	var side_h := _side_tiles() * HEX_W * 0.5 * cos(pitch)
	var cx := size.x * 0.5
	var hex_top := size.y - hex_h - side_h
	if _tile != null:
		_draw_side(cx, hex_top + hex_h, hex_h, side_h)
		draw_texture_rect(_tile, Rect2(cx - HEX_W * 0.5, hex_top, HEX_W, hex_h), false)
	if _object != null:
		var canvas_h := HEX_W * 0.5 * BoardTerrainRenderer.CANVAS_TILES
		var canvas_w := canvas_h * float(_object.get_width()) / float(_object.get_height())
		# 足元＝マスの中心から、手前寄せのぶん下へ。寄せ量の物差しは盤と同じ 1タイル＝R（ヘックス
		# の中心〜頂点）＝ここでは HEX_W の半分。
		var foot_y := hex_top + hex_h * 0.5 + _foot_z * sin(pitch) * HEX_W * 0.5
		draw_texture_rect(_object, Rect2(cx - canvas_w * 0.5, foot_y - canvas_h, canvas_w, canvas_h), false)

## 帯の高さ（タイル単位）。
func _side_tiles() -> float:
	return maxf(0.0, _elevation) + SIDE_EXTRA

## 手前側の3辺に厚みの帯を貼る。bottom＝ヘックスの下端のy。
## 辺ごとの四角形で描く（盤のスカートと同じ割り方）＝辺をまたいでUVが続き、継ぎ目が出ない。
func _draw_side(cx: float, bottom: float, hex_h: float, side_h: float) -> void:
	if side_h <= 0.0:
		return
	var r := HEX_W * 0.5
	# フラットトップ六角形の手前側の輪郭（左の頂点→左下→右下→右の頂点）。
	var chain := [
		Vector2(cx - r, bottom - hex_h * 0.5),
		Vector2(cx - r * 0.5, bottom),
		Vector2(cx + r * 0.5, bottom),
		Vector2(cx + r, bottom - hex_h * 0.5),
	]
	# 断面の色。絵を持つスキンは染めず上端→下端の減光だけ、持たないスキンはタイルの平均色を
	# 暗くして塗る（どちらも盤のスカートと同じ決め方）。
	var top_c := Color(1, 1, 1)
	var bot_c := Color(0.8, 0.8, 0.8)
	if _side == null:
		var base := TerrainTiles.avg_color(_tile)
		top_c = base.darkened(BoardTerrainRenderer.SKIRT_DARKEN - 0.20)
		bot_c = base.darkened(BoardTerrainRenderer.SKIRT_DARKEN + 0.20)
	# 帯の縦のUV。引き伸ばし＝1枚を高さいっぱいに、繰り返し＝絵の縦横比を保って縦に並べる。
	var v_top := 0.05
	var v_bot := 0.95
	if _side != null and _side_repeats:
		var band_tiles := BoardTerrainRenderer.SIDE_TEX_WIDTH \
			* float(_side.get_height()) / float(maxi(_side.get_width(), 1))
		v_top = 0.0
		v_bot = _side_tiles() / band_tiles
	# 横のUVは画面の横位置から取る＝辺をまたいでも石の大きさと継ぎ目が揃う（盤と同じ物差し）。
	var u_w := BoardTerrainRenderer.SIDE_TEX_WIDTH * r
	for i in chain.size() - 1:
		var c0: Vector2 = chain[i]
		var c1: Vector2 = chain[i + 1]
		var pts := PackedVector2Array([c0, c1, c1 + Vector2(0, side_h), c0 + Vector2(0, side_h)])
		var cols := PackedColorArray([top_c, top_c, bot_c, bot_c])
		if _side == null:
			draw_polygon(pts, cols)
			continue
		var uvs := PackedVector2Array([
			Vector2(c0.x / u_w, v_top), Vector2(c1.x / u_w, v_top),
			Vector2(c1.x / u_w, v_bot), Vector2(c0.x / u_w, v_bot)])
		draw_polygon(pts, cols, uvs, _side)
