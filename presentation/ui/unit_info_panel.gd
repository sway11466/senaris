extends Panel
class_name UnitInfoPanel
## 選択中ユニットの情報を右側に表示するパネル（presentation）。
## 状態(BattleState)は読むだけ。HexBoard.selection_changed を受けて中身を差し替える。
## ラベルはコード生成（tscn は Panel ＋ 位置だけ持てばよい）。

var _state: BattleState
var _skins := {}        # type_id -> { ally:[UnitSkin], enemy:[UnitSkin] }
var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 16
	_label.offset_top = 14
	_label.offset_right = -16
	_label.offset_bottom = -14
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	clear()

## 状態とスキン表を渡す（main から1回）。
func bind(state: BattleState, skin_catalog: Dictionary) -> void:
	_state = state
	_skins = skin_catalog
	clear()

## 選択変更を受けて表示を更新（id<0 で未選択）。
func show_unit(unit_id: int) -> void:
	if _state == null or unit_id < 0:
		clear()
		return
	var u := _state.unit_by_id(unit_id)
	if u == null:
		clear()
		return
	_label.text = _format(u)

func clear() -> void:
	if _label != null:
		_label.text = "ユニット未選択\n\n盤上のユニットを左クリックで選択"

func _format(u: Unit) -> String:
	var skin: UnitSkin = SkinCatalog.skin(_skins, u.type_id, u.team)
	var unit_name := skin.name if skin != null else u.type_id
	var team_name := "自軍" if u.team == 0 else "敵軍"
	var terr := _state.terrain_at(u.pos)
	var exp := Combat.experience_factor(u)
	var surround := Surround.factor(_state, u)

	var lines: Array[String] = []
	lines.append("【%s】 %s" % [unit_name, team_name])
	lines.append("種別: %s" % u.type_id)
	lines.append("")
	lines.append("兵数  %d / %d" % [u.troops, u.max_troops])
	lines.append("Lv    %d  (経験 ×%.2f)" % [u.level, exp])
	var air_str := str(u.atk_air) if u.atk_air > 0 else "—"
	lines.append("攻撃  対地%d / 対空%s    防御  %d" % [u.unit_attack, air_str, u.unit_defense])
	lines.append("移動  %d (%s)   射程  %d" % [u.move, u.move_type, u.attack_range])

	var traits: Array[String] = []
	if u.is_aerial():
		traits.append("飛行")
	if u.can_capture:
		traits.append("占領可")
	if u.move_after_attack:
		traits.append("攻撃後移動")
	if u.attack_range >= 2:
		traits.append("間接(反撃なし)")
	if not traits.is_empty():
		lines.append("特性  %s" % ", ".join(traits))

	lines.append("")
	lines.append("地形  %s (攻×%.2f / 防×%.2f)" % [
		Terrain.display_name(terr), Terrain.attack_factor(terr), Terrain.defense_factor(terr)])
	if surround < 1.0:
		lines.append("包囲  ×%.2f（弱体化中）" % surround)

	var b := _state.base_at(u.pos)
	if b != null:
		var owner := "中立" if b.team < 0 else ("自軍" if b.team == 0 else "敵軍")
		lines.append("拠点  所属:%s  控え:%d" % [owner, b.garrison.size()])

	lines.append("")
	lines.append("状態  %s" % _action_state(u))
	return "\n".join(lines)

## 行動状態の短い説明。
func _action_state(u: Unit) -> String:
	if _state.is_done(u.id):
		return "行動完了"
	var parts: Array[String] = []
	parts.append("移動可" if _state.can_still_move(u.id) else "移動済")
	parts.append("攻撃可" if not _state.has_attacked(u.id) else "攻撃済")
	return " / ".join(parts)
