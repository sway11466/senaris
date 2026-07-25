extends Node
class_name BgmPlayer
## BGM の再生（AudioStreamPlayer×2 のクロスフェード）。presentation＝トラックIDを受けて鳴らすだけ。
## 曲の選択ルール（場面→曲）は application/bgm_director.gd に置く。詳細 → doc/audio/bgm.md
##
## 曲が未配置なら無音＋ログ1行で進む（ゲームは止めない）。.ogg を置けば次の切替から鳴り出す。
## ループは Godot のインポート設定（.import の loop）で持つ＝ここでは扱わない。

const BUS := "Music"       ## 効果音と別に絞れるようにする（default_bus_layout.tres）
const FADE_SEC := 1.0      ## クロスフェード時間。まずは単純な2曲クロスフェードで十分（doc/audio/bgm.md）
const DUCK_SEC := 0.3      ## スティンガー時に現曲を素早く下げる時間（ファンファーレの頭に被せない）
const SILENCE_DB := -60.0  ## 実質無音。0.0 が通常音量

var _players: Array[AudioStreamPlayer] = []
var _active := 0        ## いま表で鳴っているプレイヤーの index
var _current_track := ""
var _tween: Tween = null

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
func play(track_id: String) -> void:
	if track_id == _current_track:
		return
	_current_track = track_id
	_fade_to(_load(track_id))

## スティンガー（勝利/敗北など loop=false の一発曲）を鳴らす。現在のステージ曲は素早く下げ、
## スティンガーはフェードインせず頭から出す＝ファンファーレの立ち上がりを殺さない。
## 鳴り終えても曲は戻さない（次のステージ開始 or セレクトで play() が張り替える）。
func play_stinger(track_id: String) -> void:
	_current_track = track_id
	var stream := _load(track_id)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var outgoing := _players[_active]
	if stream != null:
		_active = 1 - _active  # 裏を表にする（現曲は素早く下げるだけ＝鳴らしたまま）
		var incoming := _players[_active]
		incoming.stream = stream
		incoming.volume_db = 0.0  # フェードインしない（頭のアタックを出す）
		incoming.play()
	_tween = create_tween()
	_tween.tween_property(outgoing, "volume_db", SILENCE_DB, DUCK_SEC)
	_tween.tween_callback(outgoing.stop)

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

## いま鳴っている（鳴っているはずの）トラックID。未配置で無音のときも要求されたIDを返す。
func current_track() -> String:
	return _current_track

## 表と裏を入れ替えてクロスフェードする。stream が null なら現在の曲を落とすだけ。
func _fade_to(stream: AudioStream) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()  # 前のフェードが生きたままだと音量の取り合いになる（会話の暗幕と同じ事情）
	var outgoing := _players[_active]
	if stream != null:
		_active = 1 - _active  # 裏を表にする（旧曲は鳴らしたままフェードアウトさせる）
		var incoming := _players[_active]
		incoming.stream = stream
		incoming.volume_db = SILENCE_DB
		incoming.play()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(outgoing, "volume_db", SILENCE_DB, FADE_SEC)
	if stream != null:
		_tween.tween_property(_players[_active], "volume_db", 0.0, FADE_SEC)
	_tween.chain().tween_callback(outgoing.stop)  # 消えてから止める（裏を空けて次の切替に備える）
