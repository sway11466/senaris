extends CanvasLayer
class_name CombatScene
## 戦闘演出シーン（第一版）。仕様 → doc/tech/combat_scene.md
## MatchController.combat_resolved(detail) を受け、プレイヤー左／敵右で隊列を並べ、
## シェイク＋フラッシュ＋損害数を出す。図は当面 map 画像を流用（正面向き・ミラー無し）。
## 状態は持たず play(detail) のたびに detail から導出して描く。detail は BattleState.attack の "detail"。

signal finished  # 演出が閉じた（自動クローズ or クリック）。AI手番のテンポ制御が待つ。

const POS := [  # 3-2-3 隊列テンプレ（x:奥0→前1／y:上0→下1）。slot1=後列中央。combat_scene.md
	Vector2(0.18, 0.55), Vector2(0.15, 0.30), Vector2(0.15, 0.80),
	Vector2(0.50, 0.40), Vector2(0.50, 0.66),
	Vector2(0.85, 0.30), Vector2(0.85, 0.55), Vector2(0.85, 0.80),
]
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

var _skins := {}
var _root: Control        # 全画面の入力キャッチ（モーダル）
var _backdrop: ColorRect  # 盤を薄暗くする幕
var _panel: Panel         # 中央のモーダル窓（地形色＝StyleBox）
var _style: StyleBoxFlat  # 窓の背景（地形色を差し替える）
var _inner: Control       # 窓の中身（図＋エフェクト）。シェイク対象
var _fig := { "L": null, "R": null }  # 各サイドの図レイヤ（Control）
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
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # 表示中は盤入力を食う（モーダル）
	_root.gui_input.connect(_on_root_input)
	add_child(_root)
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0, 0, 0, 0.45)  # 盤を薄暗く
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)
	_panel = Panel.new()  # 中央のモーダル窓
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.35, 0.38, 0.34)
	_style.set_corner_radius_all(10)
	_style.border_color = Color(0, 0, 0, 0.55)
	_style.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", _style)
	_panel.clip_contents = true  # 窓外にはみ出さない（シェイクも窓内で）
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)
	_inner = Control.new()  # 窓の中身（シェイク対象）
	_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_inner)
	for side in ["L", "R"]:
		var f := Control.new()
		f.set_anchors_preset(Control.PRESET_FULL_RECT)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inner.add_child(f)
		_fig[side] = f
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.add_child(_fx)
	visible = false

## 窓を画面中央に配置し、内寸 _area を確定する（play のたびに再計算）。
func _layout() -> void:
	var vp := Vector2(1152, 648)
	var v := get_viewport()
	if v != null:
		vp = v.get_visible_rect().size
	_area = Vector2(min(vp.x * 0.82, 980.0), min(vp.y * 0.60, 560.0))
	_panel.size = _area
	_panel.position = ((vp - _area) * 0.5).round()

func bind(skins: Dictionary) -> void:
	_skins = skins

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
	_style.bg_color = TERRAIN_COLOR.get(String(t.get("terrain", "")), Color(0.35, 0.38, 0.34))
	_render_side("L", L, int(L["troops_before"]))
	_render_side("R", R, int(R["troops_before"]))
	visible = true

	var def_dmg := int(t["troops_before"]) - int(t["troops_after"])
	var atk_dmg := int(a["troops_before"]) - int(a["troops_after"])
	_shake()
	_strike_side(def_side, def_dmg, int(t["troops_after"]), R if def_side == "R" else L)

	_tween = create_tween()
	if counter:
		_tween.tween_interval(0.18)
		_tween.tween_callback(func() -> void:
			if gen == _gen:
				_shake()
				_strike_side(atk_side, atk_dmg, int(a["troops_after"]), L if atk_side == "L" else R))
	_tween.tween_interval(0.7)
	_tween.tween_callback(func() -> void:
		if gen == _gen:
			_dismiss())

## 片側に着弾：フラッシュ＋エフェクト＋損害数＋図を after へ更新。
func _strike_side(side: String, dmg: int, after: int, comb: Dictionary) -> void:
	_render_side(side, comb, after)
	_flash(side)
	_spark(side)
	if dmg > 0:
		_damage(side, dmg)

func _render_side(side: String, comb: Dictionary, count: int) -> void:
	var layer: Control = _fig[side]
	_clear(layer)
	var vp := _size()
	var tex := _texture_for(comb)
	var team := int(comb.get("team", 0))
	var figs := []
	for i in count:
		var p: Vector2 = POS[i]
		var s := 0.65 + 0.35 * p.x
		var cx := (vp.x * 0.06 + p.x * vp.x * 0.36) if side == "L" else (vp.x * 0.94 - p.x * vp.x * 0.36)
		var feet := vp.y * 0.30 + p.y * vp.y * 0.42 + p.x * vp.y * 0.16
		figs.append({ "cx": cx, "feet": feet, "s": s })
	figs.sort_custom(func(u, v): return u["feet"] < v["feet"])  # 手前（下）を後に＝前面
	for f in figs:
		_add_figure(layer, f["cx"], f["feet"], f["s"], tex, team, comb)

func _add_figure(layer: Control, cx: float, feet: float, s: float, tex: Texture2D, team: int, comb: Dictionary) -> void:
	var vp := _size()
	var w := vp.y * 0.20 * s
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

func _texture_for(comb: Dictionary) -> Texture2D:
	var skin: UnitSkin = SkinCatalog.resolve(_skins, String(comb.get("skin_id", "")), String(comb["type_id"]), int(comb["team"]))
	if skin == null:
		return null
	var p := skin.image("combat")  # 本番アートが来れば combat スロット優先
	if p == "":
		p = skin.image("map")       # 当面は map 画像を流用
	if p != "" and ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

func _placeholder_label(comb: Dictionary) -> String:
	var skin: UnitSkin = SkinCatalog.resolve(_skins, String(comb.get("skin_id", "")), String(comb["type_id"]), int(comb["team"]))
	return skin.combat_label() if skin != null else String(comb.get("type_id", "?"))

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

func _spark(side: String) -> void:
	var vp := _size()
	var cx := vp.x * 0.28 if side == "L" else vp.x * 0.72
	var star := Polygon2D.new()
	star.polygon = _star_points(26.0, 11.0)
	star.color = Color(0.98, 0.78, 0.29)
	star.position = Vector2(cx, vp.y * 0.5)
	star.scale = Vector2(0.4, 0.4)
	_fx.add_child(star)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(star, "scale", Vector2(1.6, 1.6), 0.30)
	tw.tween_property(star, "modulate:a", 0.0, 0.30)
	tw.chain().tween_callback(star.queue_free)

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
