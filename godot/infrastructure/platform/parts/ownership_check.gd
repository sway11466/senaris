@abstract
extends RefCounted
class_name OwnershipCheck
## 所有権チェックの口。仕様 → doc/tech/platform.md 本体が見る口

## その追加コンテンツ（content_id）を持っているか。
@abstract func owns(content_id: String) -> bool
