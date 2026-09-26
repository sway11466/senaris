extends OwnershipCheck
class_name AlwaysOwned
## 所有権チェックの部品「常に所有」。手元にある製品版は買ったものとみなすチャネルと、
## DLC を収録しない体験版で使う。仕様 → doc/tech/platform.md アダプターと部品

func owns(_content_id: String) -> bool:
	return true
