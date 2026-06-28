extends GutTest
## UnitSkin（名前・説明・画像）のテスト。

func test_from_dict_and_labels() -> void:
	var s := UnitSkin.from_dict({ "name": "クレリック", "description": "癒やし手", "images": {} })
	assert_eq(s.name, "クレリック")
	assert_eq(s.description, "癒やし手")
	assert_eq(s.map_label(), "クレ", "マップは先頭2文字")
	assert_eq(s.combat_label(), "クレリック", "戦闘はフルネーム")

func test_image_slot() -> void:
	var s := UnitSkin.from_dict({ "name": "ゴブリン", "images": { "map": "res://x.png" } })
	assert_eq(s.image("map"), "res://x.png")
	assert_eq(s.image("combat"), "", "未設定スロットは空（プレースホルダ合図）")

func test_short_name_label() -> void:
	var s := UnitSkin.from_dict({ "name": "猫" })  # 2文字未満でも落ちない
	assert_eq(s.map_label(), "猫")
