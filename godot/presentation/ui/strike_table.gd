extends RefCounted
class_name StrikeTable
## 1回の打撃の3列表（左＝打つ側の攻撃力の積み上げ・中＝項目名・右＝受ける側の防御力の積み上げ）と
## 損害の式の整形。戦闘レポート（combat_report_view）とスキルレポート（skill_report_view）が
## 同じ hit（Combat.hit_from_breakdowns 形式）から同じ表を出すための共通部品＝式の見せ方を二重に持たない。
## 仕様 → doc/tech/combat_scene.md 右パネル
##
## static のみ（表示先の GridContainer は呼び出し側が持つ）。tr() は Node のものが使えないので
## TranslationServer.translate を通す（CombatReportView.status_text と同じ流儀）。

const VALUE_COLOR := Color(0.96, 0.93, 0.86)
const LABEL_COLOR := Color(0.72, 0.64, 0.50)
const NONE := "—"
const VALUE_MIN_W := 170.0    # 値セルの最低幅＝伸長フラグと二段構えで看板幅を使い切る
const MID_MIN_W := 48.0       # 中央の行ラベル列の最低幅

static func _t(key: String) -> String:
	return TranslationServer.translate(key)

## hit の3列表を grid に組む（列見出し〜実効値の行まで）。損害の式は damage_lines で別途出す
## ＝表の下の置き方（余白・フォント）は呼び出し側の器が決める。
static func fill(grid: GridContainer, striker_name: String, victim_name: String, hit: Dictionary) -> void:
	var off: Dictionary = hit["attack"]
	var def: Dictionary = hit["defense"]
	add_row(grid, _t("ui.report.col_attack") % striker_name, "", _t("ui.report.col_defense") % victim_name)
	add_row(grid, num(off, "troops"), _t("ui.report.strength"), num(def, "troops"))
	add_row(grid, atk_stat_text(off), _t("ui.report.base_stat"), String.num_int64(int(def["stat"])))
	add_row(grid, mul(off, "level"), _t("ui.report.level"), mul(def, "level"))
	add_row(grid, mul(off, "surround"), _t("ui.report.encircled"), mul(def, "surround"))
	add_row(grid, mul(off, "terrain"), _t("ui.report.terrain"), mul(def, "terrain"))
	add_row(grid, status_part(off), _t("ui.report.status"), status_part(def))
	add_row(grid, add_text(off, "support"), _t("ui.report.support"), add_text(def, "support"))
	# 貫通は防御側にだけ乗る（攻撃側の pierce が相手の防御を削る）。効いていなければ — 。
	add_row(grid, NONE, _t("ui.report.pierce"), mul(def, "pierce"))
	add_rule(grid)  # ここまでが積み上げ、ここから下が出来上がった値
	add_row(grid, total_text(off, NONE), _t("ui.report.eff_total"), total_text(def, NONE))
	# 実効値の行の下に用語を添える＝損害の式と同じ言葉で列を結ぶ。
	add_control_row(grid, term_label(_t("ui.report.eff_atk")), "", term_label(_t("ui.report.eff_def")))

## この打撃の損害の説明（表の下に置く行）。式の形を先に出し、次の行で実際の数字に置き換える。
## 2乗は「520×520」と展開する（13px では小さい ² が読めない）。
## victim_troops＝打たれる前の兵数（撃破で盤から消えていてもスナップショットから渡せる）。
static func damage_lines(victim_name: String, hit: Dictionary, victim_troops: int) -> Array[String]:
	var lines: Array[String] = []
	if bool(hit["defense"].get("capped", false)):
		lines.append(_t("ui.report.support_capped"))
	var atk := roundi(float(hit["attack"]["total"]))
	var def_total := roundi(float(hit["defense"]["total"]))
	var pct := int(round(float(hit["fraction"]) * 100.0))
	lines.append(_t("ui.report.loss_rate_formula"))
	lines.append(_t("ui.report.loss_rate_values") % [atk, atk, atk, atk, def_total, def_total, pct])
	lines.append(_t("ui.report.loss_line") % [victim_name, victim_troops, pct, int(hit["loss"])])
	return lines

# --- 行の組み立て（3列） ---

static func add_row(grid: GridContainer, lt: String, label: String, rt: String) -> void:
	add_control_row(grid, value_label(lt), label, value_label(rt))

static func add_control_row(grid: GridContainer, left: Control, label: String, right: Control) -> void:
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(left)
	grid.add_child(mid_label(label))
	grid.add_child(right)

## 表の区切り線（3列ぶんの細い線）。積み上げと結果を分ける。
static func add_rule(grid: GridContainer) -> void:
	for i in 3:
		var sep := HSeparator.new()
		sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(sep)

static func value_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(VALUE_MIN_W, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", VALUE_COLOR)
	return l

static func mid_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(MID_MIN_W, 0)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", LABEL_COLOR)
	return l

## 実効値の行の下に置く用語ラベル（実効攻撃力／実効防御力）。中央のラベルと同じ型づかい。
static func term_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", LABEL_COLOR)
	return l

# --- 値の整形 ---

## スナップショット（BattleState._unit_snapshot）の表示名。skin が引けなければ type_id。
static func display_name(skins: Dictionary, snap: Dictionary) -> String:
	var s: UnitSkin = SkinCatalog.resolve(skins, String(snap.get("skin_id", "")), snap["type_id"], snap["team"])
	return TranslationServer.translate("unit." + s.skin_id + ".name") if s != null else String(snap["type_id"])

## 攻撃の素の値＝対地/対空の別を添える（同じ駒でも相手で変わる）。サマリーと詳細で同じ書式。
static func atk_stat_text(b: Dictionary) -> String:
	return _t("ui.report.atk_vs_air" if b.get("vs_aerial", false) else "ui.report.atk_vs_ground") % int(b["stat"])

static func total_text(bd: Dictionary, empty_text: String) -> String:
	return String.num_int64(roundi(bd["total"])) if not bd.is_empty() else empty_text

## 内訳の整数値（兵数など）。内訳が空＝その向きは起きていない（反撃なし）。
static func num(b: Dictionary, key: String) -> String:
	return String.num_int64(int(b.get(key, 0))) if not b.is_empty() else NONE

## 係数1つ。1.00（＝効いていない）も表に残す＝行の有無で「効いたか」を探させない。
static func mul(b: Dictionary, key: String) -> String:
	if b.is_empty() or not b.has(key):
		return NONE
	return "×%.2f" % float(b[key])

## 加算1つ（支援）。
static func add_text(b: Dictionary, key: String) -> String:
	return "%+d" % roundi(float(b.get(key, 0.0))) if not b.is_empty() else NONE

## 状態補正（バフ/デバフ）。倍率と加算の両方が効いていれば併記する。
static func status_part(b: Dictionary) -> String:
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
