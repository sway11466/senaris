extends RefCounted
class_name SettingsStore
## 設定値の読み書き（user://settings.json）。仕様 → doc/tech/gamesystem.md §設定
## 進捗・名簿・中断セーブとは別枠＝どのセーブから再開しても設定は同じ。
## 素のJSON＋バージョン・形式チェック（不正・破損は設定が無いものとして扱い、起動を止めない）。
##
## 書くのはプレイヤーが選んだ値だけ。選んでいない項目はファイルに現れない
## ＝「まだ選ばれていない」と「選んだ結果たまたま既定と同じ」を取り違えない。

const DEFAULT_PATH := "user://settings.json"
const VERSION := 1

## 選べる言語。翻訳CSVの列（doc/tech/i18n.md）と対応する。
const LOCALES := ["ja", "en"]

## 音量の系統。ファイルの項目名は "volume_<系統>"。どの AudioServer のバスに当てるかは main が決める。
const VOLUME_BUSES := ["master", "music", "sfx"]
const VOLUME_MAX := 100  # 0〜100 の整数。100＝素材そのままの音量（バス 0 dB）

## 画面モード。仕様 → doc/gdd/settings.md 画面
const WINDOW_MODES := ["windowed", "fullscreen"]

var _path: String
var _values := {}  # 項目 -> 値（プレイヤーが選んだものだけ）

func _init(path: String = DEFAULT_PATH) -> void:
	_path = path
	_load()

## 起動時に使う言語。まだ選ばれていなければ環境から決める
## （OS の言語が日本語なら日本語・それ以外は英語。doc/tech/gamesystem.md §設定）。
func locale() -> String:
	var v: Variant = _values.get("locale", null)
	if v is String and LOCALES.has(v):
		return String(v)
	return "ja" if OS.get_locale_language() == "ja" else "en"

## 言語を選んだ。ここで初めてファイルに書く。
func set_locale(value: String) -> void:
	if not LOCALES.has(value):
		push_error("SettingsStore: 知らない言語: %s" % value)
		return
	_values["locale"] = value
	_save()

## 音量（0〜100）。まだ選ばれていなければ 100＝素材そのままの音量。
func volume(bus: String) -> int:
	if not VOLUME_BUSES.has(bus):
		push_error("SettingsStore: 知らない音量の系統: %s" % bus)
		return VOLUME_MAX
	var v: Variant = _values.get("volume_" + bus, null)
	if v is int:
		return int(v)
	return VOLUME_MAX

## 音量を選んだ。範囲外は書かない（スライダーの範囲が正本＝ここで丸めて誤魔化さない）。
func set_volume(bus: String, value: int) -> void:
	if not VOLUME_BUSES.has(bus):
		push_error("SettingsStore: 知らない音量の系統: %s" % bus)
		return
	if value < 0 or value > VOLUME_MAX:
		push_error("SettingsStore: 音量が範囲外: %s=%d" % [bus, value])
		return
	_values["volume_" + bus] = value
	_save()

## 画面モード。まだ選ばれていなければウィンドウ（project.godot の起動時の形と同じ）。
func window_mode() -> String:
	var v: Variant = _values.get("window_mode", null)
	if v is String and WINDOW_MODES.has(v):
		return String(v)
	return "windowed"

func set_window_mode(value: String) -> void:
	if not WINDOW_MODES.has(value):
		push_error("SettingsStore: 知らない画面モード: %s" % value)
		return
	_values["window_mode"] = value
	_save()

## 情報板を畳んでいるか。まだ選ばれていなければ開いている。仕様 → doc/gdd/uiux.md 最小化
func info_panel_minimized() -> bool:
	var v: Variant = _values.get("info_panel_minimized", null)
	return v is bool and bool(v)

## 情報板を畳んだ／開いた。板の操作そのものが設定＝押すたびに書く（設定画面に項目は無い）。
func set_info_panel_minimized(value: bool) -> void:
	_values["info_panel_minimized"] = value
	_save()

## 情報板を動かした位置（板の左上・1280×720 の論理座標）があるか。無ければ既定の場所。
## 仕様 → doc/gdd/uiux.md 移動
func has_info_panel_position() -> bool:
	return _values.has("info_panel_position")

func info_panel_position() -> Vector2:
	var v: Variant = _values.get("info_panel_position", null)
	if v is Dictionary:
		return Vector2(float(v["x"]), float(v["y"]))
	return Vector2.ZERO

## 情報板を動かした。位置は辞書 { x, y } で書く（JSON に Vector2 は無い）。
func set_info_panel_position(pos: Vector2) -> void:
	_values["info_panel_position"] = { "x": pos.x, "y": pos.y }
	_save()

## 情報板の位置を既定へ戻した＝動かしていない状態に戻す（項目ごと消す）。
func clear_info_panel_position() -> void:
	if not _values.has("info_panel_position"):
		return
	_values.erase("info_panel_position")
	_save()

func _load() -> void:
	# 破損・手編集・版違いの判定と退避は SaveFile が持つ（doc/tech/gamesystem.md §バックアップ）
	var result := SaveFile.read(_path, VERSION)
	var status := int(result["status"])
	if status != SaveFile.VALID:
		if status != SaveFile.MISSING:
			push_warning("SettingsStore: 設定ファイルが不正のため設定なしで起動: %s" % _path)
		return
	var data: Dictionary = result["data"]
	var loc: Variant = data.get("locale", null)
	if loc is String and LOCALES.has(loc):
		_values["locale"] = String(loc)
	for bus in VOLUME_BUSES:
		var vol: Variant = data.get("volume_" + bus, null)
		# JSON の数は float で読まれる。整数値で範囲内のものだけ採る（手編集の 50.5 や 200 は無視）。
		if _is_number(vol) and float(vol) == floor(float(vol)) and int(vol) >= 0 and int(vol) <= VOLUME_MAX:
			_values["volume_" + bus] = int(vol)
	var mode: Variant = data.get("window_mode", null)
	if mode is String and WINDOW_MODES.has(mode):
		_values["window_mode"] = String(mode)
	var minimized: Variant = data.get("info_panel_minimized", null)
	if minimized is bool:
		_values["info_panel_minimized"] = bool(minimized)
	var pos: Variant = data.get("info_panel_position", null)
	if pos is Dictionary and _is_number(pos.get("x")) and _is_number(pos.get("y")):
		_values["info_panel_position"] = { "x": float(pos["x"]), "y": float(pos["y"]) }

static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT

func _save() -> void:
	SaveFile.rotate(_path)
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("SettingsStore: 書き込めない: %s" % _path)
		return
	var out := { "version": VERSION }
	for k in _values:
		out[k] = _values[k]
	f.store_string(JSON.stringify(out, "  "))
