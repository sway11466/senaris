extends SceneTree
## 使い捨て：クロニクルの陣形スキル章（カードの格子と拡大カード）を実機で撮る。
## 起動: godot --path . -s res://tests/manual/shot_chronicle_formations.gd
## 出力: user://shot_formations_grid.png / user://shot_formations_card_*.png

var _main: Node = null
var _frame := 0
var _store: ChronicleStore = null

func _initialize() -> void:
	var packed: PackedScene = load("res://presentation/main/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)

func _chapter() -> ChronicleFormationsChapter:
	return _main._chronicle_screen._chapters[1] as ChronicleFormationsChapter

func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		20:
			TranslationServer.set_locale("ja")
			# 2本だけ解放し、ディバインジャッジメントは未解放の黒塗りを見る
			_store = ChronicleStore.new("user://chronicle_shot_test.json")
			_store.record_skill("trinity_nova")
			_store.record_skill("grace")
			_main._chronicle_screen.open(_store, _main._progress, _main._skins)
			_main._chronicle_screen._select_chapter(1)
		40:
			_shot("user://shot_formations_grid.png")
		42:
			_chapter()._open_skill_card("trinity_nova")
		60:
			_shot("user://shot_formations_card_trinity_nova.png")
		62:
			_main._chronicle_screen._on_back()  # Esc と同じ経路＝拡大だけ畳む
			print("closed_expanded=", _chapter()._expanded == null,
				" screen_visible=", _main._chronicle_screen.visible)
		64:
			_chapter()._open_skill_card("grace")
		80:
			_shot("user://shot_formations_card_grace.png")
		82:
			_main._chronicle_screen._on_back()
			TranslationServer.set_locale("en")
			_main._chronicle_screen.refresh_labels()
		100:
			_shot("user://shot_formations_grid_en.png")
		110:
			return true
	if _frame > 200:
		return true
	return false

func _shot(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
