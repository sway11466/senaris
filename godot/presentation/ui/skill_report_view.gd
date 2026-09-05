extends Control
class_name SkillReportView
## スキルレポート（右パネル）。陣形スキル・ユニットスキルの解決結果（MatchController.formation_resolved
## の result）を「サマリー＋対象ごと1ページ」で見せる。仕様 → doc/tech/combat_scene.md 右パネル（スキルレポート）
## 対象の数はレシピと着弾で変わるのでタブではなくページャーで送る（◀ n/N ▶。ホイールは
## UnitInfoPanel が届ける）。対象ページは戦闘レポートの攻撃タブと同じ3列表（StrikeTable）＝
## どのページを開いても戦闘レポートと同じ読み方ができる。

const PAGER_MIN_W := 44.0  # ◀▶ ボタンの最低幅（ユニット情報パネルのページャーと同じ）

var _skins := {}
var _result := {}
var _head: Label          # 据え置きの見出し（スキル名）＝どのページでも何のスキルかが見える
var _side_head: Label     # 対象ページの見出し（%s → %s の攻撃）。サマリーでは隠す
var _body: VBoxContainer  # ページの中身の器（ページ送りのたびに作り直す）
var _pager: HBoxContainer
var _prev: Button
var _next: Button
var _page_label: Label
var _page := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	add_child(v)
	# アンカーは add_child 後に明示設定（親 Panel の看板幅いっぱいに広げる）＝戦闘レポートと同じ余白
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 10
	v.offset_right = -12
	v.offset_bottom = -10
	v.add_theme_constant_override("separation", 8)
	_head = Label.new()
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_head)
	_side_head = Label.new()
	_side_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side_head.hide()
	v.add_child(_side_head)
	# 中身の器。板の内側で切り落とす＝対象が多くて入り切らなくても板の外へは描かれない。
	var clip := Control.new()
	clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE  # ホイールは板（UnitInfoPanel）へ通す
	v.add_child(clip)
	_body = VBoxContainer.new()
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_theme_constant_override("separation", 8)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_body)
	_build_pager(v)

## 板の下端に据え置く ◀ 2/3 ▶（ユニット情報パネルのページャーと同じ見た目・同じ位置）。
func _build_pager(box: VBoxContainer) -> void:
	_pager = HBoxContainer.new()
	_pager.add_theme_constant_override("separation", 6)
	_pager.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_pager)
	_prev = _pager_button("◀", -1)
	_page_label = Label.new()
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size = Vector2(64.0, 0)
	_pager.add_child(_page_label)
	_next = _pager_button("▶", 1)

func _pager_button(text: String, delta: int) -> Button:
	var b := TavernTheme.wood_button(text)
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(PAGER_MIN_W, 0)
	b.pressed.connect(turn_page.bind(delta))
	_pager.add_child(b)
	return b

func bind(skins: Dictionary) -> void:
	_skins = skins

## 解決結果を表示する（毎回サマリーページへリセット）。
func show_result(result: Dictionary) -> void:
	if result == null or result.is_empty():
		return
	_result = result
	_page = 0
	_render()

## 言語が変わったので文言を貼り直す（doc/tech/i18n.md 言語の切り替え）。
## 出しているページを同じ result から組み直す（作り直しはしない）。
func refresh_labels() -> void:
	if not _result.is_empty():
		_render()

## ページを送る（範囲外は無視＝端でボタンは無効になっている）。UnitInfoPanel のホイールも呼ぶ。
func turn_page(delta: int) -> void:
	var to := _page + delta
	if to < 0 or to >= _page_count():
		return
	_page = to
	_render()

## サマリー1枚＋着弾した対象ごとに1枚。
func _page_count() -> int:
	return 1 + (_result.get("results", []) as Array).size()

func _render() -> void:
	for c in _body.get_children():
		_body.remove_child(c)  # queue_free 待ちの旧行が新行と同居して1フレーム崩れるのを避ける
		c.queue_free()
	_head.text = tr("recipe.%s.name" % String(_result.get("recipe", "")))
	if _page == 0:
		_side_head.hide()
		_build_summary()
	else:
		_build_target(_result["results"][_page - 1])
	var total := _page_count()
	_page_label.text = "%d/%d" % [_page + 1, total]
	_prev.disabled = _page <= 0
	_next.disabled = _page >= total - 1

# --- サマリー（1ページ目） ---

func _build_summary() -> void:
	var caster: Dictionary = _result.get("caster", {})
	if not caster.is_empty():
		var team_text := tr("ui.info.team_ally") if int(caster.get("team", 0)) == 0 else tr("ui.info.team_enemy")
		var caster_name := tr("ui.info.header_name") % [StrikeTable.display_name(_skins, caster), team_text]
		_add_line(tr("ui.skillreport.caster") % caster_name)
	var sep := HSeparator.new()
	_body.add_child(sep)
	var results: Array = _result.get("results", [])
	if not results.is_empty():
		for r in results:
			var nm := StrikeTable.display_name(_skins, r["victim"])
			var key := "ui.skillreport.loss_line_killed" if bool(r["killed"]) else "ui.skillreport.loss_line"
			_add_line(tr(key) % [nm, int(r["loss"])])
		return
	_build_no_damage_lines()

## 損害の出ないレシピ（バフ・解除・分裂・毒）と空撃ちのサマリー。効果と持続を、状態タブ・
## 戦闘レポートのバフ行と同じ書式（CombatReportView.status_text）で出す＝画面ごとに言葉を変えない。
func _build_no_damage_lines() -> void:
	var effect := String(Formation.RECIPES.get(String(_result.get("recipe", "")), {}).get("effect", ""))
	var skill: Dictionary = _result.get("skill", {})
	match effect:
		"buff", "dot":
			_add_line(tr("ui.skillreport.target") % _buff_target_name(skill))
			var status: Dictionary = _result.get("status", {})
			_add_line(tr("ui.info.modifier_remaining") % [CombatReportView.status_text(status),
				int(status.get("remaining", 0))])
		"cleanse":
			var snap: Dictionary = skill.get("target", {})
			var nm := StrikeTable.display_name(_skins, snap) if not snap.is_empty() else ""
			var n := int(skill.get("cleansed", 0))
			_add_line(tr("ui.skillreport.cleansed") % [nm, n] if n > 0 \
				else tr("ui.skillreport.cleansed_none") % nm)
		"spawn":
			var caster: Dictionary = _result.get("caster", {})
			_add_line(tr("ui.skillreport.spawned") % StrikeTable.display_name(_skins, caster))
		_:
			_add_line(tr("ui.skillreport.no_hits"))  # 面の中に対象が1体も居ない空撃ち

## バフ・毒の掛かり先。ユニットスキル＝対象1体の名前／陣形（グレイス）＝味方全体。
func _buff_target_name(skill: Dictionary) -> String:
	var snap: Dictionary = skill.get("target", {})
	if not snap.is_empty():
		return StrikeTable.display_name(_skins, snap)
	return tr("ui.skillreport.target_all_allies")

func _add_line(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)

# --- 対象ごと（2ページ目以降）。戦闘レポートの攻撃タブと同じ3列表（StrikeTable） ---

func _build_target(r: Dictionary) -> void:
	var caster: Dictionary = _result.get("caster", {})
	var sn := StrikeTable.display_name(_skins, caster) if not caster.is_empty() else ""
	var vn := StrikeTable.display_name(_skins, r["victim"])
	_side_head.text = tr("ui.report.head_attack") % [sn, vn]
	_side_head.show()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	_body.add_child(grid)
	var hit: Dictionary = r["detail"]
	StrikeTable.fill(grid, sn, vn, hit)
	var detail := Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 表の下の補足＝表より一段小さく（戦闘レポートと同じ型づかい）。
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", StrikeTable.VALUE_COLOR)
	detail.text = "\n".join(StrikeTable.damage_lines(vn, hit, int(r["victim"]["troops_before"])))
	_body.add_child(detail)
