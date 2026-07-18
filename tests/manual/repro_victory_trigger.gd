extends SceneTree
## 【使い捨て】勝利イラストのトリガ材料を検証：victory_paths 解決と最終ステージ判定。
## 実行: godot --headless --path . -s res://tests/manual/repro_victory_trigger.gd

func _initialize() -> void:
	var cid := "tutorial1-goblin-raid"
	var progress := CampaignProgress.new(CampaignCatalog.load_all(), ProgressStore.new())
	var c := progress.campaign(cid)
	print("victory_paths = ", c.get("victory_paths", []))
	print("next_stage(st6) empty? ", progress.next_stage(cid, "st6").is_empty(), " (期待 false)")
	print("next_stage(st7) empty? ", progress.next_stage(cid, "st7").is_empty(), " (期待 true=最終)")
	# デバッグ冒険譚は勝利イラスト対象外（debug フラグ）
	var dbg := progress.campaign("debug-victory")
	print("debug campaign debug? ", dbg.get("debug", null), " victory_paths=", dbg.get("victory_paths", []))
	quit()
