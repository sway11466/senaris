extends RefCounted
class_name RankEvaluator
## 評価ランクの判定（純ロジック）。仕様 → doc/gdd/rank.md
## ターン消費率と生存率それぞれで S/A/B を判定し、低い方が最終ランク。

const RANK_S := "S"
const RANK_A := "A"
const RANK_B := "B"

## ランクの強さ順（小さいほど上位）。比較・ベスト判定に使う。
const _ORDER := { "S": 0, "A": 1, "B": 2 }

## 評価する。rank_data はステージ JSON の "rank" 辞書。
## 無ければ（空辞書）ランクなし＝空文字を返す。
static func evaluate(turn_number: int, alive_allies: int, start_allies: int, rank_data: Dictionary) -> String:
	if rank_data.is_empty():
		return ""
	var turn_rank := _turn_rank(turn_number, rank_data)
	var survival_rank := _survival_rank(alive_allies, start_allies, rank_data)
	return worse(turn_rank, survival_rank)

## 2つのランクのうち低い方を返す。
static func worse(a: String, b: String) -> String:
	return a if _ORDER.get(a, 99) >= _ORDER.get(b, 99) else b

## a は b より上位か（ベスト更新の判定に使う）。
static func is_better(a: String, b: String) -> bool:
	return _ORDER.get(a, 99) < _ORDER.get(b, 99)

static func _turn_rank(turn_number: int, rank_data: Dictionary) -> String:
	var turn_s: int = int(rank_data.get("turn_s", 0))
	var turn_a: int = int(rank_data.get("turn_a", 0))
	if turn_s > 0 and turn_number < turn_s:
		return RANK_S
	if turn_a > 0 and turn_number < turn_a:
		return RANK_A
	return RANK_B

static func _survival_rank(alive: int, start: int, rank_data: Dictionary) -> String:
	if start <= 0:
		return RANK_B
	var survival_s: int = int(rank_data.get("survival_s", 0))
	var survival_a: int = int(rank_data.get("survival_a", 0))
	if survival_s > 0 and alive >= survival_s:
		return RANK_S
	if survival_a > 0 and alive >= survival_a:
		return RANK_A
	return RANK_B
