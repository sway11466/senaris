extends RefCounted
class_name StrikeTable
## 1回の打撃の3列表（左＝打つ側の攻撃力の積み上げ・中＝項目名・右＝受ける側の防御力の積み上げ）と
## 損害の式の整形。戦闘レポート（combat_report_view）とスキルレポート（skill_report_view）が
## 同じ HitDetail から同じ表を出すための共通部品＝式の見せ方を二重に持たない。
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
static func fill(grid: GridContainer, striker_name: String, victim_name: String, hit: HitDetail) -> void:
	var off := hit.attack
	var def := hit.defense
	add_row(grid, _t("ui.report.col_attack") % striker_name, "", _t("ui.report.col_defense") % victim_name)
	add_row(grid, atk_stat_text(off), _t("ui.report.base_stat"), def_stat_text(def))
	add_row(grid, times(off.troops), _t("ui.report.strength"), times(def.troops))
	add_row(grid, mul(off.level), _t("ui.report.level"), mul(def.level))
	add_row(grid, opt_mul(off.surround), _t("ui.report.encircled"), opt_mul(def.surround))
	add_row(grid, mul(off.terrain), _t("ui.report.terrain"), mul(def.terrain))
	add_row(grid, opt_mul(off.status_mul), _t("ui.report.status_mul"), opt_mul(def.status_mul))
	add_row(grid, add_text(off.support), _t("ui.report.support"), add_text(def.support))
	add_row(grid, add_text(off.status_add), _t("ui.report.status_add"), add_text(def.status_add))
	# 貫通は防御側にだけ乗る（攻撃側の pierce が相手の防御を削る）。
	add_row(grid, NONE, _t("ui.report.pierce"), opt_mul(def.pierce))
	add_rule(grid)  # ここまでが積み上げ、ここから下が出来上がった値
	add_row(grid, total_text(off, NONE), _t("ui.report.eff_total"), total_text(def, NONE))
	# 実効値の行の下に用語を添える＝損害の式と同じ言葉で列を結ぶ。
	add_control_row(grid, term_label(_t("ui.report.eff_atk")), "", term_label(_t("ui.report.eff_def")))

## この打撃の損害の説明（表の下に置く行）。式の形を先に出し、次の行で実際の数字に置き換える。
## 2乗は「520×520」と展開する（13px では小さい ² が読めない）。
## victim_troops＝打たれる前の兵数（撃破で盤から消えていてもスナップショットから渡せる）。
static func damage_lines(victim_name: String, hit: HitDetail, victim_troops: int) -> Array[String]:
	var lines: Array[String] = []
	if hit.defense.capped:
		lines.append(_t("ui.report.support_capped"))
	var atk := roundi(hit.attack.total)
	var def_total := roundi(hit.defense.total)
	var pct := int(round(hit.fraction * 100.0))
	lines.append(_t("ui.report.loss_rate_formula"))
	lines.append(_t("ui.report.loss_rate_values") % [atk, atk, atk, atk, def_total, def_total, pct])
	lines.append(_t("ui.report.loss_line") % [victim_name, victim_troops, pct, hit.loss])
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

## スナップショット（BattleState.unit_snapshot）の表示名。skin が引けなければ type_id。
static func display_name(skins: Dictionary, snap: UnitSnapshot) -> String:
	var s: UnitSkin = SkinCatalog.resolve(skins, snap.skin_id, snap.type_id, snap.team)
	return TranslationServer.translate("unit." + s.skin_id + ".name") if s != null else snap.type_id

## 攻撃の素の値＝対地/対空の別を添える（同じ駒でも相手で変わる）。サマリーと詳細で同じ書式。
static func atk_stat_text(b: StatBreakdown) -> String:
	return _t("ui.report.atk_vs_air" if b.vs_aerial else "ui.report.atk_vs_ground") % b.stat

## 防御の素の値＝攻撃側が対地/対空を名乗るのに対応して「防御」を添える（左右で何の値かを揃える）。
static func def_stat_text(b: StatBreakdown) -> String:
	return _t("ui.report.def_stat") % b.stat

## 実効値。内訳が無い（null）＝その向きは起きていない（反撃なし）＝empty_text。
static func total_text(bd: StatBreakdown, empty_text: String) -> String:
	return String.num_int64(roundi(bd.total)) if bd != null else empty_text

## 兵数＝基準値に掛ける頭数。積み上げの向き（掛ける）を記号で見せる。
static func times(v: int) -> String:
	return "×%d" % v

## 常に働く補正（Lv・地形）の係数。×1.00 も出す＝「このレベル／この地形では得も損もしない」。
static func mul(v: float) -> String:
	return "×%.2f" % v

## 条件が揃ったときだけ働く補正（包囲・状態補正×・貫通）の係数。外れていれば — ＝土俵に上がっていない。
static func opt_mul(v: float) -> String:
	return NONE if is_equal_approx(v, 1.0) else mul(v)

## 加算の補正（支援・状態補正＋）。効いていなければ — 。
static func add_text(v: float) -> String:
	return NONE if is_zero_approx(v) else "%+d" % roundi(v)
