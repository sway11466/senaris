extends SceneTree
## 使い捨て：盤高無視スキン（水面）・負の elevation・floor・マスごとの高さ上書きの見え方を撮る。
## ステージJSONもCSVも触らず、実行時に注入する（river スキンをその場で水面設定に書き換える）。
## 実行: godot --path . -s res://tests/manual/shot_height_override.gd -- <出力ディレクトリの絶対パス>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const STAGE := "res://data/stages/debug-skins/terrain.json"
const STEP := 0.30   # 1行あたりの上がり幅（ワールド・TILE=1）

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
		_apply()
	if _frames == 60:
		_report()
		_save("height_override")
		return true
	return false

## river スキンを水面設定（盤高無視・沈む上面・足元は水面の上）に書き換え、
## 行の基準高さと水域2つ（既定レベル＋上書きレベル）と、駒の乗る水マスを注入する。
func _apply() -> void:
	var board: Node = _main.get_node("HexBoard")
	var tr: BoardTerrainRenderer = board._terrain_renderer
	var state = board.state
	var s := TerrainSkinCatalog.skin_by_id("river")
	s.elevation = -0.18
	s.floor = 0.0
	s.ignore_board_height = true
	# 奥（row0）ほど高い盤。
	var rows: Array = []
	for r in state.rows:
		rows.append(float(state.rows - 1 - r) * STEP)
	tr._board_height = { "row": rows, "col": [] }
	# 水域A（既定レベル）: 左手前の 3x2。
	for col in range(1, 4):
		for row in range(state.rows - 3, state.rows - 1):
			tr._terrain_skins[Hex.offset_to_axial(col, row)] = "river"
	# 水域B（上書きで1段深いレベル）: 右手前の 3x2。
	for col in range(6, 9):
		for row in range(state.rows - 3, state.rows - 1):
			var hex := Hex.offset_to_axial(col, row)
			tr._terrain_skins[hex] = "river"
			tr._height_overrides[hex] = { "elevation": -0.54, "floor": -0.36 }
	# 駒を水域へ動かす＝floor（絶対高さ）に浮き、影は水面に落ちるのを見る。
	var units: Array = state.units()
	if units.size() >= 2:
		units[0].pos = Hex.offset_to_axial(2, state.rows - 2)  # 水域A（floor 0）
		units[1].pos = Hex.offset_to_axial(7, state.rows - 2)  # 水域B（floor -0.36）
	tr.build_tiles()
	board._sync()
	board.fit_to_view()

## 代表マスの高さの実測（期待値と突き合わせる）。
func _report() -> void:
	var board: Node = _main.get_node("HexBoard")
	var tr: BoardTerrainRenderer = board._terrain_renderer
	var state = board.state
	var a := Hex.offset_to_axial(1, state.rows - 2)
	var b := Hex.offset_to_axial(6, state.rows - 2)
	var land := Hex.offset_to_axial(0, state.rows - 2)
	print("水域A: elev=%.2f (期待 -0.18) floor=%.2f (期待 0.00)" % [tr.elev(a), tr.unit_floor(a)])
	print("水域B: elev=%.2f (期待 -0.54) floor=%.2f (期待 -0.36)" % [tr.elev(b), tr.unit_floor(b)])
	print("隣の地面: elev=%.2f (基準高さが乗る)" % tr.elev(land))
	var units: Array = state.units()
	if not units.is_empty():
		var u = units[0]
		print("駒のマス: elev=%.2f floor=%.2f（駒は floor に立つ）" % [tr.elev(u.pos), tr.unit_floor(u.pos)])

func _save(name: String) -> void:
	var out := "%s/%s.png" % [_dir, name]
	root.get_texture().get_image().save_png(out)
	print("saved: ", out)
