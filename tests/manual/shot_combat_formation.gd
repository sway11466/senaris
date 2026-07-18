extends SceneTree
## 【使い捨て】戦闘演出の隊列レイアウトを実機描画し、スクショ保存して目視確認する。
## 実行: godot --path . -s res://tests/manual/shot_combat_formation.gd
## （headless 不可＝ viewport 描画が要る）

const OUT_DIR := "user://shot_combat/"
var _cs: CombatScene
var _frames := 0
var _shots := [8, 4, 2]  # 各兵数でスクショ（両サイド同数）
var _idx := 0

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_cs = CombatScene.new()
	_cs.bind(SkinCatalog.load_standard())
	root.add_child(_cs)

func _process(_delta: float) -> bool:
	_frames += 1
	# 各ショットを 20 フレーム間隔で：play→数フレーム待って撮る。
	var phase := _frames % 20
	if phase == 2:
		if _idx >= _shots.size():
			print("shot: done")
			return true
		var n: int = _shots[_idx]
		var detail := {
			"attacker": { "type_id": "fighter", "skin_id": "fighter", "team": 0, "level": 1,
				"troops_before": n, "troops_after": n, "max": 8, "terrain": "plain" },
			"defender": { "type_id": "goblin", "skin_id": "goblin", "team": 1, "level": 1,
				"troops_before": n, "troops_after": n, "max": 8, "terrain": "plain" },
			"to_defender": {}, "to_attacker": null,
		}
		_cs.play(detail)
	if phase == 10 and _idx < _shots.size():
		var n: int = _shots[_idx]
		var img := root.get_texture().get_image()
		var path := OUT_DIR + "formation_%d.png" % n
		img.save_png(path)
		print("shot: saved %s (%s)" % [ProjectSettings.globalize_path(path), img.get_size()])
		_idx += 1
	return false
