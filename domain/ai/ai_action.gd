extends RefCounted
class_name AiAction
## AI が「次に行う1手」を表す純データ。
## domain は application のコマンドに依存できないため、AIはコマンドではなくこれを返し、
## application(MatchController) が MoveCommand/AttackCommand に翻訳して実行する。

enum Kind { MOVE, ATTACK, DEPLOY }

var kind: Kind
var unit_id: int
var to: Vector2i         ## MOVE / DEPLOY のとき有効（DEPLOY は出撃先hex）
var target_id: int       ## ATTACK のとき有効
var base_hex: Vector2i   ## DEPLOY のとき有効（出撃元の拠点hex）
var garrison_index: int  ## DEPLOY のとき有効（出す控えの index）

static func move_to(unit_id: int, to: Vector2i) -> AiAction:
	var a := AiAction.new()
	a.kind = Kind.MOVE
	a.unit_id = unit_id
	a.to = to
	return a

static func attack(unit_id: int, target_id: int) -> AiAction:
	var a := AiAction.new()
	a.kind = Kind.ATTACK
	a.unit_id = unit_id
	a.target_id = target_id
	return a

## 拠点 base_hex の garrison_index を to へ出撃させる1手（詳細 → doc/gdd/ai.md §7 拠点出撃）。
static func deploy(base_hex: Vector2i, garrison_index: int, to: Vector2i) -> AiAction:
	var a := AiAction.new()
	a.kind = Kind.DEPLOY
	a.base_hex = base_hex
	a.garrison_index = garrison_index
	a.to = to
	return a
