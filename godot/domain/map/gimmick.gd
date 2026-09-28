extends RefCounted
class_name Gimmick
## 盤の上の仕掛け1つ（純データ・Node非依存）。拠点と同じく地形とは別の層に置き、地形タイプは持たない
## ＝マスのルールは地図の地形のまま。種類ごとの状態の一覧と振る舞いは GimmickKinds が持つ。
## 詳細 → doc/gdd/gimmicks.md

var id: String            ## ステージ内で一意の名前（勝敗条件とセーブがこれで指す）
var kind: String          ## 種類（GimmickKinds.KINDS のキー）
var hex: Vector2i         ## 置いたマス（axial）
var state: String         ## 今の状態（種類ごとに決まった値のどれか）
var params := {}          ## 種類ごとの固有の要素（読み込み済みの値。例 production_switch の "base": Vector2i）

func _init(p_id: String, p_kind: String, p_hex: Vector2i, p_state: String, p_params: Dictionary = {}) -> void:
	id = p_id
	kind = p_kind
	hex = p_hex
	state = p_state
	params = p_params
