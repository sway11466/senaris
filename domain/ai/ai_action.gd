extends RefCounted
class_name AiAction
## AI が「次に行う1手」を表す純データ。
## domain は application のコマンドに依存できないため、AIはコマンドではなくこれを返し、
## application(MatchController) が MoveCommand/AttackCommand に翻訳して実行する。

enum Kind { MOVE, ATTACK }

var kind: Kind
var unit_id: int
var to: Vector2i    ## MOVE のとき有効
var target_id: int  ## ATTACK のとき有効

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
