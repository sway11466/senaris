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

static var _instance: SfxPlayer = null

var _players: Array[AudioStreamPlayer] = []
var _next := 0                  ## 次に使うプレイヤー（古いものから使い回す）
var _streams := {}              ## sfx_id -> AudioStream（読み込みキャッシュ）
var _missing := {}              ## 未配置ログを1回に留める（毎フレーム出さない）
var _last_played := {}          ## sfx_id -> 直近の再生時刻（間引き判定）

func _ready() -> void:
	for _i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)
	_instance = self

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

## どこからでも鳴らす入口。main が SfxPlayer を組む前・組まない場面では黙って何もしない。
static func play_event(event_id: String) -> void:
	if _instance != null:
		_instance.play(event_id)

## 発火点IDの音を鳴らす。対応表に無い／ファイルが未配置なら無音で進む。
func play(event_id: String) -> void:
	var sfx_id := SfxCatalog.sfx_of(event_id)
	if sfx_id.is_empty():
		return  # 対応表に無い発火点＝まだ音を割り当てていない。ログも出さない（設計どおりの無音）
	var now := Time.get_ticks_msec() / 1000.0
	var last: float = _last_played.get(sfx_id, -1.0)
	if last >= 0.0 and now - last < REPEAT_GUARD_SEC:
		return  # 同じ音が連射された＝間引く
	var stream := _stream_of(sfx_id)
	if stream == null:
		return
	_last_played[sfx_id] = now
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.play()

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
