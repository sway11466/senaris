extends SceneTree
## アプリアイコンの SVG を各寸法の PNG に焼く。仕様 → doc/art/icon.md
##
## 寸法で紋章を使い分ける（64px 以上＝7枚版・48px 以下＝1枚版）。小さいほうは
## タイルの粒が塊に潰れるため、中央ヘックス1枚に武器を刺した版へ切り替える。
##
##   godot --headless --path godot --script res://tools/logo/build_icon.gd
##
## .ico に束ねるのは ImageMagick なので、通しで作り直すときは build_icon.ps1 を使う。

const SRC_DIR := "res://assets/appicon-src"
const OUT_DIR := "res://assets/appicon"
const SMALL := [16, 24, 32, 48]  # 1枚版（icon_small.svg）
const LARGE := [64, 128, 256]    # 7枚版（icon_large.svg）
const APP_ICON_PX := 256         # project.godot の config/icon に指す PNG

const PREVIEW_GAP := 24
const PREVIEW_DARK := Color(0.125, 0.149, 0.180)   # タスクバー相当
const PREVIEW_LIGHT := Color(0.949, 0.949, 0.949)  # エクスプローラ相当


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SRC_DIR + "/png")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var made: Array[Image] = []
	for pair in [[SMALL, "icon_small"], [LARGE, "icon_large"]]:
		var svg := _read(SRC_DIR + "/%s.svg" % pair[1])
		if svg.is_empty():
			quit(1)
			return
		for px in pair[0]:
			var img := _render(svg, px)
			if img == null:
				quit(1)
				return
			var dst := SRC_DIR + "/png/icon_%d.png" % px
			img.save_png(dst)
			print("%s (%d x %d)" % [dst, img.get_width(), img.get_height()])
			made.append(img)
			if px == APP_ICON_PX:
				img.save_png(OUT_DIR + "/icon.png")
				print(OUT_DIR + "/icon.png")
	_preview(made)
	quit(0)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("読めない: %s (err %d)" % [path, FileAccess.get_open_error()])
		return ""
	var text := f.get_as_text()
	f.close()
	return text


## SVG を、指定の辺の長さちょうどに焼く（倍率ではなく px を指定したいため）。
func _render(svg: String, px: int) -> Image:
	var base := Image.new()
	if base.load_svg_from_string(svg, 1.0) != OK:
		printerr("SVG を読めない")
		return null
	var img := Image.new()
	if img.load_svg_from_string(svg, float(px) / float(base.get_width())) != OK:
		printerr("SVG を焼けない (%d px)" % px)
		return null
	return img


## 全寸法を暗い地と明るい地に並べた1枚。透過のままでは実際の見えが分からない。
func _preview(images: Array[Image]) -> void:
	var w := 0
	for img in images:
		w += img.get_width() + PREVIEW_GAP
	var row := images[images.size() - 1].get_height() + PREVIEW_GAP
	var sheet := Image.create(w, row * 2, false, Image.FORMAT_RGBA8)
	for i in 2:
		var band := Rect2i(0, row * i, w, row)
		sheet.fill_rect(band, PREVIEW_DARK if i == 0 else PREVIEW_LIGHT)
		var x := 0
		for img in images:
			var px := img.get_width()
			sheet.blend_rect(img, Rect2i(0, 0, px, px),
					Vector2i(x + PREVIEW_GAP / 2, row * i + (row - px) / 2))
			x += px + PREVIEW_GAP
	var dst := SRC_DIR + "/preview.png"
	sheet.save_png(dst)
	print("%s (%d x %d)" % [dst, sheet.get_width(), sheet.get_height()])
