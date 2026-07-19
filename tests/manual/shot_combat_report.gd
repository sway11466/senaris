extends SceneTree
## 【使い捨て】戦闘レポート（右パネル）のサマリー/詳細タブを実機描画し、スクショ保存して目視確認する。
## 実行: godot --path . -s res://tests/manual/shot_combat_report.gd
## （headless 不可＝ viewport 描画が要る）
## パターン: 近接（バフ・支援・包囲あり）のサマリー/攻撃側/守備側 ＋ 間接（反撃なし）のサマリー。

const OUT_DIR := "user://shot_combat_report/"
var _view: CombatReportView
var _shots: Array = []  # [ファイル名, detail, タブid]
var _frames := 0
var _idx := 0

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# 右ボックスと同寸の看板パネルに載せる（実機の InfoPanel と同じ見た目にする）
	var panel := Panel.new()
	panel.position = Vector2(344, 58)  # 撮影用に画面中央へ（実機では UiLayout.RIGHT_BOX の位置）
	panel.size = UiLayout.RIGHT_BOX.size
	panel.add_theme_stylebox_override("panel", TavernTheme.signboard_stylebox())
	panel.add_child(TavernTheme.signboard_frame())
	root.add_child(panel)
	_view = CombatReportView.new()
	_view.bind(SkinCatalog.load_standard())
	panel.add_child(_view)
	var melee := _melee_detail()
	var ranged := _ranged_detail()
	_shots = [
		["summary_melee", melee, "summary"],
		["attacker_melee", melee, "attacker"],
		["defender_melee", melee, "defender"],
		["summary_ranged", ranged, "summary"],
	]

## 近接戦: 攻撃側にバフ（ホーリーアリア）＋支援、守備側は森＋包囲。全行が埋まるパターン。
func _melee_detail() -> Dictionary:
	var s := BattleState.new(10, 8)
	var ap := Hex.offset_to_axial(3, 3)
	var a := Unit.new(1, 0, ap, 3, 6, 50, 40, 3, "fighter")
	var t := Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 30, 30, 1, "goblin")
	s.add_unit(a)
	s.add_unit(t)
	s.add_unit(Unit.new(3, 0, Hex.neighbor(t.pos, 2), 3, 8, 50, 40, 1, "fighter"))  # 支援＋包囲要員
	s.set_terrain(t.pos, "forest")
	s.add_status_mod({"scope": "team", "team": 0, "owner_team": 0, "op": "mul", "target": "both", "value": 1.3, "remaining": 2, "name": "ホーリーアリア"})
	return s.attack(1, 2)["detail"]

## 間接戦（距離2・反撃なし）: 「反撃なし」「—」の描き分け確認用。
func _ranged_detail() -> Dictionary:
	var s := BattleState.new(10, 8)
	var a := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3, 8, 30, 10, 1, "archer")
	a.attack_range = 2
	var t := Unit.new(2, 1, Hex.offset_to_axial(4, 2), 3, 8, 10, 10, 1, "goblin")
	s.add_unit(a)
	s.add_unit(t)
	return s.attack(1, 2)["detail"]

func _process(_delta: float) -> bool:
	_frames += 1
	var phase := _frames % 20
	if phase == 2:
		if _idx >= _shots.size():
			print("shot: done")
			return true
		var shot: Array = _shots[_idx]
		_view.show_report(shot[1])
		var tab: Button = _view._tabs[shot[2]]
		tab.button_pressed = true
		_view._show_tab(shot[2])
	if phase == 10 and _idx < _shots.size():
		var shot: Array = _shots[_idx]
		var img := root.get_texture().get_image()
		var path := OUT_DIR + "%s.png" % shot[0]
		img.save_png(path)
		print("shot: saved %s (%s)" % [ProjectSettings.globalize_path(path), img.get_size()])
		_idx += 1
	return false
