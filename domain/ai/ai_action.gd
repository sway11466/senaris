extends RefCounted
class_name AiAction
## AI が「次に行う1手」を表す純データ。
## domain は application のコマンドに依存できないため、AIはコマンドではなくこれを返し、
## application(MatchController) が MoveCommand/AttackCommand に翻訳して実行する。

enum Kind { MOVE, ATTACK, DEPLOY, SKILL, UNLOAD }

var kind: Kind
var unit_id: int         ## 行動する駒。UNLOAD では降ろす側＝輸送の id
var to: Vector2i         ## MOVE / DEPLOY / SKILL / UNLOAD のとき有効（DEPLOY は出撃先hex・SKILL は対象hex・UNLOAD は降車先hex）
var target_id: int       ## ATTACK のとき有効
var base_hex: Vector2i   ## DEPLOY のとき有効（出撃元の拠点hex）
var garrison_index: int  ## DEPLOY のとき有効（出す控えの index）
var passenger_index: int ## UNLOAD のとき有効（降ろす搭乗駒の index）
var option: Dictionary   ## SKILL のとき有効（Formation.available_for の1要素）

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

## unit_id が option のユニットスキルを target へ放つ1手（詳細 → doc/gdd/ai.md 特性詳細のスキルの行）。
## option は Formation.available_for が返す辞書そのまま＝application が FormationCommand へ翻訳する。
static func skill(unit_id: int, option: Dictionary, target: Vector2i) -> AiAction:
	var a := AiAction.new()
	a.kind = Kind.SKILL
	a.unit_id = unit_id
	a.option = option
	a.to = target
	return a

## 輸送 transport_id の搭乗リスト index を to へ降ろす1手（詳細 → doc/gdd/ai.md 輸送ユニット）。
## 降車は乗員の手番＝輸送自身が動き終えていても打てる。
static func unload(transport_id: int, index: int, to: Vector2i) -> AiAction:
	var a := AiAction.new()
	a.kind = Kind.UNLOAD
	a.unit_id = transport_id
	a.passenger_index = index
	a.to = to
	return a

## 拠点 base_hex の garrison_index を to へ出撃させる1手（詳細 → doc/gdd/ai.md 拠点出撃）。
static func deploy(base_hex: Vector2i, garrison_index: int, to: Vector2i) -> AiAction:
	var a := AiAction.new()
	a.kind = Kind.DEPLOY
	a.base_hex = base_hex
	a.garrison_index = garrison_index
	a.to = to
	return a
