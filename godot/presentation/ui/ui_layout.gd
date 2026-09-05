class_name UiLayout
## 画面レイアウトの共有定数。右の情報ボックス（InfoPanel／会話／戦闘詳細が入る箱）の矩形と、
## それを除いた盤エリアの計算をここに集約する。main.tscn の InfoPanel 配置と必ず一致させること
## （.tscn は定数を参照できないため、変更時は両方を同時に更新する）。
## 参照元: main.gd（会話パネル）・combat_scene.gd（演出窓・暗幕）・hex_board_3d.gd（カメラ可視域）

const RIGHT_BOX_LEFT := 800.0
const RIGHT_BOX := Rect2(RIGHT_BOX_LEFT, 96.0, 464.0, 608.0)  # x=800..1264 / y=96..704（下も右と同じ 16px 余白）

## 盤に常設するタイトルロゴ。右ボックスの上に空く帯（y=0..96）の中に、右端を右ボックスの
## 右端にそろえて置く。幅は絵の縦横比から決める（透明な余白を除いた実体で測る）。
## 仕様 → doc/gdd/uiux.md
const LOGO_H := 72.0
const LOGO_TOP := 12.0  # 帯の上下中央（(96 - 72) / 2）

## 情報板が右ボックスを塞いでいるか（＝既定の場所で開いているか）。畳んでいる・動かしてある間は
## false になり、盤エリアが画面全体に広がる。板の状態を知っているのは main だけなので、そこから
## 押してもらう＝レイアウトの計算がノードツリーを覗きに行かない。仕様 → doc/gdd/uiux.md 盤エリア
static var _panel_holds_right_box := true

## 情報板の状態が変わった（畳む／開く／動かす／既定へ戻す）。main が押す。
static func set_panel_holds_right_box(holds: bool) -> void:
	_panel_holds_right_box = holds

## 盤エリア＝情報板が塞いでいない側（戦闘演出の窓・カットイン・完走イラスト・カメラの基準）。
## 板が既定の場所で開いていれば右ボックスを除いた左側、それ以外は画面全体。
## ビューポートが右ボックスより狭ければ、どちらでも全幅。仕様 → doc/gdd/uiux.md 盤エリア
static func board_area(vp: Vector2) -> Rect2:
	var w := minf(vp.x, RIGHT_BOX_LEFT) if _panel_holds_right_box else vp.x
	return Rect2(0.0, 0.0, w, vp.y)

## ターン終了ボタンの左端（幅 w のボタンを置く x）。盤エリアではなく右ボックスの既定の場所を見る
## ＝板を畳んでも動かしても場所が変わらない（毎ターン押す物はいつも同じ所にある）。
static func end_turn_left(vp: Vector2, w: float) -> float:
	return minf(vp.x, RIGHT_BOX_LEFT) - 16.0 - w
