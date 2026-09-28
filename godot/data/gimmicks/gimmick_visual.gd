extends RefCounted
class_name GimmickVisual
## 仕掛け1種類ぶんの見た目の数値（gimmick_visual.csv の1行）。振る舞い（状態の一覧・踏んだときの動き）は
## GimmickKinds（domain）が持ち、ここは持たない＝見た目は表・振る舞いはコード。
## 絵は規約で引く＝assets/gimmicks/{kind}_{state}.png（盤）／{kind}_{state}_combat_{slot}.png（戦闘）。
## 仕様 → doc/gdd/gimmicks.md 絵／作り方 → doc/art/gimmicks.md

var kind: String      ## 種類（GimmickKinds.KINDS のキーと一致）
var name: String      ## 管理名（開発用のメモ）
## 盤での大きさ＝絵の幅がヘックスの幅の何割か。書き出し（tools/gen_gimmick.ps1）だけが読む
## ＝盤は絵のキャンバスの余白で大きさを出す（地形のオブジェクトと同じ）。
var map_scale: float
## 画面のどれだけ下（手前）へ寄せるか（地形の object_foot_z と同じ意味）。駒（0.6）より小さくする
## ＝駒が仕掛けのマスに乗ると駒が手前に立つ。
var foot_z: float
## 戦闘の隊列の後ろの絵の背丈（ファイター何体ぶん）。書き出しだけが読む。隊列の後ろの絵を持たない種類は 0。
var combat_scale: float

static func from_dict(d: Dictionary) -> GimmickVisual:
	var v := GimmickVisual.new()
	v.kind = String(d.get("kind", ""))
	v.name = String(d.get("name", ""))
	v.map_scale = _num(d.get("map_scale"))
	v.foot_z = _num(d.get("foot_z"))
	v.combat_scale = _num(d.get("combat_scale"))
	return v

## 数値だけを受ける（空・文字列は 0＝convert が先に弾くので、ここに来るのは検証済みの値）。
static func _num(x: Variant) -> float:
	return float(x) if typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT else 0.0
