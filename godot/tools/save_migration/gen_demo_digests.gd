extends SceneTree
## 体験版 demo-v0.1.0 に同梱したステージ定義から、印（StageDigest）の表を作る使い捨てツール。
## 出力は res://data/save/demo-v0.1.0_digests.json（{ "冒険譚ID/ステージID": 印 }）で、
## SaveMigration が v2 中断セーブの移行で引く。今のステージJSONから計算しないための表
## （→ doc/tech/gamesystem.md §版と移行）なので、入力はタグ時点のファイルを展開して渡す。
##
## 使い方（リポジトリ直下で）:
##   git archive demo-v0.1.0 godot/data/stages | tar -x -C <展開先>
##   godot --headless --path godot -s res://tools/save_migration/gen_demo_digests.gd -- <展開先>/godot/data/stages

const OUT_PATH := "res://data/save/demo-v0.1.0_digests.json"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("使い方: gen_demo_digests.gd -- <タグ展開先の stages ディレクトリ>")
		quit(1)
		return
	var root := String(args[0])
	var dir := DirAccess.open(root)
	if dir == null:
		push_error("開けない: %s" % root)
		quit(1)
		return
	var table := {}
	for sub in dir.get_directories():
		var manifest_path := "%s/%s/campaign.json" % [root, sub]
		if not FileAccess.file_exists(manifest_path):
			continue  # マニフェストの無いフォルダはゲームからも見えない（CampaignCatalog と同じ）
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("マニフェストが不正: %s" % manifest_path)
			continue
		var manifest: Dictionary = parsed
		var cid := String(manifest.get("id", sub))
		for s in manifest.get("stages", []):
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var sid := String(s.get("id", ""))
			var file := String(s.get("file", ""))
			if sid.is_empty() or file.is_empty():
				continue
			var digest := StageDigest.of_file("%s/%s/%s" % [root, sub, file])
			if digest.is_empty():
				push_error("印を計算できない: %s/%s" % [sub, file])
				continue
			table["%s/%s" % [cid, sid]] = digest
	var out := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if out == null:
		push_error("書き出せない: %s" % OUT_PATH)
		quit(1)
		return
	out.store_string(JSON.stringify(table, "  ") + "\n")
	print("%s: %d 件" % [OUT_PATH, table.size()])
	quit(0)
