extends SceneTree
## 地形タイルのプレースホルダ画像を生成するツール（headless で1回走らせる）。
## ヘックス型（flat-top・中心〜頂点=R）に切り抜いた透過PNGをベタ塗りで出力する。
## アート確定後は assets/terrain/*.png を差し替えるだけ（盤の描画コードは不変）。
##
## 実行: godot --headless --script res://tools/gen_terrain_tiles.gd
##
## placeholder の色は「生成時に1回その場で決める」だけのもの＝terrain.csv には持たない。
## 地形を足したら、ここに1行（ファイル名＋色）足して実行。アート確定後は同名PNGを差し替え。
## 出力ファイル名は terrain.csv の image 列と合わせること（盤は Terrain.image_path で引く）。

const SQRT3 := 1.7320508075688772
const R := 128.0          ## 中心〜頂点（px）。表示時は盤側で hex_size にスケール。
const SS := 4             ## 1ピクセルあたりのスーパーサンプル数（辺のアンチエイリアス用）

func _initialize() -> void:
	var dir := DirAccess.open("res://")
	dir.make_dir_recursive("assets/terrain")
	_generate("res://assets/terrain/plain.png", Color.html("#CCEBC7"))      # 平地: ペールグリーン
	_generate("res://assets/terrain/road.png", Color.html("#D8C9A8"))       # 道: 砂利のタン
	_generate("res://assets/terrain/plateau.png", Color.html("#EBDBB8"))    # 台地: ペールベージュ
	_generate("res://assets/terrain/wasteland.png", Color.html("#AE9F76"))  # 荒地: くすんだ土・枯草色
	_generate("res://assets/terrain/forest.png", Color.html("#8FBF8F"))     # 森: 深めの緑
	_generate("res://assets/terrain/bush.png", Color.html("#B6D98C"))       # 茂み: 明るい黄緑
	_generate("res://assets/terrain/fence.png", Color.html("#C8A86A"))      # 柵: 木のタン
	_generate("res://assets/terrain/trap.png", Color.html("#D9A99A"))       # 罠: くすんだ赤（危険）
	_generate("res://assets/terrain/mountain.png", Color.html("#B7A892"))   # 山: 岩のグレータン
	_generate("res://assets/terrain/cliff.png", Color.html("#998E7E"))      # 崖: 暗い岩
	_generate("res://assets/terrain/rampart.png", Color.html("#B6AFA8"))    # 城壁: 石のグレー
	_generate("res://assets/terrain/wall.png", Color.html("#5F584F"))       # 壁: 暗いダンジョン石
	_generate("res://assets/terrain/fort.png", Color.html("#C7B27A"))       # 砦: 拠点の石・金茶
	print("terrain tiles generated.")
	quit()

## fill 色のヘックス型ベタ塗りPNGを path に出力（外側は透過）。
func _generate(path: String, fill: Color) -> void:
	var w := int(2.0 * R)             # 幅 = 頂点〜頂点
	var h := int(ceil(SQRT3 * R))     # 高さ = 上下の平辺間
	var cx := w / 2.0
	var cy := h / 2.0
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var inv := 1.0 / float(SS)
	var half_h := R * SQRT3 / 2.0
	for py in h:
		for px in w:
			var inside := 0
			for sy in SS:
				for sx in SS:
					var x: float = (px + (sx + 0.5) * inv) - cx
					var y: float = (py + (sy + 0.5) * inv) - cy
					var ax := absf(x)
					var ay := absf(y)
					if ay <= half_h and ax + ay / SQRT3 <= R:
						inside += 1
			if inside > 0:
				var a := float(inside) / float(SS * SS)
				img.set_pixel(px, py, Color(fill.r, fill.g, fill.b, a))
	var err := img.save_png(path)
	if err != OK:
		push_error("save_png failed (%d): %s" % [err, path])
	else:
		print("  wrote %s (%dx%d)" % [path, w, h])
