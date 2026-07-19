extends Control
class_name CombatReportView
## 戦闘レポート（右パネル）。演出シーンと同じ detail（BattleState.attack の "detail"）を
## 「サマリー（表）／攻撃側詳細／守備側詳細」の3タブで見せる。
## サマリー＝ユーザーが見える特徴の左右比較（式は出さない）、詳細＝数式チェーン（数字の根拠）。
## 左右は陣営で固定（自軍左・敵右）＝戦闘演出シーンと同じ並び。仕様 → doc/tech/combat_scene.md
## 攻/防のペア表記（地形・支援・バフ）は常に「攻/防」の順。

const VALUE_COLOR := Color(0.96, 0.93, 0.86)
const LABEL_COLOR := Color(0.72, 0.64, 0.50)
const TEAM_COLOR := { 0: Color(0.18, 0.48, 0.84), 1: Color(0.86, 0.29, 0.29) }
const NONE := "—"
const FIG_SIZE := 72.0

var _skins := {}
var _detail := {}
var _tabs := {}  # "summary"/"attacker"/"defender" -> Button
var _summary: GridContainer
var _detail_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 10
	v.offset_right = -12
	v.offset_bottom = -10
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	# タブ（トグル＋グループ＝押し込まれた板が選択中）。戦闘のたびにサマリーへ戻す。
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	v.add_child(tabs)
	var group := ButtonGroup.new()
	for t in [["summary", "サマリー"], ["attacker", "攻撃側"], ["defender", "守備側"]]:
		var b := TavernTheme.wood_button(t[1])
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_show_tab.bind(t[0]))
		tabs.add_child(b)
		_tabs[t[0]] = b
	_summary = GridContainer.new()
	_summary.columns = 3
	_summary.add_theme_constant_override("h_separation", 8)
	_summary.add_theme_constant_override("v_separation", 4)
	v.add_child(_summary)
	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

func _show_tab(id: String) -> void:
	if _detail.is_empty():
		return
	_summary.visible = id == "summary"
	_detail_label.visible = id != "summary"
	if id == "summary":
		_rebuild_summary()
	else:
		_detail_label.text = _format_side_detail(id == "attacker")

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
	_add_row(_troops_text(ls), "兵量", _troops_text(rs))
	_add_row(_total_text(L["atk"], "反撃なし"), "総攻撃", _total_text(R["atk"], "反撃なし"))
	_add_row(_total_text(L["def"], NONE), "総防御", _total_text(R["def"], NONE))
	_add_row(_base_atk_text(L["atk"]), "攻撃", _base_atk_text(R["atk"]))
	_add_row(_base_def_text(L["def"]), "防御", _base_def_text(R["def"]))
	_add_row(_terrain_text(ls), "地形", _terrain_text(rs))
	# ここから下は効いているときだけの行（両側とも素通しなら出さない＝サマリーを薄めない）
	var lsur := _surround_of(L)
	var rsur := _surround_of(R)
	if not (is_equal_approx(lsur, 1.0) and is_equal_approx(rsur, 1.0)):
		_add_row(_factor_text(lsur), "包囲", _factor_text(rsur))
	var lsup := _support_text(L)
	var rsup := _support_text(R)
	if lsup != NONE or rsup != NONE:
		_add_row(lsup, "支援", rsup)
	_add_status_rows(ls, rs)

## バフ行（両側の statuses を行単位でペアにする。数が違う側は空欄）。
func _add_status_rows(ls: Dictionary, rs: Dictionary) -> void:
	var lst: Array = ls.get("statuses", [])
	var rst: Array = rs.get("statuses", [])
	for i in maxi(lst.size(), rst.size()):
		var lt: String = _status_text(lst[i]) if i < lst.size() else ""
		var rt: String = _status_text(rst[i]) if i < rst.size() else ""
		_add_row(lt, "バフ" if i == 0 else "", rt)

func _add_row(lt: String, label: String, rt: String) -> void:
	_add_control_row(_value_label(lt), label, _value_label(rt))

func _add_control_row(left: Control, label: String, right: Control) -> void:
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.add_child(left)
	_summary.add_child(_mid_label(label))
	_summary.add_child(right)

func _value_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", VALUE_COLOR)
	return l

func _mid_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(44, 0)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", LABEL_COLOR)
	return l

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
	var s: UnitSkin = SkinCatalog.resolve(_skins, String(snap.get("skin_id", "")), snap["type_id"], snap["team"])
	return s.name if s != null else String(snap["type_id"])

func _name_lv(snap: Dictionary) -> String:
	return "%s Lv%d" % [_display_name(snap), int(snap["level"])]

func _troops_text(snap: Dictionary) -> String:
	return "%d/%d → %d/%d" % [snap["troops_before"], snap["max"], snap["troops_after"], snap["max"]]

func _total_text(bd: Dictionary, empty_text: String) -> String:
	return String.num_int64(roundi(bd["total"])) if not bd.is_empty() else empty_text

func _base_atk_text(bd: Dictionary) -> String:
	if bd.is_empty():
		return NONE
	return "%s%d" % ["対空" if bd.get("vs_aerial", false) else "対地", int(bd["stat"])]

func _base_def_text(bd: Dictionary) -> String:
	return String.num_int64(int(bd["stat"])) if not bd.is_empty() else NONE

func _terrain_text(snap: Dictionary) -> String:
	var terr := String(snap["terrain"])
	return "%s ×%.2f/×%.2f" % [TerrainSkinCatalog.display_name(terr), TerrainType.attack_factor(terr), TerrainType.defense_factor(terr)]

## 包囲は攻防共通の係数＝どちらかの内訳から取り出す（反撃なし側は攻が空）。
func _surround_of(side: Dictionary) -> float:
	var atk: Dictionary = side["atk"]
	var bd: Dictionary = atk if not atk.is_empty() else side["def"]
	return float(bd.get("surround", 1.0))

func _factor_text(f: float) -> String:
	return "×%.2f" % f if not is_equal_approx(f, 1.0) else NONE

## 支援（攻/防の加算ペア）。両方 0 なら NONE ＝行ごと省略の判定に使う。
func _support_text(side: Dictionary) -> String:
	var atk: Dictionary = side["atk"]
	var def: Dictionary = side["def"]
	var sa := roundi(float(atk.get("support", 0.0)))
	var sd := roundi(float(def.get("support", 0.0)))
	if sa == 0 and sd == 0:
		return NONE
	return "%s/%s" % [("+%d" % sa) if sa != 0 else NONE, ("+%d" % sd) if sd != 0 else NONE]

## バフ1件の表記（例: ホーリーアリア ×1.30/×1.30）。target で攻/防の効き先を描き分ける。
func _status_text(m: Dictionary) -> String:
	var nm := String(m.get("name", ""))
	if nm.is_empty():
		nm = "補正"
	var eff: String
	if String(m.get("op", "mul")) == "mul":
		eff = "×%.2f" % float(m.get("value", 1.0))
	else:
		eff = "%+d" % roundi(float(m.get("value", 0.0)))
	var t := String(m.get("target", "both"))
	var atk_part := eff if t != "defense" else NONE
	var def_part := eff if t != "attack" else NONE
	return "%s %s/%s" % [nm, atk_part, def_part]

# --- 詳細（数式チェーン）。式の整形は旧 UnitInfoPanel._format_combat から移設 ---

func _format_side_detail(attacker_side: bool) -> String:
	var a: Dictionary = _detail["attacker"]
	var t: Dictionary = _detail["defender"]
	var fwd: Dictionary = _detail["to_defender"]
	var ret: Variant = _detail["to_attacker"]
	var snap: Dictionary = a if attacker_side else t
	var other: Dictionary = t if attacker_side else a
	var nm := _display_name(snap)
	var on := _display_name(other)
	var lines: Array[String] = []
	lines.append("%s Lv%d（%s）" % [nm, snap["level"], TerrainSkinCatalog.display_name(snap["terrain"])])
	lines.append("兵 %d/%d → %d/%d (%+d)" % [snap["troops_before"], snap["max"], snap["troops_after"], snap["max"], snap["troops_after"] - snap["troops_before"]])
	lines.append("──────────────────────")
	if attacker_side:
		lines.append("▼ 攻撃 → %s" % on)
		lines.append(_chain(fwd["attack"]))
		lines.append(_damage_line(nm, on, fwd, t["troops_before"]))
		lines.append("▼ 防御 ← %s の反撃" % on)
		if ret != null:
			lines.append(_chain(ret["defense"]))
			lines.append(_damage_line(on, nm, ret, a["troops_before"]))
		else:
			lines.append("  反撃なし（無傷）")
	else:
		lines.append("▼ 防御 ← %s" % on)
		lines.append(_chain(fwd["defense"]))
		lines.append(_damage_line(on, nm, fwd, t["troops_before"]))
		lines.append("▼ 反撃 → %s" % on)
		if ret != null:
			lines.append(_chain(ret["attack"]))
			lines.append(_damage_line(nm, on, ret, a["troops_before"]))
		else:
			lines.append("  反撃なし")
	lines.append("──────────────────────")
	lines.append("損害の式  割合=攻²÷(攻²+防²)、失う兵=相手の現在兵×割合")
	return "\n".join(lines)

## 補正チェーン1行。breakdown は Combat.attack_breakdown / defense_breakdown。
func _chain(b: Dictionary) -> String:
	var is_atk: bool = b["kind"] == "attack"
	var head := "攻" if is_atk else "防"
	var stat_label := ("対空" if b.get("vs_aerial", false) else "対地") if is_atk else "防"
	# 状態補正（バフ/デバフ）は効いているときだけ式に出す（既定 mul=1.0・add=0 なら非表示）。
	var smul: float = b.get("status_mul", 1.0)
	var sadd: float = b.get("status_add", 0.0)
	var smul_str := " × 状態×%.2f" % smul if not is_equal_approx(smul, 1.0) else ""
	var sadd_str := " ＋状態%d" % roundi(sadd) if not is_zero_approx(sadd) else ""
	return "  %s %d = 兵%d × %s%d × 経験×%.2f × 包囲×%.2f × 地形×%.2f%s ＋支援%d%s" % [
		head, roundi(b["total"]), b["troops"], stat_label, b["stat"],
		b["experience"], b["surround"], b["terrain"], smul_str, roundi(b["support"]), sadd_str]

## 損害1行: 「攻撃側 → 受け手  攻A 対 防D → P% → 兵N×P% = 失う兵」。
func _damage_line(from_name: String, to_name: String, hit: Dictionary, defender_troops: int) -> String:
	var pct := int(round(hit["fraction"] * 100.0))
	return "  %s → %s  攻%d 対 防%d → %d%% → 兵%d×%d%% = %d" % [
		from_name, to_name, roundi(hit["attack"]["total"]), roundi(hit["defense"]["total"]),
		pct, defender_troops, pct, hit["loss"]]
