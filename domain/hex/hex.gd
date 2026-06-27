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

# --- レイアウト（flat-top）。描画に渡す純粋な座標変換。size = ヘックスの中心〜頂点 ---

const SQRT3 := 1.7320508075688772

## axial 座標 → ピクセル中心座標。
static func to_pixel(hex: Vector2i, size: float) -> Vector2:
	var x := size * 1.5 * hex.x
	var y := size * SQRT3 * (hex.y + hex.x / 2.0)
	return Vector2(x, y)

## ピクセル座標 → 最も近い axial 座標。
static func from_pixel(p: Vector2, size: float) -> Vector2i:
	var qf := (2.0 / 3.0 * p.x) / size
	var rf := (-1.0 / 3.0 * p.x + SQRT3 / 3.0 * p.y) / size
	return axial_round(qf, rf)

## 小数の axial を最も近い整数 axial へ丸める（cube 丸め）。
static func axial_round(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var q := roundi(qf)
	var r := roundi(rf)
	var s := roundi(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(q, r)

# --- 矩形マップ用の offset(col,row) ↔ axial 変換（flat-top / odd-q） ---

## offset(col, row) → axial。矩形フィールドを敷くのに使う。
static func offset_to_axial(col: int, row: int) -> Vector2i:
	var q := col
	var r := row - int((col - (col & 1)) / 2)
	return Vector2i(q, r)

## axial → offset(col, row)。
static func axial_to_offset(hex: Vector2i) -> Vector2i:
	var col := hex.x
	var row := hex.y + int((hex.x - (hex.x & 1)) / 2)
	return Vector2i(col, row)

# --- 探索 ---

## start から max_steps 歩で到達できるヘックス一覧（start 含む）。
## passable: Callable(Vector2i) -> bool。各ステップ一律コスト1の BFS。
## 純ロジック: 通行判定は呼び出し側から関数で渡す（マップ/地形に非依存）。
static func flood_reach(start: Vector2i, max_steps: int, passable: Callable) -> Array[Vector2i]:
	var dist := {start: 0}
	var frontier: Array[Vector2i] = [start]
	var head := 0
	while head < frontier.size():
		var current: Vector2i = frontier[head]
		head += 1
		var d: int = dist[current]
		if d >= max_steps:
			continue
		for n in neighbors(current):
			if dist.has(n):
				continue
			if not passable.call(n):
				continue
			dist[n] = d + 1
			frontier.append(n)
	var result: Array[Vector2i] = []
	for k in dist:
		result.append(k)
	return result
