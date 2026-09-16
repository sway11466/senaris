extends GutTest
## ChronicleStory（クロニクルの通し読みの並び）のテスト。仕様 → doc/gdd/chronicle.md 物語
## 章の並びはマニフェスト順、会話は経験した記録に在るものだけ、未クリアで打ち切り。

const CAMPAIGN := "test-campaign"

func _manifest() -> Array:
	return [
		{ "stage": "st1", "events": [] },
		{ "stage": "st2", "events": ["rescue", "ambush"] },
		{ "stage": "st3", "events": [] },
	]

## 既定は「3ステージとも全部クリア・全イベント経験」。各テストが必要な枝だけ差し替える。
func _stages(overrides: Dictionary = {}) -> Dictionary:
	var stages := {
		"st1": _stage("st1", true, { "start": ["knight"], "clear": ["knight"], "events": [] }),
		"st2": _stage("st2", true, { "start": ["knight"], "clear": ["knight"],
				"events": ["rescue", "ambush"] }),
		"st3": _stage("st3", true, { "start": ["knight"], "clear": ["knight"], "events": [] }),
	}
	for k in overrides:
		stages[k] = overrides[k]
	return stages

func _stage(id: String, cleared: bool, record: Dictionary) -> Dictionary:
	return {
		"title": "stage.%s.title" % id,
		"path": "res://data/stages/%s.json" % id,
		"cleared": cleared,
		"record": record,
		"event_talks": {
			"rescue": { "name": "ev.rescue.name", "dialogue": "talk_rescue" },
			"ambush": { "name": "ev.ambush.name", "dialogue": "talk_ambush" },
		},
	}

func _keys(chapter: Dictionary) -> Array:
	var out: Array = []
	for t in chapter["talks"]:
		out.append(t["key"])
	return out

func test_chapters_follow_the_manifest_order() -> void:
	var chapters := ChronicleStory.build(CAMPAIGN, _manifest(), _stages())
	assert_eq(chapters.size(), 3, "3ステージぶんの章")
	assert_eq(chapters[0]["stage"], "st1")
	assert_eq(chapters[1]["stage"], "st2")
	assert_eq(chapters[2]["stage"], "st3")
	assert_eq(chapters[0]["title"], "stage.st1.title", "章題はステージの題名キー")

func test_talks_run_intro_then_events_then_outro() -> void:
	var chapters := ChronicleStory.build(CAMPAIGN, _manifest(), _stages())
	assert_eq(_keys(chapters[1]), ["intro", "talk_rescue", "talk_ambush", "outro"],
			"開幕→イベント→決着")
	assert_eq(chapters[1]["talks"][1]["event"], "rescue", "イベントの会話は id を持つ")

func test_events_follow_the_manifest_not_the_record() -> void:
	# 起きた順（記録）は ambush → rescue でも、出す順はマニフェストの並び。
	var record := { "start": ["knight"], "clear": ["knight"], "events": ["ambush", "rescue"] }
	var chapters := ChronicleStory.build(CAMPAIGN, _manifest(),
			_stages({ "st2": _stage("st2", true, record) }))
	assert_eq(_keys(chapters[1]), ["intro", "talk_rescue", "talk_ambush", "outro"])

func test_unexperienced_events_are_left_out() -> void:
	var record := { "start": ["knight"], "clear": ["knight"], "events": ["rescue"] }
	var chapters := ChronicleStory.build(CAMPAIGN, _manifest(),
			_stages({ "st2": _stage("st2", true, record) }))
	assert_eq(_keys(chapters[1]), ["intro", "talk_rescue", "outro"], "経験していない ambush は出ない")

func test_uncleared_stage_ends_the_story() -> void:
	# st2 は遊んだが決着していない＝その章までで終わる（開幕は読める）。
	var record := { "start": ["knight"], "events": [] }
	var chapters := ChronicleStory.build(CAMPAIGN, _manifest(),
			_stages({ "st2": _stage("st2", false, record) }))
	assert_eq(chapters.size(), 2, "st3 は出さない")
	assert_eq(_keys(chapters[1]), ["intro"], "決着の会話は無い")

func test_unplayed_stage_is_not_listed() -> void:
	var chapters := ChronicleStory.build(CAMPAIGN, _manifest(),
			_stages({ "st2": _stage("st2", false, {}) }))
	assert_eq(chapters.size(), 1, "一度も遊んでいない章は出さない＝存在も匂わせない")

func test_cleared_without_record_keeps_the_chapter_title_only() -> void:
	# 仕組みより前にクリアしたステージ＝記録が無い。章題だけ出して先へ続く。
	var chapters := ChronicleStory.build(CAMPAIGN, _manifest(),
			_stages({ "st2": _stage("st2", true, {}) }))
	assert_eq(chapters.size(), 3, "打ち切らない")
	assert_eq(chapters[1]["talks"], [], "本文は無い")

func test_outro_uses_the_clear_roster() -> void:
	var record := { "start": ["knight"], "clear": ["knight", "priest"], "events": [] }
	var chapters := ChronicleStory.build(CAMPAIGN, _manifest(),
			_stages({ "st1": _stage("st1", true, record) }))
	var talks: Array = chapters[0]["talks"]
	assert_eq(talks[0]["actors"], ["knight"], "開幕は開始時の顔ぶれ")
	assert_eq(talks[1]["actors"], ["knight", "priest"], "決着はクリア後の顔ぶれ")

func test_stage_missing_from_the_campaign_is_skipped() -> void:
	var manifest := _manifest()
	manifest.insert(1, { "stage": "ghost", "events": [] })
	var chapters := ChronicleStory.build(CAMPAIGN, manifest, _stages())
	assert_eq(chapters.size(), 3, "冒険譚に無いステージは飛ばして続ける")

func test_art_is_empty_when_no_picture_is_placed() -> void:
	assert_eq(ChronicleStory.art_path(CAMPAIGN, "st1"), "", "絵が無ければ空＝暗幕だけ")
