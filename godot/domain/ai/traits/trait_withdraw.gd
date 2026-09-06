extends TraitCharge
class_name TraitWithdraw
## withdraw（撤退）の行動ルール。突撃と同じく前へ出るが、削られたら拠点へ退いて回復し、また出てくる。
## 詳細 → doc/gdd/ai.md withdraw
## 1 占領兵で、移動範囲に自陣営以外の拠点 → 占領
## 2 損耗 ≧ retreat で、自陣営の拠点hexにいる → 拠点に入る
## 3 損耗 ≧ retreat で、移動距離が測れる自陣営拠点 → 移動距離が最小の自陣営拠点へ最大前進
## 4〜12 突撃と同じ（TraitCharge）。撃つ行 6〜9 だけ仕留められる敵を先に見る（prefer_kill）＝
## 空敵 → 仕留められる敵 → 反撃されない敵 → 盤上距離が最小。倒せば次のターン以降その駒から
## 撃たれない＝退いて回復するまでに受ける被害が減るので、反撃1回ぶんより得になる。
##
## 2・3 を攻撃より上に置くのは、下に置くと退けないため。攻撃した駒はその時点で手番が終わるので、
## 退く行が攻撃より下だと、射程内に敵がいるかぎり殴り続けて拠点へ戻らない。上に置けば 3 で下がった
## あとに表を上から当て直し、移動を伴う行は飛ばされて攻撃の行が拾う＝退きながら撃ち返す。
##
## 帰り道は最大前進（移動距離）で敵ZOCを避けない（flee の回り込みとの差）。ZOCマスに入れば移動が
## 終わるので、プレイヤーはZOCの帯で足を止められる。自陣営の拠点が無い・道が塞がれて測れない・
## 縮むマスが無いときは 2・3 が通らず突撃として戦う＝退けないなら諦めて殴る。

func _init() -> void:
	prefer_kill = true

func id() -> String:
	return "withdraw"

func action(state: BattleState, u: Unit) -> AiAction:
	var row := rows.capture_row(state, u)
	if row != null:
		return row
	if AiPick.damage_percent(u) >= params.retreat_percent_of(state, u):
		if state.can_enter_base(u.id):
			return AiAction.enter_base(u.id)
		if rows.can_advance(state, u):
			row = rows.move_to_base(state, u, pick.friendly_base_hexes(state, u))
			if row != null:
				return row
	return super.action(state, u)
