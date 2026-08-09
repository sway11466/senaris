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

## 戦闘演出での並べ方（unit_skin.csv の combat_lineup 列）。→ doc/tech/combat_scene.md
const LINEUP_SQUAD := "squad"      ## 本人の絵を兵量ぶん複製（既定）
const LINEUP_RETINUE := "retinue"  ## 先頭＝本人・残りは retainers（ボス系）
const LINEUP_SINGLE := "single"    ## 1体だけ描く（馬車・ドラゴン級＝数えられない駒）
const LINEUPS := [LINEUP_SQUAD, LINEUP_RETINUE, LINEUP_SINGLE]

var skin_id: String       ## スキンID（主キー。ステージはこれで見た目を指定）。skin→type は1:1
var type_id: String       ## 紐づく性能(UnitType)のID
var name: String          ## 表示名（例: クレリック / ゴブリン）
var category: String      ## 管理分類（基準/ゴブリン/アンデッド…）。参考データ＝ゲームロジックで参照しない（ツール・図鑑用）
var description: String    ## 説明文（図鑑/ツールチップ用。任意）
var images: Dictionary     ## { "map": "res://...", "combat": "res://...", "portrait": "res://..." }（未設定は空＝プレースホルダ）
var combat_lineup: String = LINEUP_SQUAD  ## 戦闘演出での並べ方（LINEUPS のいずれか）
var combat_effect: String  ## 攻撃エフェクトID（data/effects/combat_effect.csv）。空＝既定のスパーク
var map_move_sfx: String   ## 移動音の素材ID（SfxCatalog.MOVE_SFX）。空＝移動タイプの既定。→ doc/audio/sfx.md
var retainers: Array       ## 戦闘演出で脇に並べる別スキンの skin_id（先頭＝本人の隣）。retinue のときだけ使う。→ doc/tech/combat_scene.md

static func from_dict(d: Dictionary) -> UnitSkin:
	var s := UnitSkin.new()
	s.skin_id = String(d.get("skin_id", ""))
	s.type_id = String(d.get("type_id", ""))
	s.name = String(d.get("name", ""))
	s.category = String(d.get("category", ""))
	s.description = String(d.get("description", ""))
	s.images = d.get("images", {})
	var lineup := String(d.get("combat_lineup", ""))
	s.combat_lineup = lineup if LINEUPS.has(lineup) else LINEUP_SQUAD  # 未知値は既定へ倒す（描かない事故にしない）
	s.combat_effect = String(d.get("combat_effect", ""))
	s.map_move_sfx = String(d.get("map_move_sfx", ""))
	var r: Variant = d.get("retainers", [])
	s.retainers = r if typeof(r) == TYPE_ARRAY else []
	return s

## 1体だけ描く駒か（複製しない）。馬車・飛空艇・ドラゴン級＝兵として数えられない見た目。
func is_single_figure() -> bool:
	return combat_lineup == LINEUP_SINGLE

## マップ表示のプレースホルダ文字（名前の先頭2文字）。
func map_label() -> String:
	return name.substr(0, 2)

## 戦闘表示のプレースホルダ文字（フルネーム）。
func combat_label() -> String:
	return name

## 会話の顔（portrait）のプレースホルダ文字（名前の先頭2文字）。未用意時に丸顔などへ描く合図。
func portrait_label() -> String:
	return name.substr(0, 2)

## スロットの画像パス（"map"/"combat"…）。未設定は ""（＝プレースホルダで描く合図）。
func image(slot: String) -> String:
	return String(images.get(slot, ""))
