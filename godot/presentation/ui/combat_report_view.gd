extends Control
class_name CombatReportView
## 戦闘レポート（右パネル）。演出シーンと同じ detail（BattleState.attack の "detail"）を
## 「サマリー（表）／攻撃／反撃」の3タブで見せる。
## サマリー＝ユーザーが見える特徴の左右比較（式は出さない）。左右は陣営で固定
## （自軍左・敵右）＝戦闘演出シーンと同じ並び。仕様 → doc/tech/combat_scene.md
## 攻撃・反撃＝打撃の向きごとの数式チェーン（左＝打つ側の攻撃力・右＝受ける側の防御力・下＝損害）。
## こちらの左右は陣営でなく式の順（攻÷防）で固定＝攻撃する側が常に左。
## 攻/防のペア表記（地形・支援・バフ）は常に「攻/防」の順。

## 3列の表の組み立てと値の整形は StrikeTable（スキルレポートと共通部品）。色・列幅もそちらが持つ。
const TEAM_COLOR := { 0: Color(0.18, 0.48, 0.84), 1: Color(0.86, 0.29, 0.29) }
const NONE := StrikeTable.NONE
const FIG_SIZE := 96.0        # ユニットの絵の一辺
const TAB_MIN_W := 120.0      # タブ1枚の最低幅

var _skins := {}
var _detail := {}
var _tabs := {}  # "summary"/"attack"/"counter" -> Button
var _tab := "summary"  # いま出しているタブ。言語が変わったとき同じタブで描き直すのに使う

## タブの id と文言キー。見出しは _ready で焼き込む＝言語が変わったら refresh_labels で貼り直す。
const TABS := [["summary", "ui.report.tab_summary"], ["attack", "ui.report.tab_attack"],
		["counter", "ui.report.tab_counter"]]
var _summary: GridContainer
var _side_head: Label
var _detail_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 押下は板（UnitInfoPanel）へ通す＝レポートの上を掴んでも板が動く
	var v := VBoxContainer.new()
	add_child(v)
	# アンカーは add_child 後に明示設定（親 Panel の看板幅いっぱいに広げる）
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 10
	v.offset_right = -12
	v.offset_bottom = -10
	v.add_theme_constant_override("separation", 8)
	# タブ（トグル＋グループ＝押し込まれた板が選択中）。戦闘のたびにサマリーへ戻す。
	var tabs := HBoxContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_theme_constant_override("separation", 6)
	v.add_child(tabs)
	var group := ButtonGroup.new()
	for t in TABS:
		var b := TavernTheme.wood_button(tr(t[1]))
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(TAB_MIN_W, 0)
		b.pressed.connect(_show_tab.bind(t[0]))
		tabs.add_child(b)
		_tabs[t[0]] = b
	_side_head = Label.new()  # 攻撃/反撃タブの見出し（どの向きの打撃か）
	_side_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side_head.hide()
	v.add_child(_side_head)
	# サマリーも攻撃/反撃も同じ3列の表を使い回す（中＝項目名）。
	_summary = GridContainer.new()
	_summary.columns = 3
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.add_theme_constant_override("h_separation", 8)
	_summary.add_theme_constant_override("v_separation", 4)
	v.add_child(_summary)
	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 表の下の補足＝表より一段小さく（中央のラベル12・値14と同じ型づかい）。
	_detail_label.add_theme_font_size_override("font_size", 13)
	_detail_label.add_theme_color_override("font_color", StrikeTable.VALUE_COLOR)
	v.add_child(_detail_label)

func bind(skins: Dictionary) -> void:
	_skins = skins

## 戦闘結果 detail を表示する（毎回サマリータブへリセット）。
func show_report(detail: Dictionary) -> void:
	if detail == null or detail.is_empty():
		return
	_detail = detail
	var b: Button = _tabs["summary"]
	b.button_pressed = true
	_show_tab("summary")

## 言語が変わったので文言を貼り直す（doc/tech/i18n.md 言語の切り替え）。
## タブ見出しに加え、出している内訳も同じ detail から組み直す（作り直しはしない）。
func refresh_labels() -> void:
	for t in TABS:
		var b: Button = _tabs[String(t[0])]
		b.text = tr(String(t[1]))
	_show_tab(_tab)

func _show_tab(id: String) -> void:
	if _detail.is_empty():
		return
	_tab = id
	_side_head.visible = id != "summary"
	if id == "summary":
		_rebuild_summary()
		_detail_label.text = ""
	else:
		_rebuild_direction(id == "attack")

# --- 表示の左右解決 ---

## 表示サイドの束を組む。snap＝スナップショット／atk・def＝その側が実際に使った内訳
## （反撃なしの向きは空 dict＝表示は「反撃なし」や「—」で描き分ける）。
func _sides() -> Dictionary:
	var a: Dictionary = _detail["attacker"]
	var t: Dictionary = _detail["defender"]
	var fwd: Dictionary = _detail["to_defender"]
	var ret: Variant = _detail["to_attacker"]
	var atk_side := {
		"snap": a, "is_attacker": true,
		"atk": fwd["attack"],
		"def": (ret["defense"] if ret != null else {}),
	}
	var def_side := {
		"snap": t, "is_attacker": false,
		"atk": (ret["attack"] if ret != null else {}),
		"def": fwd["defense"],
	}
	var left := atk_side if int(a["team"]) == 0 else def_side
	var right := def_side if int(a["team"]) == 0 else atk_side
	return {"left": left, "right": right}

# --- サマリー（表） ---

func _rebuild_summary() -> void:
	for c in _summary.get_children():
		_summary.remove_child(c)  # queue_free 待ちの旧行が新行と同居して1フレーム崩れるのを避ける
		c.queue_free()
	var s := _sides()
	var L: Dictionary = s["left"]
	var R: Dictionary = s["right"]
	var ls: Dictionary = L["snap"]
	var rs: Dictionary = R["snap"]
	_add_control_row(_figure(ls), "", _figure(rs))
	_add_row(_name_lv(ls), "", _name_lv(rs))
	_add_row(_troops_text(ls), tr("ui.report.strength_change"), _troops_text(rs))
	_add_row(_total_text(L["atk"], tr("ui.report.no_counter")), tr("ui.report.total_atk"), _total_text(R["atk"], tr("ui.report.no_counter")))
	_add_row(_total_text(L["def"], NONE), tr("ui.report.total_def"), _total_text(R["def"], NONE))
	_add_row(_base_atk_text(L["atk"]), tr("ui.report.attack"), _base_atk_text(R["atk"]))
	_add_row(_base_def_text(L["def"]), tr("ui.report.defense"), _base_def_text(R["def"]))
	_add_row(_terrain_text(ls), tr("ui.report.terrain"), _terrain_text(rs))
	# 包囲・支援は常設行＝行の有無で「効いたか」を探させない。効いていなければ — 表示。
	_add_row(_factor_text(_surround_of(L)), tr("ui.report.encircled"), _factor_text(_surround_of(R)))
	_add_row(_support_text(L), tr("ui.report.support"), _support_text(R))
	_add_status_rows(ls, rs)

## バフ行（両側の statuses を行単位でペアにする。数が違う側は空欄）。
func _add_status_rows(ls: Dictionary, rs: Dictionary) -> void:
	var lst: Array = ls.get("statuses", [])
	var rst: Array = rs.get("statuses", [])
	for i in maxi(lst.size(), rst.size()):
		var lt: String = status_text(lst[i]) if i < lst.size() else ""
		var rt: String = status_text(rst[i]) if i < rst.size() else ""
		_add_row(lt, tr("ui.report.buff") if i == 0 else "", rt)

func _add_row(lt: String, label: String, rt: String) -> void:
	StrikeTable.add_row(_summary, lt, label, rt)

func _add_control_row(left: Control, label: String, right: Control) -> void:
	StrikeTable.add_control_row(_summary, left, label, right)

## ユニットの絵（combat スロット優先・map 代用＝演出シーンと同じ解決）。無ければ陣営色の板。
func _figure(snap: Dictionary) -> Control:
	var tex := _texture_of(snap)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(FIG_SIZE, FIG_SIZE)
		return tr
	var box := ColorRect.new()
	box.color = TEAM_COLOR.get(int(snap.get("team", 0)), Color(0.5, 0.5, 0.5))
	box.custom_minimum_size = Vector2(FIG_SIZE, FIG_SIZE)
	return box

func _texture_of(snap: Dictionary) -> Texture2D:
	var skin: UnitSkin = SkinCatalog.resolve(_skins, String(snap.get("skin_id", "")), String(snap["type_id"]), int(snap["team"]))
	if skin == null:
		return null
	var p := skin.image("combat")
	if p == "":
		p = skin.image("map")
	if p != "" and ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

func _display_name(snap: Dictionary) -> String:
	return StrikeTable.display_name(_skins, snap)

func _name_lv(snap: Dictionary) -> String:
	return tr("ui.report.name_lv") % [_display_name(snap), int(snap["level"])]

func _troops_text(snap: Dictionary) -> String:
	return "%d/%d → %d/%d" % [snap["troops_before"], snap["max"], snap["troops_after"], snap["max"]]

func _total_text(bd: Dictionary, empty_text: String) -> String:
	return StrikeTable.total_text(bd, empty_text)

func _base_atk_text(bd: Dictionary) -> String:
	if bd.is_empty():
		return NONE
	return StrikeTable.atk_stat_text(bd)

func _base_def_text(bd: Dictionary) -> String:
	return String.num_int64(int(bd["stat"])) if not bd.is_empty() else NONE

func _terrain_text(snap: Dictionary) -> String:
	var terr := String(snap["terrain"])
	return "%s ×%.2f/×%.2f" % [tr("terrain_type." + terr + ".name"), TerrainType.attack_factor(terr), TerrainType.defense_factor(terr)]

## 包囲は攻防共通の係数＝どちらかの内訳から取り出す（反撃なし側は攻が空）。
func _surround_of(side: Dictionary) -> float:
	var atk: Dictionary = side["atk"]
	var bd: Dictionary = atk if not atk.is_empty() else side["def"]
	return float(bd.get("surround", 1.0))

func _factor_text(f: float) -> String:
	return "×%.2f" % f if not is_equal_approx(f, 1.0) else NONE

## 支援（攻/防の加算ペア）。両方 0 なら NONE（行は常設＝効果なしの表示）。
func _support_text(side: Dictionary) -> String:
	var atk: Dictionary = side["atk"]
	var def: Dictionary = side["def"]
	var sa := roundi(float(atk.get("support", 0.0)))
	var sd := roundi(float(def.get("support", 0.0)))
	if sa == 0 and sd == 0:
		return NONE
	return "%s/%s" % [("+%d" % sa) if sa != 0 else NONE, ("+%d" % sd) if sd != 0 else NONE]

## バフ1件の表記（例: グレイス ×1.30/×1.30、ピクシーダスト +80/+80）。
## target で攻/防の効き先を描き分ける。
static func status_text(m: Dictionary) -> String:
	var nm := String(m.get("name", ""))
	if nm.is_empty():
		nm = TranslationServer.translate("ui.report.modifier_unnamed")  # static なので tr() は使えない
	# 継続ダメージは攻防に効かない＝攻/防の2列に置けない。毎ターン何人減るかをそのまま出す。
	if StatusMod.is_dot(m):
		return TranslationServer.translate("ui.report.status_dot") % [nm, int(m.get("value", 0))]
	var eff: String
	if String(m.get("op", "mul")) == "mul":
		eff = "×%.2f" % float(m.get("value", 1.0))
	else:
		eff = "%+d" % roundi(float(m.get("value", 0.0)))
	var t := String(m.get("target", "both"))
	var atk_part := eff if t != "defense" else NONE
	var def_part := eff if t != "attack" else NONE
	return "%s %s/%s" % [nm, atk_part, def_part]

# --- 攻撃／反撃タブ（1回の打撃の内訳）。サマリーと同じ3列の表で、係数を1行1項目で並べる ---
# 左＝打つ側の攻撃力の積み上げ／中＝項目名／右＝受ける側の防御力の積み上げ。下の損害の式に
# 入る2つの実効値が同じ画面に並ぶ＝1タブで「誰の攻撃 × 誰の防御 ＝ 結果」が完結する。
# 攻撃タブ＝往路（攻撃側→守備側）、反撃タブ＝復路。

func _rebuild_direction(forward: bool) -> void:
	for c in _summary.get_children():
		_summary.remove_child(c)
		c.queue_free()
	var a: Dictionary = _detail["attacker"]
	var t: Dictionary = _detail["defender"]
	var hit: Variant = _detail["to_defender"] if forward else _detail["to_attacker"]
	var striker: Dictionary = a if forward else t
	var victim: Dictionary = t if forward else a
	var sn := _display_name(striker)
	var vn := _display_name(victim)
	_side_head.text = tr("ui.report.head_attack" if forward else "ui.report.head_counter") % [sn, vn]
	if hit == null:
		_detail_label.text = tr("ui.report.no_counter_reason")
		return
	# 表と損害の式は StrikeTable（スキルレポートと共通部品）。損害の出し方は左右に割らず、
	# 幅いっぱいで式に数字を入れて見せる＝表の2つの実効値がそのまま式に入るのを見せる。
	StrikeTable.fill(_summary, sn, vn, hit)
	_detail_label.text = "\n".join(StrikeTable.damage_lines(vn, hit, int(victim["troops_before"])))

