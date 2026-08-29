# デバッグステージ一覧（カテゴリ別）

動作確認用のデバッグ冒険譚は、機能別に分けている。各フォルダに `campaign.json`（`"debug": true`）を置くと、`CampaignCatalog.load_all()` がフォルダ走査で拾い、セレクト画面では `OS.is_debug_build()` のときだけ末尾のデバッグボードに並ぶ。デバッグ冒険譚は常時解放・クリア記録なし（進行に混ぜない）。仕組み → [../gdd/stage_select.md](../gdd/stage_select.md)。

各ステージは目的と変更の引き金を記す。盤の配置の詳細はステージJSONが正本。

補足:
- 起動時の下敷き（セレクトの裏に出る空盤）は `godot/data/stages/_boot/underlay.json`。どのデバッグ冒険譚にも属さない（`campaign.json` が無いのでセレクトには出ない）。

## debug-photo（撮影）

外に出すスクリーンショット（devlog・紹介画像）の画を、開始配置でそのまま組んだ撮影セット。`tools/marketing/shot_stage`（[tools.md](tools.md)）で撮る前提＝動作確認ではなく構図が正本。撮りたい画が増えたらステージを足す。

| ステージ | ファイル | 目的 |
| --- | --- | --- |
| devlog1-1 | `debug-photo/devlog1-1.json` | devlog 1本目の1枚目の画 |
| devlog1-2 | `debug-photo/devlog1-2.json` | devlog 1本目の2枚目の画（戦闘連写） |
| store1 | `debug-photo/store1.json` | 紹介画像の1枚目（ゴブリン討伐令の盤を移植し、駒を包囲の形に置き直したもの。会話は外す） |
| store2 | `debug-photo/store2.json` | 紹介画像の2枚目（同じ盤。攻め手をノービスにして、演出の左右に隊列が残る殴り合いにする） |

## debug-combat（戦闘シーンの見た目確認）

戦闘シーンでのユニットとエフェクトの見た目をカテゴリ別に確認する。設計 → [../gdd/combat.md](../gdd/combat.md)・[combat_scene.md](combat_scene.md)。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| ally | `debug-combat/ally.json` | 味方ユニットの戦闘シーン確認 | 味方スキンを追加したとき |
| goblin | `debug-combat/goblin.json` | ゴブリンの戦闘シーン確認 | ゴブリンスキンを追加したとき |
| undead | `debug-combat/undead.json` | アンデッドの戦闘シーン確認 | アンデッドスキンを追加したとき |
| orc | `debug-combat/orc.json` | オークの戦闘シーン確認 | オークスキンを追加したとき |
| beast | `debug-combat/beast.json` | 魔獣の戦闘シーン確認 | 魔獣スキンを追加したとき |
| giant | `debug-combat/giant.json` | 巨人の戦闘シーン確認 | 巨人スキンを追加したとき |
| plant | `debug-combat/plant.json` | 植物の戦闘シーン確認 | 植物スキンを追加したとき |
| dragon | `debug-combat/dragon.json` | ドラゴンの戦闘シーン確認 | ドラゴンスキンを追加したとき |
| magic_creature | `debug-combat/magic_creature.json` | 魔法生物の戦闘シーン確認 | 魔法生物スキンを追加したとき |
| rogue | `debug-combat/rogue.json` | 悪党の戦闘シーン確認 | 悪党スキンを追加したとき |
| terrain | `debug-combat/terrain.json` | 地形ごとの戦闘背景確認 | 戦闘背景を追加したとき |

## debug-unit-skill（ユニットスキル）

味方ユニットスキル全般の動作確認。設計 → [../gdd/skills.md](../gdd/skills.md)。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| skill | `debug-unit-skill/skill.json` | 味方ユニットスキルの動作確認 | スキルを追加したとき |

## debug-formation-skill（陣形スキル）

陣形スキルの動作確認。設計 → [../gdd/formations.md](../gdd/formations.md)。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| formation | `debug-formation-skill/formation.json` | 陣形スキルの動作確認 | レシピを追加したとき |

## debug-ai（敵AI）

特性ごとの振る舞いを確認する。設計 → [../gdd/ai.md](../gdd/ai.md)。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| charge | `debug-ai/charge.json` | 突撃の動作確認 | charge の行動ルールを変えたとき |
| ambush | `debug-ai/ambush.json` | 待ち伏せの動作確認 | ambush の行動ルールを変えたとき |
| raid | `debug-ai/raid.json` | 拠点攻略の動作確認 | raid の行動ルールを変えたとき |
| predator | `debug-ai/predator.json` | 弱者狙いの動作確認 | predator の行動ルールを変えたとき |
| swarm | `debug-ai/swarm.json` | 群れの動作確認 | swarm の行動ルールを変えたとき |
| flee | `debug-ai/flee.json` | 逃走の動作確認 | flee の行動ルールを変えたとき |
| withdraw | `debug-ai/withdraw.json` | 撤退の動作確認 | withdraw の行動ルールを変えたとき |
| standoff | `debug-ai/standoff.json` | 睨み合いの動作確認 | standoff の行動ルールを変えたとき |
| transport | `debug-ai/transport.json` | 輸送ユニットの動作確認 | 輸送の行動ルールを変えたとき |

## debug-victory（勝敗条件）

決着判定を条件ごとに確認する。設計 → [../gdd/map.md](../gdd/map.md)。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| boss | `debug-victory/boss.json` | ボス撃破の勝利判定 | defeat_unit の判定を変えたとき |
| hq | `debug-victory/hq.json` | 本拠地占領の勝利判定 | capture_hq の判定を変えたとき |
| turnlimit | `debug-victory/turnlimit.json` | ターン制限の敗北判定 | turn_limit の判定を変えたとき |
| defend_base | `debug-victory/defend_base.json` | 拠点防衛（1つ）の敗北判定 | lose_base の判定を変えたとき |
| defend_two | `debug-victory/defend_two.json` | 拠点防衛（2つ・AND）の敗北判定 | lose_base の複数AND判定を変えたとき |
| annihilate | `debug-victory/annihilate.json` | 殲滅の勝利判定 | 殲滅判定を変えたとき |
| total_loss | `debug-victory/total_loss.json` | 自軍全滅の敗北判定 | 全滅判定を変えたとき |
| lose_hq | `debug-victory/lose_hq.json` | 自軍本拠地喪失の敗北判定 | hq喪失判定を変えたとき |
| lose_unit | `debug-victory/lose_unit.json` | 護衛対象喪失の敗北判定 | lose_unit の判定を変えたとき |

## debug-mapops（マップ操作）

拠点・輸送などの盤上操作を確認する。設計 → [../gdd/map.md](../gdd/map.md)・[../gdd/movement.md](../gdd/movement.md)。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| base | `debug-mapops/base.json` | 拠点と勝敗（消滅判定・寝返り・閉じ込め） | 拠点の仕様を変えたとき |
| transport | `debug-mapops/transport.json` | 輸送（乗車・運搬・降車） | 輸送の仕様を変えたとき |
| barricade | `debug-mapops/barricade.json` | バリケード輸送（出撃→隣接乗降） | バリケードの仕様を変えたとき |
| event | `debug-mapops/event.json` | イベント＝増援 | イベントの仕様を変えたとき |

## debug-skins（ユニット/地形スキン）

見た目レイヤー（skin）の一覧確認。設計 → [../art/units.md](../art/units.md)・[../art/terrain.md](../art/terrain.md)。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| ally | `debug-skins/ally.json` | 味方ユニットのマップ表示確認 | 味方スキンを追加したとき |
| goblin | `debug-skins/goblin.json` | ゴブリンのマップ表示確認 | ゴブリンスキンを追加したとき |
| undead | `debug-skins/undead.json` | アンデッドのマップ表示確認 | アンデッドスキンを追加したとき |
| orc | `debug-skins/orc.json` | オークのマップ表示確認 | オークスキンを追加したとき |
| beast | `debug-skins/beast.json` | 魔獣のマップ表示確認 | 魔獣スキンを追加したとき |
| giant | `debug-skins/giant.json` | 巨人のマップ表示確認 | 巨人スキンを追加したとき |
| plant | `debug-skins/plant.json` | 植物のマップ表示確認 | 植物スキンを追加したとき |
| dragon | `debug-skins/dragon.json` | ドラゴンのマップ表示確認 | ドラゴンスキンを追加したとき |
| magic_creature | `debug-skins/magic_creature.json` | 魔法生物のマップ表示確認 | 魔法生物スキンを追加したとき |
| rogue | `debug-skins/rogue.json` | 悪党のマップ表示確認 | 悪党スキンを追加したとき |
| terrain | `debug-skins/terrain.json` | 地形見本（基本地形・7ヘクスずつ） | 地形スキンを追加したとき |
| height | `debug-skins/height.json` | 高さ見本（徐々に上がる傾斜・崖） | 高さの仕様を変えたとき |

## debug-misc（その他）

上のどれにも入らない演出・UI検証。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| talk | `debug-misc/talk.json` | 会話シーンの動作確認 | 会話の仕様を変えたとき |
