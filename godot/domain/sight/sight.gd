extends RefCounted
class_name Sight
## 視線（索敵の遮蔽・減衰）の規則計算。state を引数に取る static ヘルパー。
## 詳細 → doc/gdd/movement.md（視線）, doc/gdd/ai.md（起動）
##
## 視線コスト表そのものは BattleState が持つ（`set_sight_cost` で注入・`sight_cost_at` で引く）。
## ここにあるのは表を読んで判定する規則だけ＝状態を持たない。

## from から to へ視線が通り、累積視線コストが budget 以内か（起動 sight の判定に使う）。
## 壁の角をかすめる線は1本だと角を拾って穴が開くので、±両側にずらした2本を試し、安い方で判定する。
## 真後ろの壁は両側とも貫く＝遮断が残る／角かすめは片側が通る＝穴が消える。
## 各マス（from を除き to を含む）の視線コストを積算。全地形コスト1なら「累積＝ヘックス距離」＝純距離の索敵に一致。
static func reaches(state: BattleState, from: Vector2i, to: Vector2i, budget: int) -> bool:
	return mini(_line_cost(state, from, to, 1.0), _line_cost(state, from, to, -1.0)) <= budget

## from から budget 以内で視認できる盤内ヘックスの集合（from 含む）。索敵範囲の可視化に使う。
## 全コスト≥1 前提で距離 budget 以内を候補にし、視線が通るものだけ残す（壁は影を作る・森は範囲が縮む）。
static func visible_hexes(state: BattleState, from: Vector2i, budget: int) -> Dictionary:
	var out := { from: true }
	for h in _candidates(state, from, budget):
		if state.in_field(h) and reaches(state, from, h, budget):
			out[h] = true
	return out

## 走査する候補マス。予算の輪が盤より大きくなるなら盤の全マスを回す。
## sight `*`（上限なし）の予算は盤より桁違いに大きく、輪をそのまま回すと盤外を億単位で
## 走査して固まる。盤内しか残さないので結果は変わらず、狭い索敵では輪のほうが安いので残す。
## この関数は盤を描き直すたびに呼ばれる（検知域の輪郭）＝走査量がそのまま操作の重さになる。
static func _candidates(state: BattleState, from: Vector2i, budget: int) -> Array:
	if budget >= 0 and 3 * budget * (budget + 1) + 1 <= state.cols * state.rows:
		return Hex.within_range(from, budget)
	var out: Array = []
	for col in state.cols:
		for row in state.rows:
			out.append(Hex.offset_to_axial(col, row))
	return out

## from→to の直線（bias でずらした1本）の視線コスト積算（from を除き to を含む）。
static func _line_cost(state: BattleState, from: Vector2i, to: Vector2i, bias: float) -> int:
	var acc := 0
	var path := Hex.line(from, to, bias)
	for i in range(1, path.size()):
		acc += state.sight_cost_at(path[i])
	return acc
