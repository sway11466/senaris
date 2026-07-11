extends Panel
class_name UnitInfoPanel
## 選択中ユニットの情報を右側に表示するパネル（presentation）。
## 状態(BattleState)は読むだけ。HexBoard.selection_changed を受けて中身を差し替える。
## ラベルはコード生成（tscn は Panel ＋ 位置だけ持てばよい）。

var _state: BattleState
var _skins := {}        # type_id -> { ally:[UnitSkin], enemy:[UnitSkin] }
var _label: Label

func _ready() -> void:
	# 暗い木の看板（材質ルール: 木＝常設の面。TavernTheme 参照）
	add_theme_stylebox_override("panel", TavernTheme.signboard_stylebox())
	add_child(TavernTheme.signboard_frame())
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
		_label.text = "ユニット未選択\n\n盤上のユニットを左クリックで選択\n空きマスをクリックで地形を確認"

## 空きマスの地形情報を表示（拠点なら控え＝garrison も一覧）。HexBoard.tile_inspected を受ける。
func show_terrain(hex: Vector2i) -> void:
	if _state == null:
		clear()
		return
	_label.text = _format_terrain(hex)

func _format_terrain(hex: Vector2i) -> String:
	var terr := _state.terrain_at(hex)
	var lines: Array[String] = []
	lines.append("【地形】 %s" % TerrainSkinCatalog.display_name(terr))
	lines.append("")
	lines.append("攻撃補正  ×%.2f" % TerrainType.attack_factor(terr))
	lines.append("防御補正  ×%.2f" % TerrainType.defense_factor(terr))

	var b := _state.base_at(hex)
	if b != null:
		lines.append("")
		lines.append("──────────────────────")
		var owner := "中立" if b.team < 0 else ("自軍" if b.team == 0 else "敵軍")
		var kind_name := "本拠地" if b.is_hq() else "拠点"
		lines.append("【%s】 所属:%s" % [kind_name, owner])
		if b.garrison.is_empty():
			lines.append("控え  なし")
		else:
			lines.append("控え  %d体" % b.garrison.size())
			for gu in b.garrison:
				lines.append("  ・%s" % _garrison_line(gu, b))
	return "\n".join(lines)

## 控え1体の1行表示（名前・兵数・レベル）。
func _garrison_line(gu: Unit, b: Base) -> String:
	var team_for_skin := gu.team if gu.team >= 0 else (b.team if b.team >= 0 else 0)
	var sk := SkinCatalog.resolve(_skins, gu.skin_id, gu.type_id, team_for_skin)
	var nm := sk.name if sk != null else gu.type_id
	return "%s  兵%d/%d  Lv%d" % [nm, gu.troops, gu.max_troops, gu.level]

func _format(u: Unit) -> String:
	var skin: UnitSkin = SkinCatalog.resolve(_skins, u.skin_id, u.type_id, u.team)
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
	lines.append("移動  %d (%s)   射程  %d" % [u.move, Movement.display_name(u.move_type), u.attack_range])

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
		TerrainSkinCatalog.display_name(terr), TerrainType.attack_factor(terr), TerrainType.defense_factor(terr)])
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

# --- 戦闘結果ビュー（攻撃時に右パネルへ）。detail は BattleState.attack の "detail"。---
# 攻防の導出と損害を、戦闘解決と同じ内訳(dict)からそのまま整形＝盤の数字と一致する。

func show_combat(detail: Dictionary) -> void:
	if detail == null or detail.is_empty():
		return
	_label.text = _format_combat(detail)

func _format_combat(d: Dictionary) -> String:
	var a: Dictionary = d["attacker"]
	var t: Dictionary = d["defender"]
	var fwd: Dictionary = d["to_defender"]
	var ret: Variant = d["to_attacker"]  # null＝反撃なし
	var an := _combatant_name(a)
	var tn := _combatant_name(t)
	var lines: Array[String] = []
	lines.append("⚔ 戦闘結果")
	lines.append("──────────────────────")
	lines.append("%s Lv%d  →  %s Lv%d" % [an, a["level"], tn, t["level"]])
	lines.append("  %s  %d/%d → %d/%d (%+d)" % [an, a["troops_before"], a["max"], a["troops_after"], a["max"], a["troops_after"] - a["troops_before"]])
	lines.append("  %s  %d/%d → %d/%d (%+d)" % [tn, t["troops_before"], t["max"], t["troops_after"], t["max"], t["troops_after"] - t["troops_before"]])
	lines.append("──────────────────────")
	lines.append("▼ 攻撃 %s（%s）" % [an, TerrainSkinCatalog.display_name(a["terrain"])])
	lines.append(_chain(fwd["attack"]))
	if ret != null:
		lines.append(_chain(ret["defense"]))
	lines.append("▼ 防御 %s（%s）" % [tn, TerrainSkinCatalog.display_name(t["terrain"])])
	lines.append(_chain(fwd["defense"]))
	if ret != null:
		lines.append(_chain(ret["attack"]))
	lines.append("──────────────────────")
	lines.append("▼ 損害  割合=攻²÷(攻²+防²)、失う兵=相手の現在兵×割合")
	lines.append(_damage_line(an, tn, fwd, t["troops_before"]))
	if ret != null:
		lines.append(_damage_line(tn, an, ret, a["troops_before"]))
	else:
		lines.append("  %s → %s  反撃なし" % [tn, an])
	return "\n".join(lines)

func _combatant_name(snap: Dictionary) -> String:
	var s: UnitSkin = SkinCatalog.resolve(_skins, String(snap.get("skin_id", "")), snap["type_id"], snap["team"])
	return s.name if s != null else String(snap["type_id"])

## 補正チェーン1行。breakdown は Combat.attack_breakdown / defense_breakdown。
func _chain(b: Dictionary) -> String:
	var is_atk: bool = b["kind"] == "attack"
	var head := "攻" if is_atk else "防"
	var stat_label := ("対空" if b.get("vs_aerial", false) else "対地") if is_atk else "防"
	return "  %s %d = 兵%d × %s%d × 経験×%.2f × 包囲×%.2f × 地形×%.2f ＋支援%d" % [
		head, roundi(b["total"]), b["troops"], stat_label, b["stat"],
		b["experience"], b["surround"], b["terrain"], roundi(b["support"])]

## 損害1行: 「攻撃側 → 受け手  攻A 対 防D → P% → 兵N×P% = 失う兵」。
func _damage_line(from_name: String, to_name: String, hit: Dictionary, defender_troops: int) -> String:
	var pct := int(round(hit["fraction"] * 100.0))
	return "  %s → %s  攻%d 対 防%d → %d%% → 兵%d×%d%% = %d" % [
		from_name, to_name, roundi(hit["attack"]["total"]), roundi(hit["defense"]["total"]),
		pct, defender_troops, pct, hit["loss"]]
