extends RefCounted
class_name GimmickVisual
## 仕掛け1種類ぶんの見た目の数値（gimmick_visual.csv の1行）。振る舞い（状態の一覧・踏んだときの動き）は
## GimmickKinds（domain）が持ち、ここは持たない＝見た目は表・振る舞いはコード。
## 絵は規約で引く＝assets/gimmicks/{kind}_{state}.png（盤）／{kind}_{state}_combat_{slot}.png（戦闘）。
## 仕様 → doc/gdd/gimmicks.md 絵／作り方 → doc/art/gimmicks.md

const STAND := "stand"  ## 立てる＝駒と同じくカメラに正対する立ち絵
const FLAT := "flat"    ## 床に貼る＝マスの中心に寝かせた板に貼る（床に刻まれた紋・爆発の跡）

var kind: String      ## 種類（GimmickKinds.KINDS のキーと一致）
var name: String      ## 管理名（開発用のメモ）
## 絵のある状態 → 置き方（STAND / FLAT）。表では「状態:置き方」を | で区切って1つのセルに書く
## （例 found:stand|spent:flat）。絵の無い状態（隠れている罠）は書かない。
var placement := {}
## 盤での大きさ＝絵の幅がヘックスの幅の何割か。書き出し（tools/gen_gimmick.ps1）だけが読む
## ＝盤は絵のキャンバスの余白で大きさを出す（地形のオブジェクトと同じ）。立てる絵と床に貼る絵で共用。
var map_scale: float
## 画面のどれだけ下（手前）へ寄せるか（地形の object_foot_z と同じ意味）。駒（0.6）より小さくする
## ＝駒が仕掛けのマスに乗ると駒が手前に立つ。立てる絵だけが使う（立てる状態の無い種類は 0）。
var foot_z: float
## 戦闘の隊列の後ろの絵の背丈（ファイター何体ぶん）。書き出しだけが読む。隊列の後ろの絵を持たない種類は 0。
var combat_scale: float
## 罠の一撃で駒の上に出す絵＝攻撃エフェクトの表（combat_effect.csv）の effect_id。既存の絵を使い回せる
## （地雷＝ボマーの爆発 bomb）。空＝一撃の絵がまだ無い（マスを光らせるだけ）。罠でない種類は空。
var hit_effect: String

static func from_dict(d: Dictionary) -> GimmickVisual:
	var v := GimmickVisual.new()
	v.kind = String(d.get("kind", ""))
	v.name = String(d.get("name", ""))
	v.placement = parse_placement(d.get("placement"))["map"]
	v.map_scale = _num(d.get("map_scale"))
	v.foot_z = _num(d.get("foot_z"))
	v.combat_scale = _num(d.get("combat_scale"))
	v.hit_effect = String(d.get("hit_effect", "")).strip_edges()
	return v

## state を床に貼るか。表に無い状態は false（絵が無い＝描かない状態なので、置き方は問われない）。
func is_flat(state: String) -> bool:
	return String(placement.get(state, "")) == FLAT

## 置き方のセル → { map: 状態 → 置き方, problems: 書き間違い }。convert の検査と読み込みが同じ解釈を使う。
static func parse_placement(cell: Variant) -> Dictionary:
	var out := {}
	var problems: Array = []
	var text := String(cell).strip_edges() if typeof(cell) == TYPE_STRING else ""
	if text.is_empty():
		problems.append("placement が空（状態:stand|状態:flat の形で、絵のある状態を全部書く）")
		return { "map": out, "problems": problems }
	for part in text.split("|"):
		var kv := part.split(":")
		var st := kv[0].strip_edges() if kv.size() == 2 else ""
		var how := kv[1].strip_edges() if kv.size() == 2 else ""
		if st.is_empty() or not (how == STAND or how == FLAT):
			problems.append("placement の '%s' が不正（状態:stand か 状態:flat）" % part)
		elif out.has(st):
			problems.append("placement の状態 '%s' が重複" % st)
		else:
			out[st] = how
	return { "map": out, "problems": problems }

## 数値だけを受ける（空・文字列は 0＝convert が先に弾くので、ここに来るのは検証済みの値）。
static func _num(x: Variant) -> float:
	return float(x) if typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT else 0.0
