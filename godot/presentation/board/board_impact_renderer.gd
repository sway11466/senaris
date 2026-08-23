extends Node3D
class_name BoardImpactRenderer
## 陣形スキル／ユニットスキルの着弾演出（hex_board_3d.gd から切り出し）。
## 面の光 → 被弾した駒を1体ずつ（エフェクト→フラッシュ→兵数、撃破はフェード）。
## このノード自身が一時的な演出メッシュ（着弾の光・駒に重ねるエフェクト）の入れ物になる。
## オーバーレイの作り直しで消えない層＝hex_board_3d の旧 _fx_root に相当する。
## 詳細 → doc/gdd/formations.md 発動の演出

## 着弾演出が終わった（打ち切りでも必ず発行＝待ち手を取り残さない）。
signal impact_finished

const TILE := HexBoard3D.TILE

# --- 着弾演出のタイミングと色 ---
# 揺れ→面の光→被弾した駒を1体ずつ。
const COLOR_FORMATION_HIT := Color(1.00, 0.82, 0.40)  # 着弾した面の光（金）
const HIT_LEAD_SEC := 0.10        # 揺れてから面が光るまでの間（同時に出すと1つの衝撃に潰れる）
const HIT_CELL_RISE := 0.07       # 面の光の立ち上がり
const HIT_CELL_SETTLE := 0.18     # 立ち上がりから居座りの濃さへ落とすまで
const HIT_CELL_HOLD := 0.16       # 同・居座り（この間に駒の処理が進む）
const HIT_CELL_FADE := 0.32       # 同・引き
const HIT_CELL_ALPHA := 0.34      # 同・立ち上がりの濃さ（加算合成。これ以上は地形が白く飛ぶ）
const HIT_CELL_ALPHA_HOLD := 0.13 # 同・居座りの濃さ。駒に重ねるエフェクトを埋もれさせない
const HIT_STEP_SEC := 0.13        # 駒1体ぶんの間隔＝何体が受けたのかを数えられる範囲で詰める
const HIT_DROP_SEC := 0.16        # 駒に落とすエフェクトの落下時間（着弾＝ここで駒が反応する）
const HIT_DROP_FROM := TILE * 2.0 # 同・落とし始める高さ（駒の頭より上）
const HIT_BURST_SEC := 0.18       # 同・着弾して弾けて消えるまで
const HIT_BURST_TILES := 2.2      # 同・大きさの基準（scale 1.0 でヘックス幅の何倍か）
const HIT_BURST_OPEN := 1.35      # 同・着弾で開く倍率
const HIT_FLASH_SEC := 0.14       # 被弾フラッシュ（立ち絵を白く飛ばす）の片道
const HIT_FLASH_GAIN := 2.2       # 同・明るさの倍率
const HIT_FADE_SEC := 0.22        # 撃破された駒が消えるまで

# --- 外部依存（setup で注入）---
var _unit_renderer: BoardUnitRenderer
var _overlay_mesh: ArrayMesh
var _elev_fn: Callable        # (hex: Vector2i) -> float（標高）
var _in_board_fn: Callable    # (hex: Vector2i) -> bool（盤内判定）
var _state: BattleState
var _sync_fn: Callable        # () -> void（盤の見た目を作り直す）
var _set_locked_fn: Callable  # (v: bool) -> void（入力ロック）

# --- 着弾演出の状態 ---
var _impact_gen := 0            # 世代。ステージが変わったら増やす＝await の先で打ち切る
var _impact_pending := false    # 着弾待ち＝盤の作り直しを保留している（撃たれる前の姿のまま置く）
var _impact_lock := false       # 演出の間だけ入力を止めた＝終わったら元へ戻す
var _impact_tex := {}           # recipe_id -> Texture2D|null（駒に重ねる着弾の絵）


func setup(unit_renderer: BoardUnitRenderer, overlay_mesh: ArrayMesh,
		elev_fn: Callable, in_board_fn: Callable, p_state: BattleState,
		sync_fn: Callable, set_locked_fn: Callable) -> void:
	_unit_renderer = unit_renderer
	_overlay_mesh = overlay_mesh
	_elev_fn = elev_fn
	_in_board_fn = in_board_fn
	_state = p_state
	_sync_fn = sync_fn
	_set_locked_fn = set_locked_fn


## 着弾を待つ状態にする。陣形の解決時に hex_board_3d が呼ぶ。
func set_pending(v: bool) -> void:
	_impact_pending = v


## 着弾演出が進行中か（盤が撃たれる前の姿を保持している間）。
func is_impacting() -> bool:
	return _impact_pending


## 決着が割り込んだとき、着弾演出が終わっても入力ロックを解除しないようにする。
## hex_board_3d._on_battle_finished から呼ばれる。
func cancel_unlock() -> void:
	_impact_lock = false


## ステージ再ロード時の初期化。進行中の演出を打ち切り、子ノード（一時メッシュ）を全て消す。
func reset() -> void:
	_impact_gen += 1
	_impact_pending = false
	_impact_lock = false
	for c in get_children():
		remove_child(c)
		c.free()


## 着弾を見せる：面の光 → 被弾した駒を1体ずつ（エフェクト→フラッシュ→兵数、撃破はフェード）。
## 画面全体の揺れは main が持つ（盤だけを揺らしても画面全体にはならない）。
## 着弾が無いもの（バフ・解除）は光らせず盤を更新するだけ＝呼び出し側で分岐しなくていい。
## is_locked は呼び出し元の現在のロック状態（演出終了後に元に戻すか判定するため）。
func play(result: Dictionary, is_locked: bool) -> void:
	if not _impact_pending:
		return  # 着弾の無いもの（バフ・解除）＝盤は解決した時点で更新済み
	var hits: Array = result.get("results", [])
	if hits.is_empty():
		_end_impact()
		_sync_fn.call()
		return
	var gen := _impact_gen
	_impact_lock = not is_locked
	_set_locked_fn.call(true)  # 演出中に盤を触らせない（別の作り直しが割り込むと消えかけの駒が飛ぶ）
	await _wait(HIT_LEAD_SEC)  # 揺れと同時に光らせない＝1つの衝撃に潰れる
	if gen != _impact_gen:
		_end_impact()
		return
	var center := Vector2i(result.get("center", Vector2i.ZERO))
	# 面の光は駒の処理が終わるまで保たせる＝どの範囲の中で起きているのかが見えたまま進む。
	_flash_cells(result.get("cells", []), HIT_CELL_HOLD + HIT_DROP_SEC + HIT_STEP_SEC * float(hits.size()))
	var tex := _impact_texture(String(result.get("recipe", "")))
	# 着弾中心に近い駒から外へ。同距離は id 順＝毎回同じ順で出る（見え方が揺れない）。
	var order: Array = hits.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := Hex.distance(Vector2i(a["hex"]), center)
		var db := Hex.distance(Vector2i(b["hex"]), center)
		return da < db if da != db else int(a["target_id"]) < int(b["target_id"]))
	for i in order.size():
		_hit_unit(order[i], tex)
		# 最後の1発は落ちて当たって消えるまで待ってから盤を作り直す（消えかけの駒を飛ばさない）。
		await _wait(HIT_STEP_SEC if i < order.size() - 1 else HIT_DROP_SEC + maxf(HIT_BURST_SEC, HIT_FADE_SEC))
		if gen != _impact_gen:
			_end_impact()
			return
	_end_impact()
	_sync_fn.call()


## 着弾演出の後始末＝保留を解き、止めた入力を戻し、待っている側（main）へ知らせる。
## 決着が割り込んだ場合は _impact_lock が下りている＝解錠しない。
func _end_impact() -> void:
	_impact_pending = false
	if _impact_lock:
		_set_locked_fn.call(false)
		_impact_lock = false
	impact_finished.emit()


## 被弾した駒1体ぶん。エフェクトが上から落ちきった瞬間に駒が反応する
## （撃破ならその場でフェードアウト、生き残りは新しい兵数で組み直して光らせる）。
func _hit_unit(hit: Dictionary, tex: Texture2D) -> void:
	var gen := _impact_gen
	_spawn_burst(Vector2i(hit["hex"]), tex, func() -> void:
		if gen == _impact_gen:
			_land_hit(hit))


func _land_hit(hit: Dictionary) -> void:
	var uid := int(hit["target_id"])
	var node: Node3D = _unit_renderer.get_unit_node(uid)
	if node == null:
		return
	if bool(hit["killed"]):
		_unit_renderer.forget_unit(uid)
		_fade_out_unit(node)
		return
	# 兵数バーは組み立て時に焼くので、減った値を出すには組み直すのが早い（state は解決済み）。
	_unit_renderer.remove_unit(uid)
	var u := _state.unit_by_id(uid)
	if u != null:
		_flash_unit(_unit_renderer.build_unit_node(u))


## 被弾フラッシュ＝立ち絵を一瞬白く飛ばして戻す。行動終了の暗さ（modulate）を基準に掛ける。
func _flash_unit(node: Node3D) -> void:
	for c in node.get_children():
		if not (c is Sprite3D):
			continue
		var spr := c as Sprite3D
		var base := spr.modulate
		var hot := Color(base.r * HIT_FLASH_GAIN, base.g * HIT_FLASH_GAIN, base.b * HIT_FLASH_GAIN, base.a)
		var tw := create_tween()
		tw.tween_property(spr, "modulate", hot, HIT_FLASH_SEC)
		tw.tween_property(spr, "modulate", base, HIT_FLASH_SEC)


## 撃破された駒を消す。立ち絵は薄くして消し、影・バー・輪は共有材質なので隠すだけにする
## （材質のアルファを触ると、同じ色を使う他の駒まで一緒に薄くなる）。
func _fade_out_unit(node: Node3D) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	for c in node.get_children():
		if c is Sprite3D:
			var spr := c as Sprite3D
			spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED  # discard のままでは薄くならない
			tw.tween_property(spr, "modulate:a", 0.0, HIT_FADE_SEC)
		elif c is Label3D:
			tw.tween_property(c, "modulate:a", 0.0, HIT_FADE_SEC)
		elif c is Node3D:
			(c as Node3D).hide()
	tw.chain().tween_callback(node.queue_free)


## 着弾した面を光らせる。駒の居ない空ヘックスも光らせる＝面の広さが伝わる。
## 盤の外へはみ出したヘックスは出さない。材質は1枚ごとに作る（アルファを個別に動かすため）。
func _flash_cells(cells: Array, hold: float) -> void:
	for c in cells:
		var hex := Vector2i(c)
		if not _in_board_fn.call(hex):
			continue
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(COLOR_FORMATION_HIT, 0.0)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # 地形の上に載せる（塗り潰さない）
		var mi := MeshInstance3D.new()
		mi.mesh = _overlay_mesh
		mi.material_override = m
		var p := Hex.to_pixel(hex, TILE)
		mi.position = Vector3(p.x, _elev_fn.call(hex) + 0.05, p.y)
		add_child(mi)
		# 立ち上がりで一度強く光らせ、駒を処理している間は薄く居座らせる（面は見えたまま・
		# 駒に重ねるエフェクトは埋もれない）。最後に引く。
		var tw := create_tween()
		tw.tween_property(m, "albedo_color:a", HIT_CELL_ALPHA, HIT_CELL_RISE)
		tw.tween_property(m, "albedo_color:a", HIT_CELL_ALPHA_HOLD, HIT_CELL_SETTLE)
		tw.tween_interval(hold)
		tw.tween_property(m, "albedo_color:a", 0.0, HIT_CELL_FADE)
		tw.tween_callback(mi.queue_free)


## 駒に当てるエフェクト1発。レシピ専用の絵を駒の真上から落として当てる。
## 落ちきった時点で on_land を呼ぶ＝駒の反応（フラッシュ・兵数・撃破）はそこに揃う。
## 絵が無いときは、そのヘックスだけを濃く光らせる＝穴が開かない。
func _spawn_burst(hex: Vector2i, tex: Texture2D, on_land: Callable) -> void:
	if tex == null:
		_flash_cells([hex], HIT_BURST_SEC)
		on_land.call()
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.no_depth_test = true      # 駒より手前に出す（足元の地形や後列に潜り込ませない）
	spr.render_priority = 6
	# 大きさの基準は長辺。倍率は持たず、絵の側を枠いっぱいに描いて釣り合わせる。
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	spr.pixel_size = (HIT_BURST_TILES * TILE) / maxf(longest, 1.0)
	var p := Hex.to_pixel(hex, TILE)
	var land := Vector3(p.x, _elev_fn.call(hex) + TILE * 0.9, p.y + BoardUnitRenderer.SPRITE_FOOT_Z)
	spr.position = land + Vector3(0, HIT_DROP_FROM, 0)
	add_child(spr)
	var tw := create_tween()
	tw.tween_property(spr, "position", land, HIT_DROP_SEC).set_ease(Tween.EASE_IN)  # 落下＝加速
	tw.tween_callback(on_land)
	tw.set_parallel(true)  # 着弾＝開きながら消える
	tw.tween_property(spr, "scale", Vector3.ONE * HIT_BURST_OPEN, HIT_BURST_SEC)
	tw.tween_property(spr, "modulate:a", 0.0, HIT_BURST_SEC)
	tw.chain().tween_callback(spr.queue_free)


## 着弾に使う絵（キャッシュ）。レシピIDで規約解決する＝assets/formations/{recipe_id}_impact.png。
## カットイン（{recipe_id}.png）と同じ置き場・同じ規約で、接尾辞だけが違う。
## 盤でしか使わないので絵は最初から下向きに描く＝ここで回さない。
## 無ければ null＝絵を出さず面の光だけで済ませる（武器の攻撃エフェクトへは落とさない。
## 借り物を落とすと剣の弧が天から降ってくる）。詳細 → doc/gdd/formations.md 発動の演出
func _impact_texture(recipe: String) -> Texture2D:
	if recipe.is_empty():
		return null
	if _impact_tex.has(recipe):
		return _impact_tex[recipe]
	var p := "res://assets/formations/%s_impact.png" % recipe
	var tex := load(p) as Texture2D if ResourceLoader.exists(p) else null
	_impact_tex[recipe] = tex
	return tex


func _wait(sec: float) -> void:
	if is_inside_tree():
		await get_tree().create_timer(sec).timeout
