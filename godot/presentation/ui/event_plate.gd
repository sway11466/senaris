extends Control
class_name EventPlate
## 残りターン板（presentation）。未発生の増援があるあいだ、あと何ターンで来るかを常時見せる。
## 右の情報ボックスの直下に、幅を合わせた板を1枚。仕様 → doc/gdd/uiux.md 残りターン板
##
## 文言はイベントの label（翻訳キー）が全部を持つ。訳文に {n} を書くと残りターン数が入る
## （例「飛空艇 到着まで あと{n}ターン」）＝言語ごとに語順を変えられる。
## 状態は持たず main から set_event() で流し込む。無ければ隠れる。

const LABEL_SIZE := 20

var _panel: Panel
var _label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 盤の入力を邪魔しない
	visible = false
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)

func _build() -> void:
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", TavernTheme.plaque_stylebox())
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", LABEL_SIZE)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)

## 右ボックスの直下へ置き直す。リサイズでも呼ばれる。
func _layout() -> void:
	position = UiLayout.EVENT_PLATE.position
	size = UiLayout.EVENT_PLATE.size

## 予告を流し込む。event＝BattleState.next_event() の戻り（{ label, turns }）。空なら隠す。
func set_event(event: Dictionary) -> void:
	var key := String(event.get("label", ""))
	if key.is_empty():
		visible = false
		return
	_label.text = tr(key).format({ "n": int(event.get("turns", 0)) })
	visible = true
