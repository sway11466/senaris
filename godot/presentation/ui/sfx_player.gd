extends Node
class_name SfxPlayer
## 効果音の再生（AudioStreamPlayer のプール）。presentation＝発火点IDを受けて鳴らすだけ。
## 発火点→素材の対応は data/audio/sfx_catalog.gd。詳細 → doc/audio/sfx.md
##
## 音が未配置なら無音＋ログ1行で進む（ゲームは止めない）。音を置けば次の発火から鳴り出す。
## BGM（bgm_player.gd）と違い効果音は重なるので、プールを持って同時発音を許す。
##
## 盤・セレクトの各所から細かく鳴らすため、main が持つ実体を静的に参照できるようにしている
## （play_event が唯一の入口）。参照を各画面へ配って回らないための割り切りで、presentation 内に閉じる。

const BUS := "SFX"          ## 曲と別に絞れるようにする（default_bus_layout.tres）
const POOL_SIZE := 8        ## 同時発音数。足りなければ最も古い再生を奪う
const REPEAT_GUARD_SEC := 0.05  ## 同じ音の連続をこの間隔で間引く（ホバー・文字送りの高頻度対策）
const LOOP_POOL_SIZE := 4       ## 続く型の移動音（ループ）の同時発音数。一度に動く駒は1体なので余裕を持って
const FADE_FLOOR_DB := -40.0    ## フェードアウトの終点。ここまで下げてから止める

static var _instance: SfxPlayer = null

var _players: Array[AudioStreamPlayer] = []
var _next := 0                  ## 次に使うプレイヤー（古いものから使い回す）
var _streams := {}              ## sfx_id -> AudioStream（読み込みキャッシュ）
var _missing := {}              ## 未配置ログを1回に留める（毎フレーム出さない）
var _last_played := {}          ## sfx_id -> 直近の再生時刻（間引き判定）
var _loop_players: Array[AudioStreamPlayer] = []  ## 続く型の移動音用（ループするので一発音のプールと分ける）
var _loop_next := 0
var _loop_streams := {}         ## sfx_id -> ループ用に複製した AudioStream（元のキャッシュは loop=false のまま）
var _fades := {}                ## AudioStreamPlayer -> 進行中のフェードアウト Tween

func _ready() -> void:
	for _i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)
	for _i in LOOP_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_loop_players.append(p)
	_instance = self

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

## どこからでも鳴らす入口。main が SfxPlayer を組む前・組まない場面では黙って何もしない。
static func play_event(event_id: String) -> void:
	if _instance != null:
		_instance.play(event_id)

## 素材IDを直に指定して鳴らす入口。対応表を通さない発火点のためにある。
## 攻撃エフェクト（cmb_attack）は素材がエフェクトIDで決まり、BIND に並べると
## エフェクトを足すたびに表が伸びる＝規約解決（assets/sfx/{effect_id}.ogg）に任せる。
static func play_sfx(sfx_id: String) -> AudioStreamPlayer:
	if _instance != null:
		return _instance.play_id(sfx_id)
	return null

## 続く型の移動音（doc/audio/sfx.md 素材の型）。ループ再生を始め、鳴らしている口を返す。
## 止めるのは stop_move。未配置・組まれていない場面では null。
static func play_move_loop(sfx_id: String) -> AudioStreamPlayer:
	if _instance != null:
		return _instance.play_loop(sfx_id)
	return null

## 移動音を到着で止める（続く型・周期の型）。fade_sec かけて下げてから止め、0 なら即止める。
## 一発音のプールは使い回されるので、その口がまだ同じ素材を鳴らしているときだけ止める。
static func stop_move(player: AudioStreamPlayer, sfx_id: String, fade_sec: float) -> void:
	if _instance != null:
		_instance.fade_stop(player, sfx_id, fade_sec)

## 発火点IDの音を鳴らす。対応表に無い／ファイルが未配置なら無音で進む。
func play(event_id: String) -> void:
	var sfx_id := SfxCatalog.sfx_of(event_id)
	if sfx_id.is_empty():
		return  # 対応表に無い発火点＝まだ音を割り当てていない。ログも出さない（設計どおりの無音）
	play_id(sfx_id)

## 素材IDの音を鳴らす。未配置なら無音＋ログ1行で進む。鳴らした口を返す（間引き・未配置は null）。
func play_id(sfx_id: String) -> AudioStreamPlayer:
	if sfx_id.is_empty():
		return null
	var now := Time.get_ticks_msec() / 1000.0
	var last: float = _last_played.get(sfx_id, -1.0)
	if last >= 0.0 and now - last < REPEAT_GUARD_SEC:
		return null  # 同じ音が連射された＝間引く
	var stream := _stream_of(sfx_id)
	if stream == null:
		return null
	_last_played[sfx_id] = now
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	_cancel_fade(p)
	p.stream = stream
	p.play()
	return p

## 続く型の移動音のループ再生。素材を複製して loop を立てる＝一発音のキャッシュは触らない。
func play_loop(sfx_id: String) -> AudioStreamPlayer:
	if sfx_id.is_empty():
		return null
	var stream := _loop_stream_of(sfx_id)
	if stream == null:
		return null
	var p := _loop_players[_loop_next]
	_loop_next = (_loop_next + 1) % LOOP_POOL_SIZE
	_cancel_fade(p)
	p.stream = stream
	p.play()
	return p

## フェードアウトして止める。player がもう別の素材を鳴らしていれば何もしない。
func fade_stop(p: AudioStreamPlayer, sfx_id: String, fade_sec: float) -> void:
	if p == null or not p.playing:
		return
	var expected: Variant = _loop_streams.get(sfx_id, null)
	if expected == null:
		expected = _streams.get(sfx_id, null)
	if p.stream != expected:
		return  # 口が使い回されて別の音になっている＝その音を止めてはいけない
	_cancel_fade(p)
	if fade_sec <= 0.0:
		p.stop()
		return
	var t := create_tween()
	t.tween_property(p, "volume_db", FADE_FLOOR_DB, fade_sec)
	t.tween_callback(func() -> void:
		p.stop()
		p.volume_db = 0.0
		_fades.erase(p))
	_fades[p] = t

## 進行中のフェードを畳んで音量を戻す（口を次の音に使い回す前に呼ぶ）。
func _cancel_fade(p: AudioStreamPlayer) -> void:
	var t: Variant = _fades.get(p, null)
	if t is Tween and (t as Tween).is_valid():
		(t as Tween).kill()
	_fades.erase(p)
	p.volume_db = 0.0

## ループ用の AudioStream（複製して loop=true）。未配置は _stream_of と同じく null＋ログ1行。
func _loop_stream_of(sfx_id: String) -> AudioStream:
	if _loop_streams.has(sfx_id):
		return _loop_streams[sfx_id]
	var base := _stream_of(sfx_id)
	if base == null:
		return null
	var stream := base.duplicate() as AudioStream
	if "loop" in stream:
		stream.set("loop", true)
	_loop_streams[sfx_id] = stream
	return stream

## 素材IDの AudioStream（キャッシュ付き）。未配置・読めない場合は null＋ログ1行。
func _stream_of(sfx_id: String) -> AudioStream:
	if _streams.has(sfx_id):
		return _streams[sfx_id]
	var path := SfxCatalog.path_of(sfx_id)
	if path.is_empty():
		if not _missing.has(sfx_id):
			_missing[sfx_id] = true
			print("SfxPlayer: 音が未配置＝無音で進行: %s（%s/%s.ogg）" % [sfx_id, SfxCatalog.SFX_ROOT, sfx_id])
		return null
	var stream := ResourceLoader.load(path) as AudioStream
	if stream == null and not _missing.has(sfx_id):
		_missing[sfx_id] = true
		print("SfxPlayer: 音を読めない＝無音で進行: %s" % path)
	_streams[sfx_id] = stream
	return stream
