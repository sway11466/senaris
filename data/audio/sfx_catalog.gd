extends RefCounted
class_name SfxCatalog
## 発火点ID → 素材ID → 効果音ファイルの解決（規約 autowire）。
## data層＝純データ・純ロジック（音は鳴らさない）。詳細 → doc/audio/sfx.md
##
## 効果音は「素材（sfx_id）」と「発火点（event_id）」を別に管理し、対応表 BIND で結ぶ。
## 1:1 にならないため分けている＝確定音は多くの発火点で共用（多対1）、攻撃音は1発火点で多数（1対多）。
##
## 素材は assets/sfx/{sfx_id} を規約で解決する。ファイルが在れば鳴り、無ければ ""＝
## 呼び出し側は無音＋ログ1行（BgmCatalog と同型・ゲームは止めない）。音を置くだけで鳴り出す。

const SFX_ROOT := "res://assets/sfx"

## 素材の拡張子。.ogg（Ogg Vorbis）が本命だが、書き出したままの .wav も受ける。
## 先に見つかった方を使う＝ffmpeg を通す前でも音を確認できる（doc/audio/sfx.md データ形式）。
const EXTS := [".ogg", ".wav"]

## 発火点 → 素材の対応表。基本音（ui_*）は画面をまたいで共用する。
## 素材が未用意の発火点はここに載せない＝載っていない発火点は無音で進む。
## 増えて手に負えなくなったら data/audio/sfx_bind.csv へ出す（doc/audio/sfx.md）。
const BIND := {
	# --- メニュー（タイトル・冒険譚選択・ステージセレクト）---
	"menu_tier": "menu_slide",  # 難易度帯ボードを繰る。布が滑る音（map_capture と同じ収録）
	"menu_command": "ui_confirm",  # タイトルのメニュー項目を選ぶ
	"menu_campaign": "ui_confirm",
	"menu_stage": "ui_confirm",
	"menu_back": "ui_cancel",
	"menu_locked": "ui_denied",
	# --- マップ（開始・ターン・終了）---
	# 陣営の切り替わりはホルン3音＋ティンパニ。自軍は長三和音・敵軍は短三和音で、
	# 3音目の半音だけが違う＝同じ合図と分かったうえで、どちらの番かが音色で分かる。
	"map_turn_player": "map_turn_player",
	"map_turn_enemy": "map_turn_enemy",
	"map_turn_end": "ui_confirm",
	# --- マップ（会話）---
	"map_talk": "ui_hover",  # 文字送り。ホバーと同じ極短クリックを共用する
	# --- マップ（盤の操作）---
	"map_hover": "ui_hover",
	"map_select": "ui_confirm",
	"map_confirm": "ui_confirm",
	"map_cancel": "ui_cancel",
	"map_board": "map_board",  # 輸送への乗車・降車
	"map_capture": "map_capture",  # 占領成立。チューブラーベル＋旗の布（2層を重ねた唯一の素材）
	# 出撃は駒を「置く」＝歩く絵が無いので専用音を持たない。手札を1枚出すだけの操作で、
	# 盤の支配が動く占領とは重みが違う。ここを専用音にすると重み付けが崩れる。
	"map_deploy": "ui_confirm",
	# --- 戦闘演出 ---
	# 幕開けは依頼ボードを繰る音を共用する。どちらも「表示が切り替わった」という同じ出来事で、
	# セレクト画面と盤は同時に出ないので取り違えようがない。無音程なのでどの曲にも乗る。
	"cmb_open": "menu_slide",
}

## 移動タイプ → 移動音の素材（既定）。移動タイプは地形コストの都合で分かれているが、
## 音としては3系統に集約する（doc/audio/sfx.md 移動音）。未知値・fixed は ""＝無音。
## 駒ごとの例外は unit_skin.csv の map_move_sfx 列で上書きする（飛行の飛び方の違いはこちら）。
const MOVE_BIND := {
	"ground": "move_ground",
	"forest_walk": "move_ground",
	"bush_walk": "move_ground",
	"mountain_walk": "move_ground",
	"light_foot": "move_light_foot",
	"flight": "move_flight",
}

## 移動音の素材と、繰り返す最小間隔（秒）。0＝1マス踏むごと。
## 飛行を1マスごと（0.12秒間隔）に鳴らすと羽ばたきに聞こえず連続したノイズになるため、
## マス数ではなく時間で間引く。移動アニメは経路が長いほど1マスが縮む（MOVE_ANIM_MAX_SEC で
## 頭打ち）ので、マス数で持つと長い経路で間隔が詰まる。→ doc/audio/sfx.md 鳴らす間隔
## ここが移動音の素材IDの正本＝unit_skin.csv の map_move_sfx 列はこのキーだけを許す。
const MOVE_SFX := {
	"move_ground": 0.0,
	"move_light_foot": 0.0,
	"move_flight": 0.30,
	"move_float": 0.30,      # 魔法で浮く（ピクシー・ゴースト）＝羽ばたかない。全力移動で2回鳴る
	"move_propeller": 0.16,  # 飛空艇。飛行と同じ素材を、重なるまで詰めて連続音にする
}

## 発火点IDに割り当てられた素材ID。未登録なら ""。
static func sfx_of(event_id: String) -> String:
	return String(BIND.get(event_id, ""))

## 移動タイプの足音・羽ばたきの素材ID（既定）。未登録なら ""。
static func move_sfx_of(move_type: String) -> String:
	return String(MOVE_BIND.get(move_type, ""))

## 移動音を繰り返す最小間隔（秒）。0＝1マスごと。未登録の素材も 0 に倒す
## （鳴らない方向ではなく既定の鳴り方へ落とす）。
static func move_interval_of(sfx_id: String) -> float:
	return float(MOVE_SFX.get(sfx_id, 0.0))

## 素材IDのファイルパス。素材IDが空、またはファイルが未配置なら ""。
static func path_of(sfx_id: String) -> String:
	if sfx_id.is_empty():
		return ""
	for ext in EXTS:
		var p: String = "%s/%s%s" % [SFX_ROOT, sfx_id, ext]
		if ResourceLoader.exists(p):
			return p
	return ""

## 発火点IDから直接ファイルパスを引く（対応表→autowire を一度に）。未解決なら ""。
static func path_of_event(event_id: String) -> String:
	return path_of(sfx_of(event_id))

## 発火点に鳴らせる音が在るか。
static func exists(event_id: String) -> bool:
	return not path_of_event(event_id).is_empty()
