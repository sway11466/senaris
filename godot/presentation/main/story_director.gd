extends RefCounted
class_name StoryDirector
## 会話の進行（presentation/main）。ステージ前後の intro／outro、盤のイベントで挟む会話、
## 「ストーリーを確認」の読み直しを、盤のロック・暗幕・情報板の隠しと一緒に進める。
## 経験した会話の記録（CampaignProgress）と目次（HUD）の貼り直しもここ。
## 会話が終わったら closed(phase) で main に返す＝intro 後のターン復帰・outro 後の行き先は main が決める。
## 仕様 → doc/gdd/uiux.md 畳んでいるときの会話・doc/tech/gamesystem.md 経験した会話

## 会話が終わった（読了 or スキップ）。phase＝"intro"/"event"/"review"/"outro"。盤の凍結・暗幕・
## 情報板の隠しは戻してから飛ばす。
signal closed(phase: String)
## 畳んでいて会話を出さないイベントで、カメラ寄せを見せ切ったことを知らせる
## （AIターンの待ち＝await_dialogue が、会話の代わりにこれを待つ）。
signal event_skip_finished
## イベントの会話板をこれから出す（カメラ寄せの前）。寄せは会話板が出る前に走るので、main は
## これを受けて「出る予定の板」を可視域から外す＝寄せ先が会話板の裏にならない
## （情報板を畳んで「会話のみ表示する」のとき。doc/gdd/uiux.md カメラの可視域）。
signal talk_opening

var _board: HexBoard3D = null
var _info_panel: UnitInfoPanel = null
var _hud: Hud = null
var _screen: ScreenLighting = null  # 暗幕（共通基盤）。フェード・重ね掛けの管理は ScreenLighting 持ち
var _conversation: ConversationPanel = null
var _turn_banner: TurnBanner = null  # ターンの頭で起きる会話と重ねない＝始める前に引く
var _progress: CampaignProgress = null  # 読み取りのみ（story の目次・会話の記録の参照）
var _outcome: StageOutcome = null  # 書き込みの門番（stage_started / event_fired）
var _settings_store: SettingsStore = null

var _context: StageContext = null
var _controller: MatchController = null  # ステージごとに作り直される＝set_stage で差し替える
var _dialogue := { "intro": [], "outro": [] }  # 現ステージの会話（台本キー→行。presentation専用・案P）
var _event_talks := {}  # 会話つきイベント id -> { name, dialogue }（「ストーリーを確認」の目次用）
var _phase := ""  # "intro"/"outro"/"event"/"event_skip"/"review"/""＝いま流している会話フェーズ
var _turn_enabled_before_review := false  # 読み直しの前のターン終了の可否（読み終えたら戻す）

## 協力者を受ける（起動時に1回）。会話パネルの closed はここで受け、closed(phase) に変えて返す。
func bind(board: HexBoard3D, info_panel: UnitInfoPanel, hud: Hud, screen: ScreenLighting,
		conversation: ConversationPanel, turn_banner: TurnBanner, progress: CampaignProgress,
		settings_store: SettingsStore, outcome: StageOutcome) -> void:
	_board = board
	_info_panel = info_panel
	_hud = hud
	_screen = screen
	_conversation = conversation
	_turn_banner = turn_banner
	_progress = progress
	_outcome = outcome
	_settings_store = settings_store
	_conversation.closed.connect(_on_conversation_closed)
	_conversation.enter_pace = _on_enter_line  # 台本の enter 行＝隠していた駒を盤に出す
	_hud.story_requested.connect(_on_story_requested)

## ステージごとの台本と文脈。新規ロードでも中断セーブ復元でも呼ぶ。
func set_stage(dialogue: Dictionary, event_talks: Dictionary, context: StageContext, controller: MatchController) -> void:
	_dialogue = dialogue
	_event_talks = event_talks
	_context = context
	_controller = controller
	_phase = ""
	refresh_menu()  # 目次はステージごと＝貼り直す

## 台本を差し替える（クリア後の名簿で when を見直した outro を読ませる）。
func set_dialogue(dialogue: Dictionary) -> void:
	_dialogue = dialogue

func outro_lines() -> Array:
	return _dialogue.get("outro", [])

## 会話を流している最中か（intro/event/review/outro のいずれか）。
func is_talking() -> bool:
	return _phase != ""

## 会話中の暗転（共通基盤に頼む）。block_input=true＝幕より下（盤・HUD）へのクリックも吸う
## （盤ロックとの二重ガード）。
func _set_scrim(on: bool) -> void:
	if _screen == null:
		return
	if on:
		_screen.dim(self, true)
	else:
		_screen.undim(self)

## 盤を沈めて会話に注視させる（intro・event・review・outro で同じ見せ方）。
func _open_talk(phase: String, lines: Array, finish_label: String) -> void:
	_phase = phase
	_info_panel.set_covered(true)  # 会話中は情報パネルを隠す（同じ箱に会話を出す）
	_board.set_input_locked(true)  # 会話中はスクロール等を会話エリアだけに
	_set_scrim(true)
	_hud.set_player_turn(false)
	_conversation.start(lines, finish_label, "ui.talk.skip")

## intro 会話があれば、盤操作をロックして先に流す（無ければ何もしない＝即戦闘）。
## 台本に enter 行があれば、その駒を隠してから流す＝行が来た瞬間に盤に現れる
## （doc/gdd/map.md 会話の途中の登場）。会話を出さないときは隠さない＝盤は台本どおりの顔ぶれで始まる。
func maybe_start_intro() -> void:
	var intro: Array = _dialogue.get("intro", [])
	if intro.is_empty():
		return
	if not shows_dialogue():
		_hud.show_dialogue_badge()  # 開幕の会話があったことだけ知らせる（読むのはメニューから）
		return
	_board.hide_units(_enter_handles(intro))
	_open_talk("intro", intro, "ui.talk.start_battle")

## intro の enter 行が指す駒のハンドルを全部集める（隠す対象）。
func _enter_handles(intro: Array) -> Array:
	var out: Array = []
	if _controller == null:
		return out
	for line in intro:
		if typeof(line) != TYPE_DICTIONARY:
			continue
		for info in StageLoader.resolve_enter(_controller.state, line):
			out.append_array((info as Dictionary).get("units", []))
	return out

## 台本の enter 行（ConversationPanel から）＝隠していた駒を登場の演出つきで盤に出す。
## 効くのは intro を流している最中だけ＝「ストーリーを確認」の読み直しでは何もしない
## （駒はもう盤に居る）。同じ行に並んだ相手は同時に出る（HexBoard3D.reveal_units）。
func _on_enter_line(line: Dictionary) -> void:
	if _phase != "intro" or _controller == null:
		return
	var infos := StageLoader.resolve_enter(_controller.state, line)
	if infos.is_empty():
		return
	await _board.reveal_units(infos)

## 決着の会話。lines＝クリア後の名簿で組み直した outro。label＝閉じるボタンの文言キー
## （次ステージがあるか無いかで変わる＝呼ぶ側が決める）。
func start_outro(lines: Array, label: String) -> void:
	_open_talk("outro", lines, label)

## 盤のイベントが起きたときの見せ方。台本があれば会話を挟み、focus 指定があれば先にその場所へ
## カメラを寄せる（喋る相手が画面に居る状態で幕を引く）。会話の間は盤とターン終了を止める
## （intro/outro と同じ扱い）。増援なら駒はもう盤に出ている＝何が来たのかを見せてから喋らせる。
## 敵ターンに出せるのは占領（on:"capture"）だけ＝1手の切れ目で controller が待ってくれている。
## turn 起点のイベントは敵の手番の頭で起きる＝AI が動き出す前に止める場所が無いので出さない
## （doc/gdd/map.md イベント）。
func on_event_fired(info: Dictionary) -> void:
	if _controller == null or _conversation == null:
		return
	# 登場は会話の有無・陣営を問わず見せる＝台本が無い増援も入口から出てくる。
	await _board.play_entry(info)
	if _phase != "":
		return
	if _controller.is_ai_turn() and String(info.get("type", "")) != "capture":
		return
	var key := String(info.get("dialogue", ""))
	if key.is_empty():
		return
	var lines: Array = _dialogue.get(key, [])
	if lines.is_empty():
		push_warning("story_director: イベントの台本が見つからない: dialogue=%s" % key)
		return
	_note_event(String(info.get("id", "")))  # 起きた＝あとで読み直せる（会話を出すかに関わらず）
	if not shows_dialogue():
		await _skip_event_dialogue(info)
		return
	# 幕より先に phase を立てる＝AIターンの待ち（dialogue_pace）がこの会話を取りこぼさない。
	_phase = "event"
	talk_opening.emit()  # 寄せる前に、会話板の出る場所を可視域から外してもらう
	if not _controller.is_ai_turn():
		await _board.await_move_animation()  # 駒が歩き切ってから喋る（敵ターンは呼ぶ側が待っている）
	if bool(info.get("focus", false)):
		var hex: Vector2i = info.get("hex", Vector2i.MAX)
		if hex != Vector2i.MAX:
			await _board.focus_camera_on([hex] as Array[Vector2i])
	if _turn_banner != null:
		_turn_banner.dismiss()  # ターンの頭で起きる＝バナーと会話を重ねない
	_open_talk("event", lines, "ui.talk.resume_battle")

## 畳んでいて会話を出さないとき。盤は止めず暗幕も降ろさないが、カメラ寄せだけは見せる
## ＝何がどこで起きたかは戦況で、会話と一緒に切ってよいものではない
## （doc/gdd/uiux.md 畳んでいるときの会話）。見せ終えたら吹き出しで知らせる。
func _skip_event_dialogue(info: Dictionary) -> void:
	# 幕より先に phase を立てるのと同じ理由＝AIターンの待ちがカメラ寄せを取りこぼさない。
	_phase = "event_skip"
	if not _controller.is_ai_turn():
		await _board.await_move_animation()  # 駒が歩き切ってから寄せる（敵ターンは呼ぶ側が待っている）
	if bool(info.get("focus", false)):
		var hex: Vector2i = info.get("hex", Vector2i.MAX)
		if hex != Vector2i.MAX:
			await _board.focus_camera_on([hex] as Array[Vector2i])
	_hud.show_dialogue_badge()
	_phase = ""
	event_skip_finished.emit()

## AIターンのテンポ制御（controller.dialogue_pace に注入）：占領で会話が始まっていれば閉じるまで待つ。
## 会話を始めるのは on_event_fired ＝ここへ来た時点で phase は立っている（カメラ寄せの前に立てている）。
func await_dialogue() -> void:
	if _phase == "event" and _conversation != null:
		await _conversation.closed
	elif _phase == "event_skip":
		await event_skip_finished  # 会話は出さないが、カメラ寄せは見せ切ってから次の手へ

## 情報板を畳んでいるときに会話を出すか（設定 → doc/gdd/settings.md 会話）。
## 開いていれば常に出す＝この設定は畳んでいるときだけ効く。
func shows_dialogue() -> bool:
	if not _info_panel.is_minimized():
		return true
	return _settings_store.dialogue_when_minimized() == "show"

## 経験した会話の記録（doc/tech/gamesystem.md 経験した会話）。書き込みは
## application/stage_outcome.gd に委ねる＝presentation は状態を直接書き換えない。
## roster＝開始時の在籍（あとで当時の顔ぶれで会話を組み直せる）。
func on_stage_started(roster: Array) -> void:
	if _outcome == null or not _context.in_campaign():
		return
	_outcome.stage_started(_context.campaign_id, _context.stage_id, roster)
	refresh_menu()

func _note_event(event_id: String) -> void:
	if _outcome == null or not _context.in_campaign() or event_id.is_empty():
		return
	_outcome.event_fired(_context.campaign_id, _context.stage_id, event_id)
	refresh_menu()

## そのステージで経験した会話の記録（無ければ空）。
func _story_record() -> Dictionary:
	if _progress == null or _context == null or not _context.in_campaign():
		return {}
	return _progress.story(_context.campaign_id, _context.stage_id)

## 「ストーリーを確認」の目次を貼り直す。経験していないものは並べない
## ＝まだ見ていない出来事の存在を目次で匂わせない（doc/gdd/uiux.md ターン終了・システムメニュー）。
## 見出しはここで訳して渡す＝言語が変われば呼び直す。イベント名は id からの規約キー（StageLoader.event_name_key）。
func refresh_menu() -> void:
	var record := _story_record()
	var entries: Array = []
	if record.has("start") and not _dialogue.get("intro", []).is_empty():
		entries.append(["intro", tr("ui.hud.story_intro")])
	for id in record.get("events", []):
		var talk: Dictionary = _event_talks.get(String(id), {})
		if not talk.is_empty():  # ステージを直してイベントごと消えた記録は出さない
			entries.append([String(id), tr(String(talk["name"]))])
	if record.has("clear") and not _dialogue.get("outro", []).is_empty():
		entries.append(["outro", tr("ui.hud.story_outro")])
	_hud.set_story_entries(entries)

## 目次から選ばれた会話を出す。当時の顔ぶれで台本を組み直す＝記録した在籍 actor を名簿の
## 代わりに渡す（会話の when が見るのは在籍だけ）。読み終えたら割り込む前の状態へ戻す。
func _on_story_requested(key: String) -> void:
	if _conversation == null or _phase != "":
		return
	var record := _story_record()
	var actors: Array = record.get("clear", []) if key == "outro" else record.get("start", [])
	var script := StageLoader.load_dialogue(_context.stage_path, _actors_as_roster(actors))
	var talk_key := key
	if key != "intro" and key != "outro":
		var talk: Dictionary = _event_talks.get(key, {})
		if talk.is_empty():
			return
		talk_key = String(talk["dialogue"])
	var lines: Array = script.get(talk_key, [])
	if lines.is_empty():
		push_warning("story_director: 読み直す台本が見つからない: %s" % talk_key)
		return
	_turn_enabled_before_review = _hud.player_turn_enabled()
	_hud.hide_dialogue_badge()
	_open_talk("review", lines, "ui.talk.close")

## 記録した actor の並びを、会話の条件（when: joined:<actor>）が見るだけの名簿に仕立てる。
## StageLoader が見るのは actor だけ＝素性も損耗も要らない。
static func _actors_as_roster(actors: Array) -> Array:
	var out: Array = []
	for a in actors:
		out.append({ "actor": String(a) })
	return out

## 会話終了（読了 or スキップ）。盤の凍結・暗幕・情報板の隠しを戻し、読み直しなら割り込む前の
## ターン終了の可否へ戻す。次に何をするか（戦闘へ戻る・次ステージへ）は closed を受けた main。
func _on_conversation_closed() -> void:
	if _phase == "intro":
		_board.reveal_all_hidden()  # スキップで読み残した enter 行の駒も盤に出す（演出なし）
	_info_panel.set_covered(false)  # 会話が終わったら情報パネルを戻す（畳んでいたなら畳んだまま）
	_board.set_input_locked(false)  # 盤の凍結を解除（intro/outro 共通）
	_set_scrim(false)  # 暗幕を戻す（盤が主役に戻る）
	var phase := _phase
	_phase = ""
	if phase == "review":  # 読み直し＝盤は何も進めない。割り込む前の状態へ戻すだけ
		_hud.set_player_turn(_turn_enabled_before_review)
	closed.emit(phase)
