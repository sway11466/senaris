extends RefCounted
class_name ArtCrop
## 絵の実体（非透過部分）の外接矩形を画像パスごとに覚える。
##
## get_image() は GPU からの読み戻しで 1 枚 10ms を超える（384 角の盤の絵で実測）。開くたびに
## 全部やると画面が 1 秒近く固まるので、矩形はプロセスの間持ち続けて 2 回目からは読み戻さない。
## 絵が変わるのはビルドの外（アセットの差し替え）なので、実行中に古くなることはない。
## 使うのはクロニクルのカード（ChronicleCardChapter）と依頼書の顔ぶれ（QuestSheet）。

static var _rects := {}  # 画像パス → Rect2（size が 0＝実体が取れない）

## 覚えているか（裏読みの絵を待たずに載せられるかの判定に使う）。
static func has(path: String) -> bool:
	return _rects.has(path)

## 実体の矩形。取れなければ size 0 の Rect2。
static func used_rect(tex: Texture2D, path: String) -> Rect2:
	if _rects.has(path):
		return _rects[path]
	var used := Rect2()
	var img := tex.get_image()
	if img != null:
		var r := img.get_used_rect()
		used = Rect2(r.position, r.size)
	_rects[path] = used
	return used
