extends RefCounted
class_name Terrain
## 地形タイプと攻防係数（純データ・ノード非依存）。詳細 → doc/gdd/combat.md, doc/gdd/map.md
##
## 各地形は 地形(攻) と 地形(防) を攻防別に持つ（乗算・1.0＝補正なし）。
## ユニットが立っているヘックスの地形が、その攻撃力・防御力に乗る。
## 今は 平地（補正なし）と 台地（攻防+15%）の2種。種類は順次追加する。

enum { PLAINS, PLATEAU }  ## 平地 / 台地

## terrain_id -> [地形(攻), 地形(防)]
const FACTORS := {
	PLAINS:  [1.0, 1.0],    ## 平地: 補正なし（基準）
	PLATEAU: [1.15, 1.15],  ## 台地: 攻守ともに+15%（有利な高所）
}

## terrain_id の地形(攻)係数。
static func attack_factor(terrain_id: int) -> float:
	return float(FACTORS[terrain_id][0])

## terrain_id の地形(防)係数。
static func defense_factor(terrain_id: int) -> float:
	return float(FACTORS[terrain_id][1])
