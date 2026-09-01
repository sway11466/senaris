extends Control
class_name CombatReportView
## 戦闘レポート（右パネル）。演出シーンと同じ detail（BattleState.attack の "detail"）を
## 「サマリー（表）／攻撃／反撃」の3タブで見せる。
## サマリー＝ユーザーが見える特徴の左右比較（式は出さない）。左右は陣営で固定
## （自軍左・敵右）＝戦闘演出シーンと同じ並び。仕様 → doc/tech/combat_scene.md
## 攻撃・反撃＝打撃の向きごとの数式チェーン（左＝打つ側の攻撃力・右＝受ける側の防御力・下＝損害）。
## こちらの左右は陣営でなく式の順（攻÷防）で固定＝攻撃する側が常に左。
## 攻/防のペア表記（地形・支援・バフ）は常に「攻/防」の順。

const VALUE_COLOR := Color(0.96, 0.93, 0.86)
const LABEL_COLOR := Color(0.72, 0.64, 0.50)
const TEAM_COLOR := { 0: Color(0.18, 0.48, 0.84), 1: Color(0.86, 0.29, 0.29) }
const NONE := "—"
const FIG_SIZE := 96.0        # ユニットの絵の一辺
const VALUE_MIN_W := 170.0    # 値セルの最低幅＝伸長フラグと二段構えで看板幅を使い切る
const MID_MIN_W := 48.0       # 中央の行ラベル列の最低幅
const TAB_MIN_W := 120.0      # タブ1枚の最低幅

var _skins := {}
var _detail := {}
var _tabs := {}  # "summary"/"attack"/"counter" -> Button

## タブの id と文言キー。見出しは _ready で焼き込む＝言語が変わったら refresh_labels で貼り直す。
const TABS := [["summary", "ui.report.tab_summary"], ["attack", "ui.report.tab_attack"],
		["counter", "ui.report.tab_counter"]]
var _summary: GridContainer
var _side_head: Label
var _detail_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	_detail_label.add_theme_color_override("font_color", VALUE_COLOR)
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
## 表示中の内訳は次に戦闘が起きれば組み直されるので、ここではタブ見出しだけを差し替える。
func refresh_labels() -> void:
	for t in TABS:
		var b: Button = _tabs[String(t[0])]
		b.text = tr(String(t[1]))

func _show_tab(id: String) -> void:
	if _detail.is_empty():
		return
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
	_add_control_row(_value_label(lt), label, _value_label(rt))

## 表の区切り線（3列ぶんの細い線）。積み上げと結果を分ける。
func _add_rule() -> void:
	for i in 3:
		var sep := HSeparator.new()
		sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_summary.add_child(sep)

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
	l.custom_minimum_size = Vector2(VALUE_MIN_W, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", VALUE_COLOR)
	return l

func _mid_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(MID_MIN_W, 0)
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
	return tr("unit." + s.skin_id + ".name") if s != null else String(snap["type_id"])

func _name_lv(snap: Dictionary) -> String:
	return tr("ui.report.name_lv") % [_display_name(snap), int(snap["level"])]

func _troops_text(snap: Dictionary) -> String:
	return "%d/%d → %d/%d" % [snap["troops_before"], snap["max"], snap["troops_after"], snap["max"]]

func _total_text(bd: Dictionary, empty_text: String) -> String:
	return String.num_int64(roundi(bd["total"])) if not bd.is_empty() else empty_text

func _base_atk_text(bd: Dictionary) -> String:
	if bd.is_empty():
		return NONE
	return _atk_stat_text(bd)

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
	var off: Dictionary = hit["attack"]
	var def: Dictionary = hit["defense"]
	_add_row(tr("ui.report.col_attack") % sn, "", tr("ui.report.col_defense") % vn)
	_add_row(_num(off, "troops"), tr("ui.report.strength"), _num(def, "troops"))
	_add_row(_atk_stat_text(off), tr("ui.report.base_stat"), String.num_int64(int(def["stat"])))
	_add_row(_mul(off, "level"), tr("ui.report.level"), _mul(def, "level"))
	_add_row(_mul(off, "surround"), tr("ui.report.encircled"), _mul(def, "surround"))
	_add_row(_mul(off, "terrain"), tr("ui.report.terrain"), _mul(def, "terrain"))
	_add_row(_status_part(off), tr("ui.report.status"), _status_part(def))
	_add_row(_add_text(off, "support"), tr("ui.report.support"), _add_text(def, "support"))
	# 貫通は防御側にだけ乗る（攻撃側の pierce が相手の防御を削る）。効いていなければ — 。
	_add_row(NONE, tr("ui.report.pierce"), _mul(def, "pierce"))
	_add_rule()  # ここまでが積み上げ、ここから下が出来上がった値
	_add_row(_total_text(off, NONE), tr("ui.report.eff_total"), _total_text(def, NONE))
	# 実効値の下に用語を添える＝下の損害の式と同じ言葉で列を結ぶ。
	_add_control_row(_term_label(tr("ui.report.eff_atk")), "", _term_label(tr("ui.report.eff_def")))
	# 損害の出し方は左右に割らず、幅いっぱいで式に数字を入れて見せる＝表の2つの実効値が
	# そのまま式に入るのを見せる。
	var lines: Array[String] = []
	if bool(def.get("capped", false)):
		lines.append(tr("ui.report.support_capped"))
	lines.append_array(_damage_block(vn, hit, victim))
	_detail_label.text = "\n".join(lines)

## この打撃の損害の説明。式の形を先に出し、次の行で実際の数字に置き換える。
## 2乗は「520×520」と展開する（13px では小さい ² が読めない）。
## victim＝兵を失う側／hit は Combat.hit_detail（攻/防の内訳と損害率・損害）。
func _damage_block(victim_name: String, hit: Dictionary, victim_snap: Dictionary) -> Array[String]:
	var atk := roundi(float(hit["attack"]["total"]))
	var def_total := roundi(float(hit["defense"]["total"]))
	var pct := int(round(float(hit["fraction"]) * 100.0))
	return [
		tr("ui.report.loss_rate_formula"),
		tr("ui.report.loss_rate_values") % [atk, atk, atk, atk, def_total, def_total, pct],
		tr("ui.report.loss_line") % [victim_name, int(victim_snap["troops_before"]), pct, int(hit["loss"])],
	]

## 実効値の行の下に置く用語ラベル（実効攻撃力／実効防御力）。中央のラベルと同じ型づかい。
func _term_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", LABEL_COLOR)
	return l


## 攻撃の素の値＝対地/対空の別を添える（同じ駒でも相手で変わる）。サマリーと詳細で同じ書式。
func _atk_stat_text(b: Dictionary) -> String:
	return tr("ui.report.atk_vs_air" if b.get("vs_aerial", false) else "ui.report.atk_vs_ground") % int(b["stat"])

## 内訳の整数値（兵数など）。内訳が空＝その向きは起きていない（反撃なし）。
func _num(b: Dictionary, key: String) -> String:
	return String.num_int64(int(b.get(key, 0))) if not b.is_empty() else NONE

## 係数1つ。1.00（＝効いていない）も表に残す＝行の有無で「効いたか」を探させない。
func _mul(b: Dictionary, key: String) -> String:
	if b.is_empty() or not b.has(key):
		return NONE
	return "×%.2f" % float(b[key])

## 加算1つ（支援）。
func _add_text(b: Dictionary, key: String) -> String:
	return "%+d" % roundi(float(b.get(key, 0.0))) if not b.is_empty() else NONE

## 状態補正（バフ/デバフ）。倍率と加算の両方が効いていれば併記する。
func _status_part(b: Dictionary) -> String:
	if b.is_empty():
		return NONE
	var parts: Array[String] = []
	var smul := float(b.get("status_mul", 1.0))
	var sadd := float(b.get("status_add", 0.0))
	if not is_equal_approx(smul, 1.0):
		parts.append("×%.2f" % smul)
	if not is_zero_approx(sadd):
		parts.append("%+d" % roundi(sadd))
	return " ".join(parts) if not parts.is_empty() else NONE

