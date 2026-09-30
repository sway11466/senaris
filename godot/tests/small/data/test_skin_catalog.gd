extends GutTest
## SkinCatalog（スキン表 → {type_id:{ally/enemy:[UnitSkin]}}）のテスト。

func test_build_and_resolve() -> void:
	var cat := SkinCatalog.build({ "skins": {
		"cleric": {
			"ally":  [ { "name": "クレリック" } ],
			"enemy": [ { "name": "ゴブリン" }, { "name": "守護像" } ],
		},
	} })
	assert_true(cat.has("cleric"))
	assert_eq(SkinCatalog.skin(cat, "cleric", 0).name, "クレリック", "味方")
	assert_eq(SkinCatalog.skin(cat, "cleric", 1).name, "ゴブリン", "敵 既定(index0)")
	assert_eq(SkinCatalog.skin(cat, "cleric", 1, 1).name, "守護像", "敵 エイリアス(index1)")
	assert_eq(SkinCatalog.skin(cat, "cleric", 1, 9).name, "ゴブリン", "範囲外は先頭")

func test_resolve_missing_type_returns_null() -> void:
	var cat := SkinCatalog.build({ "skins": {} })
	assert_null(SkinCatalog.skin(cat, "unknown", 0))

func test_load_standard() -> void:
	var cat := SkinCatalog.load_standard()
	assert_true(cat.has("cleric"))
	assert_eq(SkinCatalog.skin(cat, "cleric", 0).name, "クレリック")
	assert_eq(SkinCatalog.skin(cat, "cleric", 1).name, "ゴブリン", "敵名はミラー")
	assert_eq(SkinCatalog.skin(cat, "paladin", 1).name, "ゴブリンロード")

func test_skin_by_id_and_resolve() -> void:
	var cat := SkinCatalog.build({ "skins": {
		"priest": {
			"ally": [ { "skin_id": "priest", "type_id": "priest", "name": "プリースト" } ],
			"enemy": [
				{ "skin_id": "hobgoblin", "type_id": "priest", "name": "ホブゴブリン" },
				{ "skin_id": "skeleton", "type_id": "priest", "name": "スケルトン" },
			],
		},
	} })
	# skin_id 直引き・type 逆引き
	assert_eq(SkinCatalog.skin_by_id(cat, "skeleton").name, "スケルトン", "skin_id で引く")
	assert_eq(SkinCatalog.type_of_skin(cat, "skeleton"), "priest", "skin_id → type_id")
	assert_null(SkinCatalog.skin_by_id(cat, "unknown"), "未知 skin_id は null")
	# resolve: skin_id 優先、無ければ type_id+team の先頭へフォールバック
	assert_eq(SkinCatalog.resolve(cat, "skeleton", "priest", 1).name, "スケルトン", "skin_id 優先")
	assert_eq(SkinCatalog.resolve(cat, "", "priest", 1).name, "ホブゴブリン", "skin無→enemy先頭")
	assert_eq(SkinCatalog.resolve(cat, "", "priest", 0).name, "プリースト", "skin無→ally先頭")

## 攻撃エフェクトの始点（muzzle）。stand＝足元、"横|縦"＝立ち絵の絵の外枠に対する割合。
## 仕様 → doc/tech/combat_scene.md 攻撃エフェクト
func test_muzzle_from_dict() -> void:
	var stand := UnitSkin.from_dict({ "skin_id": "a", "muzzle": "stand" })
	assert_true(stand.muzzle_stand, "stand は足元から")
	var point := UnitSkin.from_dict({ "skin_id": "b", "muzzle": "0.00|0.24" })
	assert_false(point.muzzle_stand, "割合なら立ち絵の中の点から")
	assert_almost_eq(point.muzzle.y, 0.24, 0.0001, "縦の割合")
	assert_true(SkinCatalog.skin_by_id(SkinCatalog.load_standard(), "turret").muzzle_stand == false, "固定砲台は砲口から撃つ")
