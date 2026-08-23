extends Control
class_name SoundCheckTool
## サウンドチェッカー（開発用・ゲーム本体非依存）。BGMと効果音を組み合わせて鳴らし、
## 曲どうしの音量差・ループの継ぎ目・効果音の被り具合を耳で確かめる。
##
## - 左＝BGM。assets/bgm/*.ogg を実ファイル基準で並べる（カタログ非依存＝置いた曲がそのまま出る）。
##   2曲を交互に押せばそのまま聴き比べになる（同じ曲の再押下は BgmPlayer 側で無視される）。
## - 右＝効果音。素材（assets/sfx の実ファイル）と発火点（SfxCatalog.BIND）の2タブ。BGMに重ねて鳴る。
## - 下＝Master / Music / SFX の音量とピークメーター（本体と同じバス構成）。
##
## 鳴らす経路は本体と同じ BgmPlayer / SfxPlayer を使う＝ここでの聴こえ方が実機と一致する。
## 実行: godot --path . res://tools/sound_check/sound_check.tscn（エディタで開いて再生でも可）。

const BGM_DIR := "res://assets/bgm"
const SFX_DIR := "res://assets/sfx"
const SFX_EXTS := [".ogg", ".wav"]
const BUSES := ["Master", "Music", "SFX"]
const STINGERS := ["victory", "defeat"]  ## 決着の一発曲（BGMとして鳴らすと挙動が違う＝専用ボタンで出す）
const SEAM_TAIL_SEC := 3.0   ## 「継ぎ目へ」で飛ぶ位置＝末尾からこの秒数
const METER_FLOOR_DB := -60.0
const BG := Color(0.20, 0.22, 0.25)

var _bgm: BgmPlayer = null
var _sfx: SfxPlayer = null
var _material_player: AudioStreamPlayer = null  ## 素材の直接再生（SfxPlayer の入口は発火点IDのみのため）

var _tracks: Array = []          # [{id, length, loop}]
var _track_buttons := {}         # track_id -> Button（再生中の強調に使う）
var _now_label: Label = null
var _pos_label: Label = null
var _meters := {}                # bus 名 -> ProgressBar

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_install_audio()
	_tracks = _scan_bgm()
	_build_ui()

## 本体と同じ再生ノードを載せる。SfxPlayer は _ready で自身を静的に登録するので、
## 発火点は SfxPlayer.play_event で鳴らせるようになる。
func _install_audio() -> void:
	_bgm = BgmPlayer.new()
	_bgm.name = "BgmPlayer"
	add_child(_bgm)
	_sfx = SfxPlayer.new()
	_sfx.name = "SfxPlayer"
	add_child(_sfx)
	_material_player = AudioStreamPlayer.new()
	_material_player.bus = SfxPlayer.BUS
	add_child(_material_player)

# --- 走査（実ファイル基準）---

## assets/bgm の .ogg を全部拾う。長さとループ設定はストリームから読む。
func _scan_bgm() -> Array:
	var out: Array = []
	var d := DirAccess.open(BGM_DIR)
	if d == null:
		push_warning("sound_check: %s を開けない" % BGM_DIR)
		return out
	var names := d.get_files()
	names.sort()
	for f in names:
		if not f.ends_with(".ogg"):
			continue  # .ogg.import 等は落ちる
		var stream := ResourceLoader.load("%s/%s" % [BGM_DIR, f]) as AudioStream
		if stream == null:
			continue
		var looped := false
		if stream is AudioStreamOggVorbis:
			looped = (stream as AudioStreamOggVorbis).loop
		out.append({"id": f.trim_suffix(".ogg"), "length": stream.get_length(), "loop": looped})
	return out

## assets/sfx の素材ID（拡張子違いは1つにまとめる）。
func _scan_sfx_materials() -> Array:
	var seen := {}
	var out: Array = []
	var d := DirAccess.open(SFX_DIR)
	if d == null:
		return out
	var names := d.get_files()
	names.sort()
	for f in names:
		for ext in SFX_EXTS:
			if not f.ends_with(ext):
				continue
			var stem := f.trim_suffix(ext)
			if not seen.has(stem):
				seen[stem] = true
				out.append(stem)
			break
	return out

# --- UI ---

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var hint := Label.new()
	hint.text = "サウンドチェッカー — BGMを1つ選び、効果音を重ねて鳴らす。曲を聴き比べるときは2曲を交互に押す。"
	root.add_child(hint)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	root.add_child(cols)
	cols.add_child(_build_bgm_pane())
	cols.add_child(_build_sfx_pane())

	root.add_child(_build_bus_pane())

func _build_bgm_pane() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var head := Label.new()
	head.text = "BGM（%s・%d曲）" % [BGM_DIR, _tracks.size()]
	box.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for t in _tracks:
		var id := String(t["id"])
		var row := HBoxContainer.new()
		var btn := Button.new()
		btn.text = id
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_play_bgm.bind(id))
		row.add_child(btn)
		_track_buttons[id] = btn
		var info := Label.new()
		info.text = "%6.1f秒 %s" % [float(t["length"]), "ループ" if bool(t["loop"]) else "一発"]
		info.custom_minimum_size.x = 110
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(info)
		list.add_child(row)

	box.add_child(HSeparator.new())

	_now_label = Label.new()
	box.add_child(_now_label)
	_pos_label = Label.new()
	box.add_child(_pos_label)

	var ops := HBoxContainer.new()
	box.add_child(ops)
	ops.add_child(_button("停止", _stop_bgm))
	ops.add_child(_button("頭出し", _seek_head))
	ops.add_child(_button("継ぎ目へ（残り%.0f秒）" % SEAM_TAIL_SEC, _seek_seam))

	var st_head := Label.new()
	st_head.text = "スティンガー（現在の曲を素早く下げて頭から一発）"
	box.add_child(st_head)
	var st_row := HBoxContainer.new()
	box.add_child(st_row)
	for id in STINGERS:
		st_row.add_child(_button(id, _play_stinger.bind(id)))
	return box

func _build_sfx_pane() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var head := Label.new()
	head.text = "効果音（BGMに重ねて鳴る）"
	box.add_child(head)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)

	var materials := _scan_sfx_materials()
	var mat_box := VBoxContainer.new()
	mat_box.name = "素材（%d）" % materials.size()
	tabs.add_child(mat_box)
	for sfx_id in materials:
		mat_box.add_child(_button(sfx_id, _play_material.bind(String(sfx_id))))
	if materials.is_empty():
		mat_box.add_child(_note("素材が1つも無い（%s）" % SFX_DIR))

	var events: Array = SfxCatalog.BIND.keys()
	events.sort()
	var ev_box := VBoxContainer.new()
	ev_box.name = "発火点（%d）" % events.size()
	tabs.add_child(ev_box)
	for e in events:
		var event_id := String(e)
		var sfx_id := SfxCatalog.sfx_of(event_id)
		var ready := SfxCatalog.exists(event_id)
		var row := HBoxContainer.new()
		var btn := Button.new()
		btn.text = event_id
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = not ready
		btn.pressed.connect(SfxPlayer.play_event.bind(event_id))
		row.add_child(btn)
		var info := Label.new()
		info.text = "→ %s %s" % [sfx_id, "○" if ready else "×（素材なし）"]
		info.custom_minimum_size.x = 170
		row.add_child(info)
		ev_box.add_child(row)
	ev_box.add_child(_note("×＝対応表にはあるが assets/sfx にファイルが無い＝実機でも無音。"))
	return box

func _build_bus_pane() -> Control:
	var box := VBoxContainer.new()
	box.add_child(HSeparator.new())
	var head := Label.new()
	head.text = "音量バス（本体と同じ構成）"
	box.add_child(head)
	for bus_name in BUSES:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)

		var name_label := Label.new()
		name_label.text = bus_name
		name_label.custom_minimum_size.x = 60
		row.add_child(name_label)

		var db_label := Label.new()
		db_label.custom_minimum_size.x = 70
		db_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		db_label.text = "%+.1f dB" % AudioServer.get_bus_volume_db(idx)

		var slider := HSlider.new()
		slider.min_value = METER_FLOOR_DB
		slider.max_value = 6.0
		slider.step = 0.5
		slider.value = AudioServer.get_bus_volume_db(idx)
		slider.custom_minimum_size.x = 200
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(v: float) -> void:
			AudioServer.set_bus_volume_db(idx, v)
			db_label.text = "%+.1f dB" % v)
		row.add_child(slider)
		row.add_child(db_label)

		var meter := ProgressBar.new()
		meter.min_value = METER_FLOOR_DB
		meter.max_value = 0.0
		meter.value = METER_FLOOR_DB
		meter.show_percentage = false
		meter.custom_minimum_size.x = 160
		row.add_child(meter)
		_meters[bus_name] = meter
	return box

func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_pressed)
	return b

func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# --- 操作 ---

func _play_bgm(track_id: String) -> void:
	_bgm.play(track_id)

func _play_stinger(track_id: String) -> void:
	_bgm.play_stinger(track_id)

func _stop_bgm() -> void:
	_bgm.stop()

func _play_material(sfx_id: String) -> void:
	var path := SfxCatalog.path_of(sfx_id)
	if path.is_empty():
		return
	_material_player.stream = ResourceLoader.load(path) as AudioStream
	_material_player.play()

func _seek_head() -> void:
	var p := _active_player()
	if p != null and p.playing:
		p.seek(0.0)

## ループの継ぎ目へ飛ぶ＝末尾手前から聴いて、折り返しの繋がりを確かめる。
func _seek_seam() -> void:
	var p := _active_player()
	if p == null or not p.playing or p.stream == null:
		return
	p.seek(maxf(p.stream.get_length() - SEAM_TAIL_SEC, 0.0))

## BgmPlayer は位置取得・シークの口を持たないので、ツール側から表のプレイヤーを直接見る。
## 開発ツールのために本体へAPIを足さないための割り切り（ここだけに閉じる）。
func _active_player() -> AudioStreamPlayer:
	if _bgm == null or _bgm._players.is_empty():
		return null
	return _bgm._players[_bgm._active]

# --- 表示の更新 ---

func _process(_delta: float) -> void:
	var track := _bgm.current_track() if _bgm != null else ""
	_now_label.text = "再生中: %s" % (track if not track.is_empty() else "（なし）")
	for id in _track_buttons:
		var btn: Button = _track_buttons[id]
		btn.button_pressed = (id == track)

	var p := _active_player()
	if p != null and p.playing and p.stream != null:
		_pos_label.text = "位置: %.1f / %.1f 秒" % [p.get_playback_position(), p.stream.get_length()]
	else:
		_pos_label.text = "位置: —"

	for bus_name in _meters:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			continue
		var peak := AudioServer.get_bus_peak_volume_left_db(idx, 0)
		var meter: ProgressBar = _meters[bus_name]
		meter.value = clampf(peak, METER_FLOOR_DB, 0.0)
