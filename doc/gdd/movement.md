# 移動システム

ユニットの移動範囲（reachable）を、移動タイプ×地形の進入コストで決める。

> 関連: 戦闘解決は [combat.md](combat.md)／地形は [map.md](map.md)・[combat.md](combat.md)の地形効果／ユニットは [units.md](units.md)。

---

## 設計

### 移動タイプ＝完全表（差分なし）

- 移動タイプは **「地形→進入コスト」の完全な表**。各移動タイプが全地形のコストを明示的に持つ（差分上書きはしない＝定義時の一覧性を優先）。
- **1ユニット＝1移動タイプ**（`UnitType.move_type` → `Unit.move_type`）。エルフのような特殊は、専用の完全表（例 `forest_walk`）を1つ用意して参照する（「徒歩＋森だけ特殊」を1枚の表に書ききる）。
- **`x`＝進入不可**。表に無い地形は既定コスト1（表が空＝全地形1＝従来の一律移動と等価）。

### コスト計算

- `reachable` はダイクストラ（`Hex.flood_reach_cost`）。起点から各ヘックスへの**最短コストが移動力以内**なら到達可能。
- 進入コスト ＝ そのヘックスの地形に対する移動タイプのコスト。盤外・他ユニット占有は進入不可。
- 実装: `data/movement/movement.gd`（`Movement`）／`domain/battle_state.gd`（`reachable`/`_enter_cost`）／`domain/hex/hex.gd`（`flood_reach_cost`）。

### データ

- **配置は独立フォルダ `data/movement/`**。移動コストは「移動タイプ（ユニット属性）×地形（マップ属性）→コスト」の関係（行列）で、units にも terrain にも属さない独立概念のため。
- 正本 `data/movement/movement.csv`（行=移動タイプ、列=地形コスト、2行ヘッダ）→ 生成 `data/movement/movement.json`（[[csv-data-pipeline]] と同じ仕組み）。
- 地形名は `Terrain.NAMES`（`plain`/`plateau`…）と一致させる。
- 現状の表（叩き台・要チューニング）:

| 移動タイプ | 平地 | 台地 | 森 |
|---|---|---|---|
| ground（地上） | 1 | 2 | 2 |
| flight（飛行） | 1 | 1 | 1 |

- 地形は **データ駆動**（[combat.md](combat.md) 地形効果／`data/terrain/terrain.csv`）。地形を増やす＝terrain.csv に1行＋この movement.csv に1列。山・水辺なども同様。

---

## ZOC 停止（実装済み）

- **敵ZOC（敵ユニットに隣接するマス）に入ると、そこで移動終了**＝その先へは進めない。マス自体には入れる。
- **飛行を含む全移動タイプに適用**（移動タイプ非依存）。包囲（戦闘補正）とは別軸。
- **起点が敵ZOC内でも動き出せる**（起点には停止判定を適用しない）。
- 実装: `BattleState.reachable`/`_in_enemy_zoc`、`Hex.flood_reach_cost` の `stop_fn`（終端ヘックス＝到達可だが非展開）。

## 未決・残作業

- [ ] 地形のデータ化（移動コスト列の拡張＝森・山・水辺…）と、地形タイプごとのコスト確定。
- [ ] 移動タイプの拡充（騎乗・水棲・特殊パターン）。
