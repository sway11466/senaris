extends VBoxContainer
class_name ChronicleChapter
## クロニクルの1章＝ユーザーが目にする1つのオブジェクト（ユニット／陣形スキル／冒険譚）。
## 仕様 → doc/gdd/chronicle.md
##
## 画面（ChronicleScreen）が持つのは暗幕・見出し・左の目次・戻るボタンまでで、右のペインから
## 先はこの章が自分で組む。章のなかの選び（どのレシピを選んだか・どの冒険譚を開いたか・
## その2段目のどれを見ているか）も章が持つ＝画面は「いまどの章か」しか知らない。
##
## 画面との口:
##   bind            画面を開くときに1回。持ち物を渡す
##   rebuild         中身を組み直せ
##   reset           章を離れる＝選びを捨てろ
##   toc_keys        左の目次に出す行（空なら画面が1段目＝章の一覧を出す）
##   toc_selected    そのうち枠を付ける番号
##   select_toc      目次が押された
##   handle_back     戻る／Esc。自分で受け止めたら true
##   back_label      戻るボタンに出す翻訳キー
##   refresh_labels  言語が変わった
##   toc_changed     目次と戻るの文言を組み直してほしい（中身は章が自分で組み直す）

signal toc_changed

var _store: ChronicleStore = null
var _progress: CampaignProgress = null
var _skins: Dictionary = {}   # SkinCatalog
var _types: Dictionary = {}   # UnitCatalog（{ type_id: UnitType }）
var _overlay: Control = null  # 画面全体を覆うものの置き場（ユニットの拡大カード）

var _content_scroll: ScrollContainer
var _content_box: VBoxContainer        # 上段＝一覧
var _detail_box: VBoxContainer = null  # 下段＝詳細。1段で組んだ章では null

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", ChronicleStyle.HEAD_GAP)
	_build_panes()

## 画面が開くときに1回。持ち物を渡し、章のなかの選びを初期に戻す。
func bind(p_store: ChronicleStore, p_progress: CampaignProgress, p_skins: Dictionary,
		p_types: Dictionary, p_overlay: Control) -> void:
	_store = p_store
	_progress = p_progress
	_skins = p_skins
	_types = p_types
	_overlay = p_overlay
	reset()

## 章のなかの選びを初期に戻す（画面を開くとき・この章を離れるとき）。
func reset() -> void:
	pass

## 中身を組み直す。空にしてから章ごとの _build を呼ぶ。
func rebuild() -> void:
	for c in _content_box.get_children():
		c.queue_free()
	if _detail_box != null:
		for c in _detail_box.get_children():
			c.queue_free()
	_build()

## 中身を組む（章ごと）。
func _build() -> void:
	pass

## 左の目次に出す翻訳キー。空なら画面が1段目（章の一覧）を出す。
func toc_keys() -> Array:
	return []

## 目次のうち枠を付ける番号（toc_keys が空なら見ない）。
func toc_selected() -> int:
	return -1

func select_toc(_idx: int) -> void:
	pass

## 戻る／Esc。自分で受け止めたら true（画面は閉じない）。効果音も自分で鳴らす。
func handle_back() -> bool:
	return false

## 戻るボタンに出す翻訳キー。
func back_label() -> String:
	return "ui.chronicle.back"

## 言語が変わった。中身は画面が rebuild を呼ぶので、それ以外の後始末だけ。
func refresh_labels() -> void:
	pass

## 下段の詳細ペインを持つか。ユニット章は拡大カードで詳細を出すので持たない。
func _wants_detail_pane() -> bool:
	return true

## 上段の器の幅が変わった（寸法が幅で決まるユニット章だけが使う）。
func _on_content_resized() -> void:
	pass

## 右のペイン＝上段のスクロールと、章が望めば下段の詳細。
func _build_panes() -> void:
	_content_scroll = ScrollContainer.new()
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_box = VBoxContainer.new()
	_content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_box.add_theme_constant_override("separation", ChronicleStyle.ITEM_GAP)
	_content_scroll.add_child(_content_box)
	_content_scroll.resized.connect(_on_content_resized)
	add_child(_content_scroll)

	if not _wants_detail_pane():
		return
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.custom_minimum_size = Vector2(0, 160)
	_detail_box.add_theme_constant_override("separation", 4)
	add_child(_detail_box)
