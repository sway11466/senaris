extends RefCounted
class_name StageDigest
## ステージ定義の印（内容ハッシュ）。中断セーブに記録し、セーブ後にステージ定義が
## 変わったこと（難易度調整）の検出に使う。仕様 → doc/tech/gamesystem.md §ステージ更新の検出
##
## 盤に効かないキーだけを明示的に外し、それ以外すべてを対象にする＝新しいキーを足したとき
## 書き忘れても「印が変わる＝通知が出る」側へ倒れる。
## ステージJSONに版番号は持たない（上げ忘れが起きない）＝印は内容から毎回計算する。

## 印の算出から外すキー（盤に効かないもの）。
const EXCLUDED_KEYS := ["name", "dialogue", "bgm", "backdrop", "haze"]

## ステージ辞書 → 印（sha256 の16進文字列）。
static func compute(data: Dictionary) -> String:
	var pruned := data.duplicate()
	for k in EXCLUDED_KEYS:
		pruned.erase(k)
	return _canonical(pruned).sha256_text()

## res:// パスの JSON から印を計算する。読めない/不正 → ""（印なし＝不明として通知側へ倒れる）。
static func of_file(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ""
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	return compute(data)

## 正規化した文字列表現。JSON.stringify に寄せず自前で組む＝エンジンの整形の癖（版差）に
## 印を依存させない。辞書のキーはソートする＝書き並べ順では印が変わらない。
static func _canonical(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var keys: Array = (v as Dictionary).keys()
			keys.sort()
			var parts: Array = []
			for k in keys:
				parts.append("%s:%s" % [_canonical(String(k)), _canonical(v[k])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var items: Array = []
			for e in v:
				items.append(_canonical(e))
			return "[%s]" % ",".join(items)
		TYPE_STRING:
			return JSON.stringify(v)  # エスケープだけエンジンに任せる（文字列単体の形は一意）
		TYPE_FLOAT:
			# JSON経由の数値はすべて float で届く。整数値は整数表記に寄せる＝手元の dict（int）と
			# JSON往復後（float）で印が割れないようにする。
			var f := float(v)
			return str(int(f)) if f == floorf(f) else str(f)
		TYPE_INT:
			return str(v)
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_NIL:
			return "null"
		_:
			return JSON.stringify(v)
