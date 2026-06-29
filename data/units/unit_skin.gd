extends RefCounted
class_name UnitSkin
## ユニットの見た目＋識別（名前・説明・画像）。性能(UnitType)とは分離。
## 詳細 → doc/gdd/units.md, doc/art/overview.md
##
## 1つの性能(UnitType)に複数のスキンがぶら下がる（陣営別・テーマ別の別名）。
## ゴブリンと守護像は同じ cleric 性能の別スキン。どのスキンを使うかは冒険譚側が決める。
##
## 画像が未用意の間は name のプレースホルダで描く:
##   マップ表示 = 名前の先頭2文字（例: クレリック→「クレ」）
##   戦闘表示   = フルネーム
## images にパスを入れれば、描画側がそちらに切り替える（コードは不変）。

var skin_id: String       ## スキンID（主キー。ステージはこれで見た目を指定）。skin→type は1:1
var type_id: String       ## 紐づく性能(UnitType)のID
var name: String          ## 表示名（例: クレリック / ゴブリン）
var description: String    ## 説明文（図鑑/ツールチップ用。任意）
var images: Dictionary     ## { "map": "res://...", "combat": "res://..." }（未設定は空＝プレースホルダ）

static func from_dict(d: Dictionary) -> UnitSkin:
	var s := UnitSkin.new()
	s.skin_id = String(d.get("skin_id", ""))
	s.type_id = String(d.get("type_id", ""))
	s.name = String(d.get("name", ""))
	s.description = String(d.get("description", ""))
	s.images = d.get("images", {})
	return s

## マップ表示のプレースホルダ文字（名前の先頭2文字）。
func map_label() -> String:
	return name.substr(0, 2)

## 戦闘表示のプレースホルダ文字（フルネーム）。
func combat_label() -> String:
	return name

## スロットの画像パス（"map"/"combat"…）。未設定は ""（＝プレースホルダで描く合図）。
func image(slot: String) -> String:
	return String(images.get(slot, ""))
