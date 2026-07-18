extends CanvasLayer
class_name VictoryScreen
## キャンペーン完走（最終ステージ勝利）で出す全画面の勝利イラスト。仕様 → doc/gdd/stage_select.md
## main が play(path) を呼ぶ。クリック/キーで閉じ、finished を出す（main がセレクトへ戻す）。
## 画像は冒険譚ごとの victory スロット（assets/campaign/{id}/{id}_victory.png・無ければ表示しない）。

signal finished  # 閉じた（クリック/キー or 画像なし）。main がセレクトへ戻す合図。

const FADE_IN := 0.4  # イラストの浮かび上がり（秒）

var _root: Control        # 全画面の入力キャッチ（モーダル）
var _backdrop: ColorRect  # イラスト外側を覆う黒（レターボックス）
var _pic: TextureRect     # 勝利イラスト（アスペクト維持で中央）
var _tween: Tween

func _ready() -> void:
	_build()

## ノードツリーを1度だけ組む（_ready 前に play が来ても安全なよう遅延生成にも対応）。
func _build() -> void:
	if _root != null:
		return
	layer = 60  # 戦闘演出(50)より前面＝最前面のフィナーレ
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # 表示中は盤入力を食う（モーダル）
	_root.gui_input.connect(_on_input)
	add_child(_root)
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0, 0, 0, 1)  # イラスト外側は黒帯（4:3 を画面比に収める）
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)
	_pic = TextureRect.new()
	_pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED  # 全体を見せる（端を切らない）
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_pic)
	visible = false

## 勝利イラストを出す。path が空/未存在なら即 finished（呼び出し側のスキップ判定の二重ガード）。
func play(path: String) -> void:
	_build()
	if path.is_empty() or not ResourceLoader.exists(path):
		finished.emit()
		return
	_pic.texture = load(path) as Texture2D
	visible = true
	_root.modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN)

func _on_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed):
		_dismiss()

func _dismiss() -> void:
	if not visible:
		return
	visible = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	finished.emit()
