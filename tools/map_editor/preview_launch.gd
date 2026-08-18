extends SceneTree
## マップエディタの「実機で確認」の起動口。編集中のステージ（一時ファイルのコピー）を受け取り、
## ゲーム本体を起動して直接読み込む。エディタから別プロセスで呼ばれる（map_editor.gd の _on_preview）。
## 手動実行: godot --path . -s res://tools/map_editor/preview_launch.gd -- <ステージJSONの絶対パス>
## （--headless は付けない＝実機の絵を見るためのツール）

var _main: Node
var _path := ""
var _frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("preview: ステージのパスが指定されていない")
		quit(1)
		return
	_path = args[0]
	root.title = "Senaris 実機プレビュー"
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _main == null:
		return true
	_frames += 1
	if _frames == 20:  # タイトル画面の初期化が済むのを待つ（shot_board_height.gd と同じ待ち方）
		_main._title.close()
		_main._select.close()
		_main.load_stage(_path)
	return false
