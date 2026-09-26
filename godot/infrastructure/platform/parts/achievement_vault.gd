@abstract
extends RefCounted
class_name AchievementVault
## 実績の保管庫の口。実績はゲーム本体の機能で、Steam はその保管先の1つ。仕様 → doc/tech/platform.md 本体が見る口
## id は Steamworks に登録する API 名と同じ文字列＝チャネルごとの読み替え表は持たない。

## 実績を解除する。解除済みなら何もしない＝発火点で確かめずに呼んでよい。
@abstract func unlock(id: String) -> void

@abstract func is_unlocked(id: String) -> bool

## 解除済みの実績の一覧。
@abstract func unlocked_ids() -> PackedStringArray
