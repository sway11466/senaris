extends RefCounted
class_name Sight
## 視線（索敵の遮蔽・減衰）の規則計算。state を引数に取る static ヘルパー。
## 詳細 → doc/gdd/movement.md（視線）, doc/gdd/ai.md（起動）
##
## 視線コスト表そのものは BattleState が持つ（`set_sight_cost` で注入・`sight_cost_at` で引く）。
## ここにあるのは表を読んで判定する規則だけ＝状態を持たない。位置ごとの結果の記憶も BattleState 側。

## from から budget 以内で視認できる盤内ヘックスの集合（from 含む）。起動判定と索敵範囲の可視化の両方がこれを引く。
## 範囲内（盤内・距離 budget 以内）の各マスへ ±両側にずらしたヘックス直線を引き、線上で累積視線コストが budget 以内の
## マスをすべて見えるとする（from を除く）。奥まで通った線の途中のマスも見える＝集合は必ず from からひと続きになる。
## マスごとに自分宛ての線だけで判定すると、奥のマスへの線は隙間を抜けるのに、手前のマスへの線（角度が少し違う）は
## 壁に当たる、という飛び地ができる。壁（コスト x）は累積が必ず budget を超えるので、その先は線ごと切れる＝影は残る。
## 全地形コスト1なら「累積＝ヘックス距離」＝純距離の索敵に一致。
static func visible_hexes(state: BattleState, from: Vector2i, budget: int) -> Dictionary:
	var out := { from: true }
	for h in _candidates(state, from, budget):
		if not state.in_field(h):
			continue
		_mark_line(state, from, h, budget, 1.0, out)
		_mark_line(state, from, h, budget, -1.0, out)
	return out

## from から to へ視線が通り、累積視線コストが budget 以内か＝to が visible_hexes に入っているか。
## 呼ぶたびに集合を作る（規則の定義そのもの）。ゲーム中は BattleState.sight_reaches が位置ごとの記憶を引く。
static func reaches(state: BattleState, from: Vector2i, to: Vector2i, budget: int) -> bool:
	return visible_hexes(state, from, budget).has(to)

## 走査する候補マス。予算の輪が盤より大きくなるなら盤の全マスを回す。
## sight `*`（上限なし）の予算は盤より桁違いに大きく、輪をそのまま回すと盤外を億単位で
## 走査して固まる。盤内しか残さないので結果は変わらず、狭い索敵では輪のほうが安いので残す。
static func _candidates(state: BattleState, from: Vector2i, budget: int) -> Array:
	if budget >= 0 and 3 * budget * (budget + 1) + 1 <= state.cols * state.rows:
		return Hex.within_range(from, budget)
	var out: Array = []
	for col in state.cols:
		for row in state.rows:
			out.append(Hex.offset_to_axial(col, row))
	return out

## from→to の直線（bias でずらした1本）をたどり、累積が budget 以内のマスを out に足す。超えた所で線ごと打ち切る。
## 壁の角をかすめる線は1本だと角を拾って穴が開くので、呼ぶ側が ±両側の2本を試す（真後ろの壁は両側とも貫く＝遮断が残る）。
static func _mark_line(state: BattleState, from: Vector2i, to: Vector2i, budget: int, bias: float, out: Dictionary) -> void:
	var acc := 0
	var path := Hex.line(from, to, bias)
	for i in range(1, path.size()):
		acc += state.sight_cost_at(path[i])
		if acc > budget:
			return
		if state.in_field(path[i]):
			out[path[i]] = true
