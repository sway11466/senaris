extends AiTrait
class_name TraitCharge
## charge（突撃）の行動ルール。常時起動で前へ出る。ambush（待ち伏せ）は起動後の行が同じなので
## これを継承し、withdraw（撤退）は退く行を足してから同じ表を当てる。詳細 → doc/gdd/ai.md charge
## 1 占領兵で移動範囲に自陣営以外の拠点 → 盤上距離が最小の拠点へ移動して占領
## 2 スキル射程内に stack 条件を満たす対象 → 盤上距離が最小の対象にスキル
## 3 間接攻撃できる駒で、移動範囲のどこかから撃てる敵 → 空敵を優先し、盤上距離が最小のその敵へ最大間合い
## 4 攻撃射程内に空敵 → 反撃されない敵を優先し、その中で盤上距離が最小の敵を攻撃
## 5 攻撃射程内に敵 → 反撃されない敵を優先し、その中で盤上距離が最小の敵を攻撃
## 6 移動範囲のどこかから攻撃できる空敵 → 移動距離が最小のその空敵へ最大前進
## 7 移動距離が測れる敵 → 移動距離が最小の敵へ最大前進
## 8 地形距離が測れる敵 → 地形距離が最小の敵へ見込前進
## 9 盤上に攻撃できる敵 → 盤上距離が最小の敵へ直線寄せ

## 撃つ行で仕留められる敵を先に見るか。突撃は見ない（盲目的に近い敵を殴る）、撤退は見る
## ＝withdraw の 6〜9 はこの2行をさらに仕留められる敵で分けたもの（doc/gdd/ai.md withdraw）。
var prefer_kill := false

func id() -> String:
	return "charge"

func action(state: BattleState, u: Unit) -> AiAction:
	var row := rows.capture_row(state, u)
	if row != null:
		return row
	row = rows.skill_row(state, u, AiPick.PICK_NEAR)
	if row != null:
		return row
	var air := pick.air_prey(state, u)
	row = rows.standoff_row(state, u, null, air)  # 3 空敵を優先（撃てる空敵が居なければ全体から）
	if row == null:
		row = rows.standoff_row(state, u)
	if row != null:
		return row
	var in_range := rows.attack_targets(state, u)
	if not in_range.is_empty():
		# 4・5 空敵の行 → （撤退だけ）仕留められる敵を優先 → 反撃されない敵を優先 → 盤上距離が最小
		var ids := pick.air_first(air, in_range)
		if prefer_kill:
			ids = pick.killable_first(state, u, ids)
		return AiAction.attack(u.handle, pick.safest_id(state, u, ids))
	return rows.advance_to_nearest_enemy(state, u, true)
