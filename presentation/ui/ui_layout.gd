class_name UiLayout
## 画面レイアウトの共有定数。右の情報ボックス（InfoPanel／会話／戦闘詳細が入る箱）の矩形と、
## それを除いた盤エリアの計算をここに集約する。main.tscn の InfoPanel 配置と必ず一致させること
## （.tscn は定数を参照できないため、変更時は両方を同時に更新する）。
## 参照元: main.gd（会話パネル）・combat_scene.gd（演出窓・暗幕）・hex_board_3d.gd（カメラ可視域）

const RIGHT_BOX_LEFT := 800.0
const RIGHT_BOX := Rect2(RIGHT_BOX_LEFT, 96.0, 464.0, 532.0)  # x=800..1264 / y=96..628

## 盤に常設するタイトルロゴ。右ボックスの上に空く帯（y=0..96）の中に、右端を右ボックスの
## 右端にそろえて置く。幅は絵の縦横比から決める（透明な余白を除いた実体で測る）。
## 仕様 → doc/gdd/uiux.md
const LOGO_H := 72.0
const LOGO_TOP := 12.0  # 帯の上下中央（(96 - 72) / 2）

## 残りターン板（増援の予告）。右ボックスの直下に幅を合わせて置く。仕様 → doc/gdd/uiux.md
const EVENT_PLATE_GAP := 10.0
const EVENT_PLATE_H := 44.0
const EVENT_PLATE := Rect2(
	RIGHT_BOX_LEFT, RIGHT_BOX.end.y + EVENT_PLATE_GAP, RIGHT_BOX.size.x, EVENT_PLATE_H)

## 右ボックスを除いた盤エリア（戦闘演出の窓・暗幕の基準）。ビューポートが狭ければ全幅。
static func board_area(vp: Vector2) -> Rect2:
	return Rect2(0.0, 0.0, minf(vp.x, RIGHT_BOX_LEFT), vp.y)
