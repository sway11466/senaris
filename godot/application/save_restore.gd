extends RefCounted
class_name SaveRestore
## 中断セーブからの盤の組み立て（application）。仕様 → doc/tech/gamesystem.md §中断セーブが持つもの
## ステージJSONを正本に盤の器（広さ・地形・勝敗条件・部隊定義・増援の中身）を組み、その上に
## セーブの動的差分（BattleState.to_save_diff）を被せる。名簿は渡さない＝駒の顔ぶれはセーブが正本。
## fire_due_events は呼ばない＝発火済みのイベントはセーブの pending_events から抜けている。

## stage_path のステージJSONで盤を組み、diff を被せた BattleState を返す。失敗時は null。
static func restore(stage_path: String, diff: Dictionary) -> BattleState:
	var text := FileAccess.get_file_as_string(stage_path)
	if text.is_empty():
		push_error("SaveRestore: ステージを読めない/空: %s" % stage_path)
		return null
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("SaveRestore: ステージJSONが不正: %s" % stage_path)
		return null
	var catalog := UnitCatalog.load_default()
	var state := StageLoader.build(data, catalog, SkinCatalog.load_standard())
	state.set_movement(Movement.load_default())  # 静的コンフィグ＝セーブに含めず再適用（load_file と同じ流儀）
	state.set_sight_cost(TerrainType.sight_cost_table())
	state.apply_save_diff(diff, catalog)  # movement 適用のあと＝盤に立てない駒の判定に使う
	return state
