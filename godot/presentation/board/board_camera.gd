extends Node3D
class_name BoardCamera
## 盤面カメラリグ。俯角固定で注視点(target)と距離(dist)だけ動かす。
## HexBoard3D が子ノードとして持ち、パン・ズーム・追従・揺れを委譲する。
## 盤のゲーム状態には依存しない＝hex 座標や BattleState は呼び出し側が変換して渡す。

const PITCH_DEG := 52.0
const FOV := 42.0
const MIN_DIST := 5.0
const MAX_DIST := 90.0
const ZOOM_STEP := 1.15
const FOCUS_PAN_SEC := 0.25          # 追従パンの所要秒数
const FOCUS_MARGIN := 96.0           # 追従デッドゾーン＝可視域の内側マージン(px)
const FOCUS_PULL_IN := 40.0          # 追従時は安全域の少し内側まで入れる
const FOCUS_SLACK := 0.5             # 縁ぴったりは見えている扱い(px)＝歩行追従で縁に置いた駒を着地の確認でもう一度寄せない
const SHAKE_PX := 7.0                # 着弾の揺れ幅（画面px）
const SHAKE_STEP := 0.05             # 同・1振りの秒数
## 決着のとどめの寄せ（仕様 → doc/gdd/uiux.md 決着の合図）。追従（focus_on）と違い距離も詰める。
const FINISH_ZOOM_SEC := 0.45        # 寄せの所要秒数
const FINISH_ZOOM_FACTOR := 0.55     # 距離に掛ける倍率（現在の画角から相対で寄る）
const FINISH_MIN_DIST := 8.0         # 寄り過ぎない下限（1ヘックスで画面が埋まらない距離）
const PAN_GESTURE_SPEED := 24.0      # パンジェスチャの感度
const PAN_WHEEL_STEP := 50.0         # 2本指スクロール1ノッチのパン量(px)

## カメラ本体。外から picking（project_ray_origin 等）に使う。
var camera: Camera3D
## 注視点（ワールド座標・盤平面上 y≈0）。
var target := Vector3.ZERO
## 注視点からカメラまでの距離。
var dist := 20.0
## カメラの上方向（ビルボードの持ち上げ向き）。update_rig が算出する。
var cam_up := Vector3.UP
## 追従の行き先を収める範囲（ワールドxz）。既定は無制限＝呼び出し側が set_focus_bounds で渡す。
var focus_min := Vector2(-INF, -INF)
var focus_max := Vector2(INF, INF)

## 追従パンの所要秒数。既定は FOCUS_PAN_SEC。盤面の演出の設定で HexBoard3D が上書きする。
var pan_sec := FOCUS_PAN_SEC

var _tween: Tween = null

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = FOV
	add_child(camera)
	update_rig()
	camera.make_current()

# =========================================================================
# リグ制御
# =========================================================================

## 注視点＋距離からカメラの位置と向きを更新する。
func update_rig() -> void:
	var pitch := deg_to_rad(PITCH_DEG)
	camera.position = target + Vector3(0.0, sin(pitch), cos(pitch)) * dist
	camera.look_at(target, Vector3.UP)
	cam_up = view_up()

## カメラの上方向（像面内の真上）。俯角が固定なので定数から出せる＝カメラを持たない描画側も引ける。
static func view_up() -> Vector3:
	var pitch := deg_to_rad(PITCH_DEG)
	return Vector3(0.0, cos(pitch), -sin(pitch))

## 画面1pxがワールドで何mか（注視点の距離基準の近似）。
func world_per_pixel() -> float:
	return 2.0 * dist * tan(deg_to_rad(FOV) * 0.5) / get_viewport().get_visible_rect().size.y

## マウス移動(px)ぶん盤が指に追随するよう注視点を動かす。
func pan_by(px: Vector2) -> void:
	var wpp := world_per_pixel()
	target.x -= px.x * wpp
	target.z -= px.y * wpp / sin(deg_to_rad(PITCH_DEG))
	update_rig()

## screen の直下の盤面(y=0)を固定したままズーム（カーソル基点）。
func zoom_at_point(factor: float, screen: Vector2) -> void:
	var nd := clampf(dist / factor, MIN_DIST, MAX_DIST)
	if is_equal_approx(nd, dist):
		return
	var before := _plane_point(screen)
	dist = nd
	update_rig()
	var after := _plane_point(screen)
	if before.is_finite() and after.is_finite():
		target += Vector3(before.x - after.x, 0.0, before.z - after.z)
		update_rig()

## 盤全体が vis_rect（使用可能な画面領域 px）に収まるよう距離と注視点を合わせる。
## hex_min / hex_max はヘックス中心のピクセル座標（Hex.to_pixel の結果）。tile はヘックスサイズ。
##
## 傾いたカメラの遠近は距離に比例しない＝手前の列ほど大きく映るので、寸法から一発で解くと
## 手前側がはみ出す。ここでは概算の距離から始めて、四隅を実際に画面へ投影し、はみ出したぶんだけ
## 引く、を数回くり返す。画面上の大きさは距離にほぼ反比例するので数回で収まる。
const FIT_STEPS := 6      # 投影して詰め直す回数
const FIT_MARGIN := 1.02  # 収めたうえで残す余白（1.0 ちょうどだと縁が可視域の線に触れる）

func fit_to_bounds(hex_min: Vector2, hex_max: Vector2, tile: float, vis_rect: Rect2) -> void:
	# 描かれるのはヘックスの中心より半径ぶん外まで＝外周を1タイル広げた矩形を収める。
	var mn := hex_min - Vector2(tile, tile)
	var mx := hex_max + Vector2(tile, tile)
	var c := (mn + mx) * 0.5
	target = Vector3(c.x, 0.0, c.y)
	dist = clampf(_rough_dist(mn, mx, vis_rect), MIN_DIST, MAX_DIST)
	update_rig()
	_center_on(mn, mx, vis_rect)
	for _i in FIT_STEPS:
		var r := _projected_rect(mn, mx)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			break
		var k := maxf(r.size.x / vis_rect.size.x, r.size.y / vis_rect.size.y) * FIT_MARGIN
		var nd := clampf(dist * k, MIN_DIST, MAX_DIST)
		var moved := absf(nd - dist) > 0.01
		dist = nd
		update_rig()
		_center_on(mn, mx, vis_rect)
		if not moved:
			break

## 投影で詰める前の当たり＝寸法から解く近似（そのままだと手前がはみ出すので出発点にだけ使う）。
func _rough_dist(mn: Vector2, mx: Vector2, vis_rect: Rect2) -> float:
	var half := (mx - mn) * 0.5
	var vp := get_viewport().get_visible_rect().size
	var tanf := tan(deg_to_rad(FOV) * 0.5)
	var sp := sin(deg_to_rad(PITCH_DEG))
	var d_h := half.x / (tanf * vis_rect.size.x / vp.y)
	var d_v := half.y * sp / (tanf * vis_rect.size.y / vp.y)
	return maxf(d_h, d_v) * 1.05

## 盤の外周（ワールドxz）を画面へ投影した矩形。
func _projected_rect(mn: Vector2, mx: Vector2) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in [mn, Vector2(mx.x, mn.y), Vector2(mn.x, mx.y), mx]:
		var s := camera.unproject_position(Vector3(p.x, 0.0, p.y))
		lo = lo.min(s)
		hi = hi.max(s)
	return Rect2(lo, hi - lo)

## 投影した盤の中心を可視域の中心へ合わせる。px×world_per_pixel の線形換算ではなく、
## 「その画面位置の真下にある盤上の点」の差で動かす（zoom_at_point と同じ手）。
func _center_on(mn: Vector2, mx: Vector2, vis_rect: Rect2) -> void:
	var have := _plane_point(_projected_rect(mn, mx).get_center())
	var want := _plane_point(vis_rect.get_center())
	if not (have.is_finite() and want.is_finite()):
		return
	target += Vector3(have.x - want.x, 0.0, have.z - want.z)
	update_rig()

## 追従の行き先を収める範囲を hex ピクセル座標＋余白で渡す（保険＝盤の外へ飛ばさない）。
func set_focus_bounds(hex_min: Vector2, hex_max: Vector2, margin: float) -> void:
	focus_min = hex_min - Vector2(margin, margin)
	focus_max = hex_max + Vector2(margin, margin)

## points（主体の一覧・ワールド座標）が vis_rect 内の安全域(FOCUS_MARGIN 内側)に見えていなければ、
## そこへなめらかにパンする。すでに見えていれば何もしない。
func focus_on(points: Array[Vector3], vis_rect: Rect2) -> void:
	var dest := focus_dest(points, vis_rect, FOCUS_PULL_IN)
	if dest.is_equal_approx(target):
		return
	await pan_target_to(dest)

## 歩行中の追従（敵ターンの移動アニメ中に毎フレーム呼ぶ）。主体が安全域の縁に触れたら、
## はみ出す分だけ注視点を動かす＝縁に触れるまでは動かず、触れてからは駒と同じ速さで付いていく。
## 内側へ引き込まない（pull_in 0）＝引き込むと縁に触れた瞬間に画面が跳ぶ。Tween は使わず直接書く。
func follow(world_pos: Vector3, vis_rect: Rect2) -> void:
	var points: Array[Vector3] = [world_pos]
	var dest := focus_dest(points, vis_rect, 0.0)
	if dest.is_equal_approx(target):
		return
	_set_target(dest)

## focus_on の行き先（注視点）。points をまとめて安全域へ入れる。
## - 全部が安全域に入っていれば target のまま＝追わない（デッドゾーン）。
## - はみ出していれば、はみ出した軸だけ安全域の内側 pull_in まで入れる＝「最小限だけ動かす」。
## - ズームを変えずには入らない（外接矩形が安全域より大きい）／カメラの背後で手掛かりが無いなら、
##   points の中間を可視域の中央に置く＝2体が縁近くに来るが両方見える（doc/gdd/uiux.md 敵ターンのカメラ）。
## 動かす量は px から逆算せず、「寄せたい画面位置の真下にある盤上の点」をレイ交差で求め、主体との差だけ
## 注視点をずらす。リグは平行移動なので、この差分だけ動かせば主体はちょうどその画面位置に来る。
## px × world_per_pixel の線形近似は注視点の奥行きでしか合わず、画面の上下に離れた主体ほど
## 外れる（手前側では数十倍に膨らみ、盤の外まで飛んで真っ暗になる）。
## 2点以上のときは points[0]（行動主体）を基準に差分を取る＝主体は狙った画面位置に正確に来て、
## 相手は遠近のぶんだけずれる（pull_in の余裕で吸収する）。
func focus_dest(points: Array[Vector3], vis_rect: Rect2, pull_in: float) -> Vector3:
	var safe := vis_rect.grow(-FOCUS_MARGIN)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var behind := false
	for p in points:
		if camera.is_position_behind(p):
			behind = true
			break
		var sp := camera.unproject_position(p)
		lo = lo.min(sp)
		hi = hi.max(sp)
	var size := hi - lo
	if behind or size.x > safe.size.x or size.y > safe.size.y:
		var mid := Vector3.ZERO
		for p in points:
			mid += p
		mid /= float(points.size())
		return _dest_placing(mid, vis_rect.get_center())
	var shift := Vector2.ZERO
	if lo.x < safe.position.x - FOCUS_SLACK:
		shift.x = safe.position.x + minf(pull_in, safe.size.x - size.x) - lo.x
	elif hi.x > safe.end.x + FOCUS_SLACK:
		shift.x = safe.end.x - minf(pull_in, safe.size.x - size.x) - hi.x
	if lo.y < safe.position.y - FOCUS_SLACK:
		shift.y = safe.position.y + minf(pull_in, safe.size.y - size.y) - lo.y
	elif hi.y > safe.end.y + FOCUS_SLACK:
		shift.y = safe.end.y - minf(pull_in, safe.size.y - size.y) - hi.y
	if shift.is_zero_approx():
		return target  # 安全域に見えている＝追わない（デッドゾーン）
	var lead := points[0]
	return _dest_placing(lead, camera.unproject_position(lead) + shift)

## world_pos が画面位置 aim に来る注視点。行き先は盤の範囲（set_focus_bounds）で止める。
func _dest_placing(world_pos: Vector3, aim: Vector2) -> Vector3:
	var anchor := _plane_point(aim, world_pos.y)
	if not anchor.is_finite():
		return target
	var dest := target + Vector3(world_pos.x - anchor.x, 0.0, world_pos.z - anchor.z)
	dest.x = clampf(dest.x, focus_min.x, focus_max.x)
	dest.z = clampf(dest.z, focus_min.y, focus_max.y)
	return dest

## 注視点を dest へ Tween でなめらかに移す。完了まで待てる。
func pan_target_to(dest: Vector3) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_target, target, dest, pan_sec)
	_tween = t
	await t.finished

## 決着のとどめの寄せ＝注視点を world_pos へ移しつつ距離も詰める。完了まで待てる。
## プレイヤーの画角を奪う操作なので、使うのは決着した回だけ（以後の操作は無い）。
func zoom_to_finish(world_pos: Vector3) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var nd := clampf(dist * FINISH_ZOOM_FACTOR, FINISH_MIN_DIST, MAX_DIST)
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.set_parallel(true)
	t.tween_method(_set_target, target, Vector3(world_pos.x, 0.0, world_pos.z), FINISH_ZOOM_SEC)
	t.tween_method(_set_dist, dist, nd, FINISH_ZOOM_SEC)
	_tween = t
	await t.finished

## 着弾の揺れ（盤ぶん）。frustum offset で揺らす＝注視点は動かさない。
func shake(px: float = SHAKE_PX) -> void:
	if camera == null:
		return
	var d := px * world_per_pixel()
	var tw := create_tween()
	tw.tween_method(_set_shake, Vector2.ZERO, Vector2(-d, d * 0.5), SHAKE_STEP)
	tw.tween_method(_set_shake, Vector2(-d, d * 0.5), Vector2(d * 0.8, -d * 0.3), SHAKE_STEP)
	tw.tween_method(_set_shake, Vector2(d * 0.8, -d * 0.3), Vector2(-d * 0.4, -d * 0.2), SHAKE_STEP)
	tw.tween_method(_set_shake, Vector2(-d * 0.4, -d * 0.2), Vector2.ZERO, SHAKE_STEP)

# =========================================================================
# 内部
# =========================================================================

func _set_target(p: Vector3) -> void:
	target = p
	update_rig()

func _set_dist(v: float) -> void:
	dist = v
	update_rig()

func _set_shake(v: Vector2) -> void:
	if camera == null:
		return
	camera.h_offset = v.x
	camera.v_offset = v.y

## screen 直下の水平面(既定は盤面 y=0)上の点。ズームのカーソル基点と追従の基準に使う。
## plane_y は主体の高さ（起伏のぶん盤面より上）に合わせるために渡す。
func _plane_point(screen: Vector2, plane_y: float = 0.0) -> Vector3:
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	if absf(d.y) < 1e-6:
		return Vector3.INF
	var t := (plane_y - o.y) / d.y
	if t < 0.0:
		return Vector3.INF
	return o + d * t
