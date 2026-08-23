extends GutTest
## ステージ一覧の連戦レーン（隊ごとの綴じ紐）の組み立て。仕様 → doc/gdd/stage_select.md 連戦の区間
## 描画は目視（tests/manual）に任せ、ここは「どの隊がどの行に線を持つか」の導出だけを固定する。

func _stages(parties: Array) -> Array:
	var out: Array = []
	for i in parties.size():
		out.append({ "id": "st%d" % (i + 1), "party": parties[i] })
	return out

func test_no_party_means_no_lane() -> void:
	# party を書かないステージだけなら線は出ない（単発ステージの一覧）。
	assert_eq(StageSelect.lanes_of(_stages([[], [], []])), [], "レーンなし")

func test_single_party_spans_its_stages() -> void:
	var lanes := StageSelect.lanes_of(_stages([["A"], ["A"], ["A"]]))
	assert_eq(lanes.size(), 1, "隊が1つならレーンも1本")
	assert_eq(int(lanes[0]["first"]), 0)
	assert_eq(int(lanes[0]["last"]), 2)
	assert_eq((lanes[0]["active"] as Dictionary).size(), 3, "全話に出る")

func test_two_parties_run_side_by_side() -> void:
	# 冒険譚3の形＝2隊が全話とも同じ盤に出る。線は2本が並走する。
	var lanes := StageSelect.lanes_of(_stages([["veterans", "rookies"], ["veterans", "rookies"]]))
	assert_eq(lanes.size(), 2, "隊の数だけレーンが立つ")
	for lane in lanes:
		assert_eq(int(lane["first"]), 0)
		assert_eq(int(lane["last"]), 1)

func test_split_and_merge_leaves_dormant_gap() -> void:
	# A隊 → B隊 → 合流。A は st3・st4 に出ないが、線は最後の登場まで続く（待機＝薄い線の区間）。
	var lanes := StageSelect.lanes_of(_stages([["A"], ["A"], ["B"], ["B"], ["A", "B"]]))
	assert_eq(lanes.size(), 2, "登場順に A・B の2本")
	var a: Dictionary = lanes[0]
	assert_eq(int(a["first"]), 0, "A は st1 から")
	assert_eq(int(a["last"]), 4, "A は合流の st5 まで")
	assert_false((a["active"] as Dictionary).has(2), "st3 は出番なし＝薄い区間")
	assert_false((a["active"] as Dictionary).has(3), "st4 も出番なし")
	assert_true((a["active"] as Dictionary).has(4), "合流で戻る")
	var b: Dictionary = lanes[1]
	assert_eq(int(b["first"]), 2, "B は st3 から始まる＝それより上に線は出ない")
	assert_eq(int(b["last"]), 4)

func test_lane_order_follows_first_appearance() -> void:
	# レーンの並びは登場順（後から出る隊が左に割り込まない）。
	var lanes := StageSelect.lanes_of(_stages([["B"], ["A", "B"]]))
	assert_eq(int(lanes[0]["first"]), 0, "先に出た B が1本目")
	assert_eq(int(lanes[1]["first"]), 1, "後から出た A が2本目")
