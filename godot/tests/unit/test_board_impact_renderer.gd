extends GutTest
## presentation/board/board_impact_renderer.gd の単体テスト。
## SceneTree に載せて Tween が動く状態でテストする。

var renderer: BoardImpactRenderer

func before_each() -> void:
	renderer = BoardImpactRenderer.new()
	add_child_autofree(renderer)
	await get_tree().process_frame

# --- 初期状態 ---

func test_initial_not_impacting() -> void:
	assert_false(renderer.is_impacting(), "初期状態では着弾中でない")

func test_initial_no_children() -> void:
	assert_eq(renderer.get_child_count(), 0, "初期状態で子ノードは空")

# --- 定数 ---

func test_tile_matches_hex_board() -> void:
	assert_eq(BoardImpactRenderer.TILE, HexBoard3D.TILE, "TILE が HexBoard3D と一致")

func test_hit_lead_positive() -> void:
	assert_true(BoardImpactRenderer.HIT_LEAD_SEC > 0.0, "HIT_LEAD_SEC は正の値")

func test_hit_flash_gain_greater_than_one() -> void:
	assert_true(BoardImpactRenderer.HIT_FLASH_GAIN > 1.0, "HIT_FLASH_GAIN は 1 より大きい")

func test_hit_cell_alpha_in_range() -> void:
	var a := BoardImpactRenderer.HIT_CELL_ALPHA
	assert_true(a > 0.0 and a < 1.0, "HIT_CELL_ALPHA は 0〜1 の範囲")

func test_hit_cell_alpha_hold_less_than_alpha() -> void:
	assert_true(BoardImpactRenderer.HIT_CELL_ALPHA_HOLD < BoardImpactRenderer.HIT_CELL_ALPHA,
		"居座りの濃さは立ち上がりより低い")

func test_color_formation_hit_is_gold() -> void:
	var c := BoardImpactRenderer.COLOR_FORMATION_HIT
	assert_true(c.r > 0.9 and c.g > 0.7, "着弾の光は金色系")

# --- set_pending / is_impacting ---

func test_set_pending_true() -> void:
	renderer.set_pending(true)
	assert_true(renderer.is_impacting(), "set_pending(true) で着弾中になる")

func test_set_pending_false() -> void:
	renderer.set_pending(true)
	renderer.set_pending(false)
	assert_false(renderer.is_impacting(), "set_pending(false) で解除")

# --- reset ---

func test_reset_clears_pending() -> void:
	renderer.set_pending(true)
	renderer.reset()
	assert_false(renderer.is_impacting(), "reset で着弾中が解除される")

func test_reset_increments_gen() -> void:
	var before := renderer._impact_gen
	renderer.reset()
	assert_eq(renderer._impact_gen, before + 1, "reset で世代が上がる")

func test_reset_clears_children() -> void:
	var child := Node3D.new()
	renderer.add_child(child)
	assert_eq(renderer.get_child_count(), 1)
	renderer.reset()
	assert_eq(renderer.get_child_count(), 0, "reset で子ノードが全て消える")

# --- cancel_unlock ---

func test_cancel_unlock_clears_impact_lock() -> void:
	renderer._impact_lock = true
	renderer.cancel_unlock()
	assert_false(renderer._impact_lock, "cancel_unlock で _impact_lock が false")

# --- play（着弾なし）---
# 呼ばれたことの記録は辞書に書く。ラムダはローカル変数を値でコピーして持つので、
# ラムダの中で bool のローカルに代入しても外側は false のまま＝何を書いても通るテストになる。

func test_play_without_pending_does_nothing() -> void:
	# _impact_pending が false なら何もしない。
	var called := { "sync": false }
	renderer.setup(null, null, Callable(), Callable(), null,
		func() -> void: called["sync"] = true, Callable())
	await renderer.play({}, false)
	assert_false(called["sync"], "pending でなければ sync は呼ばれない")

func test_play_with_empty_hits_syncs() -> void:
	renderer.set_pending(true)
	var called := { "sync": false }
	renderer.setup(null, null, Callable(), Callable(), null,
		func() -> void: called["sync"] = true, Callable())
	await renderer.play({"results": []}, false)
	assert_true(called["sync"], "空の hits で sync が呼ばれる")
	assert_false(renderer.is_impacting(), "演出後は pending が解除される")

# --- impact_finished シグナル ---

func test_impact_finished_emitted_on_empty_hits() -> void:
	renderer.set_pending(true)
	renderer.setup(null, null, Callable(), Callable(), null,
		func() -> void: pass, Callable())
	var called := { "emitted": false }
	renderer.impact_finished.connect(func() -> void: called["emitted"] = true)
	await renderer.play({"results": []}, false)
	assert_true(called["emitted"], "impact_finished が発行される")
