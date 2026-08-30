extends RefCounted
class_name SaveFile
## 保存ファイルに共通する版の判定と退避。仕様 → doc/tech/gamesystem.md §版と移行・§バックアップ
## 進捗・名簿・中断・設定の各ストアはここを通して読み書きする＝退避を書き忘れる場所を作らない。
## 退避したファイルはゲームから読まない（復旧はサポートで手順を伝え、プレイヤーが手で戻す）。

## 平常時に残す世代の数。書き込むたびに直前の中身を1つ足し、超えたぶんを古い順に消す。
const GENERATIONS := 5

## 読み込みの結果。VALID 以外は中身を使わない。
enum {
	VALID,       ## 辞書として読めて、版が現行と一致した
	MISSING,     ## ファイルが無い（退避しない）
	UNREADABLE,  ## JSON として読めない／辞書でない
	MISMATCHED,  ## 版が現行と違う（旧版・現行より新しい版のどちらも）
}

## ファイルを読んで版まで確かめる。{ "status": int, "data": Dictionary } を返す。
## 中身を使ってよいのは status == VALID のときだけ。使えないファイルはここで退避して元の場所から消す
## ＝同じファイルを読み直しても退避が重ならない。
static func read(path: String, version: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return { "status": MISSING, "data": {} }
	# 破損・手編集がありうるファイルなので、エンジンエラーを出さない JSON.parse で静かに検証する
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_aside(path, "broken")
		return { "status": UNREADABLE, "data": {} }
	var data: Dictionary = parsed
	var found := int(data.get("version", 0))
	if found != version:
		# 版が読み取れた側は形が保たれている＝復旧の手の入れ方が broken と違うので、名前で分ける
		_set_aside(path, "v%d" % found)
		return { "status": MISMATCHED, "data": {} }
	return { "status": VALID, "data": data }

## 書き込む前に現物を退避する。過去 GENERATIONS 世代を残し、超えたぶんを古い順に消す。
static func rotate(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var dest := _sibling(path, _timestamp())
	if FileAccess.file_exists(dest):
		return  # 同じ秒に既に取ってある。先に取ったほうが古い＝戻り先として価値があるので残す
	if DirAccess.copy_absolute(_abs(path), _abs(dest)) != OK:
		push_error("SaveFile: 世代を残せない: %s" % dest)
		return
	_trim(path)

## 使えなかったファイルを印つきの名前へ移す。平常時の世代とは別勘定で、自動では消さない。
static func _set_aside(path: String, mark: String) -> void:
	var dest := _sibling(path, "%s-%s" % [mark, _timestamp()])
	if DirAccess.rename_absolute(_abs(path), _abs(dest)) != OK:
		push_error("SaveFile: 退避できない: %s" % dest)

## 世代が GENERATIONS を超えていたら古い順に消す。
static func _trim(path: String) -> void:
	var files := _generations(path)
	if files.size() <= GENERATIONS:
		return
	files.sort()  # 名前に入れた時刻がそのまま古い順になる
	var dir := path.get_base_dir()
	for i in range(files.size() - GENERATIONS):
		DirAccess.remove_absolute(_abs(dir.path_join(files[i])))

## 平常時の世代のファイル名を集める。印つきの退避は形が違うので入らない＝自動で消さない。
static func _generations(path: String) -> PackedStringArray:
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return PackedStringArray()
	var prefix := path.get_file().get_basename() + "."
	var suffix := "." + path.get_extension()
	var out := PackedStringArray()
	for file in dir.get_files():
		if not file.begins_with(prefix) or not file.ends_with(suffix):
			continue
		if _is_timestamp(file.substr(prefix.length(), file.length() - prefix.length() - suffix.length())):
			out.append(file)
	return out

## 世代の印＝20260830-101500 の形か。印つきの退避（broken-…／v2-…）はここで外れる。
static func _is_timestamp(mark: String) -> bool:
	if mark.length() != 15 or mark[8] != "-":
		return false
	return mark.substr(0, 8).is_valid_int() and mark.substr(9).is_valid_int()

## 元のファイル名に印を挟んだ隣のパス（save_1.json ＋ v2-… → save_1.v2-….json）。
static func _sibling(path: String, mark: String) -> String:
	var file := "%s.%s.%s" % [path.get_file().get_basename(), mark, path.get_extension()]
	return path.get_base_dir().path_join(file)

static func _timestamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d-%02d%02d%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"]]

static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)
