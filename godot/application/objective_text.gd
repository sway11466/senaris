extends RefCounted
class_name ObjectiveText
## 勝敗条件を人の読む文に組む（application）。システムメニューの「勝利／敗北条件を確認」が出す紙の中身。
## 仕様 → doc/gdd/uiux.md ターン終了・システムメニュー／判定そのものは domain/victory/victory.gd。
##
## 文はステージのデータからだけ組む＝ステージ側に条件の文言を書かない。条件タイプを足したときは
## Victory の分岐と対にここへも1つ足す（足し忘れると判定はあるのに紙に出ない条件ができる）。
##
## 条件リストに書かれないが常に効くもの（敵の殲滅・自軍の全滅・ターン制限・自軍本拠地の喪失）も
## 並べる＝盤の上で勝つ道・負ける道は、すべてこの紙に載っている状態にする。
##
## Node の外（RefCounted）なので tr() ではなく TranslationServer で解決する（CampaignProgress と同じ）。
##
## 駒の名前は盤の駒から引く。ステージを読んだ直後に組んでおけば、名指された駒が撃破された後
## （決着後に開いたとき）も同じ文が出る＝main が load のたびに1度だけ組んで持つ。

## 勝利・敗北それぞれの行を組む。skins＝SkinCatalog.load_standard()（駒の表示名を引くため）。
## 返す形: { "victory": PackedStringArray, "defeat": PackedStringArray }
static func build(state: BattleState, skins: Dictionary) -> Dictionary:
	return {
		"victory": _victory_lines(state, skins),
		"defeat": _defeat_lines(state, skins),
	}

## 勝利の行。ステージが名指した条件を先に、常に効く殲滅を後に置く＝その回に狙うものが上にくる。
static func _victory_lines(state: BattleState, skins: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for c in state.victory_conditions:
		var line := _victory_line(state, skins, c)
		if not line.is_empty():
			out.append(line)
	out.append(_t("ui.objective.win.wipe"))
	return out

static func _victory_line(state: BattleState, skins: Dictionary, c: Dictionary) -> String:
	match String(c.get("type", "")):
		"capture_hq":
			return _t("ui.objective.win.capture_hq")
		"defeat_unit":
			var names := _unit_names(state, skins, c.get("unit_ids"))
			if names.is_empty():
				return ""
			var key := "ui.objective.win.defeat_unit" if names.size() == 1 else "ui.objective.win.defeat_units"
			return _t(key) % _join(names)
	return ""  # 未知のタイプ＝出さない（Victory も不成立として扱う）

## 敗北の行。ステージが名指した条件 → 自軍本拠地 → 全滅 → ターン制限の順。
## 下の2つはどのステージでも同じなので、その回だけの条件を上に置く。
static func _defeat_lines(state: BattleState, skins: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for c in state.defeat_conditions:
		var line := _defeat_line(state, skins, c)
		if not line.is_empty():
			out.append(line)
	if _has_own_hq(state):
		out.append(_t("ui.objective.lose.hq"))
	out.append(_t("ui.objective.lose.wipe"))
	if state.turn_limit > 0:
		out.append(_t("ui.objective.lose.turn_limit") % state.turn_limit)
	return out

static func _defeat_line(state: BattleState, skins: Dictionary, c: Dictionary) -> String:
	match String(c.get("type", "")):
		"lose_base":
			var bases: Variant = c.get("bases", [])
			var many: bool = typeof(bases) == TYPE_ARRAY and (bases as Array).size() > 1
			return _t("ui.objective.lose.bases" if many else "ui.objective.lose.base")
		"lose_unit":
			var names := _unit_names(state, skins, c.get("unit_ids"))
			if names.is_empty():
				return ""
			var key := "ui.objective.lose.lose_unit" if names.size() == 1 else "ui.objective.lose.lose_units"
			return _t(key) % _join(names)
	return ""  # 未知のタイプ＝出さない（Victory も不成立として扱う）

## 自軍の本拠地が盤に在るか（在れば奪われた時点で敗北＝条件リストに書かれない常時のルール）。
static func _has_own_hq(state: BattleState) -> bool:
	for b in state.bases():
		if b.is_hq_of(0):
			return true
	return false

## 名指された unit_id の表示名を並べる。1件の中は AND＝並べた全員が対象。
static func _unit_names(state: BattleState, skins: Dictionary, unit_ids: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(unit_ids) != TYPE_ARRAY:
		return out
	for id in unit_ids:
		var u := _find_unit(state, String(id))
		if u != null:
			out.append(_unit_name(skins, u))
	return out

## unit_id の駒を探す。盤・拠点の控え・未発生の増援の順に見る＝登場前の駒も名前で指せる。
static func _find_unit(state: BattleState, unit_id: String) -> Unit:
	if unit_id.is_empty():
		return null
	for u in state.units():
		if u.unit_id == unit_id:
			return u
	for b in state.bases():
		for u in b.garrison:
			if u.unit_id == unit_id:
				return u
	for e in state.pending_events():
		for eu in e.units:
			if eu.unit is Unit and eu.unit.unit_id == unit_id:
				return eu.unit
			for p in eu.passengers:
				if p.unit_id == unit_id:
					return p
	return null

## 駒の表示名（情報板と同じ引き方＝盤に見えている姿の名前）。
static func _unit_name(skins: Dictionary, u: Unit) -> String:
	var skin: UnitSkin = SkinCatalog.resolve(skins, u.skin_id, u.type_id, u.team)
	return _t("unit." + skin.skin_id + ".name") if skin != null else u.type_id

## 1件の中の対象どうしをつなぐ（言語ごとに区切りが違う＝翻訳キーで持つ）。
static func _join(names: PackedStringArray) -> String:
	return String(_t("ui.objective.name_sep")).join(names)

static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
