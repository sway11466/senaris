# 効果音（SFX）

効果音の制作方針と組込の運用。BGM（[bgm.md](bgm.md)）と同じく予算ゼロ・商用可を前提に、少ない素材を使い回して揃える。

## 前提

- 予算ゼロ。有料の音源・外注は使わない。
- 配布はまず Steam（PC）＝商用。使う素材はすべて商用利用可であることを確認する。
- BGM で整えたパイプライン（MuseScore ＋ Muse Sounds → wav → Ogg Vorbis）と音源を共有し、BGM と地続きの音世界にする。

## 二層構造（素材と発火点を分けて管理する）

効果音は「音の実体」と「ゲーム中で鳴る瞬間」を別々に管理し、対応表で結ぶ。1枚の表にまとめない。

| 層 | 実体 | 決まり方 |
|---|---|---|
| 素材 | `sfx_id`（音そのもの） | 音の性質で分類。制作・調達の単位 |
| 発火点 | `event_id`（鳴る瞬間） | ゲームの構造で決まる。下の一覧 |
| 対応表 | `event_id` → `sfx_id` | データで持つ。差し替えは1行 |

分けるのは、両者が 1:1 に対応しないため。

- 多対1: 確定・キャンセル・否定はメニューでも盤でも同じ音を鳴らす。発火点は何個あっても素材は1つ。
- 1対多: 「攻撃した」という発火点は1つだが、鳴る音はスキンのエフェクト次第で十数種になる。

この構造は既存の管理と同型。BGM の「トラックライブラリ ↔ ステージJSONの `bgm` 欄」、絵の「スキン ↔ 画像スロット」と同じ考え方で、素材が無くても発火点の配線を先に済ませられる。

素材は `assets/sfx/{sfx_id}.ogg` を規約で解決する（autowire）。ファイルがあれば鳴り、無ければ無音＋開発ログ1行でゲームは止めない。

## 基本音

操作の意味に対して1つの音を割り当て、画面をまたいで同じ音を使う。狙いは学習性で、「この音＝通った」を一度覚えればどの画面でも通用する。同じ意味の操作が場所によって違う音になると、雰囲気で得るものより混乱の損が大きい。画面ごとの材質感は BGM と絵で出し、操作音では出さない。

| sfx_id | 意味 | 望まれる音 | 種別 |
|---|---|---|---|
| `ui_confirm` | 確定・決定・選択 | 決定の芯になる1音。短く、明るすぎない | 楽音 |
| `ui_cancel` | 戻る・キャンセル | 下行2音。否定だが咎めない | 楽音 |
| `ui_denied` | 操作の否定（できない） | 短い不協和。連打しても耳に障らない | 楽音 |
| `ui_hover` | ホバー強調・文字送り | ごく短いクリック。音程を持たせない。マップ系でのみ使う | 楽音 |

いずれも高頻度で鳴るため、短さと控えめさを最優先する。単体で聴いて物足りないくらいでちょうどよい。

`ui_denied` は「押せそうに見えるのに拒否される場所」にだけ置く。鍵つきのステージ行のように、一覧に並んでいて押せるように見えるものが応じないときは、無反応だと壊れたのか操作が届いていないのか分からない。ここは音で返す。

逆に、盤の無効なマスのように最初から候補として提示していないものには置かない。提示していないものを拒否する音は意味が重複するうえ、盤をつつき回して考えるゲームでは探るたびに鳴って耳障りになる。何もない場所は無音で返すのが既定で、`map_hover` を空きマスで鳴らさないのも同じ考え方。

## 発火点カタログ

「どこで鳴るか」の一覧。素材欄が基本音のものは上記を共用し、専用と書いたものだけ個別に用意する。

### メニュー — タイトル・冒険譚選択・ステージセレクト

画面構成は [../gdd/stage_select.md](../gdd/stage_select.md)。ホバー音は使わない（盤ほど密に指を動かす画面ではないため）。

| event_id | 鳴る瞬間 | 素材 | 望まれる音 |
|---|---|---|---|
| `menu_tier` | ◁▷ で難易度帯ボードを繰る | `menu_slide`（専用） | シャッ。板がスライドして切り替わる |
| `menu_campaign` | 冒険譚カードを選ぶ | `ui_confirm` | |
| `menu_stage` | ステージ行を選ぶ | `ui_confirm` | |
| `menu_locked` | 未解放（鍵）を触る | `ui_denied` | |
| `menu_sortie` | 「出撃」＝ステージ開始 | `menu_sortie`（専用） | 短いファンファーレ。戦場へ渡る区切り |
| `menu_back` | 戻る・閉じる | `ui_cancel` | |
| `menu_title` | タイトルで開始 | `menu_title`（専用） | 酒場の扉を開く音。依頼ボードのある店へ入る |

クリア記録の演出（討伐済スタンプ・ステージ解放）に伴う音は、演出そのものが固まってから決める。

完走時の勝利イラスト表示には専用音を置かない。決着の音は BGM の `victory` / `defeat` スティンガー（[bgm.md](bgm.md)）が担う。

### マップ（会話）

ステージ前後の会話パート。盤を暗幕で沈めて会話に注視させる（[../gdd/uiux.md](../gdd/uiux.md)）。

| event_id | 鳴る瞬間 | 素材 | 望まれる音 |
|---|---|---|---|
| `map_talk` | 会話の文字送り | `ui_hover` | 性質が同じ極短クリックのため共用する |
| `map_scrim` | 暗幕フェード（会話の開始・終了） | 専用 | 空気が沈む低いスウェル。0.5秒前後 |

### マップ（開始・ターン・終了）

盤面の局面が切り替わる節目。個々の操作より重く、区切りとして聞かせる。

| event_id | 鳴る瞬間 | 素材 | 望まれる音 |
|---|---|---|---|
| `map_deploy` | 出撃（拠点から駒が現れる） | 専用 | 門が開いて兵が出る。短い金属＋足音 |
| `map_turn_player` | 自軍ターン開始 | 専用 | ニ長調の短い上行。`victory` と同じ明るさの系統 |
| `map_turn_end` | ターン終了ボタン押下 | `ui_confirm` | 直後に `map_turn_enemy` が続く |
| `map_turn_enemy` | 敵ターン開始 | 専用 | ニ短調。`map_turn_player` と同主調ペアで設計 |

### マップ（盤の操作）

操作モデルは [../gdd/uiux.md](../gdd/uiux.md)。コマンドメニュー・拠点メニュー・システムメニューの開閉には専用音を置かない。開くきっかけのクリックが `ui_confirm` を、閉じる操作が `ui_cancel` を鳴らすため、重ねると二度鳴りになる。

| event_id | 鳴る瞬間 | 素材 | 望まれる音 |
|---|---|---|---|
| `map_hover` | ユニットまたは拠点があるマスにホバー | `ui_hover` | 空きマスでは鳴らさない。下記 |
| `map_select` | 自軍ユニットを選択（移動範囲が開く） | `ui_confirm` | |
| `map_confirm` | メニュー項目を決定 | `ui_confirm` | |
| `map_cancel` | キャンセル・戻る（右クリック／Esc） | `ui_cancel` | |
| `map_move` | 移動アニメ中（1マス0.12秒・最大0.6秒） | 専用 | 移動タイプごと。踏むたびに鳴らす。下記の動的解決 |
| `map_board` | 輸送への乗車・降車 | 専用 | 木の荷台に乗り込む鈍い音 |
| `map_capture` | 占領成立 | 専用 | 山場。チューブラーベル（神域の役割）＋旗の布音。盤面が変わった重み |
| `map_formation` | 陣形スキル発動（詠唱が起こる瞬間＝演出の頭） | 専用 | 特別感。ハープ／グロッケンの上行グリス＋ホルン。数少ない華 |
| `map_formation_hit` | 陣形スキルの効果が届いた瞬間（面ダメージの着弾・全体バフの発効） | 専用 | 発動音の落とし所。`map_formation` と対で設計する。ダメージ系は低く重い一撃、バフ系は澄んだ和音 |
| `map_skill` | ユニットスキル発動（味方1体に効果が乗る瞬間） | 専用 | 陣形より軽く短い。ハープの短い上行＋鈴。毎ターン鳴りうるので耳に残しすぎない |
| `map_crisis` | 危機BGMへ切り替わる瞬間 | 専用 | 曲の切替を後押しする一撃。低い鐘＋弦のスタブ |

ホバー音はユニットと拠点の上でだけ鳴らす。盤は空きマスが大半のため全マスで鳴らすとカーソルを動かすだけで鳴り続け、音が意味を失う。対象を絞ると「そこに何かある」という情報になり、盤を見ずに指を動かしても気付ける。

陣形スキルとユニットスキルは仕組みを共有するが（[../gdd/formations.md](../gdd/formations.md)・[../gdd/skills.md](../gdd/skills.md)）、鳴らし方は分ける。陣形は成立させるのが難しく1ステージに数回しか撃てない＝長めの華でよい。ユニットスキルは単独で撃てて毎ターン飛ぶ＝短く軽い音に留める。同じ音を共用すると、頻度の高いユニットスキル側で「特別な音」が擦り切れる。

陣形スキルは戦闘演出シーン（下記）を通らないため、着弾音を `cmb_hit` から借りられない。`map_formation_hit` を別に持つのはこのため。

### 戦闘 — 戦闘演出シーン

演出の構成は [../tech/combat_scene.md](../tech/combat_scene.md)。立ち絵は静止で、動きはシェイク・フラッシュ・攻撃エフェクトで付ける。音はその3つに寄り添う。

| event_id | 鳴る瞬間 | 素材 | 望まれる音 |
|---|---|---|---|
| `cmb_open` | 開幕（背景＋両隊列が出る） | 専用 | 場面転換の空気。弦の短いスウェル＋構える金属 |
| `cmb_attack` | 攻撃の瞬間。近接は振る瞬間、遠距離は放つ瞬間 | 専用 | 武器の音。下記の動的解決 |
| `cmb_hit` | 飛び道具が着弾した瞬間 | 専用 | 遠距離だけ。近接では鳴らない。下記の動的解決 |

どちらも一撃ごとに鳴る＝攻撃側の一撃でも反撃の一撃でも同じ規則で鳴る。近接どうしで反撃があれば2音、遠距離どうしなら最大4音。

近接に着弾音を置かないのは、振る瞬間と当たる瞬間が事実上同時だから。両者の間隔は `(発数-1) × STAGGER` しかなく、1体同士なら 0 秒になる。分けても2音が重なって潰れるだけで、代わりに得られる情報も無い。

演出のスキップは `ui_cancel` を共用する。

## 動的解決

発火点1つに対して素材が複数あるものは、既存データや戦闘結果をキーにして引く。

### 攻撃エフェクト

攻撃エフェクトはスキンごとに決める。全スキンに個別の音を作ると量が過大になるため、エフェクトの種類を決めてスキンから参照する。エフェクトIDは絵と音の共通キーとし、同じIDで `combat_effect` の画像と `assets/sfx/{effect_id}.ogg` の両方を解決する（エフェクト＝絵と音のセット）。

`unit_skin.csv` のエフェクトID列から素材を引く。種類は斬撃・打撃・刺突・射撃・魔法などの系統に、威力の段階（小・中・大）を掛けた粒度で持つ。実際のカタログは絵の制作と同時に決める（音だけ先に決めない）。

素材はエフェクトの出し方（`kind`）と損害の値で引く。損害は domain が算出した値をそのまま見る。

| kind | `cmb_attack` | `cmb_hit` |
|---|---|---|
| `impact`（近接） | 損害0なら `cmb_hit_none`、それ以外は `{effect_id}` | 鳴らさない |
| `projectile`（遠距離） | 損害によらず `{effect_id}` | 損害0なら `cmb_hit_none`、それ以外は `{effect_id}_hit` |

`cmb_hit_none` は武器によらず常に同じ1つ。弾かれた＝効かなかったことだけを表す。

損害0だけを分ける。減少と全滅は音で区別しない。どちらも隊列・数字・兵量バーが伝えており、音を足しても情報が増えないため。効かなかったことだけは、殴った側の判断が外れたという意味を持つので耳で分かる価値がある。

近接で損害0のときに武器音が弾き返し音へ置き換わるのは、振る瞬間と当たる瞬間が同時だから成立する。振ってから鎧で弾かれるまでが1音に収まる。

### 移動音

`map_move` は `unit_type.csv` の `move_type` から引く。ただし移動タイプは地形コストの都合で分かれており、音としては集約される。

| move_type | sfx_id | 音の系統 |
|---|---|---|
| `ground` / `forest_walk` / `bush_walk` / `mountain_walk` | `move_ground` | 足音（重） |
| `light_foot` | `move_light_foot` | 足音（軽） |
| `flight` | `move_flight` | 羽ばたき |
| `fixed` | （無し） | 無音（移動しない） |

1マス踏むごとに1回鳴らす。移動アニメは1マス 0.12 秒だが、経路が長いと上限（`MOVE_ANIM_MAX_SEC`）に収めるため1マスあたりが縮む。縮んだぶんは `SfxPlayer` の連射間引き（`REPEAT_GUARD_SEC`）が受け止めるので、機関銃にはならない。

蹄・車輪など個別の音が要るユニットが出たら、攻撃エフェクトと同じくスキン側の指定で上書きする。既定は移動タイプから、必要な駒だけ個別に、という順序を守る。

## 調達方針

素材の性質で手段を分ける。BGM の二段構えと同じ発想。

- 楽音（占領・ターン切替・陣形など）: MuseScore ＋ Muse Sounds で自作する。権利は完全に自作物になり、追加コストはゼロ。`victory` / `defeat` スティンガーで実証済みの手順がそのまま使える。
- 物音（攻撃・移動・扉や板の手触り）: オーケストラ音源では出ないため外部から調達する。帰属表記の管理を最小化するため CC0 を軸にし、身近な物での自録り（フォーリー）も併用する。

境目は音の材質で決まる。低く長い余韻や和音が要るものはオーケストラの得意分野なので、物音に見えても楽音側に置く。逆に金属の擦れや足音は音源から出ないので外から取る。

楽器の役割は BGM と共有する（[tracks.md](tracks.md) の横断方針）。フルート＝主役の声、ホルン＝威厳と力、グロッケン＝きらめき、チューブラーベル＝死と神域、ティンパニ＝重心。曲と関わる場面の音（占領・陣形など）では同じ割り当てを守ることで、単発の音が曲と喧嘩しない。

### 基本音は無音程の打楽器で作る

基本音だけは上と方針が違う。旋律楽器を使わず、音程を持たない打楽器で作る。理由は2つ。

トラックライブラリは調をムードごとに散らしている（ニ長調・ロ短調・ホ短調・ト短調・イ短調ドリア・ホフリジア・ニフリジアンドミナント・ハ短調・嬰ヘ短調）。**音程のある確定音は、そのうち何曲かとは必ずぶつかる。** 特定の調に寄せても解決しない＝多調のライブラリと有音程のUI音は原理的に両立しない。無音程ならこの問題自体が消える。

もう一つは立ち上がり。旋律楽器は発音が遅い。フルートで試作した確定音は発音からピークまで245ms、100ms 時点でまだピークの30%で、クリックと音がズレて感じた。打楽器なら数ms で立ち上がる。

主役を張らない音なので、メロディを邪魔しないことが最優先になる。木質の打楽器（ウッドブロック等）はセレクト画面の依頼ボードとも素材感が合う。低い音ほど余韻が伸びるため、乾いた音が欲しければ音程を上げる。

基本音は使用頻度が突出して高いため、ここだけは時間をかけて作り込む。曲を1本足すより体験への効き目が大きい。

`ui_cancel` だけはこの方針の例外で、フルートの下行3音（シ・ラ・ソ）を採っている。立ち上がりは実測 249ms と他の基本音（0〜4ms）より遅いが、キャンセルは咎めない音であることを優先した。作り直さない。

### 音量は MuseScore で作る

BGM と同じ流儀に揃える（[bgm.md](bgm.md)）。音量はミキサーの master フェーダーで決め、ツールは触らない。フェーダーは書き出しに 1:1 で反映される（実測: 書き出しが -20.4 dBFS の素材で master を +11.4 にすると -9.0 dBFS）。手順は「フェーダー 0 で一度書き出す → 測る → 基準との差をフェーダーに入れて書き出し直す」の2回で決まる。

基準はピーク -9 dBFS。理由は2つ。

- BGM のピークは実測 -11〜-12 dBFS。-9 なら曲の 2〜3 dB 上に乗り、UI 音が曲を突き抜けて聞こえる。
- `SfxPlayer` のプールは8声。無関係な波形どうしの合算は 10log₁₀(N) で効くので、-9 の素材が8つ重なっても合計はおよそ 0 dBFS。天井にちょうど収まる。

用途によって基準から外してよい。外した素材は `gen_sfx.ps1` の `$IntendedPeak` に狙いの値を書いて記録する。書かないと、後から見た者が「ずれている」と判断して基準へ戻してしまう。現在の例外は `ui_hover` の -11 dBFS で、ホバーと文字送りで鳴り続けるため他より控えめに置いている。

### 外部素材はゲインを当てて合わせる

上の「ツールは触らない」は自作素材の話。外部素材にはフェーダーが無いので、切り出しの段階でゲインを当てて基準に寄せる。フェーダーの設定ミスを隠す心配は、そもそもフェーダーが無いため起きない。

かわりにレシピを残す。`assets/sfx-src/{sfx_id}_recipe.txt` に、原本から `{sfx_id}.wav` を作った ffmpeg のコマンドをそのまま1行で書く。地形タイルの `{skin_id}_recipe.txt` と同じ流儀（[../art/terrain.md](../art/terrain.md)）で、狙いも同じ。切り出し位置とゲイン量は素材ごとに実測して決めるため、残さないと作り直しのたびに測り直しになる。どの原本を使ったかもレシピが示す。

```
ffmpeg -y -i "sonniss/2026/magic_bolt__WINDDsgn_....wav" -af "atrim=0.02:0.60,volume=6.8dB" -c:a pcm_s24le magic_bolt.wav
```

`atrim` が切り出し、`volume` がゲイン。`-c:a pcm_s24le` は必須で、付けないと ffmpeg が 16bit に落とす。原本は 96〜192kHz / 24bit なので、ogg にする前にここで削る意味はない。

ゲインの値は `.wav` を -9 dBFS に合わせるのではなく、`gen_sfx.ps1` が測る `.ogg` の値で追い込む。符号化でピークが上がるためで、実測では最大 2.2 dB 動いた（`.wav` を -9.0 に揃えて出した ogg が -6.8）。手順は自作素材と同じ2回で、レシピのゲインを 0 で一度出す → 測る → 差をレシピに入れて出し直す。

参照する原本は必ず `sonniss/<年>/` に置いたものにする。試聴用に切った中間ファイルを指すと、それを消した時点で再現できなくなる。

原本は無加工のまま残す。レシピは `.txt` なのでコミットされ、`.wav` は両方とも gitignore で残らない。つまりリポジトリには「どう作ったか」だけが残り、再配布不可の素材そのものは入らない。

ベロシティで音量を変えない。打楽器では強打サンプルに切り替わり、音量ではなく音色が変わる。フェーダーは純粋な音量なのでこの問題がない。

揃える指標は BGM と違う。BGM は統合ラウドネス（-23 LUFS）、効果音はピーク（dBFS）。統合ラウドネスは 400ms のブロックにゲートを掛けて求めるため、1秒未満の音では成立しない（実測: 0.40秒の `ui_cancel` は -70 LUFS ＝「該当するブロック無し」を返す）。

### 書き出しの後処理

MuseScore から書き出した `.wav` は、そのままでは使えない。`tools/gen_sfx.ps1` が2工程を処理する。

```
powershell -File tools\gen_sfx.ps1 ui_confirm ui_cancel ui_denied ui_hover
```

- 前後の無音を切る。MuseScore は譜面の長さぶん余白を付けるため、0.3秒の打撃音が3.5秒のファイルになる。末尾の無音は鳴り終わった後もプールの発音枠を占有し、先頭の無音は入力の遅れとして聞こえる。
- Ogg Vorbis に変換する。エンコーダを libvorbis に固定してあるので Opus の罠を踏めない。変換後にコーデックを検証する。

音量には触らない。書き出した `.ogg` のピークを測り、基準から外れていれば警告するだけに留める（黙って直すとフェーダーの設定ミスが見えなくなる）。

場面ごとのバランスはこのスクリプトの仕事ではなく、下記のバスで取る（書き出し直さずに調整できる）。

### 物音の素材候補

物音系の素材プールは Sonniss GDC バンドル（[sonniss.md](sonniss.md)）。索引を `sfx_id` ごとに引いた結果を候補として残す。

採否が決まったら、その `sfx_id` の候補を1つに絞り、`assets/sfx-src/credits.md` に出典を記録する。候補の列が消えて素材が1つ書かれている状態が、決まった印になる。

場所の表記は「年 パート番号 / ライブラリ名」。zip の URL は products 側の `raw/<年>_<パート>.json` にある。

移動音（`map_move`、移動タイプごとの動的解決）。

| move_type | 候補 | 場所 |
|---|---|---|
| `ground` 系 | `237_Foley_Footsteps_Metal_Boot_Walk_Normal_Close.wav` | 2017 p8 / Tovusound - Edward Foleyart Add-On Extended Footsteps |
| | `FS Metal Soldier Walk N01.wav` | 2016 p2 / Levan Nadashvili - Soldier Footsteps |
| | `PM_SDNG_Single_Step_Footstep_19.wav` | 2019 p3 / PMSFX - STEPS Dirt & Gravel |
| | `PM_SDGS_14 Footstep Step Dry Grass Shrubs Pine Needles Meadow .wav` | 2020 p5 / PMSFX - STEPS Dry Grass & Shrubs |
| `light_foot` | `FS Ground Civilian Walk N03.wav` | 2016 p2 / Levan Nadashvili - Civilian Footsteps |
| | `FS Wood Civilian Crouch N03.wav` | 2016 p2 / 同上 |
| | `169_Foley_Footsteps_Grass_Sneaker_Walk_Fast_Run_Jog_Close.wav` | 2017 p8 / Tovusound - Extended Footsteps |
| `flight` | 適当な素材が無い。下記 | |

金属床のブーツを名前で明示しているのは Tovusound と Levan Nadashvili の2つだけ。土・草は PMSFX が単発ステップを出しているため踏むたびに鳴らす用途に向く。Levan Nadashvili は Soldier（重）と Civilian（軽）が同じ収録で対になっており、重い足音と軽い足音の音色差を揃えやすい。

弾き返す音（`cmb_hit_none`）。損害0のとき、近接でも遠距離でも、武器によらずこれ1つだけを鳴らす。

| 素材 | 場所 |
|---|---|
| `Weapon_Impact_Parry_01.wav` | 2017 p3 / Double Trouble Audio - Medieval Armor and Impacts |

試聴して決めた。同じライブラリの `Plate_Impact_Hard_02.wav`（板金鎧）と `Chainmail_Impact_Hard_03.wav`（鎖帷子）は不採用。

血肉系（Gore）のライブラリも各年にあるが、作風に対して生々しすぎるため候補から外した。

攻撃エフェクトの音。エフェクトIDは絵と音の共通キーなので、候補も [combat_effect.csv](../../data/effects/combat_effect.csv) の `effect_id` で並べる。

| effect_id | 候補 | 場所 |
|---|---|---|
| `slash_s` | `WEAPSwrd_Sword Slide Cuts, Metallic, Impact CM4 2_344 Audio_Medieval Weapons Vol 2.wav` | 2026 p1 / 344 Audio - Historical Weapons Vol. 2 |
| `slash_m` | `METLFric_SWING SCRAPE Swift Melee Weapon Swing With A Long Blade 14_DDUMAIS_MWP2.wav` | 2026 p2 / David Dumais Audio - Melee Weapons Pack 2 |
| `slash_l` | `MeleeSwingsPack_96khz_Mono_DesignedSwings12.wav` | 2020 p3 / David Dumais Audio - Weapon Sounds - Weapon Swings |
| `arrow` | `MELEE - CK - ROPE WHOOSH Fast Light 01.wav` の6テイク目 | 2019 p5 / Rock The Speakerbox - Melee |
| `arrow_bone` | 同上（矢と呪いの矢は発射も着弾も共用する） | 2019 p5 / 同上 |
| `stone` | 同ファイルの3テイク目 | 2019 p5 / 同上 |
| `arrow_hit` | `BOW Arrow Hit 05.wav` | 2020 p9 / SmartSoundFX – Medieval |
| `arrow_bone_hit` | 同上 | 2020 p9 / 同上 |
| `stone_hit` | `PM_RI_Source_92 Rocks Impact Hit Single Stone.wav` | 2020 p5 / PMSFX - Rocky Impacts |
| `magic_bolt` | `WINDDsgn_Wind, Rush, Whoosh, Long x5 01_344 Audio_Elemental Palette Designed Vol 1.wav` | 2026 p1 / 344 Audio - Elemental Palette Designed Vol. 1 |
| `curse` | `Dark_Spell_Life_Tap_03.wav` | 2019 p5 / Sound Spark LLC – Magic Spells, Buffs and Attacks |
| `punch` | `MELEE - DESIGNED - HEADBUTT Crack.wav` の2テイク目 | 2019 p5 / Rock The Speakerbox - Melee |
| `holy` | `Button Arp Twinkle.wav` | 2026 p2 / Cinematic Sound Design - User Interface |

すべて試聴して決めた。

飛び道具3種の発射は同じ「ロープを速く振る」収録の別テイク。スリングは実際に紐を振り回して投げるものなので、投石にはこれが直接あたる。弓の発射も、弦の弾ける音より風切りのほうが飛んでいく感じが出た（弓の収録＝2019 p2 Eiravaein Works - Nocked は試聴して不採用）。

`claw` と `magic_bolt_hit` は未定。索引を claw で引いて出るのは動物の足音ライブラリだけなので、布や革を裂く音から作ることになる。

`magic_bolt`（魔弾＝青白い魔力の弾・projectile）はエネルギーが飛ぶ音を当てる。ソニックブームのように空気を裂いて通り過ぎる質感。試聴して決めた。

`holy`（聖光＝近接の聖なる一撃・impact）はキラキラした音を当てる。伸びる魔法音ではなく、粒が立つ短い音。試聴して決めた。`MAGAngl`（Angelic）が付いた Fantasy Game 2 は、明るい一撃ではなく水魔法・回復系に聞こえたため外した。名前に Bright / Positive とあっても実体は柔らかく伸びる音であることが多く、同じ理由で `Buff_Positive` 系も期待しにくい。狙うのは風鈴・鈴・アルペジオのほう。

`curse` `claw` `punch` `arrow_bone` は未探索。

### 遠距離の発射音からは着弾を落とす

外部素材は「飛んで当たる」までを1ファイルに収めていることが多い。遠距離（`projectile`）の発射音に採るときは着弾を切り落とす。着弾は `{effect_id}_hit` で別に鳴るため、含めると二重になる。

近接（`impact`）は着弾音を持たないので、この制約は掛からない。接触まで入っていても振り抜くだけでも構わない。

`magic_bolt` に採った素材は 1.05 秒に飛翔（0.03〜0.60秒）と着弾（0.60〜1.02秒）が入っていたため、飛翔だけを切り出した。落とした着弾部分は原本に残っているので、`magic_bolt_hit` の素材にそのまま使える。

盤の操作。

| event_id | 候補 | 場所 |
|---|---|---|
| `map_capture` | `CLOTHFlp_Action Inventory Open Flip Cloth Canvas Bag Slide Light 02_ESM_FG2.wav` | 2026 p2 / Epic Stock Media - Fantasy Game 2 |
| `map_board` | `WOODImpt_Impact Wood 23_DDUMAIS_NONE.wav` | 2023 p2 / David Dumais Audio - Melee Weapons Pack 1 |
| | `WOODImpt_Drops20_InMotionAudio_Wood.wav` | 2024 p2 / InMotionAudio - Wood |
| | `EFX CTM Floor Board Creak 03 A.wav`（軋み） | 2019 p2 / Coll Anderson - House Library Add Ons |

`map_capture` は楽音（チューブラーベル）と布音を重ねる設計なので、布側だけをここから取る。採用したのは布バッグを開く 0.7 秒の音で、旗の録音ではない。それでも旗が翻る質感として通ると試聴で判断した。バンドル内に旗そのものの録音は無い。

`map_board` は木の打撃音に軋みを重ねて作る。輸送ユニットの移動音を将来個別に持たせる場合は、2023 p2 の Dramatic Cat - Horse Carriage に `VEHWagn_Wood Cart Roll On Stone Pavement In Courtyard 03`（荷馬車が石畳を進む音）と馬の足音が揃っている。

### バンドルで賄えないもの

探して見つからなかったものを記録する。次に探すときの手がかりになる。

- 羽ばたき（`map_move` の `flight`）。実用になるのは 2019 p6 / Soundmind - Predatory Birds の `PRB315 Northern Goshawk` 1本だけで、鳴き声と羽ばたきが同一ファイルに同居しており切り出しが要る。`map_capture` に採用した布の音を短く切って連打するほうが早い。
- 投石の発射音。古代のスリング（投げ紐）は無い。近いのは 2018 p3 / Eiravaein Works - Vaeyan IV のゴム式パチンコ1本だが音が違う。布を鋭く振る音を自録りするのが現実的。着弾側は候補が揃っている。
- 旗のはためき単体。録音そのものが無いため、布の小物音で代用する（`map_capture` で採用済み）。

## データ形式・ディレクトリ

BGM（`bgm` / `bgm-src`）・絵（`units` / `units-src`）と同型で対を作る。

```
assets/
  sfx/                  ← ゲーム用 .ogg（Godot が読む）
    ui_confirm.ogg
    ui_confirm.ogg.import
  sfx-src/              ← 制作元（.gdignore を置いて Godot のスキャン対象外にする）
    .gdignore
    ui_confirm.mscz     ← 楽音系の原本
    ui_confirm.wav      ← gen_sfx.ps1 の入力（コミットしない）
    slash_s.wav         ← 物音系も同じ位置に置く。原本ではなく1テイクに絞ったもの
    credits.md          ← 権利・ライセンス台帳
    sonniss/2026/       ← 外部素材の原本。無加工・多テイクのまま（コミットしない）
    sonniss/trash/2026/ ← 試聴して不採用にしたもの。消さずに残す
data/audio/
  sfx.csv               ← 素材台帳（sfx_id・種別・状態・出典・ライセンス）
  sfx_bind.csv          ← 対応表（event_id → sfx_id）
```

- 外部素材は3段で持つ。原本（`sonniss/<年>/`）→ 1テイクに絞ったもの（`sfx-src/{sfx_id}.wav`）→ ゲーム用（`sfx/{sfx_id}.ogg`）。絵の `_01_raw` → `_03_master` → `assets/units/` と同型。原本は多テイクの詰め合わせであることが多く、そのままでは鳴らせない。どちらの `.wav` も gitignore 済みで、Sonniss の素材は再配布不可なのでコミットしてはいけない。
- 形式は `.ogg`（Ogg Vorbis 限定）。同じ拡張子でも Ogg Opus は Godot が読めないため、書き出し時にコーデックを確認する（[bgm.md](bgm.md) と同じ罠）。
- 効果音はループしない。`.import` の `loop` は false のままでよい。
- 短い音が多く尺が総じて軽いため、圧縮率は BGM ほど攻めなくてよい。歯切れが鈍るようなら `.wav` のまま載せる判断もありうる。
- 表形式のデータは CSV を正本にし、`.csv` は importer=keep を必ず設定する（翻訳CSVと取り違えると壊れる）。

## レイヤー配置

BGM（[bgm.md](bgm.md)）と同じ責務分担に揃える。音の再生は presentation、鳴らす判断は application、`domain` / `data` は音を知らない（[../tech/architecture.md](../tech/architecture.md)）。

| レイヤー | 実体 | 責務 |
|---|---|---|
| `data` | `data/audio/sfx_catalog.gd` | 素材カタログと対応表の読み取り（`event_id` → `sfx_id` 解決・autowire）。純ロジック |
| `application` | — | 動的解決の引数（エフェクトID・移動タイプ）を渡す |
| `presentation` | `presentation/ui/sfx_player.gd` | `AudioStreamPlayer` のプール。ID を受けて鳴らすだけ |

`domain` は事実をシグナルで発火するだけで、音の存在を知らない（BGM の危機切替と同じ流儀）。

## 同時再生の扱い

効果音は BGM と違い重なる。破綻を防ぐ最低限の決まりを置く。

- バス構成は `Master → Music / SFX`（`default_bus_layout.tres`）。`BgmPlayer` は Music、`SfxPlayer` は SFX へ送る。素材の音量は書き出し時に揃えてあるので、ここは場面ごとのバランスと設定画面の音量スライダーの受け皿になる。
- 同一 `sfx_id` が極短時間に連続した場合は間引く。`ui_hover` はホバーと文字送りの両方で鳴るため、ここが効く。
- 1ターンに複数の戦闘が連続する場合（[../tech/combat_scene.md](../tech/combat_scene.md) のキュー処理）は、演出の短縮に合わせて音も減らす。演出オフの設定でも決着の音は残す。

BGM に重ねたときの被り具合は `sound_check` で確かめる（[../tech/tools.md](../tech/tools.md)）。素材と発火点の両方を鳴らせて、素材が未配置の発火点も一覧で分かる。

## 権利・ライセンス台帳

商用（Steam）前提。BGM と同じく、使った素材は台帳（`assets/sfx-src/credits.md`）に記録する。記録項目は [bgm.md](bgm.md) の権利台帳に準じる（用途・出典・入手形式・ライセンス・改変度）。自作の楽音系も「自作」と明記して、外部素材との区別を残す。

表記が必要な素材は、Steam ページとゲーム内クレジットにまとめて記載する。表記文はライセンスの指定文をそのまま使う。
