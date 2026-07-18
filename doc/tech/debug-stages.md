# デバッグステージ一覧（カテゴリ別）

動作確認用のデバッグ冒険譚は、機能別に6つへ分けている。各フォルダに `campaign.json`（`"debug": true`）を置くと、`CampaignCatalog.load_all()` がフォルダ走査で拾い、セレクト画面では `OS.is_debug_build()` のときだけ末尾のデバッグボードに並ぶ。デバッグ冒険譚は常時解放・クリア記録なし（進行に混ぜない）。仕組み → [../gdd/stage_select.md](../gdd/stage_select.md)。

このページは各カテゴリの「既存ステージ」と「あるべき（未実装＝TODO）」の台帳。未実装分は着手時にここのチェックを埋める。

補足:
- 起動時の下敷き（セレクトの裏に出る空盤）は `data/stages/_boot/underlay.json`。どのデバッグ冒険譚にも属さない（`campaign.json` が無いのでセレクトには出ない）。
- 基本動作の総合マップ（旧 `debug/debug.json`）は廃止。機能別に分けたため役割は各カテゴリへ吸収した。

## debug-combat（戦闘補正）

戦闘解決の補正チェーンを1機能ずつ切り分けて見る。既存ステージは無く、すべてこれから。設計 → [../gdd/combat.md](../gdd/combat.md)。

| ステージ | ファイル | 状態 |
| --- | --- | --- |
| （なし） | — | 未着手 |

あるべき（TODO）:
- [ ] 地形補正（全13地形の攻防係数を1枚で見比べる見本）
- [ ] 間接（反撃なしの確認）
- [ ] 魔法（貫通 vs 高防御）
- [ ] 対空・対地（飛行相手の係数）
- [ ] 包囲（段階ごとの加算）
- [ ] 支援（加算・2倍上限）
- [ ] 経験Lv（レベル差の補正）

## debug-ai（敵AI）

思考プリセットの振る舞いを見る。設計 → [../gdd/ai.md](../gdd/ai.md)。

| ステージ | ファイル | 状態 |
| --- | --- | --- |
| 待機・索敵（guard＋視線） | `debug-ai/sight.json` | 実装済み |
| 弱者狙いAI（weak） | `debug-ai/weak.json` | 実装済み |
| 敵拠点の出撃（charge湧き） | `debug-ai/spawn.json` | 実装済み |

あるべき（TODO）:
- [ ] charge（突撃の素の見本＝専用ステージが無い。既定プリセットの単体確認）
- [ ] raid（拠点攻略の前進。今は勝利条件側の `hq.json` に同居＝AI単体では切れていない）
- [ ] 起動トリガー見本（sight／squad／被ダメ／自衛の各起動を1枚ずつ）

## debug-victory（勝利条件）

決着判定を条件ごとに見る。設計 → [../gdd/map.md](../gdd/map.md)。

| ステージ | ファイル | 状態 |
| --- | --- | --- |
| ボス撃破 | `debug-victory/boss.json` | 実装済み |
| 本拠地占領（raid） | `debug-victory/hq.json` | 実装済み |
| ターン制限（10で時間切れ敗北） | `debug-victory/turnlimit.json` | 実装済み |

あるべき（TODO）:
- [ ] 殲滅（既定の最小確認＝敵全滅で勝ち）
- [ ] 自軍hq喪失で敗北（奪われて負ける／奪還で解消）
- [ ] 複数条件のOR（`victory` に複数並べてどれかで勝つ）

## debug-mapops（マップ操作）

拠点・陣形・輸送などの盤上操作を見る。設計 → [../gdd/map.md](../gdd/map.md)・[../gdd/formations.md](../gdd/formations.md)・[../gdd/movement.md](../gdd/movement.md)。

| ステージ | ファイル | 状態 |
| --- | --- | --- |
| 閉じ込め判定（案B・籠城/湧き） | `debug-mapops/siege.json` | 実装済み |
| 陣形スキル（①三重詠唱） | `debug-mapops/formation.json` | 実装済み |
| 輸送（乗車・運搬・降車） | `debug-mapops/transport.json` | 実装済み |
| バリケード輸送（出撃→隣接乗降） | `debug-mapops/barricade.json` | 実装済み |

あるべき（TODO）:
- [ ] 拠点＝占領・出撃・回復の3機能を素直に1枚で
- [ ] 中立拠点の寝返り（取った側へ garrison が付く）
- [ ] 陣形②③（聖なる加護・神の裁き）
- [ ] 飛空艇（飛行輸送）・初期搭乗

## debug-skins（ユニット/地形スキン）

見た目レイヤー（skin）の一覧確認。設計 → [../art/units.md](../art/units.md)・[../art/terrain.md](../art/terrain.md)。

| ステージ | ファイル | 状態 |
| --- | --- | --- |
| ユニット一覧（全スキン） | `debug-skins/units.json` | 実装済み |

あるべき（TODO）:
- [ ] 地形スキン一覧（全タイル見本）＝現状なし

## debug-misc（その他）

上のどれにも入らない演出・UI検証。

| ステージ | ファイル | 状態 |
| --- | --- | --- |
| 会話シーン（前後・チャット風） | `debug-misc/talk.json` | 実装済み |

あるべき（TODO）:
- [ ] 追加の演出／UI検証を随時
