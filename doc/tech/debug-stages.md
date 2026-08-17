# デバッグステージ一覧（カテゴリ別）

動作確認用のデバッグ冒険譚は、機能別に6つへ分けている。各フォルダに `campaign.json`（`"debug": true`）を置くと、`CampaignCatalog.load_all()` がフォルダ走査で拾い、セレクト画面では `OS.is_debug_build()` のときだけ末尾のデバッグボードに並ぶ。デバッグ冒険譚は常時解放・クリア記録なし（進行に混ぜない）。仕組み → [../gdd/stage_select.md](../gdd/stage_select.md)。

このページは各カテゴリの既存ステージの台帳。構成見直しと不足ステージの追加は [backlog.md](../backlog.md)（feature-26）を参照。

補足:
- 起動時の下敷き（セレクトの裏に出る空盤）は `data/stages/_boot/underlay.json`。どのデバッグ冒険譚にも属さない（`campaign.json` が無いのでセレクトには出ない）。
- 基本動作の総合マップ（旧 `debug/debug.json`）は廃止。機能別に分けたため役割は各カテゴリへ吸収した。

## debug-combat（戦闘関連）

戦闘解決の補正チェーンと戦闘演出を1機能ずつ切り分けて見る。設計 → [../gdd/combat.md](../gdd/combat.md)・[combat_scene.md](combat_scene.md)。

| ステージ | ファイル |
| --- | --- |
| ユニットスキル（ピクシーダスト） | `debug-combat/skill.json` |
| 攻撃エフェクト（全種） | `debug-combat/effect.json` |

ユニットスキルの盤は全面平地。ピクシー2体と、掛ける相手（ファイター2・アーチャー・ナイト）を左に固め、索敵0の待ち伏せユニットを右に置いた。自分・隣接の味方・離れた味方で対象の絞り込みを確かめ、そのまま殴って戦闘レポートの加算バフ表示（`ピクシーダスト +80/+80`）まで見られる。2体のピクシーで同じ相手に重ねがけもできる。

攻撃エフェクトの盤も全面平地。`data/effects/combat_effect.csv` のエフェクトが1種につき1回は出るよう、味方と敵を組にして隣接させた。スキンは本来の陣営のまま置く（味方スキンを敵として並べたりはしない）。1組を1回殴れば、味方のエフェクト（右向き＝反転なし）と敵の反撃エフェクト（左向き＝反転あり）が同じ画に出る。絵を「右へ向かう一撃」で描いて左向きだけ反転する規約 → [combat_scene.md](combat_scene.md)（攻撃エフェクト）。

| 味方（エフェクト） | 敵（エフェクト） |
| --- | --- |
| ノービス（slash_s） | グール（claw） |
| ファイター（slash_m） | ゾンビ（punch） |
| クレリック（holy） | デュラハン（slash_l） |
| アーチャー（arrow） | スケルトンアーチャー（arrow_bone） |
| ハーフリング（stone） | ゴースト（curse_wisp） |
| 飛空艇（cannonball） | ゴブリンアーチャー（arrow） |
| バリスタ（arrow_bolt） | ゴブリンアーチャー（arrow） |
| ウィザード（magic_bolt） | ネクロマンサー（curse） |

- 敵AIは `ambush`（待ち伏せ）・索敵0の1部隊。隣接した相手には自衛で反撃するので、待ち伏せのまま敵側のエフェクトも出る。
- ウィザードとネクロマンサーの組だけは両方とも間接専用（射程2-4／2-5）で射程1に撃てないため、距離2に置いた。反撃が起きないので、敵の curse はターンを終えて相手に撃たせて見る（自衛起動で撃ってくる）。
- 飛空艇の相方は対空が要る（飛行＝対空0の駒は反撃できない）ためゴブリンアーチャー。arrow はアーチャーと重複するが、これは反転した側の見え方を兼ねる。
- バリスタは移動0・射程2-6で射程1に撃てないため、距離2の位置に置いてゴブリンアーチャーを飛空艇と共用する。相手は射程1-2なので反撃が返り、1回の交戦で arrow_bolt と arrow が並ぶ＝太矢と通常の矢の大きさの差をその場で比べられる。

## debug-ai（敵AI）

特性ごとの振る舞いを見る。設計 → [../gdd/ai.md](../gdd/ai.md)。

| ステージ | ファイル |
| --- | --- |
| 待ち伏せ・索敵（ambush＋視線） | `debug-ai/sight.json` |
| 弱者狙いAI（weak） | `debug-ai/weak.json` |
| 敵拠点の出撃（charge湧き） | `debug-ai/spawn.json` |
| 輸送を使う敵AI（乗る・運ぶ・降ろす） | `debug-ai/transport.json` |

## debug-victory（勝利条件）

決着判定を条件ごとに見る。設計 → [../gdd/map.md](../gdd/map.md)。

| ステージ | ファイル |
| --- | --- |
| ボス撃破 | `debug-victory/boss.json` |
| 本拠地占領（raid） | `debug-victory/hq.json` |
| ターン制限（10で時間切れ敗北） | `debug-victory/turnlimit.json` |
| 拠点防衛（奪われたら敗北） | `debug-victory/defend_base.json` |
| 拠点防衛×2（両方失ったら敗北＝AND） | `debug-victory/defend_two.json` |

## debug-mapops（マップ操作）

拠点・陣形・輸送などの盤上操作を見る。設計 → [../gdd/map.md](../gdd/map.md)・[../gdd/formations.md](../gdd/formations.md)・[../gdd/movement.md](../gdd/movement.md)。

| ステージ | ファイル |
| --- | --- |
| 拠点と勝敗（消滅判定・寝返り・閉じ込め・スキンの所有色） | `debug-mapops/base.json` |
| 陣形スキル（味方ユニット） | `debug-mapops/formation.json` |
| 輸送（乗車・運搬・降車） | `debug-mapops/transport.json` |
| バリケード輸送（出撃→隣接乗降） | `debug-mapops/barricade.json` |
| イベント＝増援（残りターン板・搭載駒ごと到着・壁指定は最寄りへずらす） | `debug-mapops/event.json` |
## debug-skins（ユニット/地形スキン）

見た目レイヤー（skin）の一覧確認。設計 → [../art/units.md](../art/units.md)・[../art/terrain.md](../art/terrain.md)。

| ステージ | ファイル |
| --- | --- |
| ユニット一覧（全スキン） | `debug-skins/units.json` |
| 地形見本（基本地形・7ヘクスずつ） | `debug-skins/terrain.json` |

地形見本は、全面平地の上に基本地形（道・台地・荒地・森・茂み・岩地）を7ヘクスの塊で1つずつ置いた盤。各塊の中心に索敵0の待ち伏せユニットを立てて、地形の上に駒が乗った見え方も一緒に確認できる。歩き回る側は移動8・軽歩行のシーフ5体。

## debug-misc（その他）

上のどれにも入らない演出・UI検証。

| ステージ | ファイル |
| --- | --- |
| 会話シーン（前後・チャット風） | `debug-misc/talk.json` |

