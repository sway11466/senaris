extends SceneTree
## 使い捨て：拠点マス（fortオブジェクト）の平面タイルと立ち絵が、bind直後と占領後に
## どう描かれるかを検証する。refresh_base_tiles が旧システム（拠点＝平らなタイル）前提の
## ままかどうかの実測。
## 実行: godot --path . -s res://tests/manual/shot_base_refresh.gd -- <出力ディレクトリの絶対パス>

const STAGE := "res://data/stages/debug-mapops/base.json"

var _main: Node
var _dir := ""
var _frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		_main._title.close()
		_main._select.close()
		_main.load_stage(STAGE)
	if _frames == 40:
		_inspect("bind直後")
		_save("base_bind")
	if _frames == 45:
		_capture_neutral()
	if _frames == 65:
		_inspect("中立拠点をplayerが占領後")
		_save("base_captured")
		return true
	return false

## 中立拠点（col4,row5）を player 所有にして盤を同期（占領の見た目だけを再現）。
func _capture_neutral() -> void:
	var board: Node = _main.get_node("HexBoard")
	var hex := Hex.offset_to_axial(4, 5)
	for b in board.state.bases():
		if b.hex == hex:
			b.team = 0
	board._sync()

## 各拠点マスについて、平面タイルの実テクスチャと「足場だけ」のテクスチャを比較し、
## 立ち絵（Sprite3D）の絵のパスを出す。
func _inspect(label: String) -> void:
	print("=== ", label, " ===")
	var board: Node = _main.get_node("HexBoard")
	var tr: BoardTerrainRenderer = board._terrain_renderer
	for b in board.state.bases():
		var skin: TerrainSkin = tr._skin_at(b.hex)
		var ground := tr._ground_texture(b.hex, skin)
		var mi: MeshInstance3D = tr._tile_nodes.get(b.hex)
		var actual: Texture2D = null
		if mi != null and mi.material_override is StandardMaterial3D:
			actual = (mi.material_override as StandardMaterial3D).albedo_texture
		var same := actual == ground
		var actual_path := actual.resource_path if actual != null else "(null)"
		print("拠点 %s team=%d skin=%s" % [str(b.hex), b.team, skin.skin_id if skin != null else "?"])
		print("  平面タイル: %s / 足場と同一=%s" % ["合成(パス無し)" if actual_path == "" else actual_path, str(same)])
		var standee := _standee_near(tr, b.hex)
		if standee != null:
			print("  立ち絵: %s" % standee.texture.resource_path)
		else:
			print("  立ち絵: 見つからない")

## そのヘックスの位置に立っている Sprite3D（オブジェクトの立ち絵）を探す。
func _standee_near(tr: Node, hex: Vector2i) -> Sprite3D:
	var p := Hex.to_pixel(hex, 1.0)
	for c in tr.get_children():
		if c is Sprite3D and Vector2(c.position.x, c.position.z).distance_to(p) < 0.6:
			return c
	return null

func _save(name: String) -> void:
	var out := "%s/%s.png" % [_dir, name]
	root.get_texture().get_image().save_png(out)
	print("saved: ", out)
