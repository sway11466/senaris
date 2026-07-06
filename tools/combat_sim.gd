extends Control
## 戦闘計算シミュレータ（開発ツール）。tools/combat_sim.tscn を Godot エディタで F6（指定シーンを実行）。
##
## 式は本体（Combat / Surround / TerrainType）をそのまま呼ぶ＝画面の数字＝実戦の数字。
## 盤を作らず包囲・支援を「値」で指定するため、Combat/Surround の *_from 系（明示係数版）を使う。
## 未対応（Phase 1）: 射程・飛行・陣形スキル(バフ)。反撃は常にあり（近接前提）。
## 製品には含めない（tools/ は export プリセットの除外対象にする）。

var _atk_inputs := {}   # 攻撃側の入力コントロール（キー -> SpinBox/OptionButton）
var _def_inputs := {}   # 防御側の入力コントロール
var _terrain_ids: Array = []
var _result: RichTextLabel


func _ready() -> void:
	_terrain_ids = TerrainType.all_ids()
	if _terrain_ids.is_empty():
		_terrain_ids = ["plain"]
	get_window().title = "Senaris 戦闘計算シミュレータ"
	get_window().min_size = Vector2i(760, 680)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "戦闘計算シミュレータ"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "式は本体 Combat をそのまま使用（画面の数字＝実戦の数字）。反撃あり。射程・飛行・陣形バフは未対応。"
	sub.modulate = Color(1, 1, 1, 0.55)
	root.add_child(sub)

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 24)
	root.add_child(sides)
	_atk_inputs = _build_side(sides, "攻撃側", 30, 10)   # 会話の例に合わせた既定値
	_def_inputs = _build_side(sides, "防御側", 10, 80)

	var attack_btn := Button.new()
	attack_btn.text = "⚔  Attack"
	attack_btn.custom_minimum_size = Vector2(0, 40)
	attack_btn.pressed.connect(_on_attack)
	root.add_child(attack_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_result = RichTextLabel.new()
	_result.bbcode_enabled = true
	_result.fit_content = true
	_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_result)

	_on_attack()  # 起動時に既定値で1回計算


## 片陣営の入力欄一式を作る。返り値はキー -> コントロールの辞書。
func _build_side(parent: HBoxContainer, head_text: String, atk_default: int, def_default: int) -> Dictionary:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var head := Label.new()
	head.text = head_text
	head.add_theme_font_size_override("font_size", 18)
	panel.add_child(head)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	panel.add_child(grid)

	var inputs := {}
	inputs["troops"] = _add_spin(grid, "兵数", 1, 8, 1, 8)
	inputs["attack"] = _add_spin(grid, "ユニット攻撃力", 0, 999, 1, atk_default)
	inputs["defense"] = _add_spin(grid, "ユニット防御力", 0, 999, 1, def_default)
	inputs["pierce"] = _add_spin(grid, "貫通 (0〜1)", 0.0, 1.0, 0.05, 0.0)
	inputs["level"] = _add_spin(grid, "経験Lv", 1, 8, 1, 1)
	inputs["terrain"] = _add_terrain(grid, "地形")
	inputs["occ"] = _add_spin(grid, "包囲: 隣接敵(占有)", 0, 6, 1, 0)
	inputs["zoc"] = _add_spin(grid, "包囲: ZOC数", 0, 6, 1, 0)
	inputs["sup_atk"] = _add_spin(grid, "攻撃支援 (Σ兵数×攻)", 0, 9999, 1, 0)
	inputs["sup_def"] = _add_spin(grid, "防御支援 (Σ兵数×防)", 0, 9999, 1, 0)
	return inputs


func _add_spin(grid: GridContainer, label: String, minv: float, maxv: float, step: float, value: float) -> SpinBox:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.step = step
	sb.value = value
	sb.custom_minimum_size = Vector2(120, 0)
	grid.add_child(sb)
	return sb


func _add_terrain(grid: GridContainer, label: String) -> OptionButton:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	var ob := OptionButton.new()
	for i in _terrain_ids.size():
		var id: String = _terrain_ids[i]
		ob.add_item("%s  (攻×%.2f 防×%.2f)" % [id, TerrainType.attack_factor(id), TerrainType.defense_factor(id)])
		if id == TerrainType.DEFAULT_ID:
			ob.select(i)  # 既定は平地（地形補正なし）
	ob.custom_minimum_size = Vector2(190, 0)
	grid.add_child(ob)
	return ob


## 入力欄を読み取り、素の値の辞書にする。
func _read(inputs: Dictionary) -> Dictionary:
	var t_idx: int = max(inputs["terrain"].selected, 0)
	return {
		"troops": int(inputs["troops"].value),
		"attack": int(inputs["attack"].value),
		"defense": int(inputs["defense"].value),
		"pierce": float(inputs["pierce"].value),
		"level": int(inputs["level"].value),
		"terrain": String(_terrain_ids[t_idx]),
		"occ": int(inputs["occ"].value),
		"zoc": int(inputs["zoc"].value),
		"sup_atk": float(inputs["sup_atk"].value),
		"sup_def": float(inputs["sup_def"].value),
	}


## この陣営が「殴る」ときの実効攻撃力の内訳（本体の式に委譲）。
func _side_attack_bd(side: Dictionary) -> Dictionary:
	return Combat.attack_breakdown_from(
		side["troops"], side["attack"],
		Combat.experience_at(side["level"]),
		Surround.factor_from_counts(side["occ"], side["zoc"]),
		TerrainType.attack_factor(side["terrain"]),
		side["sup_atk"] * Combat.SUPPORT_RATE)


## この陣営が「受ける」ときの実効防御力の内訳（本体の式に委譲）。attacker_pierce＝殴る側の貫通。
func _side_defense_bd(side: Dictionary, attacker_pierce: float) -> Dictionary:
	return Combat.defense_breakdown_from(
		side["troops"], side["defense"],
		Combat.experience_at(side["level"]),
		Surround.factor_from_counts(side["occ"], side["zoc"]),
		TerrainType.defense_factor(side["terrain"]),
		side["sup_def"] * Combat.SUPPORT_RATE,
		attacker_pierce)


func _on_attack() -> void:
	var atk := _read(_atk_inputs)
	var df := _read(_def_inputs)

	# 攻撃側 → 防御側
	var fwd := Combat.hit_from_breakdowns(_side_attack_bd(atk), _side_defense_bd(df, atk["pierce"]), df["troops"])

	# 反撃（防御側の攻撃力が0なら成立しない＝本体 can_retaliate と同じ条件）
	var ret: Variant = null
	if df["attack"] > 0:
		ret = Combat.hit_from_breakdowns(_side_attack_bd(df), _side_defense_bd(atk, df["pierce"]), atk["troops"])

	_render(atk, df, fwd, ret)


func _render(atk: Dictionary, df: Dictionary, fwd: Dictionary, ret: Variant) -> void:
	var out := ""
	out += "[color=#ff9088][b]▼ 攻撃側 → 防御側[/b][/color]\n"
	out += "[u]攻撃側 実効攻撃力[/u]\n" + _fmt_attack(fwd["attack"])
	out += "[u]防御側 実効防御力[/u]\n" + _fmt_defense(fwd["defense"])
	out += _fmt_hit(fwd)
	out += "\n"

	if ret != null:
		out += "[color=#88a8ff][b]▼ 反撃：防御側 → 攻撃側[/b][/color]\n"
		out += "[u]防御側 実効攻撃力[/u]\n" + _fmt_attack(ret["attack"])
		out += "[u]攻撃側 実効防御力[/u]\n" + _fmt_defense(ret["defense"])
		out += _fmt_hit(ret)
		out += "\n"
	else:
		out += "[color=#999999]反撃なし（防御側のユニット攻撃力が 0）[/color]\n\n"

	var d_loss: int = fwd["loss"]
	var a_loss: int = (ret["loss"] if ret != null else 0)
	out += "[b]━━━ 結果 ━━━[/b]\n"
	out += _fmt_result("防御側", df["troops"], d_loss)
	out += _fmt_result("攻撃側", atk["troops"], a_loss)
	_result.text = out


## 実効攻撃力の内訳を「素 → 支援 → 実効」の順で文字列化。
func _fmt_attack(bd: Dictionary) -> String:
	var pre := float(bd["troops"]) * float(bd["stat"]) * float(bd["experience"]) * float(bd["surround"]) * float(bd["terrain"])
	var s := "  兵%d × 攻%d × 経験%.2f × 包囲%.2f × 地形%.2f = %.1f\n" % [
		bd["troops"], bd["stat"], bd["experience"], bd["surround"], bd["terrain"], pre]
	if float(bd["support"]) > 0.0:
		s += "  ＋ 支援 %.1f\n" % bd["support"]
	s += "  → 実効攻撃力 [b]%.1f[/b]\n" % bd["total"]
	return s


## 実効防御力の内訳を「素 → 支援(2倍上限) → 貫通 → 実効」の順で文字列化。
func _fmt_defense(bd: Dictionary) -> String:
	var pre := float(bd["troops"]) * float(bd["stat"]) * float(bd["experience"]) * float(bd["surround"]) * float(bd["terrain"])
	var supported := pre + float(bd["support"])
	var capped_val: float = min(supported, pre * Combat.DEFENSE_SUPPORT_CAP)
	var s := "  兵%d × 防%d × 経験%.2f × 包囲%.2f × 地形%.2f = %.1f\n" % [
		bd["troops"], bd["stat"], bd["experience"], bd["surround"], bd["terrain"], pre]
	if float(bd["support"]) > 0.0:
		var note := "  (2倍上限で頭打ち)" if bd["capped"] else ""
		s += "  ＋ 支援 %.1f → %.1f%s\n" % [bd["support"], capped_val, note]
	if float(bd["pierce"]) < 1.0:
		s += "  × 貫通後 %.2f\n" % bd["pierce"]
	s += "  → 実効防御力 [b]%.1f[/b]\n" % bd["total"]
	return s


## 割合と失う兵の確定過程を文字列化。
func _fmt_hit(hit: Dictionary) -> String:
	var a := float(hit["attack"]["total"])
	var d := float(hit["defense"]["total"])
	var troops := int(hit["defense"]["troops"])
	var frac := float(hit["fraction"])
	var s := "  割合 = %.1f² ÷ (%.1f² + %.1f²) = [b]%.4f[/b]\n" % [a, a, d, frac]
	s += "  失う兵 = round(%.4f × %d) = round(%.2f) = [b]%d[/b]\n" % [frac, troops, frac * troops, hit["loss"]]
	return s


func _fmt_result(name: String, before: int, loss: int) -> String:
	var after: int = max(before - loss, 0)
	var killed := "  [color=#ff6666]撃破[/color]" if after <= 0 and loss > 0 else ""
	return "  %s：兵 %d → %d  (−%d)%s\n" % [name, before, after, loss, killed]
