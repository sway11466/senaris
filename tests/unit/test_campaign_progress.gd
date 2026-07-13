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

func test_next_stage_returns_following_entry() -> void:
	var p := _progress()
	assert_eq(String(p.next_stage("camp", "st1").get("id", "")), "st2", "順で直後を返す")
	assert_eq(String(p.next_stage("camp", "st2").get("id", "")), "st3")
	assert_eq(String(p.next_stage("camp", "st1").get("path", "")), "res://x/st2.json", "path も持つ")

func test_next_stage_empty_at_last_or_unknown() -> void:
	var p := _progress()
	assert_true(p.next_stage("camp", "st3").is_empty(), "最終ステージの次は無い")
	assert_true(p.next_stage("camp", "nope").is_empty(), "未知ステージは空")
	assert_true(p.next_stage("nope", "st1").is_empty(), "未知冒険譚は空")

func test_next_playable_stage_advances_when_unlocked() -> void:
	var p := _progress()
	p.record_clear("camp", "st1")
	assert_eq(String(p.next_playable_stage("camp", "st1").get("id", "")), "st2",
		"マニフェスト順で直後・解放済みなら進む")

func test_next_playable_stage_stops_at_locked() -> void:
	var p := _progress()
	assert_true(p.next_playable_stage("camp", "st1").is_empty(),
		"直後(st2)が locked（st1 未クリア）なら止まる")
	p.record_clear("camp", "st1")
	p.record_clear("camp", "st2")
	assert_true(p.next_playable_stage("camp", "st2").is_empty(),
		"st3 は entitlement 未充足で locked＝止まる")

func test_next_playable_stage_empty_at_last_stage() -> void:
	var p := _progress()
	assert_true(p.next_playable_stage("camp", "st3").is_empty(), "最終ステージの次は無い＝セレクトへ")

func test_next_playable_stage_skips_debug_campaign() -> void:
	var p := _progress()
	assert_true(p.next_playable_stage("dbg", "d1").is_empty(), "デバッグ冒険譚は自動遷移しない")

func test_next_playable_stage_unknown_campaign_is_empty() -> void:
	var p := _progress()
	assert_true(p.next_playable_stage("", "st1").is_empty(), "セレクト非経由（冒険譚ID空）は遷移しない")
	assert_true(p.next_playable_stage("nope", "st1").is_empty())

func test_unlock_text_joins_entitlement_condition() -> void:
	var p := _progress()
	assert_eq(p.unlock_text("camp", "st3"), "「二」クリアで解放・追加コンテンツ",
		"entitlement は「追加コンテンツ」、複数条件は「・」で連結")

func test_unlock_text_unknown_stage_is_empty() -> void:
	var p := _progress()
	assert_eq(p.unlock_text("camp", "nope"), "")
	assert_eq(p.unlock_text("nope", "st1"), "")

func test_cleared_count_debug_campaign_is_zero() -> void:
	# デバッグ冒険譚の記録がファイルに紛れ込んでいても進捗には数えない
	ProgressStore.new(PATH).mark_cleared("dbg", "d1")
	assert_eq(_progress().cleared_count("dbg"), 0)

func test_cleared_count_ignores_orphan_records() -> void:
	# マニフェストから消えたステージの記録（孤児レコード）は n/m に数えない
	var store := ProgressStore.new(PATH)
	store.mark_cleared("camp", "ghost")
	store.mark_cleared("camp", "st1")
	assert_eq(_progress().cleared_count("camp"), 1, "数えるのは st1 だけ")

func test_unknown_ids_are_safe() -> void:
	var p := _progress()
	assert_eq(p.stage_state("nope", "st1"), CampaignProgress.LOCKED)
	assert_eq(p.stage_state("camp", "nope"), CampaignProgress.LOCKED)
	p.record_clear("camp", "nope")  # 未知ステージは記録しない（クラッシュもしない）
	assert_eq(p.cleared_count("camp"), 0)
