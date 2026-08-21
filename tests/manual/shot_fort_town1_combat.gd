extends SceneTree
## 使い捨て：拠点「町」(road_fort_town1) の戦闘中の見え方を撮る。
## 中立／味方が持つ／敵が持つ の3通り。拠点の持ち主は盤の状態から引くので、
## 町のマスに拠点を1つ置いた BattleState を作って結線する。
## 実行: godot --path . -s res://tests/manual/shot_fort_town1_combat.gd -- <出力ディレクトリの絶対パス>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const TOWN := Vector2i(0, 0)   # 町のマス
const FIELD := Vector2i(1, 0)  # 反対側のマス（平地）

const TOWN_R := { "team": 1, "type_id": "fighter", "skin_id": "orc", "terrain": "fort", "pos": TOWN, "troops_before": 8 }
const TOWN_L := { "team": 0, "type_id": "fighter", "skin_id": "fighter", "terrain": "fort", "pos": TOWN, "troops_before": 8 }
const FIELD_L := { "team": 0, "type_id": "fighter", "skin_id": "fighter", "terrain": "plain", "pos": FIELD, "troops_before": 8 }
const FIELD_R := { "team": 1, "type_id": "fighter", "skin_id": "orc", "terrain": "plain", "pos": FIELD, "troops_before": 8 }

var _stage: CombatScene
var _town: Base
var _dir := ""
var _frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	_stage = CombatScene.new()
	root.add_child(_stage)
	var state := BattleState.new()
	_town = Base.new(TOWN, Base.NEUTRAL)
	state.add_base(_town)
	_stage.bind(SkinCatalog.load_standard())
	_stage.bind_terrain_skins({ TOWN: "road_fort_town1" })
	_stage.bind_state(state)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_open(TOWN_R, "R", FIELD_L, Base.NEUTRAL)
	if _frames == 40:  # 幕開けのワイプが開ききってから撮る
		_save("neutral_right")
		_open(TOWN_L, "L", FIELD_R, 0)
	if _frames == 80:
		_save("team0_left")
		_open(TOWN_R, "R", FIELD_L, 1)
	if _frames == 120:
		_save("team1_right")
		_open(TOWN_L, "L", FIELD_R, Base.NEUTRAL)
	if _frames == 160:
		_save("neutral_left")
		return true
	return false

## 町の持ち主を team にしてから舞台を開く（占領で絵が変わるところを撮る）。
func _open(ground: Dictionary, side: String, other: Dictionary, team: int) -> void:
	_town.team = team
	_stage._open(ground, side, other)
	if side == "R":
		_stage._render_side("L", other, 8)
		_stage._render_side("R", ground, 8)
	else:
		_stage._render_side("L", ground, 8)
		_stage._render_side("R", other, 8)

func _save(what: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/fort_town1_combat_%s.png" % [_dir, what]
	img.save_png(path)
	print("saved: ", path)
