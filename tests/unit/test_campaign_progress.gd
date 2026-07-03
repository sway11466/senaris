extends GutTest
## CampaignProgress（解放判定＝locked/unlocked/cleared の導出）のテスト。仕様 → doc/gdd/stage_select.md

const PATH := "user://test_progress.json"

func before_each() -> void:
	_remove()

func after_all() -> void:
	_remove()

func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

## テスト用の冒険譚: st1(無条件) → st2(st1クリア) → st3(st2クリア＋entitlement)、＋デバッグ冒険譚。
func _progress() -> CampaignProgress:
	var campaigns: Array = [
		CampaignCatalog.build({
			"id": "camp",
			"title": "テスト冒険譚",
			"stages": [
				{ "id": "st1", "file": "st1.json", "title": "一" },
				{ "id": "st2", "file": "st2.json", "title": "二",
					"unlock": [ { "type": "cleared", "stage": "st1" } ] },
				{ "id": "st3", "file": "st3.json", "title": "三",
					"unlock": [
						{ "type": "cleared", "stage": "st2" },
						{ "type": "entitlement", "id": "dlc1" },
					] },
			],
		}, "res://x"),
		CampaignCatalog.build({
			"id": "dbg", "title": "デバッグ", "debug": true,
			"stages": [ { "id": "d1", "file": "d1.json" } ],
		}, "res://y"),
	]
	return CampaignProgress.new(campaigns, ProgressStore.new(PATH))

func test_initial_states() -> void:
	var p := _progress()
	assert_eq(p.stage_state("camp", "st1"), CampaignProgress.UNLOCKED, "無条件は解放")
	assert_eq(p.stage_state("camp", "st2"), CampaignProgress.LOCKED, "前提未クリアはロック")
	assert_eq(p.cleared_count("camp"), 0)

func test_clear_unlocks_next() -> void:
	var p := _progress()
	p.record_clear("camp", "st1")
	assert_eq(p.stage_state("camp", "st1"), CampaignProgress.CLEARED, "クリア済みになる（再挑戦可）")
	assert_eq(p.stage_state("camp", "st2"), CampaignProgress.UNLOCKED, "次が解放される")
	assert_eq(p.cleared_count("camp"), 1, "冒険譚カードの進捗 n/m 用")

func test_entitlement_keeps_locked() -> void:
	var p := _progress()
	p.record_clear("camp", "st1")
	p.record_clear("camp", "st2")
	assert_eq(p.stage_state("camp", "st3"), CampaignProgress.LOCKED,
		"AND評価: cleared を満たしても entitlement（未実装＝未充足）でロックのまま")

func test_debug_campaign_always_unlocked_and_unrecorded() -> void:
	var p := _progress()
	assert_eq(p.stage_state("dbg", "d1"), CampaignProgress.UNLOCKED, "デバッグ冒険譚は常時解放")
	p.record_clear("dbg", "d1")
	assert_false(ProgressStore.new(PATH).is_cleared("dbg", "d1"), "クリア記録は付けない")

func test_campaigns_filters_debug() -> void:
	var p := _progress()
	assert_eq(p.campaigns(false).size(), 1, "デバッグ冒険譚を除外できる")
	assert_eq(p.campaigns(true).size(), 2)

func test_unlock_text_uses_stage_title() -> void:
	var p := _progress()
	assert_eq(p.unlock_text("camp", "st2"), "「一」クリアで解放")

func test_unknown_ids_are_safe() -> void:
	var p := _progress()
	assert_eq(p.stage_state("nope", "st1"), CampaignProgress.LOCKED)
	assert_eq(p.stage_state("camp", "nope"), CampaignProgress.LOCKED)
	p.record_clear("camp", "nope")  # 未知ステージは記録しない（クラッシュもしない）
	assert_eq(p.cleared_count("camp"), 0)
