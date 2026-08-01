extends CanvasLayer
class_name CombatScene
## 戦闘演出シーン（第一版）。仕様 → doc/tech/combat_scene.md
## MatchController.combat_resolved(detail) を受け、プレイヤー左／敵右で隊列を並べ、
## シェイク＋フラッシュ＋損害数を出す。図は当面 map 画像を流用（正面向き・ミラー無し）。
## 窓と暗幕は盤エリア（UiLayout.board_area）だけを覆う＝右の InfoPanel は隠さず、
## 補正チェーンなどの詳細内訳を演出と同時に読めるようにする（演出=結果／右パネル=根拠）。
## 状態は持たず play(detail) のたびに detail から導出して描く。detail は BattleState.attack の "detail"。

signal finished  # 演出が閉じた（自動クローズ or クリック）。AIターンのテンポ制御が待つ。

const POS := [  # 散開スキャッター隊列（x:奥0→前1／y:上0→下1）。並び順=重心から近い順で兵数少でも中央に寄る。combat_scene.md
	# x で3列に分かれる（後列 0.12/0.23/0.34・中列 0.45/0.55・前列 0.66/0.77/0.88）。
	# 後列は y を大きく（画面下へ）、前列は y を小さく（画面上へ）取って、地面の傾きで寝ていた
	# 隊列を起こす＝3列が斜めに潰れず、前後の重なりが減る。
	Vector2(0.23, 0.62), Vector2(0.45, 0.36), Vector2(0.55, 0.68), Vector2(0.77, 0.42),
	Vector2(0.66, 0.10), Vector2(0.34, 0.94), Vector2(0.12, 0.30), Vector2(0.88, 0.74),
]
const SINGLE_POS := Vector2(0.50, 0.55)  # single（複製しない駒）の立ち位置。隊列の重心あたりに1体だけ置く
const SINGLE_SCALE := 1.4  # single だけ一段大きく描く（隊列8体ぶんの面積を1体で受けるので、等倍だと画が空く）
const MAX_TROOPS := 8  # 兵量バーの目盛り数＝戦闘ルールの上限（doc/gdd/combat.md）。POS の枠数と同じ
const GROUND_BLEED := 8.0  # 地面を窓より外へ広げる量（シェイクで縁が覗かないように）
const CORNER_CUT := 0.09   # 窓の角を落とす量（短辺に対する比）。横長八角形にする
const HAZE_COLOR := Color(0.05, 0.06, 0.09)  # 奥に敷く靄の色（わずかに寒色＝空気遠近）
const HAZE_ALPHA := 0.80                     # 最奥での濃さ
const EDGE_COLOR := Color(0, 0, 0, 0.55)  # 窓の縁取り
const EDGE_WIDTH := 2.0
## 地面（3D）は守り手の地形スキンで組む。タイル画像が引けないスキンのための下地色＝どの地形かは
## 分かるが「絵が無い」ことも分かる。仕様 → doc/tech/combat_scene.md
const TERRAIN_COLOR := {
	"plain": Color(0.56, 0.71, 0.42), "forest": Color(0.30, 0.49, 0.28),
	"mountain": Color(0.60, 0.55, 0.47), "plateau": Color(0.72, 0.65, 0.42),
	"wasteland": Color(0.71, 0.55, 0.40), "road": Color(0.62, 0.56, 0.45),
	"bush": Color(0.50, 0.60, 0.35), "fence": Color(0.55, 0.55, 0.58),
	"trap": Color(0.45, 0.42, 0.40), "rampart": Color(0.54, 0.56, 0.60),
	"cliff": Color(0.58, 0.54, 0.50), "wall": Color(0.52, 0.54, 0.58),
	"fort": Color(0.54, 0.57, 0.62),
}
const TEAM_COLOR := { 0: Color(0.18, 0.48, 0.84), 1: Color(0.86, 0.29, 0.29) }
const LEAD_IN := 0.8      # 突入から最初の着弾までの「ため」（秒）
const COUNTER_GAP := 0.1  # 攻撃側の着弾から反撃までの間（秒）
const FLIGHT := 0.2       # 飛び道具が攻撃側から被弾側へ届くまで（秒）。この間ぶん着弾＝損害表示も遅れる
const BURST := 0.30       # 重ねるエフェクトの拡大フェード時間（秒）
const STAGGER := 0.025    # エフェクト1発ごとの時差（秒）。同時に出すと1枚の大きな絵に見えて斉射・乱戦にならない
const FIG_H := 0.30   # 立ち絵の高さ（窓内寸の高さに対する比）。盤エリア窓化で横が詰まるぶん少し小さく（実機で調整）
const FIG_SCALE := 0.95  # 全図で一定の拡大率（列で変えず＝サイズを揃える。旧前列サイズ相当）
# 兵量バー（窓内寸に対する比）。両陣営に常時出す＝隊列が減る駒もバーだけの駒も損害の読み方を揃える。
const BAR_W := 0.30
const BAR_H := 0.028
const BAR_Y := 0.90
const BAR_FALL := 0.35  # 目盛りが減っていく時間（秒）
const BAR_BG := Color(0, 0, 0, 0.50)
const BAR_EDGE := Color(0, 0, 0, 0.65)

var _skins := {}
var _terrain_skins := {}  # Vector2i -> skin_id（ステージの見た目差分。地面のスキン解決に使う）
var _root: Control        # 全画面の入力キャッチ（モーダル）
var _backdrop: ColorRect  # 盤を薄暗くする幕
var _panel: Control       # 中央のモーダル窓（横長八角形。中身のクリップ元も兼ねる）
var _edge: Control        # 窓の縁取り（窓の上に重ねて描く＝地面に線が隠れない）
var _bg := Color(0.35, 0.38, 0.34)  # 窓の下地色（地形色。地面が敷けないときに見える）
var _inner: Control       # 窓の中身（地面＋図＋エフェクト）。シェイク対象
var _ground: CombatGround3D  # 地面（3D・盤と同じ地形タイル）
var _haze: TextureRect       # 奥を落とす縦グラデ（タイルの繰り返しを目立たせない）
var _fig := { "L": null, "R": null }  # 各サイドの図レイヤ（Control）
var _bar := { "L": null, "R": null }  # 各サイドの兵量バー（Control・立ち絵の上に重ねる）
var _bar_val := { "L": 0.0, "R": 0.0 }   # バーの表示値（減少をアニメさせるので float）
var _bar_team := { "L": 0, "R": 1 }      # バーの色（陣営）
var _bar_tween := { "L": null, "R": null }  # 減少アニメ（連戦で前の戦闘のぶんが残らないよう都度 kill）
var _shown := { "L": 0, "R": 0 }  # いま隊列に並んでいる数。エフェクトの発数はこれに合わせる（絵と食い違わせない）
var _fx: Control                       # フラッシュ・エフェクト・損害数
var _area: Vector2        # 窓の内寸（レイアウト基準）
var _tween: Tween
var _gen := 0  # play 世代（連続戦闘で古い自動クローズを無効化）

func _ready() -> void:
	_build()

## ノードツリーを1度だけ組む（_ready 前に play が来ても安全なよう遅延生成にも対応）。
func _build() -> void:
	if _root != null:
		return
	layer = 50  # 盤・HUD より前面
	_root = Control.new()
	# 入力キャッチも盤エリアだけ（矩形は _layout が決める）＝右の戦闘レポートのタブは演出中も押せる。
	# 盤エリア内のクリック＝スキップ。
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	add_child(_root)
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)  # _root（＝盤エリア）いっぱいに敷く
	_backdrop.color = Color(0, 0, 0, 0.45)  # 盤を薄暗く
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)
	# 中央のモーダル窓。八角形を自分で描き、それをマスクに中身（地面・立ち絵・エフェクト）を
	# 切り抜く＝角の外には盤の暗幕が覗く。シェイクのはみ出しもここで止まる。
	_panel = Control.new()
	_panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_window)
	_root.add_child(_panel)
	_inner = Control.new()  # 窓の中身（シェイク対象）
	_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_inner)
	# 地面はシェイク対象（_inner）の中＝立ち絵と一緒に揺れる（背景だけ止まって見えない）。
	_ground = CombatGround3D.new()
	_inner.add_child(_ground)
	_haze = TextureRect.new()
	_haze.texture = _make_haze()
	_haze.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_haze.stretch_mode = TextureRect.STRETCH_SCALE
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.add_child(_haze)
	for side in ["L", "R"]:
		var f := Control.new()
		f.set_anchors_preset(Control.PRESET_FULL_RECT)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inner.add_child(f)
		_fig[side] = f
	# バーは立ち絵より前面（隊列に隠れない）／エフェクトより後面（フラッシュは上から被せる）。
	for side in ["L", "R"]:
		var b := Control.new()
		b.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.draw.connect(_draw_bar.bind(side))
		_inner.add_child(b)
		_bar[side] = b
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.add_child(_fx)
	# 縁取りは窓の外（クリップの外側）に置く＝線が中身に半分食われない。
	_edge = Control.new()
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.draw.connect(_draw_edge)
	_root.add_child(_edge)
	visible = false

## 窓を盤エリア（右の情報ボックスを除く）の中央に配置し、内寸 _area を確定する（play のたびに再計算）。
## 暗幕も同じ盤エリアに絞る＝右の InfoPanel が覆われず、詳細内訳を演出中に読める。
func _layout() -> void:
	var vp := Vector2(1152, 648)
	var v := get_viewport()
	if v != null:
		vp = v.get_visible_rect().size
	var board := UiLayout.board_area(vp)
	_root.position = board.position
	_root.size = board.size  # 暗幕は FULL_RECT アンカーで _root に追従する
	_area = Vector2(min(board.size.x * 0.90, 740.0), min(board.size.y * 0.62, 520.0))
	_panel.size = _area
	_panel.position = ((board.size - _area) * 0.5).round()
	# 地面と靄は窓より少し大きく取る＝シェイクで縁に窓の下地が覗かない。
	# アンカーに任せず直に置く（_layout 直後に地面を組むので、親のサイズ反映を待てない）。
	var bleed := Vector2(GROUND_BLEED, GROUND_BLEED)
	_ground.position = -bleed
	_ground.size = _area + bleed * 2.0
	_haze.position = -bleed
	_haze.size = _area + bleed * 2.0
	_edge.position = _panel.position
	_edge.size = _area
	_panel.queue_redraw()
	_edge.queue_redraw()

func bind(skins: Dictionary) -> void:
	_skins = skins

## ステージの地形の見た目差分（座標→skin_id）。地面をどのスキンで組むかの解決に使う。
## ステージごとに変わるので load_stage が呼ぶ（盤の bind と同じ出どころ）。
func bind_terrain_skins(terrain_skins: Dictionary) -> void:
	_terrain_skins = terrain_skins

## 戦闘結果 detail を演出する。detail が空なら何もしない。
func play(detail: Dictionary) -> void:
	if detail == null or detail.is_empty():
		return
	_build()  # 未生成なら組む（結線タイミングに依存しない）
	var a: Dictionary = detail["attacker"]
	var t: Dictionary = detail["defender"]
	var counter: bool = detail.get("to_attacker") != null

	# 陣営で左右を固定（team0=左／team1=右）。攻撃側/防御側では入れ替えない。
	var L: Dictionary = a if int(a["team"]) == 0 else t
	var R: Dictionary = t if int(a["team"]) == 0 else a
	var atk_side := "L" if int(a["team"]) == 0 else "R"
	var def_side := "R" if int(a["team"]) == 0 else "L"

	_gen += 1
	var gen := _gen
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_clear(_fx)

	_layout()
	_bg = TERRAIN_COLOR.get(String(t.get("terrain", "")), Color(0.35, 0.38, 0.34))
	_panel.queue_redraw()
	_ground.build(_defender_skin(t), def_side)  # 地面は守り手の地形（攻撃側の地形は使わない）
	_render_side("L", L, int(L["troops_before"]))
	_render_side("R", R, int(R["troops_before"]))
	visible = true

	var def_dmg := int(t["troops_before"]) - int(t["troops_after"])
	var atk_dmg := int(a["troops_before"]) - int(a["troops_after"])
	var def_comb: Dictionary = R if def_side == "R" else L
	var atk_comb: Dictionary = L if atk_side == "L" else R
	var def_after := int(t["troops_after"])
	var atk_after := int(a["troops_after"])

	# ため：まず隊列を見せてから斬りかかる（突入直後に即着弾しない）。
	# 一撃は放ってから着弾するまで時間がかかる（飛翔＋発数ぶんの時差）。この遅れを後続にも
	# 足して、「攻撃側が着弾 → 反撃 → 幕引き」の順番が入れ替わらないようにする。
	_tween = create_tween()
	_tween.tween_interval(LEAD_IN)
	_tween.tween_callback(func() -> void:
		if gen == _gen:
			_strike_side(def_side, def_dmg, def_after, def_comb, atk_comb, gen))
	if counter:
		_tween.tween_interval(COUNTER_GAP + _strike_time(atk_comb, int(a["troops_before"])))
		_tween.tween_callback(func() -> void:
			if gen == _gen:
				_strike_side(atk_side, atk_dmg, atk_after, atk_comb, def_comb, gen))
		_tween.tween_interval(0.7 + _strike_time(def_comb, def_after))
	else:
		_tween.tween_interval(0.7 + _strike_time(atk_comb, int(a["troops_before"])))
	_tween.tween_callback(func() -> void:
		if gen == _gen:
			_dismiss())

## 片側への一撃。side＝被弾側、comb＝被弾側の駒、by＝殴った側の駒（エフェクトの持ち主）。
## エフェクトは殴った側の兵量ぶん出し、被弾側の隊列スロットへ配る（1発が1体に当たって見える）。
## 殴った側のほうが多いときはスロットを先頭から巡回する＝誰も居ない場所を斬らない。
## シェイク・フラッシュ・損害数・兵量バーは最後の1発が届いた時点に揃える。
func _strike_side(side: String, dmg: int, after: int, comb: Dictionary, by: Dictionary, gen: int) -> void:
	var eff := _effect_of(by)
	# 発数は「いま殴った側に並んでいる数」。反撃では既に減った後の隊列が振るので、
	# detail の戦闘前の兵量を使うと、2体しか居ないのに5発斬るような絵になる。
	var shots := clampi(int(_shown.get(_other_side(side), 1)), 1, POS.size())
	var targets := _troops_of(comb)
	var fly := eff != null and eff.is_projectile()
	for i in shots:
		var to := _slot_pos(side, POS[i % targets])
		var delay := float(i) * STAGGER
		if fly:
			_spawn_fly(_slot_pos(_other_side(side), POS[i]), to, eff, delay, gen)
		else:
			_spawn_burst(to, side == "L", eff, delay, gen)
	var tw := create_tween()
	tw.tween_interval(_strike_time(by, shots))
	tw.tween_callback(func() -> void:
		if gen != _gen:
			return  # スキップで閉じた後に飛来物が届いても何もしない
		_shake()
		_render_side(side, comb, after, true)
		_flash(side)
		if dmg > 0:
			_damage(side, dmg))

## 隊列スロットに収まる兵量（1〜8）。detail の値をそのまま信じず枠内に丸める。
func _troops_of(comb: Dictionary) -> int:
	return clampi(int(comb.get("troops_before", 1)), 1, POS.size())

## その一撃が「放ってから最後の1発が届く」までの時間。飛翔＋発数ぶんの時差。
## shots は殴る時点で並んでいる数（反撃は減った後の数）＝play が先に見積もって幕引きを合わせる。
func _strike_time(by: Dictionary, shots: int) -> float:
	var stagger := float(clampi(shots, 1, POS.size()) - 1) * STAGGER
	return stagger + (FLIGHT if _is_projectile(by) else 0.0)

func _other_side(side: String) -> String:
	return "R" if side == "L" else "L"

## 片側の隊列＋兵量バーを count 兵ぶんで描き直す。animate=true は着弾時（バーが減っていく）。
## 並べ方はスキンの combat_lineup：single は複製せず1体だけ（馬車・ドラゴン級＝兵として数えない駒）。
func _render_side(side: String, comb: Dictionary, count: int, animate: bool = false) -> void:
	var layer: Control = _fig[side]
	_clear(layer)
	var team := int(comb.get("team", 0))
	_shown[side] = count
	_set_bar(side, count, team, animate)
	var skin := _skin_of(comb)
	if skin != null and skin.is_single_figure():
		# 1体だけ＝損害で絵が減らないので、減り方は兵量バーが受け持つ。
		var at := _slot_pos(side, SINGLE_POS)
		_add_figure(layer, at.x, at.y, FIG_SCALE * SINGLE_SCALE, _texture_for(comb), team, comb)
		return
	var texs := _textures_for(comb, count)  # スロットごとの絵（先頭＝本人・以降は従者）
	var figs := []
	for i in count:
		var at := _slot_pos(side, POS[i])
		figs.append({ "cx": at.x, "feet": at.y, "s": FIG_SCALE, "tex": texs[i] })
	figs.sort_custom(func(u, v): return u["feet"] < v["feet"])  # 手前（下）を後に＝前面
	for f in figs:
		_add_figure(layer, f["cx"], f["feet"], f["s"], f["tex"], team, comb)

## 隊列の正規化座標（x:奥0→前1／y:上0→下1）→ 窓内の (中心x, 足元y)。
## 敵側は x を反転して中央（激突点）へ正対させる。地面の傾きぶん、前ほど足元を下げる。
func _slot_pos(side: String, p: Vector2) -> Vector2:
	var vp := _size()
	var cx := (vp.x * 0.06 + p.x * vp.x * 0.36) if side == "L" else (vp.x * 0.94 - p.x * vp.x * 0.36)
	var feet := vp.y * 0.38 + p.y * vp.y * 0.42 + p.x * vp.y * 0.16
	return Vector2(cx, feet)

## 兵量バーを count へ更新。animate なら現在値からアニメで落とす（着弾の手応え）。
## 開幕は snap＝前の戦闘の値から動かない（連戦で前のバーが残らないよう既存アニメは kill）。
func _set_bar(side: String, count: int, team: int, animate: bool) -> void:
	_bar_team[side] = team
	var prev: Tween = _bar_tween[side]
	if prev != null and prev.is_valid():
		prev.kill()
	if not animate:
		_set_bar_val(side, float(count))
		return
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _set_bar_val(side, v), float(_bar_val[side]), float(count), BAR_FALL)
	_bar_tween[side] = tw

func _set_bar_val(side: String, v: float) -> void:
	_bar_val[side] = v
	var c: Control = _bar[side]
	if c != null:
		c.queue_redraw()

## 兵量バー（8分割の刻み＝隊列8スロットと同じ数え方）。表示パターンに関わらず両陣営に常時出す。
## 仕様 → doc/tech/combat_scene.md「兵量バー」
func _draw_bar(side: String) -> void:
	var c: Control = _bar[side]
	if c == null:
		return
	var vp := _size()
	var w := vp.x * BAR_W
	var h := vp.y * BAR_H
	var cx := vp.x * 0.24 if side == "L" else vp.x * 0.76
	var origin := Vector2(cx - w * 0.5, vp.y * BAR_Y)
	var gap := 2.0
	var cell := (w - gap * (MAX_TROOPS - 1)) / MAX_TROOPS
	var col: Color = TEAM_COLOR.get(int(_bar_team[side]), Color(0.5, 0.5, 0.5))
	var val := float(_bar_val[side])
	for i in MAX_TROOPS:
		var slot := Rect2(Vector2(origin.x + i * (cell + gap), origin.y), Vector2(cell, h))
		c.draw_rect(slot, BAR_BG)  # 空の枠も見せる＝最大8のうち今いくつかが読める
		var f := clampf(val - float(i), 0.0, 1.0)
		if f > 0.0:
			c.draw_rect(Rect2(slot.position, Vector2(cell * f, h)), col.lightened(0.15))
		c.draw_rect(slot, BAR_EDGE, false, 1.0)

func _add_figure(layer: Control, cx: float, feet: float, s: float, tex: Texture2D, team: int, comb: Dictionary) -> void:
	var vp := _size()
	var w := vp.y * FIG_H * s
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tr.custom_minimum_size = Vector2(w, w)
		tr.size = Vector2(w, w)
		tr.position = Vector2(cx - w * 0.5, feet - w)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(tr)
	else:
		var panel := ColorRect.new()
		panel.color = TEAM_COLOR.get(team, Color(0.5, 0.5, 0.5))
		panel.size = Vector2(w * 0.7, w * 0.85)
		panel.position = Vector2(cx - w * 0.35, feet - w * 0.85)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lbl := Label.new()
		lbl.text = _placeholder_label(comb)
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", int(max(11.0, w * 0.22)))
		panel.add_child(lbl)
		layer.add_child(panel)

## 隊列スロットごとの立ち絵。先頭は必ず本人で、2体目以降は従者（スキンの retainers）を
## 順に巡回して割り当てる。retainers が空なら全部本人＝従来どおりの見た目。
## ボス＋手下の一団を、絵を足さずに既存スキンの組み合わせで作るための仕組み。仕様 → doc/tech/combat_scene.md
func _textures_for(comb: Dictionary, count: int) -> Array:
	var own := _texture_for(comb)
	var skin := _skin_of(comb)
	var list: Array = skin.retainers if skin != null else []
	var out := []
	for i in count:
		if i == 0 or list.is_empty():
			out.append(own)
		else:
			out.append(_retainer_texture(String(list[(i - 1) % list.size()]), own))
	return out

## 従者1体ぶんの立ち絵。スキンが引けない／絵が無い場合は本人の絵で埋める（穴を空けない）。
func _retainer_texture(skin_id: String, fallback: Texture2D) -> Texture2D:
	var s: UnitSkin = SkinCatalog.skin_by_id(_skins, skin_id)
	if s == null:
		return fallback
	var tex := _skin_texture(s)
	return tex if tex != null else fallback

func _texture_for(comb: Dictionary) -> Texture2D:
	var skin := _skin_of(comb)
	return _skin_texture(skin) if skin != null else null

## スキンの立ち絵。combat スロット優先、無ければ map 画像を流用（本番アートが来るまでの繋ぎ）。
func _skin_texture(skin: UnitSkin) -> Texture2D:
	var p := skin.image("combat")
	if p == "":
		p = skin.image("map")
	if p != "" and ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

func _skin_of(comb: Dictionary) -> UnitSkin:
	return SkinCatalog.resolve(_skins, String(comb.get("skin_id", "")), String(comb["type_id"]), int(comb["team"]))

func _placeholder_label(comb: Dictionary) -> String:
	var skin := _skin_of(comb)
	return skin.combat_label() if skin != null else String(comb.get("type_id", "?"))

## 窓の形＝角を落とした横長八角形（左上から時計回り）。中身のクリップ形状も縁取りもこれ1つで決まる。
func _window_shape(sz: Vector2) -> PackedVector2Array:
	var c := minf(sz.x, sz.y) * CORNER_CUT
	return PackedVector2Array([
		Vector2(c, 0), Vector2(sz.x - c, 0), Vector2(sz.x, c), Vector2(sz.x, sz.y - c),
		Vector2(sz.x - c, sz.y), Vector2(c, sz.y), Vector2(0, sz.y - c), Vector2(0, c),
	])

## 窓の下地（地形色）。この描画がそのまま中身のクリップ形状になる（CLIP_CHILDREN_AND_DRAW）。
func _draw_window() -> void:
	_panel.draw_colored_polygon(_window_shape(_panel.size), _bg)

## 窓の縁取り（八角形の枠）。閉じるため始点を末尾にもう一度足す。
func _draw_edge() -> void:
	var pts := _window_shape(_edge.size)
	pts.append(pts[0])
	_edge.draw_polyline(pts, EDGE_COLOR, EDGE_WIDTH, true)

## 守り手の地形スキン（地面の材料）。ステージの見た目差分を優先し、無ければ地形の既定スキン。
## pos が来ない古い detail でも既定スキンには落ちる（平地/雪原の別は付かないが地面は出る）。
func _defender_skin(t: Dictionary) -> TerrainSkin:
	var pos: Variant = t.get("pos")
	var skin_id := ""
	if typeof(pos) == TYPE_VECTOR2I:
		skin_id = String(_terrain_skins.get(pos, ""))
	return TerrainSkinCatalog.resolve(skin_id, String(t.get("terrain", "")))

## 奥（画面上）を落とす縦グラデ。距離感を出しつつ、遠くのタイルの繰り返しを目立たせない。
## 立ち絵より下のレイヤーに敷くので、隊列は暗くならず地面だけが奥へ沈む。
func _make_haze() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.30, 0.78])
	g.colors = PackedColorArray([
		Color(HAZE_COLOR, HAZE_ALPHA),          # 最奥
		Color(HAZE_COLOR, HAZE_ALPHA * 0.55),   # 中景（落ち方を緩めて帯にしない）
		Color(HAZE_COLOR, 0.0),                 # 手前は素通し
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 8
	t.height = 128
	return t

func _flash(side: String) -> void:
	var vp := _size()
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.55)
	r.size = Vector2(vp.x * 0.5, vp.y)
	r.position = Vector2(0 if side == "L" else vp.x * 0.5, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.28)
	tw.tween_callback(r.queue_free)

## 殴った側のエフェクト定義。スキン未設定・未定義IDなら null＝既定のスパークで出す。
func _effect_of(comb: Dictionary) -> CombatEffect:
	var skin := _skin_of(comb)
	if skin == null:
		return null
	return CombatEffectCatalog.by_id(skin.combat_effect)

func _is_projectile(comb: Dictionary) -> bool:
	var e := _effect_of(comb)
	return e != null and e.is_projectile()

## エフェクト1個ぶんのノード。絵が置かれていなければ既定のスパーク（星）を描く＝穴が開かない。
## 大きさは「被弾側の立ち絵1体ぶんの幅 × カタログの scale」。絵は余白を切り詰めて作る約束なので、
## 大小の差は画像ではなく scale で付ける（切り詰めた絵をそのまま並べると全部同じ幅になる）。
func _effect_node(eff: CombatEffect) -> Node2D:
	var tex: Texture2D = null
	if eff != null:
		var p := eff.image_path()
		if p != "" and ResourceLoader.exists(p):
			tex = load(p) as Texture2D
	if tex == null:
		var star := Polygon2D.new()
		star.polygon = _star_points(26.0, 11.0)
		star.color = Color(0.98, 0.78, 0.29)
		return star
	var s := Sprite2D.new()
	s.texture = tex
	# 基準は長辺。幅で揃えると、縦長の斬撃が縦にはみ出し、横長の矢と釣り合わない。
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	if longest > 0.0:
		s.scale = Vector2.ONE * (_size().y * FIG_H * FIG_SCALE * eff.scale / longest)
	return s

## 重ねる型を1発：被弾側のスロットの上で拡大しながら消える。
## 絵は「右へ向かう一撃」で描く約束なので、左を殴るとき（＝攻撃側が右）だけ水平反転する。
## 飛ぶ型と同じ向きの規約＝どちらも1枚で両陣営に使える。
func _spawn_burst(at: Vector2, mirror: bool, eff: CombatEffect, delay: float, gen: int) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		if gen != _gen:
			return
		var node := _effect_node(eff)
		node.position = at
		if mirror:
			node.scale.x = -node.scale.x
		var base := node.scale
		node.scale = base * 0.4
		_fx.add_child(node)
		var t2 := create_tween()
		t2.set_parallel(true)
		t2.tween_property(node, "scale", base * 1.6, BURST)
		t2.tween_property(node, "modulate:a", 0.0, BURST)
		t2.chain().tween_callback(node.queue_free))

## 飛ぶ型を1発：殴った側のスロットから被弾側のスロットへ飛び、着弾で消える。
## 絵は右向きに描く約束なので、左へ飛ぶときだけ水平反転する（1枚で両陣営に使える）。
func _spawn_fly(from: Vector2, to: Vector2, eff: CombatEffect, delay: float, gen: int) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		if gen != _gen:
			return
		var node := _effect_node(eff)
		node.position = from
		if to.x < from.x:
			node.scale.x = -node.scale.x
		_fx.add_child(node)
		var t2 := create_tween()
		t2.tween_property(node, "position", to, FLIGHT)
		t2.tween_callback(node.queue_free))

func _damage(side: String, dmg: int) -> void:
	var vp := _size()
	var lbl := Label.new()
	lbl.text = "-%d" % dmg
	lbl.add_theme_font_size_override("font_size", int(vp.y * 0.09))
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	lbl.add_theme_color_override("font_outline_color", Color(0.47, 0.12, 0.12))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cx := vp.x * 0.28 if side == "L" else vp.x * 0.72
	lbl.position = Vector2(cx - vp.x * 0.06, vp.y * 0.30)
	_fx.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", vp.y * 0.20, 0.55)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.55).set_delay(0.15)
	tw.chain().tween_callback(lbl.queue_free)

func _shake() -> void:
	var tw := create_tween()
	tw.tween_property(_inner, "position", Vector2(-6, 3), 0.05)
	tw.tween_property(_inner, "position", Vector2(5, -2), 0.05)
	tw.tween_property(_inner, "position", Vector2(-3, -1), 0.05)
	tw.tween_property(_inner, "position", Vector2.ZERO, 0.05)

func _star_points(outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		var ang := PI * i / 4.0
		var rad := outer if i % 2 == 0 else inner
		pts.append(Vector2(cos(ang) * rad, sin(ang) * rad))
	return pts

func _on_root_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		_dismiss()  # クリックで即スキップ

func _dismiss() -> void:
	if not visible:
		return  # 二重クローズ（クリック＋自動）で finished を重ねない
	_gen += 1  # 進行中の自動クローズを無効化
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_inner.position = Vector2.ZERO
	visible = false
	finished.emit()

func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()

func _size() -> Vector2:
	return _area if _area != Vector2.ZERO else Vector2(980, 560)  # 窓の内寸（レイアウト基準）
