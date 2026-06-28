extends RefCounted
class_name StageLoader
## ステージデータ（JSON）→ BattleState の組み立て（純ロジック・ノード非依存）。
## 詳細 → doc/tech/architecture.md（data層）, doc/gdd/map.md
##
## マップは「ASCII地形グリッド＋ユニット配置リスト」で記述する（data/stages/*.json）。
## terrain は1行＝盤の1列ぶんの文字絵。文字→地形の対応は TERRAIN_CHARS。
##
## build(dict) はファイルIOを伴わず辞書から組み立てる（テスト対象）。
## load_file(path) はファイルを読んで build に渡す薄いラッパ。

## 地形グリッドの文字 → 地形タイプ。未定義文字は平地として扱う。
const TERRAIN_CHARS := {
	".": Terrain.PLAINS,
	"P": Terrain.PLATEAU,
}

## ステージ辞書から BattleState を組み立てる。
## 期待キー: cols, rows, terrain(配列の文字列), units(配列の辞書)。
## catalog = { id: UnitType }。ユニットが "type" を持つときステータスを引く（省略時は素の値）。
static func build(data: Dictionary, catalog: Dictionary = {}) -> BattleState:
	var cols := int(data.get("cols", 12))
	var rows := int(data.get("rows", 8))
	var state := BattleState.new(cols, rows)
	_apply_terrain(state, data.get("terrain", []))
	_apply_units(state, data.get("units", []), catalog)
	return state

## res:// パスの JSON を読み込んで BattleState を返す。失敗時は null。
## ユニット種別は標準ロスター(UnitCatalog)で解決する。
static func load_file(path: String) -> BattleState:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("StageLoader: 読み込めない/空: %s" % path)
		return null
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("StageLoader: JSON が不正: %s" % path)
		return null
	return build(data, UnitCatalog.load_default())

## 地形グリッド（文字列の配列）を盤に反映。row=行index, col=文字index → offset(col,row)。
static func _apply_terrain(state: BattleState, grid: Variant) -> void:
	if typeof(grid) != TYPE_ARRAY:
		return
	for row in grid.size():
		var line := String(grid[row])
		for col in line.length():
			var ch := line[col]
			var tid: int = TERRAIN_CHARS.get(ch, Terrain.PLAINS)
			if tid != Terrain.PLAINS:  # 平地は既定なので明示設定不要
				state.set_terrain(Hex.offset_to_axial(col, row), tid)

## ユニット配置リストを盤に追加。id 省略時は出現順に1始まりで採番。
## "type" があれば catalog からステータスを引き、個別キー(move/troops/atk/def/level)で上書きできる。
## "type" が無ければ素の値（既定: move3・troops8・atk10・def10・level1）。
static func _apply_units(state: BattleState, units: Variant, catalog: Dictionary) -> void:
	if typeof(units) != TYPE_ARRAY:
		return
	var auto_id := 1
	for u in units:
		var pos := Hex.offset_to_axial(int(u["col"]), int(u["row"]))
		var type_id := String(u.get("type", ""))
		var t: UnitType = null
		if type_id != "":
			t = catalog.get(type_id)
			if t == null:
				push_warning("StageLoader: 未知のユニット種別: %s" % type_id)
		var mv := int(u.get("move", t.move if t != null else 3))
		var tp := int(u.get("troops", t.max_troops if t != null else 8))
		var atk := int(u.get("atk", t.atk_ground if t != null else 10))
		var dfn := int(u.get("def", t.defense if t != null else 10))
		var lv := int(u.get("level", 1))
		state.add_unit(Unit.new(int(u.get("id", auto_id)), int(u["team"]), pos, mv, tp, atk, dfn, lv, type_id))
		auto_id += 1
