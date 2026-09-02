extends SceneTree
## 使い捨て: 能力タブのページ割りを実測する（ユニットスキルの節が1ページ目に入るか）。
## 実行: godot --headless --path . -s res://tests/manual/measure_info_ability_pages.gd
## 結果: res://tests/manual/out/info_ability_pages.txt
func _initialize() -> void:
	_run()

func _run() -> void:
	var f := FileAccess.open("res://tests/manual/out/info_ability_pages.txt", FileAccess.WRITE)
	for loc in ["ja", "en"]:
		TranslationServer.set_locale(loc)
		var p := UnitInfoPanel.new()
		p.position = UiLayout.RIGHT_BOX.position
		p.size = UiLayout.RIGHT_BOX.size
		root.add_child(p)
		await process_frame
		await process_frame
		var s := BattleState.new(10, 8)
		var priest := Unit.new(1, 0, Hex.offset_to_axial(3, 3), 2, 8, 40, 20, 1, "priest")
		priest.can_capture = true  # 実際のプリーストは「特性 占領」の行が付く
		s.add_unit(priest)
		s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(5, 3), 8, 8, 10, 10, 5, "ghost"))
		p.bind(s, {})
		for uid in [1, 2]:
			p.show_unit(uid)
			await process_frame
			f.store_line("[%s] unit=%d content_h=%.1f rows_w=%.1f pages=%d" % [loc, uid, p._content.size.y, p._rows.size.x, p._pages.size()])
			for i in p._pages.size():
				f.store_line(" page %d (h=%.1f):" % [i + 1, p._stack_height(p._pages[i])])
				for it in p._pages[i]:
					var d: Dictionary = it
					var txt: String = (String(d.get("label", "")) + " | " + String(d.get("value", ""))) if String(d.get("t", "full")) == "row" else String(d.get("text", ""))
					f.store_line("   %5.1f  %s%s" % [p._item_height(d), "    " if float(d.get("indent", 0.0)) > 0.0 else "", txt])
		p.queue_free()
	f.close()
	quit()
