extends SceneTree
## SVG を PNG に変換する。
##
## この環境には SVG のラスタライザが無いが、Godot 自身が SVG を読める（ThorVG）。
## マスク（タイルから文字と剣を抜く処理）も描けることを確認済み。
##
##   godot --headless --script res://tools/rasterize_svg.gd -- <in.svg> <out.png> [倍率]
##
## パスは OS の絶対パスでもリポジトリ相対でもよい。倍率の既定は 1.0
## （＝SVG の width/height をそのまま px として使う）。


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: --script res://tools/rasterize_svg.gd -- <in.svg> <out.png> [scale]")
		quit(1)
		return
	var src: String = args[0]
	var dst: String = args[1]
	var scale: float = float(args[2]) if args.size() > 2 else 1.0

	var f := FileAccess.open(src, FileAccess.READ)
	if f == null:
		printerr("読めない: %s (err %d)" % [src, FileAccess.get_open_error()])
		quit(1)
		return
	var svg := f.get_as_text()
	f.close()

	var img := Image.new()
	var err := img.load_svg_from_string(svg, scale)
	if err != OK:
		printerr("SVG を読めない: %s (err %d)" % [src, err])
		quit(1)
		return
	err = img.save_png(dst)
	if err != OK:
		printerr("PNG を書けない: %s (err %d)" % [dst, err])
		quit(1)
		return
	print("wrote %s (%d x %d)" % [dst, img.get_width(), img.get_height()])
	quit(0)
