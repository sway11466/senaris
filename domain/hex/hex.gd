extends RefCounted
class_name Hex
## ヘックス座標ユーティリティ。axial 座標を Vector2i(q, r) で表す。
## 純ロジック・ノード非依存・すべて static。盤面/移動/射程/包囲の土台。
## 参考: redblobgames "Hexagonal Grids"（axial 系）。

## 近傍6方向（axial）。index 0..5 で時計回り相当。
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## 方向ベクトルを返す（dir は 0..5、範囲外は wrap）。
static func direction(dir: int) -> Vector2i:
	return DIRECTIONS[posmod(dir, 6)]

## hex の dir 方向の隣を返す。
static func neighbor(hex: Vector2i, dir: int) -> Vector2i:
	return hex + direction(dir)

## hex の6近傍を返す。
static func neighbors(hex: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		result.append(hex + d)
	return result

## a, b 間のヘックス距離。
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((abs(dq) + abs(dr) + abs(dq + dr)) / 2.0)

## center から距離 n 以内の全ヘックス（自身を含む）。
static func within_range(center: Vector2i, n: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dq in range(-n, n + 1):
		var lo := maxi(-n, -dq - n)
		var hi := mini(n, -dq + n)
		for dr in range(lo, hi + 1):
			result.append(center + Vector2i(dq, dr))
	return result

## center を中心とする半径 radius のリング（その距離ちょうどの環）。
static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if radius <= 0:
		result.append(center)
		return result
	var hex := center + direction(4) * radius
	for i in 6:
		for _j in radius:
			result.append(hex)
			hex = neighbor(hex, i)
	return result
