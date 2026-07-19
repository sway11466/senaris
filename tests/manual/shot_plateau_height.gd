extends SceneTree
## 【使い捨て】台地パッチのある盤を実描画し、せり上がり＋崖スカートを確認。
## あわせてピッキング往復チェック（新=標高対応／旧=y=0）を数値で対比。
## 実行: godot --path . -s res://tests/manual/shot_plateau_height.gd （headless 不可）

const OUT := "user://shot_plateau/board.png"
var _board
var _frames := 0

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://shot_plateau/"))

## tree 稼働後（_ready 実行済み）に盤を組む＝bind でノード未生成にならない。
func _setup() -> void:
	var state := BattleState.new(9, 7)
	for col in 9:
		for row in 7:
			var hex := Hex.offset_to_axial(col, row)
			var is_plat := col >= 3 and col <= 5 and row >= 2 and row <= 4
			state.set_terrain(hex, "plateau" if is_plat else "plain")
	var ctrl := MatchController.new()
	ctrl.name = "MC"
	ctrl.setup(state)
	ctrl.ai_team = 1
	root.add_child(ctrl)
	_board = preload("res://presentation/board/hex_board_3d.gd").new()
	root.add_child(_board)
	_board.bind(state, ctrl, {}, {})

func _pick_new(screen: Vector2) -> Vector2i:
	for e in _board._elev_levels():
		var p: Vector3 = _board._plane_point_at_y(screen, e)
		if not p.is_finite():
			continue
		var hex := Hex.from_pixel(Vector2(p.x, p.z), HexBoard3D.TILE)
		if _board._on_board(hex) and is_equal_approx(_board._elev(hex), e):
			return hex
	return Vector2i(-999, -999)

func _pick_old(screen: Vector2) -> Vector2i:
	var p: Vector3 = _board._plane_point_at_y(screen, 0.0)
	if not p.is_finite():
		return Vector2i(-999, -999)
	return Hex.from_pixel(Vector2(p.x, p.z), HexBoard3D.TILE)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_setup()
	if _frames == 20:
		var bad_new := 0
		var bad_old := 0
		var plat_old_bad := 0
		var total := 0
		for col in 9:
			for row in 7:
				var hex := Hex.offset_to_axial(col, row)
				var e: float = _board._elev(hex)
				var pp := Hex.to_pixel(hex, HexBoard3D.TILE)
				var screen: Vector2 = _board._cam.unproject_position(Vector3(pp.x, e, pp.y))
				total += 1
				if _pick_new(screen) != hex:
					bad_new += 1
				if _pick_old(screen) != hex:
					bad_old += 1
					if e > 0.0:
						plat_old_bad += 1
		print("PICK total=%d  new_bad=%d  old_bad=%d (plateauの旧ミス=%d)" % [total, bad_new, bad_old, plat_old_bad])
		var img := root.get_texture().get_image()
		img.save_png(OUT)
		print("shot: saved ", ProjectSettings.globalize_path(OUT))
		return true
	return false
