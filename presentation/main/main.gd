extends Node2D
## 起動確認用の最小シーン。
## Presentation 層のエントリポイント。状態は持たず、将来 application/match_controller.gd へ委譲する。

func _ready() -> void:
	print("Senaris booted.")
