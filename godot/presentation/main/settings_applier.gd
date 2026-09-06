class_name SettingsApplier
## 設定値を実機に当てる（presentation/main）。音量はバス、画面モードは窓、言語は翻訳サーバー。
## AudioServer / DisplayServer / TranslationServer を触るのはここだけ＝main は SettingsScreen の
## シグナルを受けて値を保存し、ここを呼ぶ役に留まる。仕様 → doc/gdd/settings.md
## 起動時の復元と、設定画面で値が動くたびの両方がここを通る。

## 設定の音量の系統 -> AudioServer のバス名（default_bus_layout.tres）。
const VOLUME_BUS_NAMES := { "master": "Master", "music": BgmPlayer.BUS, "sfx": SfxPlayer.BUS }

## 音量（0〜100）をバスに当てる。100＝0 dB（素材そのまま）、0＝ミュート。間は振幅に比例させる。
## つまみを引きずっている間も呼ばれる。
static func apply_volume(bus: String, value: int) -> void:
	var idx := AudioServer.get_bus_index(String(VOLUME_BUS_NAMES[bus]))
	if idx < 0:
		push_error("settings_applier: 音量のバスが無い: %s" % bus)
		return
	AudioServer.set_bus_mute(idx, value == 0)
	if value > 0:
		AudioServer.set_bus_volume_linear(idx, float(value) / float(SettingsStore.VOLUME_MAX))

## 画面モードを窓に当てる。全画面は枠なしの全画面（排他ではない＝Alt+Tab で崩れない）。
static func apply_window_mode(mode: String) -> void:
	match mode:
		"windowed":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			push_error("settings_applier: 知らない画面モード: %s" % mode)

## 言語を当てる。以後の tr() がこの言語で引く（生きている画面の貼り直しは呼ぶ側）。
static func apply_locale(locale: String) -> void:
	TranslationServer.set_locale(locale)
