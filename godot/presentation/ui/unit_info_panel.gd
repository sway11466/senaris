extends Panel
class_name UnitInfoPanel
## 選択中ユニットの情報を右側に表示するパネル（presentation）。
## 状態(BattleState)は読むだけ。HexBoard.selection_changed を受けて中身を差し替える。
## ラベルはコード生成（tscn は Panel ＋ 位置だけ持てばよい）。
##
## ユニットは1行1項目で出す。板は固定寸法（UiLayout.RIGHT_BOX）で全部は入りきらないので、
## 戦闘レポートと同じ作りのタブ（能力／状態／地形）で切り替える＝スクロールさせない。
## 見出し（名前・陣営／部隊・兵種／敵の特性）はタブの上に据え置き＝どの駒を見ているか常に分かる。
## 仕様 → doc/gdd/uiux.md ユニット情報パネル

## グループの区切り線。改行だけで離すと「どこまでが同じ話か」が読めないので線を引く。
const SEPARATOR := "──────────────────────"
const NONE := "—"
const TAB_MIN_W := 96.0  # タブ1枚の最低幅（戦闘レポートと同じ考え方）
## 項目名の欄の幅。タブをまたいで同じ値を使う＝どのタブでも値の頭が同じ位置に並ぶ。
## 空白で桁合わせしないのは、看板のフォントが等幅でないため（文字数を数えても揃わない）。
## 英語の項目名（移動コストの `Mountain Stride` ＝ 125px）が入る幅を採る。超えると欄が
## 押し広げられ、その行だけ値の頭がずれる。値の欄は 432 − 128 − 8 ＝ 296px 残り、最長の値
## （包囲の説明つき係数 ＝ 286px）が折り返さずに入る。
const LABEL_W := 128.0
const ROW_SEP := 4       # 行と行の間。ページ割りの計算にも使う
const ROW_LABEL_GAP := 8  # 項目名の欄と値の欄の間
const PAGER_MIN_W := 44.0  # ◀▶ ボタンの最低幅

signal minimized_changed(minimized: bool)  # 畳んだ／開いた（main が設定に書く）
signal moved(pos: Vector2)  # 掴んで動かし、離した（板の左上。main が設定に書く）

## タブ＝[id, 見出しの翻訳キー]。id は _rebuild_rows の分岐と合わせる。
## 見出しは const に置けない（tr() は実行時）ので、キーだけ持って _ready で引く。
const TABS := [["ability", "ui.info.tab_ability"], ["status", "ui.info.tab_status"],
	["terrain", "ui.info.tab_terrain"]]

## 特性アイコン（`{特性id}.png`）。ユニット画像と同じ規約解決で、在れば出す・無ければ文字だけ。
const AI_ICON_DIR := "res://assets/icons/ai/"
const AI_FRAME_SIZE := 44.0  # 額の外寸（見出し2行ぶん）。絵は縁と余白のぶん内側に入る

var _state: BattleState
var _skins := {}        # type_id -> { ally:[UnitSkin], enemy:[UnitSkin] }
var _terrain_skins := {}  # Vector2i -> skin_id（ステージの見た目差分。地形名をスキン名で出すのに使う）
var _ai_presets := {}   # 特性id -> パラメーター辞書（data/ai/ai.json）。特性名を引くのに使う
var _ai_icons := {}     # 特性id -> Texture2D / null（無い印。毎回 load しないための控え）
var _header: HBoxContainer  # 据え置きの見出し（左＝名前と部隊/兵種・右＝敵の特性）
var _header_name: Label     # 名前（陣営）
var _header_sub: Label      # 敵＝部隊名／自軍＝兵種。どちらも無ければ隠す
var _ai_box: HBoxContainer  # 特性の欄（敵のときだけ出す）
var _ai_frame: PanelContainer  # アイコンの額（絵が無ければ額ごと隠す）
var _ai_icon: TextureRect
var _ai_name: Label
var _tabs_row: HBoxContainer
var _tabs := {}         # id -> Button
var _tab := "ability"   # いま選んでいるタブ。駒を選び直しても保つ＝同じ観点で駒を見比べられる
var _shown_unit := -1   # タブ表示中の駒（タブを押したときに描き直す相手）。-1＝素のテキスト表示中
var _content: Control     # 中身の器。板の内側で切り落とす＝行が板の外へはみ出して描かれない
var _rows: VBoxContainer  # いま出ているページの行。器いっぱいに広げる
var _pager: HBoxContainer  # 下端の ◀ 2/3 ▶。1ページのときも場所は空けたまま無効表示にする
var _minimized := false  # 畳んでいる（プレイヤーの選択。設定に残る）
var _covered := false    # 会話パネルに覆われている（同じ箱に会話を出す間）。畳みとは別の理由で隠れる
var _dragging := false   # 木の地を掴んで引きずっている
var _drag_grip := Vector2.ZERO  # 掴んだ点の、板の左上からのずれ（引きずり中は板がこの点に追従する）
var _drag_from := Vector2.ZERO  # 掴んだときの板の位置（動いていなければ離しても設定を書かない）
var _prev: Button
var _next: Button
var _page_label: Label
var _event_row: Label   # 残りターン（増援の予告）。ページャーの直上に据え置く全幅1行。無ければ隠す
var _event_text := ""   # いま出す文言（空＝出さない）。レポートで隠している間も覚えておく
var _items: Array = []  # いま表示している中身の全行（ページ割りの元）。→ _render
var _page := 0          # 何ページ目を出しているか（0起点）
var _pages: Array = []  # _items をページに割った結果。ページ数の表示にも使う
var _report: CombatReportView  # 戦闘レポート（サマリー/詳細タブ）。戦闘時だけ中身と入れ替えて表示
var _skill_report: SkillReportView  # スキルレポート（陣形・ユニットスキルの解決後）。同じく入れ替えて表示
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
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 8)
	_header.hide()
	box.add_child(_header)
	var head_left := VBoxContainer.new()
	head_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_left.add_theme_constant_override("separation", 2)
	_header.add_child(head_left)
	_header_name = Label.new()
	_header_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head_left.add_child(_header_name)
	_header_sub = Label.new()
	_header_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head_left.add_child(_header_sub)
	# 特性の欄。額は板の右端に固定し、特性名はその左に上寄せで置く。額を先（左）にすると
	# 特性名の長さで額の位置が動く＝駒を選び直すたびにアイコンが横に泳ぐ。
	_ai_box = HBoxContainer.new()
	_ai_box.add_theme_constant_override("separation", 6)
	_ai_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_ai_box.hide()
	_header.add_child(_ai_box)
	_ai_name = Label.new()
	_ai_name.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_ai_box.add_child(_ai_name)
	# 額はアプリ側で描いて絵を嵌める（絵に枠を描き込ませると生成のたびに形が揺らぐ）。
	_ai_frame = PanelContainer.new()
	_ai_frame.add_theme_stylebox_override("panel", TavernTheme.icon_frame_stylebox())
	_ai_frame.custom_minimum_size = Vector2(AI_FRAME_SIZE, AI_FRAME_SIZE)
	_ai_box.add_child(_ai_frame)
	_ai_icon = TextureRect.new()
	_ai_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ai_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ai_frame.add_child(_ai_icon)
	_tabs_row = HBoxContainer.new()
	_tabs_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs_row.add_theme_constant_override("separation", 6)
	_tabs_row.hide()
	box.add_child(_tabs_row)
	var group := ButtonGroup.new()
	for t in TABS:
		var b := TavernTheme.wood_button(tr(String(t[1])))
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(TAB_MIN_W, 0)
		b.pressed.connect(_on_tab_pressed.bind(String(t[0])))
		_tabs_row.add_child(b)
		_tabs[String(t[0])] = b
	# 中身の器。板の内側で切り落とす＝ページ割りが1行ぶんずれても板の外には描かれない。
	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.clip_contents = true
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE  # ホイールは板（_gui_input）へ通す
	box.add_child(_content)
	# 中身は「項目名／値」の2列。値を同じ位置から始めるので、行ごとの控えではなく
	# 幅を決めた欄に入れる（Label 1枚に空白で詰めても等幅フォントでないため揃わない）。
	_rows = VBoxContainer.new()
	_rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rows.add_theme_constant_override("separation", ROW_SEP)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_rows)
	# 器の寸法が決まる／変わったら割り直す。板は固定寸法だが、最初の1回はここで確定する。
	_content.resized.connect(_render)
	# 残りターン（増援の予告）。ページには乗せない＝どのページでも同じ場所に居る。出ている間は
	# 器がそのぶん狭くなり、ページ割りは器の resized で組み直される。仕様 → doc/gdd/uiux.md 残りターン
	_event_row = Label.new()
	_event_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_row.hide()
	box.add_child(_event_row)
	_build_pager(box)
	_report = CombatReportView.new()
	_report.hide()
	add_child(_report)
	_skill_report = SkillReportView.new()
	_skill_report.hide()
	add_child(_skill_report)
	clear()

## 板の下端に据え置く ◀ 2/3 ▶。タブと同じ木のボタンで作る（スクロールバーは材質から浮く）。
## 1ページしかないときも場所は空けたまま無効表示にする＝駒を選び直すたびに下端が動かない。
## 仕様 → doc/gdd/uiux.md ページャー
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
	b.pressed.connect(_turn_page.bind(delta))
	_pager.add_child(b)
	return b

# --- 最小化。仕様 → doc/gdd/uiux.md 最小化 ---
# 入口は HUD の「情報板」ボタンだけ（板に最小化ボタンは置かない）。
# 畳むと板は画面から消え、下にあった盤がそのまま見える。情報板以外（カメラ・盤エリア）は動かさない。
# 畳んでいる間に来た表示（駒の選択・レポート・通知）は中身を更新するだけで、板は開かない。

func set_minimized(minimized: bool) -> void:
	if _minimized == minimized:
		return
	_minimized = minimized
	_apply_visibility()
	minimized_changed.emit(minimized)

func is_minimized() -> bool:
	return _minimized

func toggle_minimized() -> void:
	set_minimized(not _minimized)

## 会話パネルに覆われている間（同じ箱に会話を出す）。畳んでいるかとは別の理由で隠す＝
## 会話が終わっても、畳んでいた板は畳んだまま。
func set_covered(covered: bool) -> void:
	_covered = covered
	_apply_visibility()

func _apply_visibility() -> void:
	visible = not _minimized and not _covered

## ページを送る（範囲外は無視＝端でボタンは無効になっている）。
func _turn_page(delta: int) -> void:
	var to := _page + delta
	if to < 0 or to >= _pages.size():
		return
	_page = to
	_show_page()

## パネルの上でのホイールはページ送り（盤のカメラが動くのはパネルの外だけ）。
## 木の地の左ボタンは板の移動（仕様 → doc/gdd/uiux.md 移動）。ここへ届くのはタブ・ページャー以外
## ＝ボタンは自分で押下を止め、ラベルと中身の器は素通しなので、板の地だけが残る。
## 引きずり中の motion は、押した Control に届き続ける（Viewport のマウスフォーカス）＝板の外へ
## 速く振っても追従が切れない。動ける範囲は決めない＝画面からはみ出してよい。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_grip = mb.global_position - global_position
				_drag_from = position
			elif _dragging:
				_dragging = false
				if position != _drag_from:
					moved.emit(position)  # 押して離しただけ（動いていない）では設定を書かない
			accept_event()
			return
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_DOWN:
					_wheel_page(1)
					accept_event()
				MOUSE_BUTTON_WHEEL_UP:
					_wheel_page(-1)
					accept_event()
	elif event is InputEventMouseMotion and _dragging:
		# 位置は event から取る（実カーソルを読むと、タッチや合成イベントで追従しない）。
		global_position = (event as InputEventMouseMotion).global_position - _drag_grip
		accept_event()

## 既定の場所（UiLayout.RIGHT_BOX）へ戻す。畳んでいれば開く＝戻したのに見えない、を作らない。
## 設定の消し込みは呼ぶ側（main）が行う。仕様 → doc/gdd/uiux.md ターン終了・システムメニュー
func reset_position() -> void:
	_dragging = false
	position = UiLayout.RIGHT_BOX.position
	set_minimized(false)

## ホイール1段ぶんのページ送り。スキルレポート表示中はそちらのページャーへ届ける。
func _wheel_page(delta: int) -> void:
	if _skill_report != null and _skill_report.visible:
		_skill_report.turn_page(delta)
	else:
		_turn_page(delta)

# --- 中身とページ割り ---
# 中身は行の配列（_items）で持ち、ページ1枚ぶんだけを Control にして _rows に並べる。
# 全部を作ってから隠すのではなく作る行を絞るのは、控えが24体ある拠点でも作る量が一定になるため。

## いまの中身を割り直して表示する。器の寸法が決まった／変わったときにも呼ばれる。
func _render() -> void:
	if _rows == null:
		return
	_pages = _paginate(_items)
	_page = clampi(_page, 0, maxi(_pages.size() - 1, 0))
	_show_page()

## ページ1枚ぶんの行を作り直し、ページャーの表示を合わせる。
func _show_page() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)  # queue_free 待ちの旧行が新行と同居して1フレーム崩れるのを避ける
		c.queue_free()
	if _page < _pages.size():
		for it in _pages[_page]:
			_rows.add_child(_make_row(it))
	var total := maxi(_pages.size(), 1)
	_page_label.text = "%d/%d" % [_page + 1, total]
	_prev.disabled = _page <= 0
	_next.disabled = _page >= total - 1

## 器に入る高さを実測して、入るところまで詰めて次のページへ送る。行数の決め打ちはしない
## （フォントか板の寸法を変えた時点で破綻する）。仕様 → doc/gdd/uiux.md ページャー
func _paginate(items: Array) -> Array:
	if items.is_empty():
		return []
	var avail := _content.size.y
	if avail <= 0.0:
		return [items]  # 器の寸法がまだ決まっていない（_content.resized で割り直す）
	var pages: Array = []
	var cur: Array = []
	var used := 0.0
	for it in items:
		if cur.is_empty() and _is_blank(it):
			continue  # ページの頭に空行は置かない（前のページとの間合いはページが変わること自体が示す）
		var h := _item_height(it)
		var add := h if cur.is_empty() else h + ROW_SEP
		if not cur.is_empty() and used + add > avail:
			# 見出し（区切り線・空行・【…】）がページの末尾に残るなら、見出しごと次のページへ送る。
			var carry: Array = []
			while cur.size() > 1 and bool((cur[cur.size() - 1] as Dictionary).get("keep", false)):
				carry.push_front(cur.pop_back())
			while not carry.is_empty() and _is_blank(carry[0]):
				carry.pop_front()
			pages.append(cur)
			cur = carry
			used = _stack_height(carry)
			add = h if cur.is_empty() else h + ROW_SEP
		cur.append(it)
		used += add
	if not cur.is_empty():
		pages.append(cur)
	return pages

## 空行か（ページの頭では捨てる）。
static func _is_blank(item: Dictionary) -> bool:
	return String(item.get("t", "full")) == "full" and String(item.get("text", "")).is_empty()

## 行を積んだときの高さ（行の間の余白ぶんを含む）。
func _stack_height(items: Array) -> float:
	var h := 0.0
	for it in items:
		h += _item_height(it)
	if items.size() > 1:
		h += ROW_SEP * (items.size() - 1)
	return h

## 行1つの高さ。折り返しも数える＝長い名前で2行になる行があってもページ割りがずれない。
func _item_height(item: Dictionary) -> float:
	var font := get_theme_font("font", "Label")
	var fs := get_theme_font_size("font_size", "Label")
	var line := font.get_height(fs)
	var w := _rows.size.x
	var text := String(item.get("text", ""))
	if String(item.get("t", "full")) == "row":
		w -= LABEL_W + ROW_LABEL_GAP  # 項目名の欄は短い前提＝値の欄の折り返しだけ数える
		text = String(item.get("value", ""))
	else:
		w -= float(item.get("indent", 0.0))  # 字下げした行は左が空くぶん狭く折り返す
	if text.is_empty() or w <= 0.0:
		return line
	var measured := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w, fs,
		-1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND).y
	var count := maxi(1, roundi(measured / line))
	return line * count + get_theme_constant("line_spacing", "Label") * (count - 1)

## 行1つを Control にする。「項目名／値」の2列か、幅いっぱいの1行か。
func _make_row(item: Dictionary) -> Control:
	if String(item.get("t", "full")) != "row":
		var full := Label.new()
		full.text = String(item.get("text", ""))
		full.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var indent := float(item.get("indent", 0.0))
		if indent <= 0.0:
			return full
		var box := MarginContainer.new()
		box.add_theme_constant_override("margin_left", int(indent))
		box.add_child(full)
		return box
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_LABEL_GAP)
	var l := Label.new()
	l.text = String(item.get("label", ""))
	l.custom_minimum_size = Vector2(LABEL_W, 0)
	row.add_child(l)
	var v := Label.new()
	v.text = String(item.get("value", ""))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(v)
	return row

## 状態とスキン表を渡す（main から1回）。
func bind(state: BattleState, skin_catalog: Dictionary) -> void:
	_state = state
	_skins = skin_catalog
	_report.bind(skin_catalog)
	_skill_report.bind(skin_catalog)
	clear()

## ステージの地形見た目差分（座標→skin_id）を渡す。盤・戦闘演出と同じものを受ける。
## 地形名は「平地」ではなく実際に見えている絵の名前（「墓地の草地」）で出す＝盤と言葉を合わせる。
func bind_terrain_skins(terrain_skins: Dictionary) -> void:
	_terrain_skins = terrain_skins

## 特性表（data/ai/ai.json）を渡す（main から1回）。敵の見出しに出す特性名の引き先。
func bind_ai_presets(presets: Dictionary) -> void:
	_ai_presets = presets

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
	if _skill_report != null:
		_skill_report.hide()
	_update_header(u)
	_header.show()
	var b: Button = _tabs[_tab]
	b.button_pressed = true
	_tabs_row.show()
	_content.show()
	_pager.show()
	_sync_event_row()
	_rebuild_rows(u, _tab)

## タブを押した＝表示中の駒をそのタブで描き直す。
func _on_tab_pressed(id: String) -> void:
	_tab = id
	if _shown_unit >= 0:
		show_unit(_shown_unit)

## 未選択の案内。1行1項目の箇条書きなので行ごとにキーを立てる（翻訳CSVに改行を持たせない）。
## 空行は言語の話ではないのでここで持つ。
## 言語が変わったので文言を貼り直す（doc/tech/i18n.md 言語の切り替え）。
## パネルの中身は表示のたびに組み直すので、焼き込みが残るのは戦闘レポートのタブ見出しだけ。
func refresh_labels() -> void:
	_report.refresh_labels()

func clear() -> void:
	_show_text("\n".join([
		tr("ui.info.help_no_selection"),
		"",
		tr("ui.info.help_select_unit"),
		tr("ui.info.help_inspect_tile"),
		"",
		tr("ui.info.help_controls"),
		tr("ui.info.help_end_turn"),
		tr("ui.info.help_pan"),
		tr("ui.info.help_zoom"),
		tr("ui.info.help_fit"),
	]))

## 残りターン（増援の予告）を流し込む。event＝BattleState.next_event() の戻り（{ label, turns }）。
## 文言は label（翻訳キー）の訳文が全部を持ち、{n} に残りターン数が入る＝言語ごとに語順を変えられる。
## 空なら行ごと隠れ、中身の器がそのぶん広がる。仕様 → doc/gdd/uiux.md 残りターン
func set_event(event: Dictionary) -> void:
	var key := String(event.get("label", ""))
	_event_text = "" if key.is_empty() else tr(key).format({ "n": int(event.get("turns", 0)) })
	_event_row.text = _event_text
	_sync_event_row()

## 行を出すか＝文言があり、かつ板の中身（ページャー）が出ているとき。レポート中は隠す。
func _sync_event_row() -> void:
	_event_row.visible = not _event_text.is_empty() and _pager.visible

## 一時的な通知（セーブ完了など）。数秒だけ出して未選択表示へ戻す。
## 上端の情報バーを廃した代わりの置き場（doc/gdd/uiux.md「ターン表示」）。
func notify(text: String, seconds := 2.5) -> void:
	_show_text(text)
	var token := _notify_token + 1
	_notify_token = token
	await get_tree().create_timer(seconds).timeout
	if _notify_token == token and is_inside_tree():
		clear()  # 後から別の表示に切り替わっていれば（token 不一致）何もしない

## 空きマスの地形情報を表示（拠点なら控えも一覧）。HexBoard.tile_inspected を受ける。
func show_terrain(hex: Vector2i) -> void:
	if _state == null or _rows == null:
		clear()
		return
	_enter_text_view()
	_build_terrain_lines(hex)
	_page = 0
	_render()

## 素のテキスト表示（未選択・通知）。見出しとタブは引っ込める＝ユニット専用の器なので。
## 1行ずつに割ってから積む＝長い案内もページャーで送れる（表示の仕組みはタブと共通）。
func _show_text(text: String) -> void:
	if _rows == null:
		return
	_enter_text_view()
	for line in text.split("\n"):
		_add_full_row(line)
	_page = 0
	_render()

## 幅いっぱいの行だけを出す器にする（見出しとタブを引っ込め、中身を空にする）。
func _enter_text_view() -> void:
	if _report != null:
		_report.hide()
	if _skill_report != null:
		_skill_report.hide()
	_shown_unit = -1
	_header.hide()
	_tabs_row.hide()
	_content.show()
	_pager.show()
	_sync_event_row()
	_items = []

## グループの切れ目。線の上に余白を1行取り、下は空けない＝線をその下のグループの見出し罫として
## 読ませる。板の高さは決め打ち（UiLayout.RIGHT_BOX）で、上下に空けると素の駒でも入りきらない。
func _add_separator() -> void:
	_add_full_row("")
	_add_full_row(SEPARATOR)

## そのマスの地形の表示名。ステージの見た目差分があればスキン名（「墓標の荒れ地」）、
## 無ければ地形タイプの既定スキン名（「荒地」）。盤に見えている絵と同じ言葉にする。
func _terrain_name(hex: Vector2i, type_id: String) -> String:
	var skin := TerrainSkinCatalog.resolve(String(_terrain_skins.get(hex, "")), type_id)
	return tr("terrain." + skin.skin_id + ".name") if skin != null else type_id

func _build_terrain_lines(hex: Vector2i) -> void:
	var terr := _state.terrain_at(hex)
	_add_head_row(tr("ui.info.terrain_head") % _terrain_name(hex, terr))
	_add_full_row("")
	_add_full_row("%s  ×%.2f" % [tr("ui.info.atk_mod"), TerrainType.attack_factor(terr)])
	_add_full_row("%s  ×%.2f" % [tr("ui.info.def_mod"), TerrainType.defense_factor(terr)])

	_add_separator()
	_add_head_row(tr("ui.info.move_cost_head"))
	_add_movement_cost_rows(terr)

	# 控えは体数ぶん伸びる（24体の拠点もある）ので最後に置く。行数の決まっている地形の話を
	# 先に出し切る＝はみ出すとしても控えの尻尾だけにする。
	var b := _state.base_at(hex)
	if b == null:
		return
	_add_separator()
	var kind_name := tr("ui.info.hq") if b.is_hq() else tr("ui.info.base")
	_add_head_row(tr("ui.info.base_head") % [kind_name, _team_text(b.team)])
	if b.garrison.is_empty():
		_add_full_row("%s  %s" % [tr("ui.info.reserves"), tr("ui.info.reserves_none")])
	else:
		_add_full_row("%s  %s" % [tr("ui.info.reserves"),
			tr("ui.info.reserves_count") % b.garrison.size()])
		for gu in b.garrison:
			_add_full_row(tr("ui.info.reserves_bullet") % _garrison_line(gu, b))

## 陣営の表示名。拠点の所有者（中立あり）に使う。
func _team_text(team: int) -> String:
	if team < 0:
		return tr("ui.info.team_neutral")
	return tr("ui.info.team_ally") if team == 0 else tr("ui.info.team_enemy")

## そのマスへの進入コストを「項目名／値」の行として足す（移動タイプ1行ずつ。見出しは呼ぶ側が
## 置く）。並びは movement.csv の行順で、常に全移動タイプを出す＝行の並びがステージやマスで
## 変わらない。仕様 → doc/gdd/uiux.md
## 桁合わせは他の項目と同じ LABEL_W の欄に任せる。空白で詰めると英語（文字ごとに幅が違う）で
## 崩れる。ユニットの地形タブと空きマスの表示の両方から呼ぶ＝同じ字面になる。
func _add_movement_cost_rows(terrain_id: String) -> void:
	var table := _state.movement_table()
	for mt in Movement.display_order():
		var c := Movement.cost(table, mt, terrain_id)
		_add_row(tr("movement." + mt + ".name"),
			tr("ui.info.impassable") if c == Movement.IMPASSABLE else str(c))

## 控え1体の1行表示（名前・兵数・レベル）。
func _garrison_line(gu: Unit, b: Base) -> String:
	var team_for_skin := gu.team if gu.team >= 0 else (b.team if b.team >= 0 else 0)
	var sk := SkinCatalog.resolve(_skins, gu.skin_id, gu.type_id, team_for_skin)
	var nm := tr("unit." + sk.skin_id + ".name") if sk != null else gu.type_id
	return tr("ui.info.reserves_line") % [nm, gu.troops, gu.max_troops, gu.level]

## タブの上に据え置く見出しを組み直す。仕様 → doc/gdd/uiux.md ユニット情報パネル
## 2行目は敵＝部隊名／自軍＝兵種。敵に兵種を出さないのはリスキン元（種別）が透けるため。
func _update_header(u: Unit) -> void:
	var skin: UnitSkin = SkinCatalog.resolve(_skins, u.skin_id, u.type_id, u.team)
	var unit_name := tr("unit." + skin.skin_id + ".name") if skin != null else u.type_id
	var team_name := tr("ui.info.team_ally") if u.team == 0 else tr("ui.info.team_enemy")
	_header_name.text = tr("ui.info.header_name") % [unit_name, team_name]
	var sub := ""
	if u.team == 0:
		var cat := UnitCatalog.display_category(u.type_id)
		sub = tr("category." + cat + ".name") if not cat.is_empty() else ""
	else:
		sub = _squad_name(u)
	_header_sub.text = sub
	_header_sub.visible = not sub.is_empty()
	_update_ai(u)

## 敵の見出し2行目＝所属部隊の名前。部隊は一斉警戒の範囲＝この駒に触れると誰まで起きるかを示す。
## name はステージが持つ表示名で tr() を通す（i18n 移行時にキーへ差し替えられる）。
## name の無い部隊は order から組む＝名前を書かなくても部隊が分かれていることは見せる。
func _squad_name(u: Unit) -> String:
	var squad := _state.squad_of(u.id)
	if squad.is_empty():
		return ""
	var nm := String(squad.get("name", ""))
	if not nm.is_empty():
		return tr(nm)
	var order: Variant = squad.get("order")
	var n := _state.squad_index_of(u.id) + 1
	if typeof(order) == TYPE_INT or typeof(order) == TYPE_FLOAT:
		n = int(order)
	return tr("ui.info.squad_n") % n

## 特性の欄（敵だけ）。アイコンは在れば出す＝未制作でも文字だけで成立する。
func _update_ai(u: Unit) -> void:
	var id := ""
	if u.team != 0:
		id = String(_state.squad_of(u.id).get("ai", ""))
	if id.is_empty():
		_ai_box.hide()
		return
	_ai_name.text = tr("ai." + id + ".name")
	var tex := _ai_icon_texture(id)
	_ai_icon.texture = tex
	_ai_frame.visible = tex != null  # 絵が無ければ額ごと消す＝特性名の文字だけで成立させる
	_ai_box.show()

## 特性アイコン（無ければ null）。有無は一度引いたら控えておく＝選択のたびに走らせない。
func _ai_icon_texture(id: String) -> Texture2D:
	if _ai_icons.has(id):
		return _ai_icons[id]
	var path := AI_ICON_DIR + id + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_ai_icons[id] = tex
	return tex

# --- タブの中身（項目名／値の2列）。値の頭は LABEL_W でタブをまたいで揃う ---

## いま選んでいるタブの中身を組み直して1ページ目から出す。
func _rebuild_rows(u: Unit, tab: String) -> void:
	_items = []
	match tab:
		"status":
			_build_status(u)
		"terrain":
			_build_terrain(u)
		_:
			_build_ability(u)
	_page = 0
	_render()

## 項目1つ＝「項目名（幅固定）／値」の1行。
func _add_row(label: String, value: String) -> void:
	_items.append({"t": "row", "label": label, "value": value})

## 幅いっぱいの1行（区切り線・控えの箇条書きなど、項目名／値に割れないもの）。
func _add_full_row(text: String) -> void:
	_items.append(_full_item(text))

## 幅いっぱいの見出し行（【地形】など）。ページの末尾に取り残さない印を明示的に付ける。
func _add_head_row(text: String) -> void:
	_items.append({"t": "full", "text": text, "keep": true})

## 左を indent px 空けた全幅の行（スキルの説明など、直前の行に従属する文）。折り返しの幅も
## そのぶん狭く数える＝ページ割りがずれない。
func _add_indent_row(text: String, indent: float) -> void:
	_items.append({"t": "full", "text": text, "keep": false, "indent": indent})

## 全幅1行の行データ。区切り線とその上の空行には、ページの末尾に取り残さない印（keep）を
## 付ける＝入らなければ次のページへ送られる。見出しは字面では見分けない（言語ごとに飾りが
## 変わり、日本語の【…】だけを見ると英語で印が付かなくなる）＝_add_head_row で明示する。
static func _full_item(text: String) -> Dictionary:
	var keep := text.is_empty() or text == SEPARATOR
	return {"t": "full", "text": text, "keep": keep}

## 能力＝駒そのものの性能（盤の状況で変わらない値）。
func _build_ability(u: Unit) -> void:
	_add_row(tr("ui.info.strength"), "%d / %d" % [u.troops, u.max_troops])
	_add_row(tr("ui.info.level"), str(u.level))
	_add_row(tr("ui.info.atk_ground"), str(u.unit_attack))
	_add_row(tr("ui.info.atk_air"), str(u.atk_air) if u.atk_air > 0 else NONE)
	_add_row(tr("ui.info.defense"), str(u.unit_defense))
	_add_row(tr("ui.info.move"), str(u.move))
	_add_row(tr("ui.info.move_type"), tr("movement." + u.move_type + ".name"))
	_add_row(tr("ui.info.range"), str(u.attack_range) if u.min_range == u.attack_range \
		else "%d-%d" % [u.min_range, u.attack_range])
	# 特性は「他の行を見ても分からないこと」だけ並べる。飛行は「移動種別」、遠隔・近接不可は
	# 「射程」がそのまま示すので置かない（同じことを二度書かない）。詳細 → doc/gdd/units.md
	var traits: Array[String] = []
	if u.pierce > 0.0:
		# 魔法兵50%＝相手の防御を半分無視
		traits.append(tr("ui.info.trait_pierce") % roundi(u.pierce * 100.0))
	if u.can_capture:
		traits.append(tr("ui.info.trait_capture"))
	if u.move_after_attack:
		traits.append(tr("ui.info.trait_move_after_attack"))
	for t in traits:
		_add_row(tr("ui.info.trait"), t)
	# ユニットスキル＝この駒が撃てる単独発動のスキルと、その効果の説明。盤の状況（対象の有無・
	# 行動済み）には依らない＝能力タブの「駒そのものの性能」に合わせる。敵の駒でも出す（ゴーストを
	# 選んでドレッドタッチが何をするか読める）。名前と説明は規約キー（names.csv）で引く。
	# 仕様 → doc/gdd/uiux.md ユニット情報パネル
	# 特性と同じ「項目名／値」の1行に名前を出し、説明は名前の頭に揃えて字下げした全幅行で続ける。
	# 区切り線や見出しを置かないのは、置くと1ページ目に入らず、ページ2の存在に気づかれないため
	# （2026-09 実測＝器の高さが 368px だった時点で、兵数〜特性で 239px・見出し付きの節は 161px）。
	for rid in Formation.unit_skills_of(u):
		_add_row(tr("ui.info.skill"), tr("recipe." + rid + ".name"))
		_add_indent_row(tr("recipe." + rid + ".desc"), LABEL_W + ROW_LABEL_GAP)

## 状態＝このターン何ができるか＋いま効いているバフ・デバフ。
## 包囲は地形ではなく「隣の敵に囲まれて弱っている」＝デバフなのでここに置く。
func _build_status(u: Unit) -> void:
	_add_row(tr("ui.info.action"), _action_state(u))
	_add_separator()
	var mods := _state.status_mods_for(u)
	var surround := Surround.factor(_state, u)
	if mods.is_empty() and surround >= 1.0:
		_add_row(tr("ui.info.modifier"), tr("ui.info.modifier_none"))
		return
	# 表記は戦闘レポートと共通＝名前 攻/防 の順。残りは「掛けた側のターンがあと何回で切れるか」
	# （敵ターンを跨いでも減らない＝BattleState._expire_status_mods）。
	for m in mods:
		_add_row(tr("ui.info.modifier"), tr("ui.info.modifier_remaining") \
			% [CombatReportView.status_text(m), int(m.get("remaining", 0))])
	if surround < 1.0:
		_add_row(tr("ui.info.encircled"), tr("ui.info.encircled_value") % surround)

## 地形＝いるマスの影響（拠点に乗っていればその情報も）。
func _build_terrain(u: Unit) -> void:
	var terr := _state.terrain_at(u.pos)
	_add_row(tr("ui.info.terrain"), _terrain_name(u.pos, terr))
	_add_row(tr("ui.info.atk_mod"), "×%.2f" % TerrainType.attack_factor(terr))
	_add_row(tr("ui.info.def_mod"), "×%.2f" % TerrainType.defense_factor(terr))
	_add_separator()
	_add_head_row(tr("ui.info.move_cost_head"))
	_add_movement_cost_rows(terr)
	# 控えは体数ぶん伸びるので最後（_build_terrain_lines と同じ順序）。
	var b := _state.base_at(u.pos)
	if b == null:
		return
	_add_separator()
	_add_row(tr("ui.info.hq") if b.is_hq() else tr("ui.info.base"), _team_text(b.team))
	_add_row(tr("ui.info.reserves"), tr("ui.info.reserves_count") % b.garrison.size())
	for gu in b.garrison:
		_add_full_row(tr("ui.info.reserves_bullet") % _garrison_line(gu, b))

## 行動状態の短い説明。
func _action_state(u: Unit) -> String:
	if not _state.is_current_unit(u):
		return tr("ui.info.act_awaiting_turn")
	if _state.is_done(u.id):
		return tr("ui.info.act_done")
	if _state.is_stuck(u.id):
		# 行動は残っているが動く先も撃つ相手も無い（陣形には参加できる）
		return tr("ui.info.act_stuck")
	var parts: Array[String] = []
	parts.append(tr("ui.info.act_can_move") if _state.can_still_move(u.id) \
		else tr("ui.info.act_moved"))
	parts.append(tr("ui.info.act_can_attack") if not _state.has_attacked(u.id) \
		else tr("ui.info.act_attacked"))
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
	_content.hide()
	_pager.hide()
	_event_row.hide()
	_skill_report.hide()
	_report.show()
	_report.show_report(detail)

## 陣形・ユニットスキルの解決後はスキルレポート。攻撃の戦闘レポートと同じ扱いで、発動と同時に
## 出して次の選択まで残す。result は MatchController.formation_resolved のもの。
## 仕様 → doc/tech/combat_scene.md 右パネル（スキルレポート）
func show_skill_report(result: Dictionary) -> void:
	if result == null or result.is_empty():
		return
	_shown_unit = -1
	_header.hide()
	_tabs_row.hide()
	_content.hide()
	_pager.hide()
	_event_row.hide()
	_report.hide()
	_skill_report.show()
	_skill_report.show_result(result)
