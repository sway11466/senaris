extends RefCounted
class_name BgmCatalog
## トラックID → BGM ファイルの解決（規約 autowire）と bgm スロットの読み取り。
## data層＝純データ・純ロジック（音は鳴らさない）。詳細 → doc/audio/bgm.md
##
## 曲はトラックID（"menu" / "map_calm" / "boss" …）で扱い、assets/bgm/{track_id}.ogg を規約で解決する。
## ファイルが在れば鳴り、無ければ ""＝呼び出し側は無音＋ログ1行（絵のプレースホルダの音版。ゲームは止めない）。
## 曲が完成したら .ogg を置くだけで鳴り出す＝コード・データ変更なし（skin 画像の autowire と同型）。

const BGM_ROOT := "res://assets/bgm"

## bgm 欄のスロット（main＝必須 / crisis＝任意＝状態切替用）。将来 intro 等はここに足す。
const SLOTS := ["main", "crisis"]

## トラックIDのファイルパス。トラックID が空、またはファイルが未配置なら ""。
static func path_of(track_id: String) -> String:
	if track_id.is_empty():
		return ""
	var p := "%s/%s.ogg" % [BGM_ROOT, track_id]
	return p if ResourceLoader.exists(p) else ""

## トラックIDの .ogg が置かれているか。
static func exists(track_id: String) -> bool:
	return not path_of(track_id).is_empty()

## "bgm" 欄（{ main, crisis }）→ 埋まっているスロットだけの辞書。
## ステージJSON と campaign.json の両方で同じ書式なので、data 層に置いて双方から使う。
## 値が文字列でない/空のスロットは落とす＝呼び出し側はフォールバック連鎖で埋める（BgmDirector）。
static func parse_slots(value: Variant) -> Dictionary:
	var out := {}
	if typeof(value) != TYPE_DICTIONARY:
		return out
	var bgm: Dictionary = value
	for slot in SLOTS:
		var v: Variant = bgm.get(slot, "")
		if typeof(v) == TYPE_STRING and not String(v).is_empty():
			out[slot] = String(v)
	return out
