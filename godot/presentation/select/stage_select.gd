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
const RANK_MARK_D := 38.0    # 木札に押すランクの印の直径（札の高さ48に収まる大きさ）
const RANK_MARK_FONT := 26   # 印の字の上限。実際の大きさは直径側で頭打ちになる
const RANK_MARK_FILL := 1.15 # 丸の大きさは据え置いて字だけ太らせる（戦果票の印と同じ扱い）
const RANK_MARK_DROP := 0.04 # 字を丸の中心より少し下げる（同上）
const RANK_MARK_PAD := 10.0  # 札の右端から印までの余白
const INTERLUDE_DIR := "res://assets/icons/interlude/"  # 幕間の印の絵（{interlude}.png）
const INTERLUDE_H := 24.0  # 幕間の印の高さ。札と札のあいだの中央に置く

var _rank_font_cache: Font = null

var _progress: CampaignProgress
var _title: Label
var _art: ColorRect                    # 左＝冒険譚の絵（絵が無ければタイトルのプレースホルダ）
var _art_label: Label
var _art_texture: TextureRect          # 冒険譚の扉絵（cover_path があれば表示）
var _stage_list: VBoxContainer         # 右＝縦リスト
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

	_stage_list = VBoxContainer.new()
	_stage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_list.add_theme_constant_override("separation", 8)
	stage_scroll.add_child(_stage_list)

	# 冒険譚選択へ戻る。戻りは常に画面の左下＝上はステージ名の場所なので空けておく
	# （doc/gdd/stage_select.md）。絵に重ねず行として持つ＝余白は TavernTheme と同値で揃う。
	var footer := HBoxContainer.new()
	vbox.add_child(footer)
	_back = TavernTheme.back_button(tr("ui.select.back_tales"))
	_back.pressed.connect(_on_back)
	footer.add_child(_back)

	_briefing = QuestSheet.new()
	_briefing.confirmed.connect(_on_sortie)
	add_child(_briefing)

func _on_back() -> void:
	SfxPlayer.play_event("menu_back")
	back_requested.emit()

## Esc は「← 冒険譚」と同じ入口（doc/gdd/stage_select.md 画面の骨格）。依頼書が出ているときは
## 依頼書が先に受けて閉じる（木の札は焦点を持たないので、鍵盤はここまで降りてくる）。
## visible でなく is_visible_in_tree（campaign_select.gd と同じ理由）。
func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and not _briefing.visible and event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

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
		var s: Dictionary = c["stages"][i]
		# 幕間の印は「次の行の前」＝その話の前で兵が戻るなら、前の札との間に挟む。
		# 未解放の行の前でも出す（伏せるのは題名だけ）。doc/gdd/stage_select.md 幕間の印
		var mark := _interlude_mark(String(s["interlude"]))
		if mark != null:
			_stage_list.add_child(mark)
		_stage_list.add_child(_stage_row(campaign_id, s, i + 1))

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
	var rank := ""
	match stage_state:
		CampaignProgress.CLEARED:
			# ランクがあれば札の右端に焼き印で押す＝そちらがクリアの印になるので ✓ は出さない。
			# ランクを持たないステージ（rank を書いていないデバッグ盤など）だけ ✓ のまま。
			rank = _progress.best_rank(campaign_id, String(s["id"]))
			if rank.is_empty():
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
	if not rank.is_empty():
		row.add_child(_rank_mark(rank))
	return row

## 札と札のあいだに挟む幕間の印（ベッド＝休息／十字＝復帰）。印なし・絵なしは null。
## 絵はアスペクト維持で高さ INTERLUDE_H に収め、行の中央に置く。額は付けない（板に直に載せる）。
func _interlude_mark(interlude: String) -> Control:
	if interlude.is_empty():
		return null
	var path := INTERLUDE_DIR + interlude + ".png"
	if not ResourceLoader.exists(path):
		return null
	var holder := CenterContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mark := TextureRect.new()
	mark.texture = load(path)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex_size: Vector2 = mark.texture.get_size()
	mark.custom_minimum_size = Vector2(INTERLUDE_H * tex_size.x / maxf(tex_size.y, 1.0), INTERLUDE_H)
	holder.add_child(mark)
	return holder

## 木札の右端に押すランクの印＝戦果票の判子をそのまま小さくしたもの。暗い木の上なので
## 封蝋の赤ではなく焼き印の琥珀で押す。字だけを置くと「文字が1つ増えた」に見えて押した感じが
## 出ないので、丸枠ごと縮める（38px でも二重の枠と字は潰れない。実測で確認）。
## 字は戦果票の印と同じ書体＝小さくても形が読める（手書き風は1文字だと崩れが形の全部になる）。
func _rank_mark(rank: String) -> Control:
	var mark := TavernTheme.stamp(rank, TavernTheme.BRAND, -6.0, RANK_MARK_FONT, 1.0,
		RANK_MARK_D, _rank_font(), RANK_MARK_FILL, RANK_MARK_DROP)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 札の右端に縦中央で貼る（アンカーで置く＝札の幅が変わっても付いていく）。
	mark.set_anchors_preset(Control.PRESET_CENTER_RIGHT, true)
	mark.position = Vector2(-mark.size.x - RANK_MARK_PAD, -mark.size.y * 0.5)
	return mark

## 印の字の書体（戦果票と同じ）。無ければ既定のまま。
func _rank_font() -> Font:
	if _rank_font_cache == null and ResourceLoader.exists(ResultBanner.RANK_FONT_PATH):
		_rank_font_cache = load(ResultBanner.RANK_FONT_PATH) as Font
	return _rank_font_cache

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
	var path := String(s["path"])
	_pending = {
		"campaign_id": campaign_id,
		"stage_id": String(s["id"]),
		"path": path,
	}
	# 顔ぶれ・戦力の供給は紙を開くときだけステージJSONを1本読んで作る（一覧では読まない）。
	# 名簿は毎回読み直す＝直前の戦いの損耗が紙に出る。読むのは引き継ぎ元のステージの控え（盤の開始と同じ）。
	var source := _progress.roster_source(campaign_id, String(s["id"]))
	var roster: Array = RosterStore.new().load_roster(campaign_id, source) if not source.is_empty() else []
	var brief := StageLoader.load_briefing(path, roster)
	_briefing.open(tr(String(s["title"])), brief.get("party", []), bool(brief.get("carryover", false)))

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
