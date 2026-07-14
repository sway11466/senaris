extends SceneTree
## 【使い捨て】戦闘演出シーンを合成 detail で直接再生し、runtime エラーが出ないか確認する。
## 実行: godot --headless --path . -s res://tests/manual/repro_combat_scene.gd

var _cs: CombatScene
var _frames := 0

func _initialize() -> void:
	_cs = CombatScene.new()
	_cs.bind(SkinCatalog.load_standard())
	root.add_child(_cs)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var detail := {
			"attacker": { "type_id": "fighter", "skin_id": "fighter", "team": 0, "level": 1,
				"troops_before": 6, "troops_after": 5, "max": 8, "terrain": "plain" },
			"defender": { "type_id": "goblin", "skin_id": "goblin", "team": 1, "level": 1,
				"troops_before": 5, "troops_after": 2, "max": 8, "terrain": "forest" },
			"to_defender": {}, "to_attacker": {},
		}
		print("repro: play() with counter")
		_cs.play(detail)
	if _frames == 12:
		var d2 := {
			"attacker": { "type_id": "archer", "skin_id": "archer", "team": 0, "level": 1,
				"troops_before": 4, "troops_after": 4, "max": 8, "terrain": "plain" },
			"defender": { "type_id": "goblin", "skin_id": "goblin", "team": 1, "level": 1,
				"troops_before": 3, "troops_after": 1, "max": 8, "terrain": "mountain" },
			"to_defender": {}, "to_attacker": null,
		}
		print("repro: play() indirect (no counter)")
		_cs.play(d2)
	if _frames == 24:
		print("repro: done without crash")
		return true
	return false
