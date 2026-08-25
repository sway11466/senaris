extends Control
class_name StageSelect
## ステージ選択画面。仕様 → doc/gdd/stage_select.md
## 左＝選んだ冒険譚の扉絵（無ければタイトルのプレースホルダ）／右＝ステージの縦リスト
## （locked/unlocked/cleared）→ ブリーフィング → 出撃。ステージはカードにしない
## ＝絵は冒険譚単位で1枚だけ。状態は持たず、show_campaign() のたびに導出して描く。
## 戻る・出撃はシグナルで SelectScreen へ委ねる。

signal stage_chosen(campaign_id: String, stage_id: String, path: String)
signal back_requested

const ROW_HEIGHT := 48.0
const LOCKED_TILTS := [-2.0, 1.4, -1.6, 2.2]  # 裏返した札の傾き（度）

## 連戦の綴じ紐。ステージ行の左に、隊ごとの縦線を1本ずつ通す。仕様 → doc/gdd/stage_select.md 連戦の区間
## その隊が出る話は実線、初出から最後の登場までのあいだで出ない話は薄い線＝待機していて後で戻る。
## 行の y は隣の VBox から借りる（自前で行の高さを再計算しない＝折り返しで背の伸びた行にも追随する）。
class _Lanes extends Control:
	const W := 14.0    # レーン1本ぶんの幅
	const LINE := 2.0  # 線の太さ
	const CAP := 8.0   # 端を止める横棒の長さ
	const DIM := 0.6   # 出番の無い区間の濃さ。暗い木の上では 0.3 だと消えて「線が途切れた」に見える
	const DASH := 6.0  # 出番の無い区間の破線の刻み。濃さだけでなく形も変える＝意味の違いを見せる

	var rows: VBoxContainer = null  # 行の並び（y 位置の借り元）
	var spans: Array = []           # レーンごとの { first, last, active }（表示順）

	func _draw() -> void:
		if rows == null:
			return
		var color := TavernTheme.BRAND  # 焼き印と同じ色＝暗い木の上で読める
		var count := rows.get_child_count()
		var dy := rows.position.y - position.y
		for j in spans.size():
			var span: Dictionary = spans[j]
			var first := int(span["first"])
			var last := int(span["last"])
			if first >= count or last >= count:
				continue  # 行より多い span は描かない（データが食い違っても壊れない）
			var active: Dictionary = span["active"]
			var x := W * (float(j) + 0.5)
			var top := _top(first, dy)
			var bottom := _bottom(last, dy)
			# 待機の区間は破線でつなぐ＝切れてはいないが、いまは出ていないと読める。
			draw_dashed_line(Vector2(x, top), Vector2(x, bottom), Color(color, DIM), LINE, DASH)
			for i in range(first, last + 1):
				if not active.has(i):
					continue
				var seg_end := _bottom(i, dy)
				if i < last and active.has(i + 1):
					seg_end = _top(i + 1, dy)  # 行間も埋める＝続いていることを途切れさせない
				draw_line(Vector2(x, _top(i, dy)), Vector2(x, seg_end), color, LINE)
			for y in [top, bottom]:
				draw_line(Vector2(x - CAP * 0.5, y), Vector2(x + CAP * 0.5, y), color, LINE)

	func _top(i: int, dy: float) -> float:
		return (rows.get_child(i) as Control).position.y + dy

	func _bottom(i: int, dy: float) -> float:
		var c := rows.get_child(i) as Control
		return c.position.y + c.size.y + dy

var _progress: CampaignProgress
var _title: Label
var _art: ColorRect                    # 左＝冒険譚の絵（絵が無ければタイトルのプレースホルダ）
var _art_label: Label
var _art_texture: TextureRect          # 冒険譚の扉絵（cover_path があれば表示）
var _stage_list: VBoxContainer         # 右＝縦リスト
var _lanes: _Lanes                     # 縦リストの左に通す連戦の綴じ紐
var _briefing: QuestSheet
var _back: Button                      # 冒険譚選択へ戻る（起動時に作って生き続ける＝refresh_labels の対象）
var _pending := {}  # ブリーフィング表示中のステージ { campaign_id, stage_id, path }

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	header.add_child(_title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	# --- 左: 冒険譚の絵（cover_path があれば扉絵／無ければタイトルのプレースホルダ） ---
	_art = ColorRect.new()
	_art.color = Color(0.15, 0.18, 0.24)
	_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_art.size_flags_stretch_ratio = 2.0  # 絵:リスト ≒ 2:1
	_art.clip_contents = true  # 絵をパネル枠でトリミング
	# 絵の無いときの下地も同じ丸みにする（絵だけ丸めると四隅に下地の直角が残る）。
	# 半径は彫り枠（signboard_frame）に合わせる＝直角のままだと四隅が枠線の外へ飛び出す。
	TavernTheme.round_corners(_art, float(TavernTheme.FRAME_CORNER_RADIUS))
	body.add_child(_art)

	_art_texture = TextureRect.new()
	_art_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED  # パネルを覆う（はみ出しは clip）
	TavernTheme.round_corners(_art_texture, float(TavernTheme.FRAME_CORNER_RADIUS))
	_art.add_child(_art_texture)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.add_child(center)

	_art_label = Label.new()
	_art_label.add_theme_font_size_override("font_size", 32)
	center.add_child(_art_label)

	# 縁取りは勝利画面の扉絵と同じ彫り枠を流用する（新しい見た目を発明しない）。
	# 絵の最後の子にする＝FULL_RECT アンカーでパネルの寸法に追従し、絵の上に重なる。
	_art.add_child(TavernTheme.signboard_frame())

	# --- 右: ステージの縦リスト（壁に掛かった背板の上に並べる） ---
	# 板は左の絵パネルと同じ高さに伸びる＝左右が釣り合い、行の下の壁の空きも埋まる。
	var list_board := PanelContainer.new()
	list_board.add_theme_stylebox_override("panel", TavernTheme.list_board_stylebox())
	list_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_board.size_flags_stretch_ratio = 1.0  # 絵:リスト ≒ 2:1
	body.add_child(list_board)

	var stage_scroll := ScrollContainer.new()
	stage_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_board.add_child(stage_scroll)

	# 綴じ紐は行と同じスクロール内に置く＝一覧を送っても線が置き去りにならない。
	var listing := HBoxContainer.new()
	listing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	listing.add_theme_constant_override("separation", 0)
	stage_scroll.add_child(listing)

	_lanes = _Lanes.new()
	_lanes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lanes.size_flags_vertical = Control.SIZE_FILL
	listing.add_child(_lanes)

	_stage_list = VBoxContainer.new()
	_stage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_list.add_theme_constant_override("separation", 8)
	listing.add_child(_stage_list)
	_lanes.rows = _stage_list
	# 行が並び直すたびに引き直す（初回の配置も、折り返しで背が変わったときもここで拾う）。
	_stage_list.sort_children.connect(_lanes.queue_redraw)

	# 冒険譚選択へ戻る。戻りは常に画面の左下＝上はステージ名の場所なので空けておく
	# （doc/gdd/stage_select.md）。絵に重ねず行として持つ＝余白は TavernTheme と同値で揃う。
	var footer := HBoxContainer.new()
	vbox.add_child(footer)
	_back = TavernTheme.back_button(tr("ui.select.back_tales"))
	_back.pressed.connect(func() -> void:
		SfxPlayer.play_event("menu_back")
		back_requested.emit())
	footer.add_child(_back)

	_briefing = QuestSheet.new()
	_briefing.confirmed.connect(_on_sortie)
	add_child(_briefing)

## 言語が変わったので文言を貼り直す（doc/tech/i18n.md 言語の切り替え）。
## 貼り紙の行は開くたびに組み直すので、起動時から生き続けるのは戻るボタンだけ。
func refresh_labels() -> void:
	_back.text = tr("ui.select.back_tales")

func setup(progress: CampaignProgress) -> void:
	_progress = progress

## 指定した冒険譚のステージ一覧を表示する（SelectScreen から呼ばれる）。
func show_campaign(campaign_id: String, variant: int = -1) -> void:
	var c := _progress.campaign(campaign_id)
	if c.is_empty():
		return
	_title.text = tr(String(c["title"]))  # title は翻訳キー（i18n）。生テキストでも tr() は素通し
	# variant>=0 ならボードで表示中の絵に固定（board→stage で絵が変わらない）。<0 は表示ごとにランダム。
	# 全クリア済み（カードに DONE が押されている状態）なら扉絵を勝利絵に差し替える＝踏破後の姿。
	# 勝利絵を持たない冒険譚は従来の cover のまま。カード側の絵は変えない（同じ章と分かるように）。
	var art_paths: Array = c.get("cover_paths", [])
	if _progress.is_all_cleared(campaign_id):
		var victory: Array = c.get("victory_paths", [])
		if not victory.is_empty():
			art_paths = victory
	_set_cover(_variant_at(art_paths, variant), tr(String(c["title"])))
	_clear_children(_stage_list)
	for i in c["stages"].size():
		_stage_list.add_child(_stage_row(campaign_id, c["stages"][i], i + 1))
	_lanes.spans = lanes_of(c["stages"])
	_lanes.custom_minimum_size.x = _Lanes.W * float(_lanes.spans.size())  # 隊が無ければ幅0＝溝も出ない
	_lanes.queue_redraw()

## ステージ一覧 → 連戦レーン（表示順）。1レーン＝1隊で、{ first, last, active } を持つ。
## first/last＝その隊が最初／最後に出るステージの index、active＝出るステージの index の集合。
## 純関数（描画に依存しない）。仕様 → doc/gdd/stage_select.md 連戦の区間
static func lanes_of(stages: Array) -> Array:
	var order: Array = []  # 隊の登場順＝レーンの並び順
	var by_party := {}
	for i in stages.size():
		for p in (stages[i] as Dictionary).get("party", []):
			var key := String(p)
			if not by_party.has(key):
				order.append(key)
				by_party[key] = { "first": i, "last": i, "active": {} }
			by_party[key]["last"] = i
			by_party[key]["active"][i] = true
	var out: Array = []
	for key in order:
		out.append(by_party[key])
	return out

## 扉絵を表示。cover_path があれば絵＋ラベル非表示、無ければプレースホルダ（タイトル）へ。
func _set_cover(cover_path: String, title: String) -> void:
	var tex: Texture2D = null
	if cover_path != "":
		tex = load(cover_path) as Texture2D
	_art_texture.texture = tex
	_art_texture.visible = tex != null
	_art_label.text = "" if tex != null else title

## ステージ1行。未解放は裏返した札（名前を出さず傾けた板）で返すので、戻りは Control。
func _stage_row(campaign_id: String, s: Dictionary, number: int) -> Control:
	var label := "%d. %s" % [number, tr(String(s["title"]))]  # stage.title は翻訳キー（i18n）
	var stage_state := _progress.stage_state(campaign_id, String(s["id"]))
	var locked := stage_state == CampaignProgress.LOCKED
	var text := label
	match stage_state:
		CampaignProgress.CLEARED:
			text = "✓ %s" % label
		CampaignProgress.LOCKED:
			text = "%d." % number  # 名前は伏せる＝裏返した札。解放条件は押すと依頼書で出す
	# 依頼ボードに下がる木札（focus_mode は wood_button 側で NONE 済み）。
	var row := TavernTheme.wood_button(text)
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if locked:
		# 押せるままにして押されたら音＋依頼書を返す（disabled にしない理由は dim_wood_button）。
		TavernTheme.flip_wood_button(row)
		row.pressed.connect(_open_locked.bind(campaign_id, String(s["id"])))
		return _tilted(row, number)
	row.pressed.connect(_open_briefing.bind(campaign_id, s))
	return row

## 裏返した札を少し傾ける＝掛け直されていない札に見せる。角度は番号で巡回＝並びが機械的にならない。
## Container は並べ直すたびに子の rotation を 0 に戻すので、素の Control で1枚くるんでその中で回す
## （VBox が触るのは外側だけ）。回転の軸は札の中心＝寸法が変わるたびに取り直す。
func _tilted(row: Button, number: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.rotation = deg_to_rad(float(LOCKED_TILTS[number % LOCKED_TILTS.size()]))
	row.pivot_offset = row.size * 0.5
	row.resized.connect(func() -> void: row.pivot_offset = row.size * 0.5)
	holder.add_child(row)
	return holder

# --- ブリーフィング → 出撃 ---

func _open_briefing(campaign_id: String, s: Dictionary) -> void:
	SfxPlayer.play_event("menu_stage")
	_pending = {
		"campaign_id": campaign_id,
		"stage_id": String(s["id"]),
		"path": String(s["path"]),
	}
	_briefing.open(tr(String(s["title"])))

## 未解放の札を押したとき＝拒否音＋解放条件だけを書いた紙を出す（ステージ名は出さない）。
func _open_locked(campaign_id: String, stage_id: String) -> void:
	SfxPlayer.play_event("menu_locked")
	_briefing.open_locked(_progress.unlock_text(campaign_id, stage_id))

func _on_sortie() -> void:
	if _pending.is_empty():
		return
	stage_chosen.emit(_pending["campaign_id"], _pending["stage_id"], _pending["path"])
	_pending = {}

## ボタン自身の pressed 発行中に呼ばれる（＝即時 free は「locked object」エラー）ため遅延解放。
func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

## 連番バリアントから1枚選ぶ。idx>=0 ならその index に固定（範囲外は畳む）、idx<0 は表示ごとに randi。空なら ""。
func _variant_at(paths: Array, idx: int) -> String:
	if paths.is_empty():
		return ""
	var i := (idx % paths.size()) if idx >= 0 else (randi() % paths.size())
	return String(paths[i])
