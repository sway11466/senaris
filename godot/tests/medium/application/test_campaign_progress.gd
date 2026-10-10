extends GutTest
## CampaignProgress（解放判定＝locked/unlocked/cleared の導出）のテスト。仕様 → doc/gdd/stage_select.md

const DIR := "user://test_campaign_progress"
const PATH := "user://test_campaign_progress/progress.json"

func before_each() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

func after_all() -> void:
	_clean()

func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file in dir.get_files():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))

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

## unlock_text は翻訳キー経由（i18n）なので、ja に固定して正本の文字列で検証する（test_i18n.gd と同じ流儀）。
func test_unlock_text_uses_stage_title() -> void:
	var p := _progress()
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	assert_eq(p.unlock_text("camp", "st2"), "「一」クリアで解放")
	TranslationServer.set_locale(prev)

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
	p.record_clear("camp", "st1")  # st2 を解放＝前提の名前を出してよい状態にする
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	assert_eq(p.unlock_text("camp", "st3"), "「二」クリアで解放・追加コンテンツ",
		"entitlement は「追加コンテンツ」、複数条件は「・」で連結")
	TranslationServer.set_locale(prev)

func test_unlock_text_hides_locked_prerequisite_name() -> void:
	var p := _progress()
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	assert_eq(p.unlock_text("camp", "st3"), "2番めの依頼をクリアで解放・追加コンテンツ",
		"前提(st2)自身が locked なら名前を伏せて番号で指す")
	TranslationServer.set_locale(prev)

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

## 全クリア判定（カードの DONE 焼き印・ステージ一覧の扉絵差し替えの条件）。
func test_is_all_cleared_needs_every_stage() -> void:
	var p := _progress()
	assert_false(p.is_all_cleared("camp"), "未着手")
	p.record_clear("camp", "st1")
	p.record_clear("camp", "st2")
	assert_false(p.is_all_cleared("camp"), "1本残っていれば false")
	p.record_clear("camp", "st3")
	assert_true(p.is_all_cleared("camp"), "全ステージで true")

func test_is_all_cleared_excludes_debug_and_unknown() -> void:
	var p := _progress()
	p.record_clear("dbg", "d1")  # デバッグ冒険譚は記録しない＝制覇にもならない
	assert_false(p.is_all_cleared("dbg"), "デバッグ冒険譚は対象外")
	assert_false(p.is_all_cleared("no_such"), "未知のIDは false")

func test_roster_source_reads_manifest() -> void:
	# 名簿の引き継ぎ元＝マニフェストの roster_from。無ければ空文字（doc/gdd/campaigns.md 名簿）。
	var p := CampaignProgress.new([CampaignCatalog.build({
		"id": "camp", "title": "t", "board": "tutorial",
		"stages": [
			{ "id": "st1", "file": "st1.json" },
			{ "id": "st2", "file": "st2.json", "roster_from": "st1" },
		] }, "res://x")], ProgressStore.new(PATH))
	assert_eq(p.roster_source("camp", "st1"), "", "1面は引き継ぎ元なし")
	assert_eq(p.roster_source("camp", "st2"), "st1")
	assert_eq(p.roster_source("camp", "nope"), "", "未知のステージは空")
	assert_eq(p.roster_source("nope", "st1"), "", "未知の冒険譚は空")

# --- ランク・所要時間の記録（doc/gdd/rank.md 記録）。弾く入力 ---

func test_record_rank_is_kept() -> void:
	var p := _progress()
	p.record_rank("camp", "st1", "A")
	assert_eq(p.best_rank("camp", "st1"), "A", "ランクが記録される")

func test_record_rank_empty_is_ignored() -> void:
	var p := _progress()
	p.record_rank("camp", "st1", "A")
	p.record_rank("camp", "st1", "")
	assert_eq(p.best_rank("camp", "st1"), "A", "空のランク（ランクを持たないステージ）では書き換えない")

func test_record_rank_debug_or_unknown_is_ignored() -> void:
	var p := _progress()
	p.record_rank("dbg", "d1", "S")
	p.record_rank("camp", "no-such-stage", "S")
	p.record_rank("no-such-camp", "st1", "S")
	assert_eq(p.best_rank("dbg", "d1"), "", "デバッグ冒険譚は記録しない")
	assert_eq(p.best_rank("camp", "no-such-stage"), "", "未知のステージは記録しない")
	assert_eq(p.best_rank("no-such-camp", "st1"), "", "未知の冒険譚は記録しない")

func test_record_time_is_kept() -> void:
	var p := _progress()
	p.record_time("camp", "st1", 120)
	assert_eq(p.best_time("camp", "st1"), 120, "所要時間が記録される")

func test_record_time_non_positive_is_ignored() -> void:
	var p := _progress()
	p.record_time("camp", "st1", 0)
	p.record_time("camp", "st1", -5)
	assert_eq(p.best_time("camp", "st1"), 0, "0 以下（測れていない）は記録しない")
	p.record_time("camp", "st1", 90)
	p.record_time("camp", "st1", 0)
	assert_eq(p.best_time("camp", "st1"), 90, "測れていない回でベストを潰さない")

func test_record_time_debug_or_unknown_is_ignored() -> void:
	var p := _progress()
	p.record_time("dbg", "d1", 60)
	p.record_time("camp", "no-such-stage", 60)
	assert_eq(p.best_time("dbg", "d1"), 0, "デバッグ冒険譚は記録しない")
	assert_eq(p.best_time("camp", "no-such-stage"), 0, "未知のステージは記録しない")

## 冒険譚の解放条件: part2 は part1 の踏破（最終ステージ p1b のクリア）で解放。
func _series_progress() -> CampaignProgress:
	var campaigns: Array = [
		CampaignCatalog.build({
			"id": "part1", "title": "第1部", "board": "b",
			"stages": [
				{ "id": "p1a", "file": "p1a.json", "synopsis": "s" },
				{ "id": "p1b", "file": "p1b.json", "synopsis": "s",
					"unlock": [ { "type": "cleared", "stage": "p1a" } ] },
			],
		}, "res://x"),
		CampaignCatalog.build({
			"id": "part2", "title": "第2部", "board": "b",
			"unlock": [ { "type": "campaign_cleared", "campaign": "part1" } ],
			"stages": [ { "id": "p2a", "file": "p2a.json", "synopsis": "s" } ],
		}, "res://y"),
	]
	return CampaignProgress.new(campaigns, ProgressStore.new(PATH))

func test_campaign_locked_until_previous_cleared() -> void:
	var p := _series_progress()
	assert_eq(p.campaign_state("part1"), CampaignProgress.UNLOCKED, "unlock 未指定は無条件で解放")
	assert_eq(p.campaign_state("part2"), CampaignProgress.LOCKED, "前の冒険譚が未踏破ならロック")
	assert_eq(p.stage_state("part2", "p2a"), CampaignProgress.LOCKED,
		"冒険譚がロック中は、自分の解放条件が無い1面もロック")
	p.record_clear("part1", "p1a")
	assert_eq(p.campaign_state("part2"), CampaignProgress.LOCKED, "最終ステージ以外のクリアでは解放しない")
	p.record_clear("part1", "p1b")
	assert_eq(p.campaign_state("part2"), CampaignProgress.UNLOCKED, "最終ステージのクリアで解放")
	assert_eq(p.stage_state("part2", "p2a"), CampaignProgress.UNLOCKED, "中の1面も選べるようになる")

func test_campaign_unlock_unknown_ref_stays_locked() -> void:
	var c := CampaignCatalog.build({
		"id": "lonely", "title": "孤立", "board": "b",
		"unlock": [ { "type": "campaign_cleared", "campaign": "missing" } ],
		"stages": [ { "id": "l1", "file": "l1.json", "synopsis": "s" } ],
	}, "res://z")
	var p := CampaignProgress.new([c], ProgressStore.new(PATH))
	assert_eq(p.campaign_state("lonely"), CampaignProgress.LOCKED, "参照先が無ければ未充足＝ロック側に倒す")

func test_debug_campaign_state_always_unlocked() -> void:
	var p := _progress()
	assert_eq(p.campaign_state("dbg"), CampaignProgress.UNLOCKED, "デバッグ冒険譚は常時解放")

## 冒険譚の解放条件の文: 前提が開いていれば題名入り、前提も閉じていれば空（表示側が共通の一文に倒す）。
func test_campaign_unlock_text_hides_locked_prerequisite() -> void:
	var campaigns: Array = [
		CampaignCatalog.build({ "id": "part1", "title": "第1部", "board": "b",
			"stages": [ { "id": "p1a", "file": "p1a.json", "synopsis": "s" } ] }, "res://x"),
		CampaignCatalog.build({ "id": "part2", "title": "第2部", "board": "b",
			"unlock": [ { "type": "campaign_cleared", "campaign": "part1" } ],
			"stages": [ { "id": "p2a", "file": "p2a.json", "synopsis": "s" } ] }, "res://y"),
		CampaignCatalog.build({ "id": "part3", "title": "第3部", "board": "b",
			"unlock": [ { "type": "campaign_cleared", "campaign": "part2" } ],
			"stages": [ { "id": "p3a", "file": "p3a.json", "synopsis": "s" } ] }, "res://z"),
	]
	var p := CampaignProgress.new(campaigns, ProgressStore.new(PATH))
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	assert_eq(p.campaign_unlock_text("part2"), "「第1部」を踏破すると挑める。", "前提が開いていれば題名で指す")
	assert_eq(p.campaign_unlock_text("part3"), "", "前提も未解放なら書かない＝伏せた題名を漏らさない")
	p.record_clear("part1", "p1a")
	assert_eq(p.campaign_unlock_text("part3"), "「第2部」を踏破すると挑める。", "前提が開いたら書ける")
	TranslationServer.set_locale(prev)

## 製品版だけの話の殻（full_only＝体験版の書き出しが置く）。仕様 → doc/tech/build.md 冒険譚の途中まで収録する
func _demo_progress() -> CampaignProgress:
	var campaigns: Array = [
		CampaignCatalog.build({
			"id": "camp", "title": "途中まで",
			"stages": [
				{ "id": "st1", "file": "st1.json" },
				{ "id": "st2", "file": "st2.json", "unlock": [ { "type": "cleared", "stage": "st1" } ] },
				{ "id": "st3", "full_only": true },
				{ "id": "st4", "full_only": true },
			],
		}, "res://x"),
		CampaignCatalog.build({
			"id": "next", "title": "続き",
			"unlock": [ { "type": "campaign_cleared", "campaign": "camp" } ],
			"stages": [ { "id": "n1", "file": "n1.json" } ],
		}, "res://y"),
	]
	return CampaignProgress.new(campaigns, ProgressStore.new(PATH))

func test_full_only_stage_is_always_locked_with_full_game_text() -> void:
	var p := _demo_progress()
	p.record_clear("camp", "st1")
	p.record_clear("camp", "st2")
	assert_true(p.is_full_only("camp", "st3"))
	assert_false(p.is_full_only("camp", "st2"))
	assert_eq(p.stage_state("camp", "st3"), CampaignProgress.LOCKED, "前の話を全部クリアしても殻は開かない")
	assert_eq(p.unlock_text("camp", "st3"), TranslationServer.translate("ui.quest.full_only"), "条件ではなく製品版の案内")
	assert_true(p.next_playable_stage("camp", "st2").is_empty(), "クリア後の自動遷移は殻で止まる＝セレクトへ戻る")

func test_full_only_stages_keep_campaign_from_completing() -> void:
	var p := _demo_progress()
	p.record_clear("camp", "st1")
	p.record_clear("camp", "st2")
	assert_eq(p.cleared_count("camp"), 2)
	assert_false(p.is_all_cleared("camp"), "殻が残るので踏破にならない＝DONE・勝利絵・実績は立たない")
	assert_false(p.next_stage("camp", "st2").is_empty(), "殻が「次」に居る＝最終ステージの判定にならない")
	assert_eq(p.campaign_state("next"), CampaignProgress.LOCKED, "campaign_cleared も満たさない")
