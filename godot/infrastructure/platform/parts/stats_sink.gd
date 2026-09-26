@abstract
extends RefCounted
class_name StatsSink
## Stats の口。こちらの計測用で、プレイヤーには見えない。仕様 → doc/tech/platform.md 本体が見る口
## 計測は数え上げだけ（ステージの開始数・クリア数）なので、加算だけを持つ。

@abstract func add(stat_id: String, amount: int = 1) -> void
