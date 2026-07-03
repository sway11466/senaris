extends RefCounted
class_name StageLoader
## ステージデータ（JSON）→ BattleState の組み立て（マッチのセットアップ）。
## data層(json/UnitCatalog)と domain(BattleState/Unit) の両方に依存するため application 層に置く。
## 詳細 → doc/tech/architecture.md, doc/gdd/map.md
##
## マップは「ASCII地形グリッド＋ユニット配置リスト」で記述する（data/stages/*.json）。
## terrain は1行＝盤の1列ぶんの文字絵。文字→地形の対応は Terrain（terrain.csv の char 列）。
##
## build(dict) はファイルIOを伴わず辞書から組み立てる（テスト対象）。
## load_file(path) はファイルを読んで build に渡す薄いラッパ。

## ステージ辞書から BattleState を組み立てる。
## 期待キー: cols, rows, terrain(配列の文字列), units(配列の辞書), bases(配列の辞書)。
## catalog = { id: UnitType }。ユニットが "type" を持つときステータスを引く（省略時は素の値）。
static func build(data: Dictionary, catalog: Dictionary = {}, skin_catalog: Dictionary = {}) -> BattleState:
	var cols := int(data.get("cols", 12))
	var rows := int(data.get("rows", 8))
	var state := BattleState.new(cols, rows)
	_apply_terrain(state, data.get("terrain", []))
	var next_id := _apply_units(state, data.get("units", []), catalog, skin_catalog)
	_apply_bases(state, data.get("bases", []), catalog, next_id, skin_catalog)
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
	var state := build(data, UnitCatalog.load_default(), SkinCatalog.load_standard())
	state.set_movement(Movement.load_default())  # 地形ごとの移動コストを有効化
	return state

## 地形グリッド（文字列の配列）を盤に反映。row=行index, col=文字index → offset(col,row)。
static func _apply_terrain(state: BattleState, grid: Variant) -> void:
	if typeof(grid) != TYPE_ARRAY:
		return
	for row in grid.size():
		var line := String(grid[row])
		for col in line.length():
			var tid := Terrain.char_to_id(line[col])
			if tid != Terrain.DEFAULT_ID:  # 既定地形は明示設定不要
				state.set_terrain(Hex.offset_to_axial(col, row), tid)

## ユニット配置リストを盤に追加。id 省略時は出現順に1始まりで採番。次の採番値を返す。
## "type" があれば catalog からステータスを引き、個別キー(move/troops/atk/def/level)で上書きできる。
## "type" が無ければ素の値（既定: move3・troops8・atk10・def10・level1）。
static func _apply_units(state: BattleState, units: Variant, catalog: Dictionary, skin_catalog: Dictionary = {}) -> int:
	if typeof(units) != TYPE_ARRAY:
		return 1
	var auto_id := 1
	for u in units:
		state.add_unit(_make_unit(u, catalog, int(u.get("id", auto_id)), skin_catalog))
		auto_id += 1
	return auto_id

## 拠点リストを盤に追加。各拠点は位置(col/row)・所属(team, 既定は中立)・garrison(控えユニット)を持つ。
## garrison の各要素は { type, count } ＋ ユニット個別キー（troops 省略＝満員 / level 省略＝1）。
## garrison ユニットは盤上未登場（出撃時に team/pos が決まる）＝採番だけ済ませて Base に積む。
static func _apply_bases(state: BattleState, bases: Variant, catalog: Dictionary, start_id: int, skin_catalog: Dictionary = {}) -> void:
	if typeof(bases) != TYPE_ARRAY:
		return
	var auto_id := start_id
	for b in bases:
		var hex := Hex.offset_to_axial(int(b["col"]), int(b["row"]))
		var base := Base.new(hex, int(b.get("team", Base.NEUTRAL)))
		for g in b.get("garrison", []):
			for _i in maxi(int(g.get("count", 1)), 1):
				base.garrison.append(_make_unit(g, catalog, auto_id, skin_catalog))
				auto_id += 1
		state.add_base(base)

## ユニット辞書 → Unit。"type" があれば catalog からステータスを引き、個別キーで上書き可。
## col/row 省略は (0,0)（garrison は出撃時に pos を決めるので無視される）。
static func _make_unit(u: Dictionary, catalog: Dictionary, id: int, skin_catalog: Dictionary = {}) -> Unit:
	var pos := Hex.offset_to_axial(int(u.get("col", 0)), int(u.get("row", 0)))
	# 見た目(skin)と性能(type)の解決。skin→type は1:1なので、どちらか一方の指定で両方決まる。
	var skin_id := String(u.get("skin", ""))
	var type_id := String(u.get("type", ""))
	if skin_id == "" and type_id != "":
		skin_id = type_id  # type 指定 → 同名スキンを使う
	if type_id == "" and skin_id != "" and not skin_catalog.is_empty():
		type_id = SkinCatalog.type_of_skin(skin_catalog, skin_id)  # skin 指定 → 性能を逆引き
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
	var unit := Unit.new(id, int(u.get("team", 0)), pos, mv, tp, atk, dfn, lv, type_id)
	unit.skin_id = skin_id
	unit.move_type = String(u.get("move_type", t.move_type if t != null else "ground"))
	unit.attack_range = int(u.get("range", t.attack_range if t != null else 1))
	unit.move_after_attack = bool(u.get("move_after_attack", t.move_after_attack if t != null else false))
	unit.can_capture = bool(u.get("can_capture", t.can_capture if t != null else false))
	unit.atk_air = int(u.get("atk_air", t.atk_air if t != null else 0))
	unit.pierce = float(u.get("pierce", t.pierce if t != null else 0.0))
	return unit  # 飛行判定は Unit.is_aerial()＝move_type=="flight" で行う
