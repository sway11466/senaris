extends SceneTree
## 使い捨て：クロニクルのユニット章（カードの格子と拡大カード）を実機で撮る。
## 起動: godot --path . -s res://tests/manual/shot_chronicle_units.gd
## 出力: user://shot_chronicle_grid.png / user://shot_chronicle_card_*.png

var _main: Node = null
var _frame := 0
var _store: ChronicleStore = null

func _initialize() -> void:
	var packed: PackedScene = load("res://presentation/main/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		20:
			TranslationServer.set_locale("ja")
			# 出会い済みの駒を適当に仕込む（未解放のシルエットも見たいので一部だけ）
			_store = ChronicleStore.new("user://chronicle_shot_test.json")
			for sid in ["cleric", "fighter", "archer", "knight", "mage", "priest",
					"thief", "wagon", "pixie", "skeleton", "goblin",
					"ghost", "dragon", "airship", "ballista"]:
				_store.record_skin(sid)
			_main._chronicle_screen.open(_store, _main._progress)
		40:
			_shot("user://shot_chronicle_grid.png")
		42:
			_main._chronicle_screen._open_unit_card("cleric")  # スキル＋特性を持つ駒
		60:
			_shot("user://shot_chronicle_card_cleric.png")
		62:
			_main._chronicle_screen._on_back()  # Esc と同じ経路＝拡大だけ畳む
			print("closed_expanded=", _main._chronicle_screen._expanded == null,
				" screen_visible=", _main._chronicle_screen.visible)
		64:
			_main._chronicle_screen._open_unit_card("pixie")  # 貫通を持つ小さい駒
		80:
			_shot("user://shot_chronicle_card_pixie.png")
		90:
			return true
	if _frame > 200:
		return true
	return false

func _shot(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
