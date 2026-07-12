extends RefCounted
class_name CampaignCatalog
## 冒険譚マニフェスト(data/stages/<冒険譚>/campaign.json)の読み込み。詳細 → doc/gdd/stage_select.md
## data層＝純データのみ（解放判定・クリア記録は application/campaign_progress.gd）。

const STAGES_ROOT := "res://data/stages"

## マニフェスト辞書 → 正規化した冒険譚辞書。必須項目が欠けていれば {}。
## title/desc・stage.title は翻訳キー（i18n・data/i18n/campaigns.csv）。表示側が tr() で解決。
## { id, title, desc, debug, difficulty, tier, cover_paths, card_paths,
##   stages: [ { id, title, file, path, unlock: Array } ] }
## cover_paths/card_paths＝連番バリアントの配列。表示側が表示ごとに1枚選ぶ（複数なら実質ランダム）。
static func build(data: Dictionary, dir_path: String) -> Dictionary:
	var id := String(data.get("id", ""))
	var raw_stages: Variant = data.get("stages", [])
	if id.is_empty() or typeof(raw_stages) != TYPE_ARRAY:
		push_warning("CampaignCatalog: マニフェストが不正でスキップ（id 空 or stages が非配列）: %s" % dir_path)
		return {}
	var stages: Array = []
	for s in raw_stages:
		if typeof(s) != TYPE_DICTIONARY:
			push_warning("CampaignCatalog[%s]: stage エントリが辞書でない＝スキップ" % id)
			continue
		var sid := String(s.get("id", ""))
		var file := String(s.get("file", ""))
		if sid.is_empty() or file.is_empty():
			push_warning("CampaignCatalog[%s]: stage の id/file が空＝スキップ（id='%s' file='%s'）" % [id, sid, file])
			continue
		var unlock: Variant = s.get("unlock", [])
		stages.append({
			"id": sid,
			"title": String(s.get("title", sid)),
			"file": file,
			"path": "%s/%s" % [dir_path, file],
			"unlock": unlock if typeof(unlock) == TYPE_ARRAY else [],
		})
	_warn_dangling_unlock(id, stages)
	return {
		"id": id,
		"title": String(data.get("title", id)),  # 翻訳キー（表示側で tr()）。debug 等は生テキストでも tr() は素通し
		"desc": String(data.get("desc", "")),     # 翻訳キー（貼り紙の説明文）。未指定は空＝説明なし
		"debug": bool(data.get("debug", false)),
		"tier": String(data.get("tier", "rookie")),  # 所属ボード（tutorial/rookie/adept/veteran）。未指定は rookie
		"difficulty": clampi(int(data.get("difficulty", 0)), 0, 5),  # 星レーティング 0〜5
		"cover_paths": _resolve_art_variants(id, "cover"),  # ステージ一覧の大パネル（連番バリアント）
		"card_paths": _resolve_art_variants(id, "card"),    # 冒険譚カード（絵はカード用にクロップ・連番バリアント）
		"stages": stages,
	}

## unlock の解放条件が指す stage が同じ冒険譚に実在するか検証し、dangling を警告。
## 打ち間違い・ステージ消し忘れで「永久に解放されないステージ」が黙って生まれるのを防ぐ。
## stage を参照しない条件（entitlement 等＝"stage" キー無し）は対象外。
static func _warn_dangling_unlock(campaign_id: String, stages: Array) -> void:
	var ids := {}
	for s in stages:
		ids[s["id"]] = true
	for s in stages:
		for cond in s["unlock"]:
			if typeof(cond) != TYPE_DICTIONARY:
				continue
			var ref := String(cond.get("stage", ""))
			if ref.is_empty():
				continue
			if not ids.has(ref):
				push_warning("CampaignCatalog[%s]: stage '%s' の unlock が未定義の stage '%s' を参照" % [campaign_id, s["id"], ref])

## 絵を規約で自動解決＝連番バリアントを集める：{id}_{kind}.png（＋_2/_3…）の在るものを順に。
## 1枚だけなら従来どおり固定、複数置けば表示側がランダムに1枚選ぶ（羊皮紙・地形の連番と同思想）。
## 絵を置くだけでプレースホルダ→画像に切り替わる（skin 画像 autowire と同じ思想）。
static func _resolve_art_variants(id: String, kind: String) -> Array:
	var out: Array = []
	var base := "res://assets/campaign/%s/%s_%s.png" % [id, id, kind]
	if ResourceLoader.exists(base):
		out.append(base)
	var n := 2
	while true:
		var p := "res://assets/campaign/%s/%s_%s_%d.png" % [id, id, kind, n]
		if not ResourceLoader.exists(p):
			break
		out.append(p)
		n += 1
	return out

## 1つの campaign.json を読み込む。失敗時は {}。
static func load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("CampaignCatalog: 読み込めない/空: %s" % path)
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("CampaignCatalog: JSON が不正: %s" % path)
		return {}
	return build(data, path.get_base_dir())

## data/stages/ 以下を走査して冒険譚リストを返す。
## マニフェストの無いフォルダはセレクトに出さない。デバッグ冒険譚(debug:true)は末尾に寄せる。
static func load_all(root: String = STAGES_ROOT) -> Array:
	var normals: Array = []
	var debugs: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return []
	for sub in dir.get_directories():
		var path := "%s/%s/campaign.json" % [root, sub]
		if not FileAccess.file_exists(path):
			continue
		var c := load_file(path)
		if c.is_empty():
			continue
		if c["debug"]:
			debugs.append(c)
		else:
			normals.append(c)
	return normals + debugs
