# 画像スロット仕様

性能（`UnitType`）と分離した `UnitSkin` が名前・説明・画像を持つ（→ [../gdd/units.md](../gdd/units.md)）。画像はスロット制：

| スロット | 用途 | 未用意時のプレースホルダ |
|---|---|---|
| `map` | 盤上のユニット表示 | ベタ塗り＋名前の先頭2文字（例: クレリック→「クレ」） |
| `combat` | 戦闘演出の立ち絵（1体分。演出が兵数ぶん複製表示） | ベタ塗り＋フルネーム |
| `combat_effect` | そのユニットの攻撃エフェクト（1枚。相手隊列に重ねる） | エフェクト無し |
| `portrait` | 会話の顔（任意） | `map` で代用（それも無ければベタ塗り＋名前の先頭2文字） |

- `images = { "map": "res://...", "combat": "res://..." }`。未設定はプレースホルダ（盤は名前を描く）。アートが来たらパスを入れるだけで描画が画像へ切り替わる（コード不変）。
- 行動前/行動後は当面 `map` 1枚＋盤側のグレー化（行動済みは暗くする処理が既にある）。専用画像が要るなら `map_active`/`map_done` にスロットを割ればよい。
- 戦闘立ち絵（`combat`/`combat_effect`）は3/4俯瞰・陣営で向き固定（プレイヤー左＝右向き／敵右＝左向き）。作画スペックは [units.md](units.md) §3.3、演出シーン（左右配置・兵数→隊列・シェイク/フラッシュ/エフェクト）は [../tech/combat_scene.md](../tech/combat_scene.md)。
- ボス系の「ボス＋手下」は絵を足さずに作る＝`unit_skin.csv` の `retainers` 列で既存スキンを従者に指定する（中央がボス・周りが従者）。→ [../tech/combat_scene.md](../tech/combat_scene.md)
- 戦闘背景は地形ごと（守り手のタイル地形で選択・全ユニット共通）＝ユニットスロットではなく別系統。地形IDで autowire（[../tech/combat_scene.md](../tech/combat_scene.md)）。
- 会話の顔は基本 `map` を流用する（透明余白を除いた外接矩形だけ切り出して表示）。`portrait` を使うのは、盤に出ないキャラのセリフがある場合と、`map` では出せない表情を見せたい場合。詳細 → [../campaign/authoring.md](../campaign/authoring.md)。
- 将来スロット候補: `icon`。

---

## 参考資料

- [direction.md](direction.md) — アートの全体方針（絵柄・陣営配色・共通メソッド）
- [units.md](units.md) — ユニットの見た目方針（画像スロットの参照元）
- `assets/units-src/{group}/style.md` — 陣営ごとの個体特徴（味方＝[player/style.md](../../assets/units-src/player/style.md)）
