extends SceneTree
## マップエディタの「実機で確認」の起動口。編集中のステージ（一時ファイルのコピー）と、エディタが
## でっち上げた名簿（継承の駒を全員 Lv1・満員で載せたもの）を受け取り、ゲーム本体を起動して直接読み込む。
## エディタから別プロセスで呼ばれる（map_editor.gd の _on_preview）。
## 手動実行: godot --path . -s res://tools/map_editor/preview_launch.gd -- <ステージJSON> <名簿JSON>
## （--headless は付けない＝実機の絵を見るためのツール）
##
## main.load_stage は実物の名簿（user://roster.json）を冒険譚IDと引き継ぎ元のステージIDで引くので、ここでは呼ばずに
## 同じ手順をこちらで踏む＝名簿だけ差し替える。冒険譚IDは空のまま＝クリア記録・オートセーブ・
## 実物の名簿の更新は動かない（実ロジックに実機確認の都合を持ち込まない）。

var _main: Node
var _path := ""
var _roster: Array = []
var _frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("preview: ステージと名簿のパスが指定されていない")
		quit(1)
		return
	_path = args[0]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("preview: 名簿の JSON が不正: %s" % args[1])
		quit(1)
		return
	_roster = parsed
	root.title = "Senaris 実機プレビュー"
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _main == null:
		return true
	_frames += 1
	if _frames == 20:  # タイトル画面の初期化が済むのを待つ
		_main._title.close()
		_main._select.close()
		_load_with_roster()
	return false


## main.load_stage と同じ手順を、でっち上げの名簿で踏む。
func _load_with_roster() -> void:
	var state := StageLoader.load_file(_path, _roster)
	if state == null:
		push_error("preview: ステージを読めない: %s" % _path)
		return
	_main._context.started_at = int(Time.get_unix_time_from_system())
	_main._install_state(state, _path)
	# _install_state は会話を実物の名簿（空）で読む＝when 条件が在籍を見るので、名簿つきで読み直す
	_main._story.set_dialogue(StageLoader.load_dialogue(_path, _roster))
	_main._story.record_start(_roster)
	_main._story.maybe_start_intro()
