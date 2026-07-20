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
	"menu_campaign": "ui_confirm",
	"menu_stage": "ui_confirm",
	"menu_back": "ui_cancel",
	"menu_locked": "ui_denied",
	# --- マップ（盤の操作）---
	"map_select": "ui_confirm",
	"map_confirm": "ui_confirm",
	"map_cancel": "ui_cancel",
	"map_denied": "ui_denied",
}

## 発火点IDに割り当てられた素材ID。未登録なら ""。
static func sfx_of(event_id: String) -> String:
	return String(BIND.get(event_id, ""))

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
