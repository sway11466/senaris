extends Node
class_name BgmPlayer
## BGM の再生（AudioStreamPlayer×2 の入れ替え）。presentation＝トラックIDを受けて鳴らすだけ。
## 曲の選択ルール（場面→曲）は application/bgm_director.gd に置く。詳細 → doc/audio/bgm.md
##
## 曲が未配置なら無音＋ログ1行で進む（ゲームは止めない）。.ogg を置けば次の切替から鳴り出す。
## ループは Godot のインポート設定（.import の loop）で持つ＝ここでは扱わない。

const BUS := "Music"       ## 効果音と別に絞れるようにする（default_bus_layout.tres）
const FADE_OUT_SEC := 0.35 ## 旧曲を落とす時間。短く取る＝新旧の旋律がフル音量で重ならない
const DUCK_SEC := 0.3      ## スティンガー時に現曲を素早く下げる時間（ファンファーレの頭に被せない）
const FOLLOW_FADE_SEC := 2.0  ## スティンガーの後に続く曲だけはフェードインする（下記 _follow_stinger）
const SILENCE_DB := -60.0  ## 実質無音。0.0 が通常音量
const MUFFLE_HZ := 900.0   ## 閉じた扉越しに聞こえる状態。これより上を削るとこもる
const OPEN_HZ := 20000.0   ## 実質フィルタなし（人の可聴域の上端）

var _players: Array[AudioStreamPlayer] = []
var _active := 0        ## いま表で鳴っているプレイヤーの index
var _current_track := ""
var _tween: Tween = null
var _lowpass: AudioEffectLowPassFilter = null  ## 挿している間だけ非 null（下記 muffle/open_up）
var _lowpass_tween: Tween = null

func _ready() -> void:
	for _i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = SILENCE_DB
		add_child(p)
		_players.append(p)

## トラックIDの曲へ切り替える。同じ曲なら何もしない＝場面をまたいでも鳴り続ける
## （セレクト→下敷きステージのように、同じ曲を指す画面遷移で頭出しに戻らない）。
## 空文字は「曲なし」＝現在の曲をフェードアウトして無音にする。
## fade_in_sec は既定 0＝頭から素の音量（曲の入りを聞かせる）。無音から静かに立ち上げたい
## 場面だけ秒数を渡す。
## fade_out_sec を渡すと旧曲の落ちる時間も変えられる。fade_in と同じ長さにすれば
## 両者が重なるクロスフェードになる（既定は旧曲だけ素早く落とす）。
func play(track_id: String, fade_in_sec: float = 0.0, fade_out_sec: float = FADE_OUT_SEC) -> void:
	if track_id == _current_track:
		return
	_current_track = track_id
	_fade_to(_load(track_id), fade_in_sec, fade_out_sec)

## スティンガー（勝利/敗北など loop=false の一発曲）を鳴らす。現在のステージ曲は素早く下げ、
## スティンガーはフェードインせず頭から出す＝ファンファーレの立ち上がりを殺さない。
##
## follow_track_id を渡すと、鳴り終わってからその曲へ移る。一発曲は十数秒で終わるので、
## その後も画面が続く場面（勝利→outro 会話）では無音が居座る。省略すれば鳴り終えても無音のまま
## （次のステージ開始 or セレクトで play() が張り替える）。
func play_stinger(track_id: String, follow_track_id: String = "") -> void:
	_current_track = track_id
	var stream := _load(track_id)
	if stream == null and not follow_track_id.is_empty():
		play(follow_track_id)  # スティンガーが未配置＝鳴り終わりを待つものが無い。直ちに続きへ
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var outgoing := _players[_active]
	if stream != null:
		_active = 1 - _active  # 裏を表にする（現曲は素早く下げるだけ＝鳴らしたまま）
		var incoming := _players[_active]
		incoming.stream = stream
		incoming.volume_db = 0.0  # フェードインしない（頭のアタックを出す）
		incoming.play()
		if not follow_track_id.is_empty():
			incoming.finished.connect(_follow_stinger.bind(track_id, follow_track_id), CONNECT_ONE_SHOT)
	_tween = create_tween()
	_tween.tween_property(outgoing, "volume_db", SILENCE_DB, DUCK_SEC)
	_tween.tween_callback(outgoing.stop)

## スティンガーが鳴り終わった＝続きの曲へ移る。待っている間に別の曲へ切り替わっていたら何もしない
## （会話を読み飛ばして次ステージが始まった後に、終わったスティンガーが割り込むのを防ぐ）。
##
## ここだけフェードインする。曲の切り替えと違って前の音が既に鳴り止んでいるので、
## 素の音量で入ると無音から音が生えたように聞こえる。
func _follow_stinger(stinger_id: String, follow_track_id: String) -> void:
	if _current_track != stinger_id:
		return
	play(follow_track_id, FOLLOW_FADE_SEC)

## トラックIDの AudioStream を読む。未配置・読めない時は null（呼び出し側は無音で進む）。
## Godot が扱えるのは Ogg Vorbis＝Opus や壊れた ogg は import が通らず null になる。
func _load(track_id: String) -> AudioStream:
	var path := BgmCatalog.path_of(track_id)
	if path.is_empty():
		if not track_id.is_empty():
			print("BgmPlayer: 曲が未配置＝無音で進行: %s（%s/%s.ogg）" % [track_id, BgmCatalog.BGM_ROOT, track_id])
		return null
	var stream := ResourceLoader.load(path) as AudioStream
	if stream == null:
		print("BgmPlayer: 曲を読めない＝無音で進行: %s（Ogg Vorbis か確認）" % path)
	return stream

## 曲を止める（無音へフェード）。
func stop() -> void:
	play("")

# --- こもり（ローパス）。タイトル画面で「閉じた扉の向こうの音」を作る ---
# 高い音ほど遮蔽物に吸われる＝壁越しの音が低音ばかりに聞こえる現象を、バスに挿した
# ローパスフィルタで再現する。素材を2種類持たずに済み、扉が開く動きに合わせて
# 連続的に開けられる（焼き込むとこの変化が作れない）。

## 曲をこもらせる。既に挿していれば何もしない。
func muffle() -> void:
	if _lowpass != null:
		return
	var bus := AudioServer.get_bus_index(BUS)
	if bus < 0:
		return
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = MUFFLE_HZ
	AudioServer.add_bus_effect(bus, _lowpass)

## こもりを sec 秒かけて解く。開ききったらフィルタを外す。
## 外すのは、バスの効果が場面をまたいで残り続けるため（挿しっぱなしだと以降の曲もこもる）。
## sec <= 0 なら即座に外す（スキップされた場合の後始末）。
func open_up(sec: float) -> void:
	if _lowpass == null:
		return
	if _lowpass_tween != null and _lowpass_tween.is_valid():
		return  # 既に開いている最中＝二重に走らせない
	if sec <= 0.0:
		_remove_lowpass()
		return
	_lowpass_tween = create_tween()
	_lowpass_tween.tween_property(_lowpass, "cutoff_hz", OPEN_HZ, sec)
	_lowpass_tween.tween_callback(_remove_lowpass)

func _remove_lowpass() -> void:
	if _lowpass == null:
		return
	var bus := AudioServer.get_bus_index(BUS)
	if bus >= 0:
		for i in range(AudioServer.get_bus_effect_count(bus) - 1, -1, -1):
			if AudioServer.get_bus_effect(bus, i) == _lowpass:
				AudioServer.remove_bus_effect(bus, i)
				break
	_lowpass = null

## いま鳴っている（鳴っているはずの）トラックID。未配置で無音のときも要求されたIDを返す。
func current_track() -> String:
	return _current_track

## 表と裏を入れ替える。旧曲はフェードアウトさせ、新曲は既定ではフェードインせず頭から鳴らす。
## 新曲を -60dB から上げていくと（1秒フェードだと 0.5秒地点でまだ -30dB）曲の入りが
## 聞こえないまま過ぎる＝スティンガーと同じ理由で、頭は素の音量で出す。
## fade_in_sec > 0 のときだけ無音から立ち上げる（前が鳴り止んでいて、素の音量だと唐突な場面）。
## stream が null なら現在の曲を落とすだけ。
func _fade_to(stream: AudioStream, fade_in_sec: float = 0.0, fade_out_sec: float = FADE_OUT_SEC) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()  # 前のフェードが生きたままだと音量の取り合いになる（会話の暗幕と同じ事情）
	var outgoing := _players[_active]
	if stream != null:
		_active = 1 - _active  # 裏を表にする（旧曲は鳴らしたままフェードアウトさせる）
		var incoming := _players[_active]
		incoming.stream = stream
		incoming.volume_db = SILENCE_DB if fade_in_sec > 0.0 else 0.0
		incoming.play()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(outgoing, "volume_db", SILENCE_DB, fade_out_sec)
	if stream != null and fade_in_sec > 0.0:
		_tween.tween_property(_players[_active], "volume_db", 0.0, fade_in_sec)
	_tween.chain().tween_callback(outgoing.stop)  # 消えてから止める（裏を空けて次の切替に備える）
