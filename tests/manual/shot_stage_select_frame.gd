extends SceneTree
## 使い捨て：ステージセレクトの扉絵に彫り枠（signboard_frame）を足した見た目を撮る。
## 全景と、絵の左上の角の拡大（枠と絵の角丸が合っているか）。
## 実行: godot --path . -s res://tests/manual/shot_stage_select_frame.gd -- <出力ディレクトリの絶対パス> <接尾辞>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const CAMPAIGN := "tutorial1-goblin-raid"  # 扉絵（cover）がある冒険譚

var _select: StageSelect
var _dir := ""
var _tag := "after"
var _frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	if args.size() > 1:
		_tag = String(args[1])
	root.size = Vector2i(1280, 720)
	root.add_child(TavernTheme.wall_background())  # 酒場の木の壁（SelectScreen と同じ背景）
	_select = StageSelect.new()
	_select.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_select)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_select.setup(CampaignProgress.new(CampaignCatalog.load_all(), ProgressStore.new()))
		_select.show_campaign(CAMPAIGN, 0)  # 0＝先頭の絵に固定（撮り比べで絵が変わらないように）
	if _frames == 20:  # レイアウトが確定してから撮る
		_save()
		return true
	return false

func _save() -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/stage_select_frame_%s.png" % [_dir, _tag])
	var crop := img.get_region(Rect2i(Vector2i(16, 60), Vector2i(160, 160)))
	crop.resize(480, 480, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/stage_select_frame_%s_zoom.png" % [_dir, _tag])
	print("saved: %s/stage_select_frame_%s.png" % [_dir, _tag])
