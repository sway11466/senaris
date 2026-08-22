extends SceneTree
## 使い捨て：玉座 (plain_cave1_fence_throne1) の戦闘中の見え方を撮る。
## 奥絵（_combat_back）は守り手側の半面の外端に出る。右陣営（ゴブリンロードが守る）と
## 左陣営（反転の確認）の2通り。
## 実行: godot --path . -s res://tests/manual/shot_throne_combat.gd -- <出力ディレクトリの絶対パス>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const THRONE := Vector2i(6, 3)  # 玉座のマス
const FIELD := Vector2i(5, 3)   # 反対側のマス（洞窟の床）

const THRONE_R := { "team": 1, "type_id": "paladin", "skin_id": "goblin_lord", "terrain": "fence", "pos": THRONE, "troops_before": 8 }
const THRONE_L := { "team": 0, "type_id": "fighter", "skin_id": "fighter", "terrain": "fence", "pos": THRONE, "troops_before": 8 }
const FIELD_L := { "team": 0, "type_id": "fighter", "skin_id": "fighter", "terrain": "plain", "pos": FIELD, "troops_before": 8 }
const FIELD_R := { "team": 1, "type_id": "paladin", "skin_id": "goblin_lord", "terrain": "plain", "pos": FIELD, "troops_before": 8 }

var _stage: CombatScene
var _dir := ""
var _frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	_stage = CombatScene.new()
	root.add_child(_stage)
	var state := BattleState.new()
	_stage.bind(SkinCatalog.load_standard())
	_stage.bind_terrain_skins({ THRONE: "plain_cave1_fence_throne1", FIELD: "plain_cave1" })
	_stage.bind_state(state)
	_stage.bind_backdrop("cave_wall")
	_stage.bind_haze(0.30)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_open(THRONE_R, "R", FIELD_L)
	if _frames == 40:  # 幕開けのワイプが開ききってから撮る
		_save("lord_right")
		_open(THRONE_L, "L", FIELD_R)
	if _frames == 80:
		_save("fighter_left")
		return true
	return false

func _open(ground: Dictionary, side: String, other: Dictionary) -> void:
	_stage._open(ground, side, other)
	if side == "R":
		_stage._render_side("L", other, 8)
		_stage._render_side("R", ground, 8)
	else:
		_stage._render_side("L", ground, 8)
		_stage._render_side("R", other, 8)

func _save(what: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/throne_combat_%s.png" % [_dir, what]
	img.save_png(path)
	print("saved: ", path)
