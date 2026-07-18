# ステージセレクト

ステージ選択画面と、その裏側の進行管理（解放条件・クリア記録・冒険譚マニフェスト）の設計。[map.md](map.md) で未決だった「冒険譚内のステージ順序・進行管理・ステージ選択」を本ドキュメントが引き受ける。

---

## 要件

- **カード型**でステージが並ぶ一覧画面。
- **未クリア／クリア済み**が一目で識別できる。
- **デバッグステージ**（単発機能を試す専用マップ）を開発中のみ表示できる。
- **選択できる条件（解放条件）** をステージごとに設定できる。基本は「前提ステージのクリア」、将来的には**課金（DLC等）** も条件になる。

---

## 画面フロー

```
タイトル → 冒険譚選択 → ステージセレクト（カード一覧） → ステージ開始
```

- **冒険譚選択**とステージ一覧は別画面とする（冒険譚＝配布・選択の単位。[map.md](map.md) 用語）。冒険譚が2〜3個のうちは1画面に縦積みでも成立するが、増えることを見越して分けておく。
- 冒険譚を選ぶ → その中の**プレイするステージを選ぶ**。クリア済みステージは**すべて選び直せる**（再挑戦）＋次の未クリアステージ（解放済み）が選べる。
- ステージカードを選ぶ → **ステージ詳細（ブリーフィング）** を表示 → 「出撃」で開始。誤タップでいきなり戦闘に入らないよう、開始前にワンクッション置く。

## 戦闘後フロー

戦闘の決着（battle_finished）からの遷移。判断（次に遊べるステージの決定）は application（[campaign_progress.gd](../../application/campaign_progress.gd) の `next_playable_stage`）、画面の切り替えは presentation（[main.gd](../../presentation/main/main.gd)）が担う。

```
勝利 → クリア記録 → outro 会話（あれば） → 次ステージへ自動遷移
                                        └ 次が無い ┬ 完走(最終勝利)＆勝利絵あり → 勝利イラスト → セレクトへ
                                                   └ それ以外 → セレクトへ戻る
敗北 → その場で停止（リスタート／セレクトはシステムメニューから）
```

- 勝利時、セレクト経由で開始したステージならクリアを記録する（デバッグ冒険譚は記録しない）。
- outro 会話があれば盤の操作をロックして流し、読了かスキップで遷移判定へ進む。進むボタンのラベルは次ステージがあれば「次のステージへ ▶」、無ければ「閉じる」。会話が無ければ即判定（テンポ優先）。
- 自動遷移の条件（すべて満たすとき、同じ冒険譚のマニフェスト順で直後のステージを読み込む）:
  - セレクト経由で開始している
  - デバッグ冒険譚でない（単体検証の邪魔になるため自動遷移しない）
  - マニフェスト順で直後のステージが存在する（最終ステージでない）
  - そのステージが locked でない（entitlement 等で止まりうる）
- 満たさない場合はステージセレクトへ戻る。ただし「キャンペーン完走」＝非デバッグ冒険譚の最終ステージ（マニフェスト順で次が無い）を勝利し、その冒険譚に勝利イラスト（`victory` スロット）が在るときは、セレクトへ戻る前に全画面の勝利イラストを1枚挟む（クリック/キーで閉じてセレクトへ）。完走判定は素の `next_stage` が空か（`next_playable_stage` は locked でも空になり最終判定に使えない）。勝利絵の無い冒険譚は従来どおり素通り。演出は [victory_screen.gd](../../presentation/victory/victory_screen.gd)、絵の方針・命名は [../art/keyvisual.md](../art/keyvisual.md)。
- 敗北時は遷移しない。ターン終了を無効化して盤面を残す。再挑戦はシステムメニューのリスタート、離脱は同メニューのステージセレクトで行う。

## 冒険譚カード

上に絵・下に情報帯の縦2段。カードは 340×330（絵 340×210＝黄金比 1.618:1、下に情報帯）。

- 絵（上）: カード用クロップ `assets/campaign/{id}/{id}_card.png` を優先。無ければ扉絵 `{id}_cover.png` にフォールバック（`KEEP_ASPECT_COVERED`＋clip でトリミング表示）。どちらも無ければ暗色プレースホルダ。
- 情報帯（下）: タイトル／難易度★5段階／説明文（3〜4行・自動折り返し＝依頼の紹介）。ステージ数・タグは出さない（進捗はステージ一覧の役目・全クリアは焼き印で伝わる）。
- 難易度はマニフェスト（`campaign.json` の `difficulty`）から。タイトル・説明文は翻訳キー（i18n・後述）を `tr()` で解決。
- クリック判定はカード全面の Button。中身は `mouse_filter=IGNORE` でクリックを Button へ透過する。
- デバッグ冒険譚は絵・星・説明を出さず「（開発ビルド限定）」注記のみ。

絵の管理（cover=大パネル用／card=カード用の二層）とクロップ方針・生成STYLEは [../art/keyvisual.md](../art/keyvisual.md)。

## ステージ一覧（冒険譚選択後）

**ステージはカードにしない**。絵は冒険譚単位で1枚だけ用意する方針＝ステージごとの絵は作らない。

- レイアウト: **左＝選んだ冒険譚の扉絵を最大化表示**（`{id}_cover.png`。`KEEP_ASPECT_COVERED`＋clip でパネル枠にトリミング。絵が無ければタイトルのプレースホルダ）／**右＝ステージの縦リスト**。
- リスト行の中身: **ステージ番号・ステージ名・状態**。並び順はマニフェストの記述順（＝物語順）。

| 状態 | 表示 |
|---|---|
| **未解放（locked）** | グレーアウト＋鍵アイコン。解放条件をテキストで示す（例「st2 クリアで解放」）。選択不可 |
| **未クリア（unlocked）** | 通常表示。ここが「次にやるステージ」 |
| **クリア済み（cleared）** | クリアバッジ（✓）。**常に選択可**＝再挑戦できる |

---

## 見た目（酒場の依頼ボード）

セレクト画面のビジュアルは「酒場に飾られた木の依頼ボード」。冒険譚＝ピン留めした羊皮紙の貼り紙、ステージ＝その各節、という見立て（冒険者への依頼／吟遊詩人の語る冒険譚）。

- 方式は材質だけ画像・構造と光はコードのハイブリッド。木壁・ボード板・羊皮紙・汚しはテクスチャ、枠線・ランタン光・ビネット・封蝋ピン・焼き印スタンプはコードで載せる。画面まるごと1枚の背景にはしない（ボード寸法・ポスター枚数が動くため材質だけ焼く）。
- テクスチャは autowire スロット（`assets/menu/{wall,board,parchment,grunge}.png`）。置けば材質に、無ければプロシージャル／ベタ塗りへフォールバック＝コード不変。実装は [../../presentation/select/tavern_theme.gd](../../presentation/select/tavern_theme.gd)。
- 既存データをテーマ化＝クリア済み→「討伐済」スタンプ／難易度→危険度★（焼き印）。
- 材質テクスチャの生成仕様（サイズ・シームレス条件・ナインパッチ縁幅・色味・インポート設定）→ [../art/menu.md](../art/menu.md)。

## 難易度帯ボード（tier カルーセル）

冒険譚は難易度帯（tier）ごとのボードに分かれ、◁▷ で1枚ずつ繰るカルーセルで見せる。壁に難易度別の依頼ボードが何枚か貼ってある、という見立て。

帯は4つ。ボード名は英語固定（雰囲気優先・多言語化しない）:

| tier | ボード名 | 位置づけ |
|---|---|---|
| tutorial | Tutorial | 操作を覚える導入 |
| rookie | Rookie | 駆け出し |
| adept | Adept | 中堅 |
| veteran | Veteran | ベテラン |

- 難易度★はそのボードの中での相対難易度。tier が粗い難易度・★が細かい難易度＝「Rookie の★4」で一組。★を帯の文脈から切り離してフラットに並べない限り混乱しない（Tutorial★5 と Veteran★1 の絶対比較はプレイヤーがしない比較）。
- 各冒険譚の所属帯は `campaign.json` の `tier`（未指定は rookie）。帯の一覧（4つ）はコード側の定数で固定＝内容でなく構造。
- 空の帯も常に表示（準備中の注記）＝カルーセルで巡れて今後の見通しが見える。ボード自体の解放条件はなし（全帯いつでも閲覧可・中身のステージ解放は従来どおり）。
- Debug ボードはデバッグビルドのみ・先頭（Tutorial の左）に置く。初期表示は最初の実 tier（Tutorial）。
- ボード名は上梁に手書き風フォント（RockSalt・英語）で載せる。
- 材質の棲み分け: 酒場の物（ボード・貼り紙・封蝋）はリアル系テクスチャ、カルーセルのUI（◁▷矢印・現在地ドット）はユーザー視点＝あえて無機質なグレーで描く。→ [../art/menu.md](../art/menu.md)

## 状態モデル

ステージの状態は保存しない。**クリア記録（セーブ）＋解放条件（データ）から毎回導出**する:

```
cleared   … クリア記録にある
unlocked  … 解放条件をすべて満たす（かつ未クリア）
locked    … それ以外
```

## 解放条件（unlock）

勝敗条件（[map.md](map.md) `victory` 配列）と同じ発想で、**条件リストをステージごとにデータで持つ**。ただし評価は **AND**（すべて満たして解放。勝敗の OR と逆なので注意）:

| type | 意味 | 例 |
|---|---|---|
| `cleared` | 指定ステージをクリア済み | `{ "type": "cleared", "stage": "st2" }` |
| `entitlement` | 課金・DLC等の権利を保有（将来） | `{ "type": "entitlement", "id": "campaign2" }` |

- `unlock` 未指定＝無条件で解放（各冒険譚の1面など）。
- `entitlement` の実体（Steam DLC・pck 暗号化）は [../sales/monetization.md](../sales/monetization.md) / [ADR-0002](../adr/ADR-0002-paid-data-protection.md) と接続する。当面は type だけ予約し未実装でよい。

## 冒険譚マニフェスト

冒険譚フォルダに `campaign.json` を置き、ステージの**順序・表示名・解放条件**を持たせる:

```json
{
  "id": "tutorial1-goblin-raid",
  "title": "t1.title",
  "desc": "t1.desc",
  "tier": "tutorial",
  "difficulty": 1,
  "stages": [
    { "id": "st1", "file": "st1.json", "title": "t1.st1.title" },
    { "id": "st2", "file": "st2.json", "title": "t1.st2.title",
      "unlock": [ { "type": "cleared", "stage": "st1" } ] }
  ]
}
```

- `title`・`desc`・stage の `title` は生テキストでなく翻訳キー（i18n・後述）。表示側が `tr()` で解決する（debug 冒険譚の生テキストは `tr()` 素通しで従来どおり出る）。
- ステージ JSON 本体（盤面）には手を入れない。進行・表示のメタはマニフェスト側に寄せる。
- ステージ選択画面は「`data/stages/` 以下の `campaign.json` を列挙 → 各冒険譚のカードを組み立てる」だけで動く。
- カード表示用メタ（任意）: `tier`（所属ボード tutorial/rookie/adept/veteran／未指定は rookie）・`difficulty`（0〜5・範囲外はクランプ／未指定は 0）・`desc`（説明文の翻訳キー／未指定は空＝説明なし）。絵（`cover_path` / `card_path`）は [campaign_catalog.gd](../../data/stages/campaign_catalog.gd) が `assets/campaign/{id}/{id}_{cover,card}.png` の有無で規約解決する（マニフェストに書かない）。

## 多言語化（i18n）

冒険譚名・説明・ステージ名は生テキストを持たず翻訳キーで管理する。会話（dialogue）と同じ CSV→`.translation` パイプライン（`csv_translation` インポータ）に乗せる。

- 正本: `data/i18n/campaigns.csv`（`keys,ja,en` の3列）。ドメイン別に会話（`dialogue.csv`）と分ける。
- キー規約: キャンペーンの短コード接頭辞（例 `t1`）＝会話キーと揃える。`t1.title`／`t1.desc`／`t1.stN.title`。
- 生成物（Godot インポートが作る・git 追跡・手編集しない）: `campaigns.ja/en.translation`＋`campaigns.csv.import`。`project.godot` の `locale/translations` に登録。
- キーは `.translation` 横断でグローバル＝CSV を分けても `tr()` は同じに解決する。CSV を足したら [test_i18n_translation.gd](../../tests/unit/test_i18n_translation.gd)（正本↔生成物の整合＝翻訳コミット漏れガード）の対象にも足す。
- 生成物の仕組み・importer=keep の罠は CSV データパイプラインの方針に従う。

## デバッグステージ

- デバッグ用マップは機能別に6つの **デバッグ冒険譚** へ分ける（`data/stages/debug-combat` / `-ai` / `-victory` / `-mapops` / `-skins` / `-misc`）。各フォルダに `campaign.json`（`"debug": true`）を置く。カテゴリ別の内訳・未実装TODO → [../tech/debug-stages.md](../tech/debug-stages.md)。
- `debug: true` の冒険譚は **デバッグビルドのみ表示**（Godot の `OS.is_debug_build()`）。リリースエクスポートでは自動的に消える。
- デバッグステージは**常時解放・クリア記録なし**（進行に混ぜない）。

## クリア記録（セーブ連携）

- 進捗セーブ（[../tech/gamesystem.md](../tech/gamesystem.md)）に **「冒険譚ID × ステージID → クリア済み」** を持つ。最小はクリアフラグのみ、将来クリア評価（ターン数等）を同じ場所に足す。
- 置き場所は `user://`（例 `user://progress.json`）。**素の JSON でよい**＝進行チートの被害者は本人だけで守る実益がなく、平文の方が調査・バックアップが楽。
- **改ざん対策はセーブ保護ではなく設計規律で担う**: `entitlement`（課金解放）を**セーブに書かない**。解放状態は毎回、所有権チェック（[../sales/monetization.md](../sales/monetization.md) `owns()`）へ聞きに行くので、セーブを書き換えても課金は突破できない。
- ロード時は**バージョンフィールド＋形式チェック → 不正なら新規扱いにフォールバック**（破損・手編集ファイルでクラッシュしない）。
- 戦力継承（carryover・[map.md](map.md) 戦力供給モデル）のスナップショット保存は本ドキュメントの範囲外だが、置き場所はこの進捗セーブと同居になる想定。

---

## 実装レイヤー（[../tech/architecture.md](../tech/architecture.md) 準拠）

| レイヤー | 担当 |
|---|---|
| presentation | ステージセレクト画面（カードUI・画面遷移） |
| application | 進行管理サービス＝マニフェスト読込＋クリア記録＋解放判定（locked/unlocked/cleared の導出） |
| data | `campaign.json`（マニフェスト）・進捗セーブファイル |

domain（戦闘ロジック）には手を入れない。

---

## 実装状況（2026-07-05 時点）

- **実装済み**: 冒険譚マニフェスト（`data/stages/*/campaign.json`・[campaign_catalog.gd](../../data/stages/campaign_catalog.gd)・title/desc(翻訳キー)/tier/difficulty/cover_path/card_path/victory_path を解決）／解放判定（[campaign_progress.gd](../../application/campaign_progress.gd)・cleared のAND評価、entitlement は未充足扱い）／進捗セーブ（[progress_store.gd](../../infrastructure/save/progress_store.gd)・`user://progress.json`・検証フォールバック付き）／セレクト画面（`presentation/select/`＝**2画面に分割**: [select_screen.gd](../../presentation/select/select_screen.gd)（コーディネーター・CanvasLayer・背景と遷移）＞ [campaign_select.gd](../../presentation/select/campaign_select.gd)（キャンペーン選択＝カード＝絵＋情報帯）／[stage_select.gd](../../presentation/select/stage_select.gd)（ステージ選択＝左に扉絵＋右にステージ縦リスト）。起動時に表示、システムメニュー「ステージセレクト」で再表示）／勝利時のクリア記録・戦闘後の自動遷移判定（campaign_progress の `next_playable_stage`）・キャンペーン完走時の勝利イラスト（[victory_screen.gd](../../presentation/victory/victory_screen.gd)・最終ステージ勝利で全画面表示）。
- **難易度帯ボード**: tier カルーセル実装済み（`campaign_select.gd`）。◁▷で帯を繰る／空帯は準備中表示／Debug は先頭／ボード名は RockSalt。UI（矢印・ドット）は無機質グレー。
- **絵**: 冒険譚1の扉絵（cover）実装済み・カード用クロップ（card）は未配置で cover にフォールバック中。
- **未実装**: タイトル画面（起動→直接冒険譚選択）。ブリーフィングは羊皮紙の依頼書ダイアログ（[quest_sheet.gd](../../presentation/select/quest_sheet.gd)）で出撃確認まで＝中身（勝利条件・推奨戦力など）は未決事項参照。
- dev用ステージセレクタ（presentation/dev/）は**削除済み**＝ステージ読み込みはセレクト（＋システムメニューのリスタート）に一本化。デバッグステージは `debug` 冒険譚（`debug:true`）としてセレクトに出す。

## 設計の未確定

決めきれていない設計論点（実作業の追跡は [backlog](../backlog.md)）。

- ステージ詳細（ブリーフィング）に何を出すか（勝利条件・推奨戦力・シナリオ導入など）。
- クリア評価（ターン数・ランク）を記録するか。

## 関連ドキュメント

- [map.md](map.md) — 冒険譚・ステージの用語、ステージデータ構成、戦力供給モデル
- [uiux.md](uiux.md) — 操作モデル（本画面もマウス／タッチ両対応の方針に従う）
- [../tech/gamesystem.md](../tech/gamesystem.md) — セーブ仕様
- [../sales/monetization.md](../sales/monetization.md) — DLC・課金
