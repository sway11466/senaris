extends SceneTree
## 使い捨て：新しい攻撃エフェクト（火球・魔法の粉）が飛んでいるところを撮る。
## 実行: godot --path . -s res://tests/manual/shot_effect_fire_ball.gd -- <出力ディレクトリの絶対パス>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const SHOTS := [
	{
		"name": "fire_ball",
		"hit": "L",  # 被弾側＝撃たれるほう
		"L": { "team": 0, "type_id": "fighter", "skin_id": "fighter", "terrain": "plain", "troops_before": 8 },
		"R": { "team": 1, "type_id": "mage", "skin_id": "orc_mage", "terrain": "plain", "troops_before": 8 },
	},
	{
		"name": "magic_dust",
		"hit": "R",
		"L": { "team": 0, "type_id": "pixie", "skin_id": "pixie", "terrain": "plain", "troops_before": 8 },
		"R": { "team": 1, "type_id": "fighter", "skin_id": "orc", "terrain": "plain", "troops_before": 8 },
	},
]

var _stage: CombatScene
var _dir := ""
var _frames := 0
var _shot := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	_stage = CombatScene.new()
	root.add_child(_stage)

func _process(_delta: float) -> bool:
	_frames += 1
	var t := _frames - _shot * 50
	if t == 2:
		if _shot == 0:
			_stage.bind(SkinCatalog.load_standard())
		_open(SHOTS[_shot])
	if t == 10:
		_strike(SHOTS[_shot])
	if t == 23:
		_save("%s_fly" % String(SHOTS[_shot]["name"]))  # 飛翔中
	if t == 34:
		_save("%s_hit" % String(SHOTS[_shot]["name"]))  # 着弾ぎわ
		_shot += 1
		if _shot >= SHOTS.size():
			return true
	return false

func _open(shot: Dictionary) -> void:
	var L: Dictionary = shot["L"]
	var R: Dictionary = shot["R"]
	_stage._open(L, "L")
	_stage._render_side("L", L, 8)
	_stage._render_side("R", R, 8)

func _strike(shot: Dictionary) -> void:
	var side := String(shot["hit"])
	var comb: Dictionary = shot[side]
	var by: Dictionary = shot["R" if side == "L" else "L"]
	_stage._strike_side(side, 3, 5, comb, by, _stage._gen)

func _save(name: String) -> void:
	var out := "%s/%s.png" % [_dir, name]
	root.get_texture().get_image().save_png(out)
	print("saved: ", out)
