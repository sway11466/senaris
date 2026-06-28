extends SceneTree
## 地形タイルのプレースホルダ画像を生成するツール（headless で1回走らせる）。
## ヘックス型（flat-top・中心〜頂点=R）に切り抜いた透過PNGをベタ塗りで出力する。
## アート確定後は assets/terrain/*.png を差し替えるだけ（盤の描画コードは不変）。
##
## 実行: godot --headless --script res://tools/gen_terrain_tiles.gd
##
## 色と種類は data/terrain/terrain.csv の正本（id, color 列）から読む。地形を増やしたら再実行。
## 出力は assets/terrain/<id>.png（盤は Terrain.image_path(id) で引く）。

const Csv = preload("res://data/csv_util.gd")
const SQRT3 := 1.7320508075688772
const R := 128.0          ## 中心〜頂点（px）。表示時は盤側で hex_size にスケール。
const SS := 4             ## 1ピクセルあたりのスーパーサンプル数（辺のアンチエイリアス用）

func _initialize() -> void:
	var dir := DirAccess.open("res://")
	dir.make_dir_recursive("assets/terrain")
	for t in Csv.read_table("res://data/terrain/terrain.csv"):
		var id := String(t["id"])
		_generate("res://assets/terrain/%s.png" % id, Color.html(String(t["color"])))
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
