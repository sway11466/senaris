extends Panel
class_name UnitInfoPanel
## 選択中ユニットの情報を右側に表示するパネル（presentation）。
## 状態(BattleState)は読むだけ。HexBoard.selection_changed を受けて中身を差し替える。
## ラベルはコード生成（tscn は Panel ＋ 位置だけ持てばよい）。
##
## ユニットは1行1項目で出す。板は固定寸法（UiLayout.RIGHT_BOX）で全部は入りきらないので、
## 戦闘レポートと同じ作りのタブ（能力／状態／地形）で切り替える＝スクロールさせない。
## 見出し（名前・陣営・兵種）はタブの上に据え置き＝どの駒を見ているか常に分かる。

## グループの区切り線。改行だけで離すと「どこまでが同じ話か」が読めないので線を引く。
const SEPARATOR := "──────────────────────"
const NONE := "—"
const TAB_MIN_W := 96.0  # タブ1枚の最低幅（戦闘レポートと同じ考え方）
## 項目名の欄の幅。タブをまたいで同じ値を使う＝どのタブでも値の頭が同じ位置に並ぶ。
## 空白で桁合わせしないのは、看板のフォントが等幅でないため（文字数を数えても揃わない）。
const LABEL_W := 88.0

## タブ＝[id, 見出し]。id は _tab_lines の分岐と合わせる。
const TABS := [["ability", "能力"], ["status", "状態"], ["terrain", "地形"]]

var _state: BattleState
var _skins := {}        # type_id -> { ally:[UnitSkin], enemy:[UnitSkin] }
var _terrain_skins := {}  # Vector2i -> skin_id（ステージの見た目差分。地形名をスキン名で出すのに使う）
var _header: Label      # 【名前】陣営／兵種（ユニット表示のときだけ出す据え置きの見出し）
var _tabs_row: HBoxContainer
var _tabs := {}         # id -> Button
var _tab := "ability"   # いま選んでいるタブ。駒を選び直しても保つ＝同じ観点で駒を見比べられる
var _shown_unit := -1   # タブ表示中の駒（タブを押したときに描き直す相手）。-1＝素のテキスト表示中
var _rows: VBoxContainer  # ユニット表示の「項目名／値」2列。素のテキスト表示のときは引っ込める
var _label: Label
var _report: CombatReportView  # 戦闘レポート（サマリー/詳細タブ）。戦闘時だけ _label と入れ替えて表示
var _notify_token := 0  # 一時通知の世代。待っている間に別の表示へ変わったら戻さないための印

func _ready() -> void:
	# 暗い木の看板（材質ルール: 木＝常設の面。TavernTheme 参照）
	add_theme_stylebox_override("panel", TavernTheme.signboard_stylebox())
	add_child(TavernTheme.signboard_frame())
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_top = 14
	box.offset_right = -16
	box.offset_bottom = -14
	box.add_theme_constant_override("separation", 8)
	_header = Label.new()
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_header.hide()
	box.add_child(_header)
	_tabs_row = HBoxContainer.new()
	_tabs_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs_row.add_theme_constant_override("separation", 6)
	_tabs_row.hide()
	box.add_child(_tabs_row)
	var group := ButtonGroup.new()
	for t in TABS:
		var b := TavernTheme.wood_button(String(t[1]))
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(TAB_MIN_W, 0)
		b.pressed.connect(_on_tab_pressed.bind(String(t[0])))
		_tabs_row.add_child(b)
		_tabs[String(t[0])] = b
	# ユニット表示は「項目名／値」の2列。値を同じ位置から始めるので、行ごとの控えではなく
	# 幅を決めた欄に入れる（Label 1枚に空白で詰めても等幅フォントでないため揃わない）。
	_rows = VBoxContainer.new()
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	_rows.hide()
	box.add_child(_rows)
	_label = Label.new()
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_label)
	_report = CombatReportView.new()
	_report.hide()
	add_child(_report)
	clear()

## 状態とスキン表を渡す（main から1回）。
func bind(state: BattleState, skin_catalog: Dictionary) -> void:
	_state = state
	_skins = skin_catalog
	_report.bind(skin_catalog)
	clear()

## ステージの地形見た目差分（座標→skin_id）を渡す。盤・戦闘演出と同じものを受ける。
## 地形名は「平地」ではなく実際に見えている絵の名前（「墓地の草地」）で出す＝盤と言葉を合わせる。
func bind_terrain_skins(terrain_skins: Dictionary) -> void:
	_terrain_skins = terrain_skins

## 選択変更を受けて表示を更新（id<0 で未選択）。タブの選択は駒をまたいで保つ。
func show_unit(unit_id: int) -> void:
	if _state == null or unit_id < 0:
		clear()
		return
	var u := _state.unit_by_id(unit_id)
	if u == null:
		clear()
		return
	_shown_unit = unit_id
	if _report != null:
		_report.hide()
	_header.text = _header_text(u)
	_header.show()
	var b: Button = _tabs[_tab]
	b.button_pressed = true
	_tabs_row.show()
	_label.hide()
	_rebuild_rows(u, _tab)
	_rows.show()

## タブを押した＝表示中の駒をそのタブで描き直す。
func _on_tab_pressed(id: String) -> void:
	_tab = id
	if _shown_unit >= 0:
		show_unit(_shown_unit)

func clear() -> void:
	_show_text("ユニット未選択\n\n盤上のユニットを左クリックで選択\n空きマスをクリックで地形を確認\n\n［操作］\nEnter＝ターン終了\n2本指スクロール／空き地ドラッグ＝移動\nピンチ＝ズーム\nF＝全体表示")

## 一時的な通知（セーブ完了など）。数秒だけ出して未選択表示へ戻す。
## 上端の情報バーを廃した代わりの置き場（doc/gdd/uiux.md「ターン表示」）。
func notify(text: String, seconds := 2.5) -> void:
	_show_text(text)
	var token := _notify_token + 1
	_notify_token = token
	await get_tree().create_timer(seconds).timeout
	if _notify_token == token and is_inside_tree():
		clear()  # 後から別の表示に切り替わっていれば（token 不一致）何もしない

## 空きマスの地形情報を表示（拠点なら控え＝garrison も一覧）。HexBoard.tile_inspected を受ける。
func show_terrain(hex: Vector2i) -> void:
	if _state == null:
		clear()
		return
	_show_text(_format_terrain(hex))

## 素のテキスト表示（未選択・通知・地形）。見出しとタブは引っ込める＝ユニット専用の器なので。
func _show_text(text: String) -> void:
	if _label == null:
		return
	if _report != null:
		_report.hide()
	_shown_unit = -1
	_header.hide()
	_tabs_row.hide()
	_rows.hide()
	_label.text = text
	_label.show()

## グループの切れ目。線の上に余白を1行取り、下は空けない＝線をその下のグループの見出し罫として
## 読ませる。板の高さは決め打ち（UiLayout.RIGHT_BOX）で、上下に空けると素の駒でも入りきらない。
static func _add_separator(lines: Array[String]) -> void:
	lines.append("")
	lines.append(SEPARATOR)

## そのマスの地形の表示名。ステージの見た目差分があればスキン名（「墓標の荒れ地」）、
## 無ければ地形タイプの既定スキン名（「荒地」）。盤に見えている絵と同じ言葉にする。
func _terrain_name(hex: Vector2i, type_id: String) -> String:
	var skin := TerrainSkinCatalog.resolve(String(_terrain_skins.get(hex, "")), type_id)
	return skin.name if skin != null else type_id

func _format_terrain(hex: Vector2i) -> String:
	var terr := _state.terrain_at(hex)
	var lines: Array[String] = []
	lines.append("【地形】 %s" % _terrain_name(hex, terr))
	lines.append("")
	lines.append("攻撃補正  ×%.2f" % TerrainType.attack_factor(terr))
	lines.append("防御補正  ×%.2f" % TerrainType.defense_factor(terr))

	var b := _state.base_at(hex)
	if b != null:
		_add_separator(lines)
		var owner := "中立" if b.team < 0 else ("自軍" if b.team == 0 else "敵軍")
		var kind_name := "本拠地" if b.is_hq() else "拠点"
		lines.append("【%s】 所属:%s" % [kind_name, owner])
		if b.garrison.is_empty():
			lines.append("控え  なし")
		else:
			lines.append("控え  %d体" % b.garrison.size())
			for gu in b.garrison:
				lines.append("  ・%s" % _garrison_line(gu, b))
	return "\n".join(lines)

## 控え1体の1行表示（名前・兵数・レベル）。
func _garrison_line(gu: Unit, b: Base) -> String:
	var team_for_skin := gu.team if gu.team >= 0 else (b.team if b.team >= 0 else 0)
	var sk := SkinCatalog.resolve(_skins, gu.skin_id, gu.type_id, team_for_skin)
	var nm := sk.name if sk != null else gu.type_id
	return "%s  兵%d/%d  Lv%d" % [nm, gu.troops, gu.max_troops, gu.level]

## タブの上に据え置く見出し（名前・陣営・兵種）。
func _header_text(u: Unit) -> String:
	var skin: UnitSkin = SkinCatalog.resolve(_skins, u.skin_id, u.type_id, u.team)
	var unit_name := skin.name if skin != null else u.type_id
	var lines: Array[String] = ["【%s】 %s" % [unit_name, "自軍" if u.team == 0 else "敵軍"]]
	if u.team == 0:  # 敵はリスキン元（種別）が透けるので出さない
		var category := UnitCatalog.display_category(u.type_id)
		if category != "":
			lines.append("兵種  %s" % category)
	return "\n".join(lines)

# --- タブの中身（項目名／値の2列）。値の頭は LABEL_W でタブをまたいで揃う ---

## いま選んでいるタブの行を組み直す。
func _rebuild_rows(u: Unit, tab: String) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)  # queue_free 待ちの旧行が新行と同居して1フレーム崩れるのを避ける
		c.queue_free()
	match tab:
		"status":
			_build_status(u)
		"terrain":
			_build_terrain(u)
		_:
			_build_ability(u)

## 項目1つ＝「項目名（幅固定）／値」の1行。
func _add_row(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(LABEL_W, 0)
	row.add_child(l)
	var v := Label.new()
	v.text = value
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(v)
	_rows.add_child(row)

## 幅いっぱいの1行（区切り線・控えの箇条書きなど、項目名／値に割れないもの）。
func _add_full_row(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(l)

## 能力＝駒そのものの性能（盤の状況で変わらない値）。
func _build_ability(u: Unit) -> void:
	_add_row("兵数", "%d / %d" % [u.troops, u.max_troops])
	_add_row("Lv", str(u.level))
	_add_row("対地攻撃", str(u.unit_attack))
	_add_row("対空攻撃", str(u.atk_air) if u.atk_air > 0 else NONE)
	_add_row("防御", str(u.unit_defense))
	_add_row("移動", str(u.move))
	_add_row("移動種別", Movement.display_name(u.move_type))
	_add_row("射程", str(u.attack_range) if u.min_range == u.attack_range \
		else "%d-%d" % [u.min_range, u.attack_range])
	# 特性は「他の行を見ても分からないこと」だけ並べる。飛行は「移動種別」、遠隔・近接不可は
	# 「射程」がそのまま示すので置かない（同じことを二度書かない）。詳細 → doc/gdd/units.md
	var traits: Array[String] = []
	if u.pierce > 0.0:
		traits.append("防御貫通%d%%" % roundi(u.pierce * 100.0))  # 魔法兵50%＝相手の防御を半分無視
	if u.can_capture:
		traits.append("占領可")
	if u.move_after_attack:
		traits.append("攻撃後再移動")
	for t in traits:
		_add_row("特性", t)

## 状態＝このターン何ができるか＋いま効いているバフ・デバフ。
## 包囲は地形ではなく「隣の敵に囲まれて弱っている」＝デバフなのでここに置く。
func _build_status(u: Unit) -> void:
	_add_row("行動", _action_state(u))
	_add_full_row("")
	_add_full_row(SEPARATOR)
	var mods := _state.status_mods_for(u)
	var surround := Surround.factor(_state, u)
	if mods.is_empty() and surround >= 1.0:
		_add_row("補正", "なし")
		return
	# 表記は戦闘レポートと共通＝名前 攻/防 の順。
	for m in mods:
		_add_row("補正", CombatReportView.status_text(m))
	if surround < 1.0:
		_add_row("包囲", "×%.2f（攻防とも弱体化）" % surround)

## 地形＝いるマスの影響（拠点に乗っていればその情報も）。
func _build_terrain(u: Unit) -> void:
	var terr := _state.terrain_at(u.pos)
	_add_row("地形", _terrain_name(u.pos, terr))
	_add_row("攻撃補正", "×%.2f" % TerrainType.attack_factor(terr))
	_add_row("防御補正", "×%.2f" % TerrainType.defense_factor(terr))
	var b := _state.base_at(u.pos)
	if b == null:
		return
	_add_full_row("")
	_add_full_row(SEPARATOR)
	_add_row("本拠地" if b.is_hq() else "拠点",
		"中立" if b.team < 0 else ("自軍" if b.team == 0 else "敵軍"))
	_add_row("控え", "%d体" % b.garrison.size())
	for gu in b.garrison:
		_add_full_row("  ・%s" % _garrison_line(gu, b))

## 行動状態の短い説明。
func _action_state(u: Unit) -> String:
	if _state.is_done(u.id):
		return "行動完了"
	var parts: Array[String] = []
	parts.append("移動可" if _state.can_still_move(u.id) else "移動済")
	parts.append("攻撃可" if not _state.has_attacked(u.id) else "攻撃済")
	return " / ".join(parts)

# --- 戦闘結果ビュー（攻撃時に右パネルへ）。detail は BattleState.attack の "detail"。---
# 表示は CombatReportView（サマリー/攻撃側/守備側の3タブ）へ委譲。
# 式の整形も同ビューに集約している＝盤の数字と一致する根拠は combat_report_view.gd 参照。

func show_combat(detail: Dictionary) -> void:
	if detail == null or detail.is_empty():
		return
	_shown_unit = -1
	_header.hide()
	_tabs_row.hide()
	_label.hide()
	_report.show()
	_report.show_report(detail)
