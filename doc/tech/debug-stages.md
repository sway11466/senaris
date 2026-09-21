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
| store3 | `debug-photo/store3.json` | 紹介画像の3枚目（同じ盤。魔法兵3体を相互隣接の三角に置き、トリニティノヴァを撃てる形にする） |
| store4 | `debug-photo/store4.json` | 紹介画像の4枚目（会話パート。チュートリアル1・第4話をそのまま移植＝盤も会話も本物） |
| devlog2-1 | `debug-photo/devlog2-1.json` | devlog 2本目の画（墓地の関門にバリケード＋魔法兵の三角＋アンデッドの群れ。`shot_screen --formation trinity_nova` で連写） |
| devlog2-2 | `debug-photo/devlog2-2.json` | devlog 2本目のマップの画（undead-rush-st3 の実盤面コピー。関門をバリケードで塞ぎ、アンデッドの群れが詰まり、脇からゴーストが回り込む中盤の配置） |
| manual-combat | `debug-photo/manual-combat.json` | マニュアルに貼る絵の撮影セット（平地にファイターとゴブリンを隣り合わせで1体ずつ。戦闘窓・戦闘レポート・情報板をここから撮る） |

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
| magical | `debug-combat/magical.json` | 魔法生物の戦闘シーン確認 | 魔法生物スキンを追加したとき |
| rogue | `debug-combat/rogue.json` | 悪党の戦闘シーン確認 | 悪党スキンを追加したとき |
| terrain | `debug-combat/terrain.json` | 地形ごとの戦闘背景確認 | 戦闘背景を追加したとき |

## debug-unit-skill（ユニットスキル）

味方ユニットスキル全般の動作確認。設計 → [../gdd/skills.md](../gdd/skills.md)。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| skill | `debug-unit-skill/skill.json` | 味方ユニットスキルの動作確認 | スキルを追加したとき |

## debug-formation-skill（陣形スキル）

陣形スキルの動作確認。設計 → [../gdd/formations.md](../gdd/formations.md)。

レシピごとに1枚。ファイル名はレシピID、並びは [formations.md](../gdd/formations.md) 表Aの番号順。どの盤も**そのレシピが成立する最小の配置だけ**を置く（成立しない反例は置かない）。敵は待ち伏せ・視界1の的＝こちらから殴るまで動かない。レシピを足したら1枚足す。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| trinity_nova | `debug-formation-skill/trinity_nova.json` | ①トリニティノヴァ（面7ヘクスに敵3体が入る） | ①を変えたとき |
| grace | `debug-formation-skill/grace.json` | ②グレイス（参加しないファイターで全体バフの乗りを見る） | ②を変えたとき |
| divine_judgment | `debug-formation-skill/divine_judgment.json` | ③ディバインジャッジメント（射程ちょうど10） | ③を変えたとき |
| trick_shot | `debug-formation-skill/trick_shot.json` | ④トリックショット（斥候は弓兵に隣接しない） | ④を変えたとき |
| shield_wall | `debug-formation-skill/shield_wall.json` | ⑤シールドウォール（殴って反撃を受けると防御が見える） | ⑤を変えたとき |
| arrow_rain | `debug-formation-skill/arrow_rain.json` | ⑥アローレイン（味方1体が面に入る＝誤射） | ⑥を変えたとき |
| magic_shield | `debug-formation-skill/magic_shield.json` | ⑦マジックシールド（ウィザード＋プリーストが隣接＝どちらからでも。結界の中と外に前衛が1体ずつ、敵は貫通持ちと物理が1体ずつ） | ⑦を変えたとき |
| magic_arrow | `debug-formation-skill/magic_arrow.json` | ⑨マジックアロー（射程ちょうど5） | ⑨を変えたとき |
| counter | `debug-formation-skill/counter.json` | ⑩カウンター（発動者の隣に歩兵2体＝組を選ぶ。殴られて反撃すると攻撃が見える） | ⑩を変えたとき |
| members | `debug-formation-skill/members.json` | 参加者を選ぶ段の確認（組が複数／組が1つ／候補が絞られる／人数が可変で候補が余る／可変で最低人数ちょうど／移動先で成立）。スキルをまたぐ話なので1枚にまとめる | 参加者の選び方・形を足したとき |

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
| boss_two | `debug-victory/boss_two.json` | ボス撃破（2体・AND）の勝利判定＝片方だけでは勝たない | defeat_unit の複数AND判定を変えたとき |
| hq | `debug-victory/hq.json` | 本拠地占領の勝利判定 | capture_hq の判定を変えたとき |
| turnlimit | `debug-victory/turnlimit.json` | ターン制限の敗北判定 | turn_limit の判定を変えたとき |
| defend_base | `debug-victory/defend_base.json` | 拠点防衛（1つ）の敗北判定 | lose_base の判定を変えたとき |
| defend_two | `debug-victory/defend_two.json` | 拠点防衛（2つ・AND）の敗北判定 | lose_base の複数AND判定を変えたとき |
| annihilate | `debug-victory/annihilate.json` | 殲滅の勝利判定 | 殲滅判定を変えたとき |
| total_loss | `debug-victory/total_loss.json` | 自軍全滅の敗北判定 | 全滅判定を変えたとき |
| lose_hq | `debug-victory/lose_hq.json` | 自軍本拠地喪失の敗北判定 | hq喪失判定を変えたとき |
| lose_unit | `debug-victory/lose_unit.json` | 護衛対象喪失の敗北判定 | lose_unit の判定を変えたとき |

## debug-carryover（戦力継承）

冒険譚をまたいで名簿が引き継がれるかを、2話で確認する。デバッグ冒険譚はクリア記録を残さないが、名簿（`user://roster.json`）はクリアしたステージの控え（冒険譚 id×ステージ id）として書かれる＝継承だけを切り出して見られる。inherit は `roster_from` で seed の控えを読む。設計 → [../gdd/campaigns.md](../gdd/campaigns.md) 戦力供給モデル。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| seed | `debug-carryover/seed.json` | 名簿を作る。Lv・兵数を書いた味方3体で勝ち、その値が名簿に載ることを見る（`keeper` Lv7/3・`refiller` Lv4/5・`faller` Lv9/1）。ターンを1回渡すと `faller` が倒れ、離脱者（兵数0・在籍は継続）も作れる | 決着時の名簿更新を変えたとき |
| inherit | `debug-carryover/inherit.json` | 名簿から出す。同じ3体を `supply` 違いで置く＝省略（そのまま）・`refill`（兵数だけ満員）・`revive`（離脱者も満員で復帰）。Lv が名簿のまま残ることが見分けの軸 | supply の解釈を変えたとき |

## debug-map（マップ）

盤の上で起きること全般＝拠点・輸送・イベント・移動を確認する。移動音は音だけを切り出さず、移動タイプと地形コストの確認に畳み込んで、絵と一緒に聞く。設計 → [../gdd/map.md](../gdd/map.md)・[../gdd/movement.md](../gdd/movement.md)・[../audio/sfx.md](../audio/sfx.md)。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| base | `debug-map/base.json` | 拠点と勝敗（消滅判定・寝返り・閉じ込め） | 拠点の仕様を変えたとき |
| transport | `debug-map/transport.json` | 輸送（乗車・運搬・降車。馬車にピクシーとバリスタを積み、輸送の隣に自軍拠点＝降りてから入る・スキルを撃つ導線と、移動0の兵器を隣接1マスの特例で拠点へ降ろす手も見る） | 輸送の仕様を変えたとき |
| barricade | `debug-map/barricade.json` | バリケード輸送（出撃→隣接乗降） | バリケードの仕様を変えたとき |
| event | `debug-map/event.json` | イベント＝増援 | イベントの仕様を変えたとき |
| move | `debug-map/move.json` | 移動（移動タイプ・地形コスト・移動音）。地面・軽い足音・羽ばたき・浮遊・プロペラの味方を1体ずつ置き、森・墓標・柵・墓石の山の帯を横切らせる。敵はゴーストとレイスの突撃＝敵の手番に飛んで来る浮遊音を実戦の文脈で聞く | 移動タイプ・地形コスト・移動音を変えたとき |

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
| magical | `debug-skins/magical.json` | 魔法生物のマップ表示確認 | 魔法生物スキンを追加したとき |
| rogue | `debug-skins/rogue.json` | 悪党のマップ表示確認 | 悪党スキンを追加したとき |
| terrain | `debug-skins/terrain.json` | 地形見本（基本地形・7ヘクスずつ） | 地形スキンを追加したとき |
| height | `debug-skins/height.json` | 高さ見本（徐々に上がる傾斜・崖） | 高さの仕様を変えたとき |

## debug-misc（その他）

上のどれにも入らない演出・UI検証。

| ステージ | ファイル | 目的 | 変更の引き金 |
| --- | --- | --- | --- |
| talk | `debug-misc/talk.json` | 会話シーンの動作確認 | 会話の仕様を変えたとき |
