extends CanvasLayer
class_name VictoryScreen
## キャンペーン完走（最終ステージ勝利）で出す勝利イラスト。仕様 → doc/gdd/stage_select.md
## 画像は冒険譚ごとの victory スロット（assets/campaign/{id}/{id}_victory.png・無ければ表示しない）。
## 出し方は2つ:
##  - play_over_board(path): 盤エリアに置き、outro 会話に重ねる（既定）。非モーダル＝右の会話パネルは
##    そのまま読み進められる。絵の前で最後の会話をさせる＝フィナーレを一続きにする。main が dismiss で閉じる。
##    黒帯は敷かない＝絵の周りは（暗幕越しに）マップが見えたままでよい。
##  - play(path): 全画面モーダル。outro 会話が無い冒険譚のフォールバック。クリック/キーで閉じ finished を出す。

signal finished  # 全画面モーダルを閉じた（クリック/キー or 画像なし）。main がセレクトへ戻す合図。

const FADE_IN := 0.4  # イラストの浮かび上がり（秒）
const BOARD_MARGIN := 32.0  # 重ね表示で盤エリアの内側に取る余白。右は会話パネルとの間合いになる

## 絵の四隅を彫り枠と同じ半径で削るシェーダ。枠は角丸・絵は直角だと四隅が枠の外へ飛び出すため、
## 描画時にアルファで丸める（マスク用のノードを足さない）。smoothstep の 1px 幅がアンチエイリアス。
const ROUNDED_SHADER := """
shader_type canvas_item;
uniform vec2 rect_px;     // 絵の実寸（px）
uniform float radius_px;  // 角の半径（彫り枠と同じ値）
void fragment() {
	vec2 half_px = rect_px * 0.5;
	vec2 q = abs(UV * rect_px - half_px) - (half_px - vec2(radius_px));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius_px;
	COLOR.a *= 1.0 - smoothstep(-1.0, 1.0, d);
}
"""

var _root: Control        # 表示域（モーダルは全画面・重ね表示は盤エリアの内側）
var _backdrop: ColorRect  # イラスト外側を覆う黒（レターボックス）。全画面モーダルのときだけ敷く
var _pic: TextureRect     # 勝利イラスト（アスペクト維持で中央）
var _tween: Tween
var _modal := true  # true＝入力を食いクリックで閉じる／false＝敷くだけ（入力は会話パネルへ通す）

func _ready() -> void:
	_build()

## ノードツリーを1度だけ組む（_ready 前に play が来ても安全なよう遅延生成にも対応）。
func _build() -> void:
	if _root != null:
		return
	layer = 60  # 戦闘演出(50)より前面＝最前面のフィナーレ
	_root = Control.new()  # 矩形は _layout が決める（アンカーを使わない＝盤エリアに絞れるように）
	_root.gui_input.connect(_on_input)
	add_child(_root)
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)  # _root（＝表示域）いっぱいに敷く
	_backdrop.color = Color(0, 0, 0, 1)  # イラスト外側は黒帯（4:3 を表示域に収める）
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)
	_pic = TextureRect.new()
	# 収める寸法は _fit_pic が自分で計算する（KEEP_ASPECT_CENTERED に任せない）＝
	# 絵の実寸が矩形と一致し、縁取りを絵の縁にぴったり合わせられる。
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # 元画像より小さくできるように
	_pic.stretch_mode = TextureRect.STRETCH_SCALE
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = ROUNDED_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("radius_px", float(TavernTheme.FRAME_CORNER_RADIUS))
	_pic.material = mat  # rect_px は寸法が決まる _fit_pic で渡す
	_root.add_child(_pic)
	# 縁取りは右の会話パネルと同じ彫り枠を流用する（新しい見た目を発明しない）。
	# 絵の子にする＝FULL_RECT アンカーで絵の寸法にそのまま追従する。
	_pic.add_child(TavernTheme.signboard_frame())
	var v := get_viewport()
	if v != null:
		v.size_changed.connect(func() -> void:
			if visible:
				_layout())
	visible = false

## 全画面モーダルで出す（outro 会話が無い場合のフォールバック）。
## path が空/未存在なら即 finished（呼び出し側のスキップ判定の二重ガード）。
func play(path: String) -> void:
	if not _start(path, true):
		finished.emit()

## 盤エリアに敷いて出す（outro 会話に重ねる）。閉じるのは main＝会話の終わりに合わせる。
func play_over_board(path: String) -> void:
	_start(path, false)

## 画像を読み、表示域を決めて浮かび上がらせる。出せたか（画像が在ったか）を返す。
func _start(path: String, modal: bool) -> bool:
	_build()
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	_modal = modal
	# モーダルは入力を食う。重ね表示は通す＝右の会話パネルを読み進められる。
	_root.mouse_filter = Control.MOUSE_FILTER_STOP if modal else Control.MOUSE_FILTER_IGNORE
	_backdrop.visible = modal  # 重ね表示では黒帯を敷かない＝絵の外はマップが見えたまま
	_pic.texture = load(path) as Texture2D
	visible = true
	_layout()
	_root.modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN)
	return true

## 表示域＝モーダルは全画面、重ね表示は盤エリアの内側（余白のぶん会話パネルから離す）。
## 絵はこの矩形にアスペクト維持で収まる＝余りは黒で埋めず、マップが透けて見える。
func _layout() -> void:
	var vp := Vector2(1152, 648)
	var v := get_viewport()
	if v != null:
		vp = v.get_visible_rect().size
	var r := Rect2(Vector2.ZERO, vp) if _modal else UiLayout.board_area(vp).grow(-BOARD_MARGIN)
	_root.position = r.position
	_root.size = r.size  # 黒帯は FULL_RECT アンカーで _root に追従する
	_fit_pic()

## 絵を表示域にアスペクト維持で収める（端は切らない）。位置・寸法を自分で持つので、
## 絵の子に付けた彫り枠がそのまま絵の縁を囲む。
func _fit_pic() -> void:
	if _pic.texture == null:
		return
	var ts := _pic.texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var s := minf(_root.size.x / ts.x, _root.size.y / ts.y)
	_pic.size = (ts * s).round()
	_pic.position = ((_root.size - _pic.size) * 0.5).round()
	var mat := _pic.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("rect_px", _pic.size)  # 角丸の計算に実寸が要る

func _on_input(e: InputEvent) -> void:
	if not _modal:
		return  # 重ね表示は会話が進行役＝絵をクリックしても閉じない
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed):
		if visible:
			dismiss()
			finished.emit()

## 表示を閉じる。重ね表示では main が会話の終了で呼ぶ。
## フェードアウトは掛けない＝直後に開くセレクト(layer 10)より前面(60)なので、薄れる絵がセレクトに被る。
func dismiss() -> void:
	if not visible:
		return
	visible = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
