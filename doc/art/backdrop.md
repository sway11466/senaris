# 奥の背景の方針

戦闘窓の水平線から上に敷く1枚の生成設計。全アセット共通のトーン・制作メソッド（アンカー方式・二層保管・ドロップイン差し替え）は [direction.md](direction.md) が正本。本ファイルは背景固有：役割・寸法・BACKDROP STYLE・保管。

窓の中での置き方と水平線の決まりは [../tech/combat_scene.md](../tech/combat_scene.md) が正本。

---

## 1. 何を描く絵か

戦闘窓の奥、水平線より上に見えるもの。空とは限らない。野戦なら空、洞窟や神殿の中なら岩壁や壁面で、その盤が屋外か屋内かを一枚で言う。

守り手側の半面に建つ塊（`{skin_id}_combat_back.png`）とは別物。あちらは地形スキンが持つ「その地形が何か」の絵で、こちらはステージが持つ「この盤がどこか」の絵。拠点の屋根はこの背景に抜ける。

## 2. どのステージがどれを使うか

ステージJSONの `backdrop` に絵のIDを1行書く。

```json
"backdrop": "sky_overcast"
```

書かなければ水平線を引かず、地面が窓の上端まで続く（今までの見え方）。絵を置けば出る＝コードもCSVも触らない。

## 3. 寸法

幅は窓の横幅に合わせ、高さは絵の縦横比が決める。下端が水平線に来て、上に余ったぶんは窓が切る。

縦横比は 3:1（横:縦）より横長にしない。窓の縦横比は画面解像度で変わり、一番きつい場合で 3.46:1 ぶんの高さが要る。これより横長だと背景の上に隙間が出て、窓の下地色が覗く。

靄（奥へ行くほど落とす減光）はこの絵には掛からない。暗さ・空気感は絵そのものが持つ。

## 4. BACKDROP STYLE

```
STYLE: A distant backdrop for the battle window of a fantasy tactics game, in
the same clean stylized cel-shaded look as the game's unit art: bold flat
shading, clear dark outlines, a mature, slightly muted, limited color palette
(NOT bright saturated, NOT painterly photorealism). Seen straight ahead at eye
level from far away. Large simple shapes only, low contrast, no fine detail and
no single object that draws the eye - soldiers fight in front of this and must
stay readable. A wide band, three times as wide as it is tall.
```

密度・中身は SUBJECT に書く。守るのは次の3点。

- 主役を作らない。目を引く1個（塔・月・巨木）を置くと、手前の隊列より背景を見てしまう。
- 明暗の差を小さく保つ。立ち絵は縁取りの濃い絵なので、背景が強いと輪郭が沈む。
- 下端に地面を描かない。地面は3Dの帯が担当する。下端は水平線でそのまま切れる。

## 5. 保管・命名

ユニット（[units.md](units.md) §3.1）と同じ二層。

| 段階 | 置き場（`{id}`＝ステージJSONの `backdrop` に書く名前） | 例 |
|---|---|---|
| ① AI生成（原寸） | `assets/backdrop-src/{id}/` に任意名で複数 | `backdrop-src/sky_overcast/sky_overcast_01_raw.jpg` |
| SUBJECT | `assets/backdrop-src/{id}/{id}_prompt.txt` | `backdrop-src/sky_overcast/sky_overcast_prompt.txt` |
| ② ゲーム用 | `assets/backdrop/{id}.png` | `backdrop/sky_overcast.png` |

②は原画をそのまま置く（切り抜きも余白調整も要らない＝大小は窓が決める）。透過は使わない。

---

## 参考資料

- [direction.md](direction.md) — アートの全体方針（絵柄・陣営配色・共通メソッド）
- [terrain.md](terrain.md) — 地形タイルの方針（守り手側に建つ塊 `_combat_back` はこちら）
- [../tech/combat_scene.md](../tech/combat_scene.md) — 戦闘演出シーン（水平線・重ね絵・靄）
