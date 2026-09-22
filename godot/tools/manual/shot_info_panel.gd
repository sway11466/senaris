extends Node
## マニュアル用スクリーンショット：ユニット情報パネル（情報板）だけを撮って PNG に保存する。
## 盤も HUD も出さず、板を実機と同じ幅（UiLayout.RIGHT_BOX）で描く。マニュアルの本文に貼る
## 静的画像の出どころ（doc/gdd/manual.md）。板の見た目を変えたら同じコマンドで撮り直す。
##
## 板に出せるものは3つあり、引数で選ぶ:
##   駒の情報   … --select <col,row> と --tab <ability|status|terrain>
##   空きマスの地形 … --hex <col,row>（タブは無い。駒の居ないマスだけ）
##   戦闘レポート … --attacker <col,row> --target <col,row> と --tab <summary|attack|counter>
## 戦闘レポートは実機と同じ経路で1回戦わせ、その結果を板に出したところを撮る。
##
## 板の文字は翻訳される＝貼る言語のぶんだけ撮る。どのタブを撮るかと合わせて引数で必ず渡す
## （撮り漏らしを既定値で隠さない）。
##
## 実行（リポジトリ直下）:
##   godot --path godot res://tools/manual/shot_info_panel.tscn -- <出力PNG> <ステージjsonのres://パス> --select <col,row> --tab <タブ> --locale <ja|en>
##   godot --path godot res://tools/manual/shot_info_panel.tscn -- <出力PNG> <ステージjsonのres://パス> --hex <col,row> --locale <ja|en>
##   godot --path godot res://tools/manual/shot_info_panel.tscn -- <出力PNG> <ステージjsonのres://パス> --attacker <col,row> --target <col,row> --tab <タブ> --locale <ja|en>
##
## 板は SubViewport に入れて撮る＝ウィンドウのストレッチ（canvas_items）に縮尺を触らせない。
## 板の外は透明のまま残る（貼る先の地の色を選べる）。
##
## 横は実機の板と同じ幅、縦は中身の下で切る（実機は板の丈が固定で下が空く。読み物に貼る絵で
## 木目だけの余白を持たせない）。駒の情報ではページ送りの行も一緒に落ちる。

const UNIT_TABS := ["ability", "status", "terrain"]
const REPORT_TABS := ["summary", "attack", "counter"]

func _ready() -> void:
	var uargs := OS.get_cmdline_user_args()
	var plain: Array[String] = []
	var cells := {}  # "--select"/"--hex"/"--attacker"/"--target" -> Vector2i
	var tab := ""
	var locale := ""
	var i := 0
	while i < uargs.size():
		var a := uargs[i]
		if a in ["--select", "--hex", "--attacker", "--target"] and i + 1 < uargs.size():
			var parts := uargs[i + 1].split(",")
			if parts.size() != 2:
				_die("%s は col,row 形式: %s" % [a, uargs[i + 1]])
				return
			cells[a] = Vector2i(int(parts[0]), int(parts[1]))
			i += 2
		elif a == "--tab" and i + 1 < uargs.size():
			tab = uargs[i + 1]
			i += 2
		elif a == "--locale" and i + 1 < uargs.size():
			locale = uargs[i + 1]
			i += 2
		else:
			plain.append(a)
			i += 1
	if plain.size() < 2:
		_die("引数が足りない。<出力PNG> <ステージjsonのres://パス> が要る")
		return
	var report := cells.has("--attacker") or cells.has("--target")
	var empty_hex := cells.has("--hex")
	if int(cells.has("--select")) + int(empty_hex) + int(report) != 1:
		_die("--select か --hex か、--attacker と --target の組か、どれか一つを渡す")
		return
	if report and not (cells.has("--attacker") and cells.has("--target")):
		_die("戦闘レポートには --attacker と --target の両方が要る")
		return
	# 空きマスの地形にタブは無い（板は見出しもタブも引っ込めて中身だけを出す）。
	if empty_hex:
		if not tab.is_empty():
			_die("--hex にタブは無い: %s" % tab)
			return
	else:
		var tabs: Array = REPORT_TABS if report else UNIT_TABS
		if not tabs.has(tab):
			_die("--tab は %s のどれか: %s" % [", ".join(tabs), tab])
			return
	if locale.is_empty():
		_die("--locale <ja|en> が要る")
		return
	var out := plain[0]
	var stage_path := plain[1]

	TranslationServer.set_locale(locale)

	var state := StageLoader.load_file(stage_path)
	if state == null:
		_die("ステージを読めない: %s" % stage_path)
		return

	# 板だけを入れる面。幅は実機の右の箱と同じ＝行の折り返しもページ割りも実機と同じ結果になる。
	var sub := SubViewport.new()
	sub.size = Vector2i(UiLayout.RIGHT_BOX.size)
	sub.transparent_bg = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)

	var panel := UnitInfoPanel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.add_child(panel)
	panel.bind(state, SkinCatalog.load_standard())
	panel.bind_terrain_skins(StageLoader.load_terrain_skins(stage_path))
	panel.bind_ai_presets(AiCatalog.load_default())  # 敵の見出しに出す特性名の引き先

	if report:
		if not await _play_attack(state, panel, cells["--attacker"], cells["--target"]):
			return
		panel._report._show_tab(tab)  # レポートはタブを押して切り替える作り
	elif empty_hex:
		var hex := Hex.offset_to_axial(cells["--hex"].x, cells["--hex"].y)
		if state.unit_at(hex) != null:
			_die("(%d,%d) に駒が居る＝空きマスの表示にならない" % [cells["--hex"].x, cells["--hex"].y])
			return
		panel.show_terrain(hex)
	else:
		var unit := state.unit_at(Hex.offset_to_axial(cells["--select"].x, cells["--select"].y))
		if unit == null:
			_die("(%d,%d) に駒が居ない" % [cells["--select"].x, cells["--select"].y])
			return
		panel._on_tab_pressed(tab)  # 板はタブを押して切り替える作り＝駒を出す前に選んでおく
		panel.show_unit(unit.handle)

	for f in 6:
		await get_tree().process_frame

	# 中身の下に残る空きを詰める＝板を中身の高さまで縮める。詰め幅は板から実測する＝板の余白や
	# 行間の数値をこちらで持たない（持つと板を直したときに二重管理になる）。
	var pages := panel._pages.size()
	var bottom_margin := panel.size.y - (panel._box.position.y + panel._box.size.y)
	var h := 0.0
	if report:
		# レポートは板の全面に広がる器＝中身（縦積み）の要る高さと、その上下の余白で決まる。
		var inner := panel._report.get_child(0) as Control
		h = inner.get_combined_minimum_size().y + inner.position.y * 2.0
	else:
		# 駒の情報はページ送りの行ごと落とす（貼るのは1ページに収まる形だけ）。
		var sep := float(panel._box.get_theme_constant("separation"))
		var slack := panel._content.size.y - panel._rows.get_combined_minimum_size().y
		h = panel.size.y - slack - (panel._pager.size.y + sep)
		panel._pager.hide()
	# 絵の面（駒・地形の見本）は行より背が高いことがある。絵の下端より上で切ると足元が消えるので、
	# そこまでは板を残す。
	for face: Control in [panel._unit_face, panel._terrain_face]:
		if face.visible:
			h = maxf(h, face.position.y + face.size.y + bottom_margin)
	sub.size = Vector2i(sub.size.x, int(ceil(h)))

	for f in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := sub.get_texture().get_image()
	var err := img.save_png(out)
	# ページ数も出す＝板に収まりきらず2ページ目へ送られた行があれば、撮った1枚に欠けがある。
	print("SHOT_SAVED err=", err, " path=", out, " size=", img.get_size(), " pages=", pages)
	get_tree().quit(0 if err == OK else 1)

## 実機と同じ経路で1回攻撃を通し、その戦闘レポートを板に出す。通らなければ false。
func _play_attack(state: BattleState, panel: UnitInfoPanel, atk_cell: Vector2i, tgt_cell: Vector2i) -> bool:
	var atk := state.unit_at(Hex.offset_to_axial(atk_cell.x, atk_cell.y))
	var tgt := state.unit_at(Hex.offset_to_axial(tgt_cell.x, tgt_cell.y))
	if atk == null or tgt == null:
		_die("指定マスに駒が居ない")
		return false
	var controller := MatchController.new()
	controller.name = "MatchController"
	controller.setup(state)
	controller.ai_team = 1
	add_child(controller)
	controller.combat_resolved.connect(panel.show_combat)
	for f in 6:  # 板の中身が組まれるのを待ってから戦わせる
		await get_tree().process_frame
	if not controller.execute_attack(AttackCommand.new(atk.handle, tgt.handle)):
		_die("攻撃が通らない（隣接/射程/行動済みを確認）")
		return false
	return true

func _die(msg: String) -> void:
	push_error("shot_info_panel: " + msg)
	get_tree().quit(1)
