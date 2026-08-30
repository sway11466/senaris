# CLAUDE.md

**Senaris** — Nectaris（Military Madness）系のヘックス制ターン戦術 SLG を、ファンタジー舞台でオリジナル化した趣味プロジェクト。生産で拡大せず、与えられた戦力を盤面で噛み合わせて勝つ。コンセプト詳細 → [doc/concepts.md](doc/concepts.md)

## 開発上の制約（重要）

- **実装着手はオーナーの明示的な許可後。** 設計・ドキュメント作業は随時OK。
- **git 操作は都度許可を取る。**
- ブランチは **main**（master は使わない）。
- **セッション開始時にリモートとの差分を確認する。** mainブランチの場合、`git fetch origin main` で差分があればオーナーに報告する。
- **仕様駆動（spec-anchored）で進める。** doc が現時点の仕様、実装はこれに従う。ただし面白さが上位で、仕様が面白さに反すれば仕様を変える。詳細 → [doc/tech/development.md](doc/tech/development.md)

## 説明の仕方

オーナーが分かっている前提で話を進めない。専門用語・数値指標・略号は、初めて出すときにそれが何を指すのかを説明してから使う。用語を避けて曖昧にするのではなく、説明したうえで正確な用語のまま使う。

音楽・絵・音響など、オーナーが専門でない領域でとくに守る。プログラミングは説明なしで専門用語を使ってよい。

## 技術スタック

- **エンジン**: Godot 4（GDScript・型付き）。盤は3Dハイブリッド描画＝2Dアセット流用（[doc/adr/ADR-0003-board-3d-hybrid.md](doc/adr/ADR-0003-board-3d-hybrid.md)）。テストは GUT。
- **配置**: Godot プロジェクトは `godot/`（`res://` はここ）。`doc/` と `channels/`（Steam・itch・サイトへ出す素材）はその外。
- **レイヤー**: `presentation → application → domain → data` の一方向依存。`domain` / `data` は Godot ノード非依存（純ロジック）。詳細 → [doc/tech/architecture.md](doc/tech/architecture.md)
- **配布**: まず Steam（PC）。モバイルは後回し。

## ドキュメント

### 全体

- [doc/concepts.md](doc/concepts.md) — プロダクトコンセプト（何を・なぜ・面白さの核）
- [doc/backlog.md](doc/backlog.md) — 「必要になったら着手」する作業の置き場

### ゲームデザイン — `gdd/`

- [doc/gdd/combat.md](doc/gdd/combat.md) — 戦闘解決（補正チェーン・陣形スキル）
- [doc/gdd/formations.md](doc/gdd/formations.md) — 陣形スキル（レシピ・カタログ）
- [doc/gdd/skills.md](doc/gdd/skills.md) — ユニットスキル（発動者1体で撃つ。仕組みは陣形スキルと共通）
- [doc/gdd/units.md](doc/gdd/units.md) — ユニット性能設計・対応表
- [doc/gdd/movement.md](doc/gdd/movement.md) — 移動タイプ・地形コスト・reachable
- [doc/gdd/terrain.md](doc/gdd/terrain.md) — 地形（タイプとスキン・足場とオブジェクト・盤の高さ）
- [doc/gdd/map.md](doc/gdd/map.md) — 拠点・占領・ステージデータ・ターン
- [doc/gdd/map_patterns.md](doc/gdd/map_patterns.md) — マップの型（パターンカタログ）・難易度の表し方・ステージ一覧
- [doc/gdd/campaigns.md](doc/gdd/campaigns.md) — 冒険譚（単位と用語・ステージの束ね方・戦力供給モデル＝独立／継承・名簿）
- [doc/gdd/title.md](doc/gdd/title.md) — タイトル画面（入店の動画・店内のメニュー・項目と行き先）
- [doc/gdd/stage_select.md](doc/gdd/stage_select.md) — ステージセレクト（カードUI・解放条件・クリア記録・冒険譚マニフェスト）
- [doc/gdd/settings.md](doc/gdd/settings.md) — 設定画面（開き口・見せ方・言語の選び方）
- [doc/gdd/manual.md](doc/gdd/manual.md) — ゲーム内マニュアル（章構成・画面・本文の持ち方）
- [doc/gdd/ai.md](doc/gdd/ai.md) — 敵AI（特性ごとの行動開始条件・行動ルール・部隊割り当て）
- [doc/gdd/rank.md](doc/gdd/rank.md) — 評価ランク（S/A/B の判定・閾値・記録）
- [doc/gdd/uiux.md](doc/gdd/uiux.md) — UI/UX 操作モデル（選択→移動→コマンド・デバイス別操作・カメラ）
- [doc/gdd/world.md](doc/gdd/world.md) — 世界観・設定

### 冒険譚（キャンペーン） — `campaign/`

共通の制作方針は [doc/campaign/authoring.md](doc/campaign/authoring.md)。各冒険譚は `gdd/` の仕様を土台にし、関係する箇所だけ本文でリンクする。

- [doc/campaign/roadmap.md](doc/campaign/roadmap.md) — キャンペーン全体の難易度帯・制作状況（一覧・入口）
- [doc/campaign/authoring.md](doc/campaign/authoring.md) — 冒険譚の制作方針（共通：会話パート・書式 ほか）
- [doc/campaign/tutorial1-goblin-raid.md](doc/campaign/tutorial1-goblin-raid.md) — チュートリアル１「ゴブリンの襲撃」全7ステージ（基礎：移動・地形・包囲・支援・間接・占領・釣り）
- [doc/campaign/tutorial2-undead-rush.md](doc/campaign/tutorial2-undead-rush.md) — チュートリアル２「アンデッドの群れ」全7ステージ（陣形スキル・輸送・魔法兵／ボス＝ネクロマンサー）
- [doc/campaign/tutorial3-dragon-hunt.md](doc/campaign/tutorial3-dragon-hunt.md) — チュートリアル３「竜狩り」（飛行・対空／継承carryover／中立拠点／回復拠点・泉／ボス＝ドラゴン）
- [doc/campaign/twingods.md](doc/campaign/twingods.md) — 邪神三部作「双子の神」共通設定（秩序と混沌・前史・冒険者一行・2人の聖女・悪役）
- [doc/campaign/twingods1-cult-stirrings.md](doc/campaign/twingods1-cult-stirrings.md) — 三部作 第1部「邪神徒の蠢き」（かけだし向け・街／追跡もの）
- [doc/campaign/twingods2-hidden-temple.md](doc/campaign/twingods2-hidden-temple.md) — 三部作 第2部「邪神の神殿」（中堅向け・国家／迷いの森と護衛戦）
- [doc/campaign/twingods3-advent.md](doc/campaign/twingods3-advent.md) — 三部作 第3部「邪神復活」（ベテラン向け・世界／潜入と分岐）

### 技術設計 — `tech/`（Technical Design Document）

- [doc/tech/development.md](doc/tech/development.md) — 開発の進め方（仕様駆動・何が錨か・変更の順序・ドリフト検出）
- [doc/tech/tools.md](doc/tech/tools.md) — 開発ツール索引（`godot/tools/` の画面ツール・生成スクリプト・起動方法）
- [doc/tech/architecture.md](doc/tech/architecture.md) — レイヤー／モジュール構成・依存ルール
- [doc/tech/build.md](doc/tech/build.md) — 配布ビルド（プリセット・チャネルと版の識別・同梱物の決め方・ビルドの手順）
- [doc/tech/gamesystem.md](doc/tech/gamesystem.md) — ゲームシステム仕様（セーブ ほか）
- [doc/tech/combat_scene.md](doc/tech/combat_scene.md) — 戦闘演出シーン（左右固定・兵数→隊列・シェイク/フラッシュ/攻撃エフェクト）
- [doc/tech/testing.md](doc/tech/testing.md) — テスト方針（目的・レイヤー別の線引き・運用・実行方法）
- [doc/tech/i18n.md](doc/tech/i18n.md) — 多言語対応（対応言語・翻訳CSV運用・キー命名・表示名の扱い）
- [doc/tech/debug-stages.md](doc/tech/debug-stages.md) — デバッグステージ一覧（機能別7カテゴリ）

### アート — `art/`（Art Bible）

- [doc/art/direction.md](doc/art/direction.md) — アートの全体方針（絵柄・陣営配色・共通メソッド）
- [doc/art/units.md](doc/art/units.md) — ユニットの見た目方針（共通ルール・陣営ごと・制作スペック・STYLE）
- [doc/art/terrain.md](doc/art/terrain.md) — 地形タイルの方針（TERRAIN STYLE・切り抜き・反復対策）
- [doc/art/backdrop.md](doc/art/backdrop.md) — 奥の背景の方針（戦闘窓の水平線から上・空／岩壁・BACKDROP STYLE）
- [doc/art/keyvisual.md](doc/art/keyvisual.md) — 扉絵・キービジュアルの方針（ILLUST STYLE・透かし対策）
- [doc/art/menu.md](doc/art/menu.md) — メニュー画面の材質（木壁・依頼ボード・羊皮紙・ナインパッチ）
- [doc/art/ui.md](doc/art/ui.md) — UIアイコンの方針（ICON STYLE・額・保管と書き出し）
- [doc/art/logo.md](doc/art/logo.md) — ロゴ（モチーフ・配色・寸法・作り方）
- [doc/art/icon.md](doc/art/icon.md) — アプリアイコン（寸法で使い分ける2つの紋章・保管と書き出し・プロジェクトへの指定）
- [doc/art/overview.md](doc/art/overview.md) — 画像スロット仕様（`map`/`combat`）

### サウンド — `audio/`（Audio Bible）

- [doc/audio/bgm.md](doc/audio/bgm.md) — BGM（制作方針＝二段構え・MuseScore・トラックライブラリ＝ムード別に使い回し・管理運用＝autowire／ステージJSON指定・権利台帳）
- [doc/audio/tracks.md](doc/audio/tracks.md) — トラック設計ノート（各曲の狙い・音楽的設計・参考にした語法・調整の勘所）
- [doc/audio/sfx.md](doc/audio/sfx.md) — 効果音（二層管理＝素材／発火点・発火点カタログ＝メニュー/マップ/戦闘・動的解決・調達方針・物音の素材候補）
- [doc/audio/sonniss.md](doc/audio/sonniss.md) — Sonniss GDC バンドル索引（物音系の素材プール・索引の読み方・入手元・検証）

### 販売・ブランド — `sales/`

- [doc/sales/monetization.md](doc/sales/monetization.md) — 体験版/製品版・DLC・有料データ保護・販売チャネル・AI 生成コンテンツの開示
- [doc/sales/marketing.md](doc/sales/marketing.md) — マーケティング（届ける相手・素材の方針＝要素ごとの仕事・英語の本文の正本・素材の置き場・チャネルの方針＝Steam／itch／サイト／SNS）
- [doc/sales/credits.md](doc/sales/credits.md) — クレジット・第三者権利の正本（ライセンス別の一覧・クレジット画面に出すもの・ビルドから外すもの）
- [doc/sales/naming_decision_senaris.md](doc/sales/naming_decision_senaris.md) — タイトル名「Senaris」の決定
- [doc/sales/site.md](doc/sales/site.md) — 公式サイト senaris.in（役割・ページ・言語・素材・配信構成・ドメイン運用）
- [doc/sales/steam_page.md](doc/sales/steam_page.md) — Steam のストアページ（動画の順・AI 生成の開示）
- [doc/sales/itch_page.md](doc/sales/itch_page.md) — itch のプロジェクトページ（ページの方針・記入内容・本文の HTML 版・更新のたびにやること）
- [doc/sales/itch_devlog.md](doc/sales/itch_devlog.md) — itch の devlog（方針・刻み・原稿の管理）

### 意思決定記録 — `adr/`

- [doc/adr/ADR-0001-adopt-godot.md](doc/adr/ADR-0001-adopt-godot.md) — ゲームエンジンに Godot 4 を採用
- [doc/adr/ADR-0002-paid-data-protection.md](doc/adr/ADR-0002-paid-data-protection.md) — 有料データの保護（署名＋pck 暗号化）
- [doc/adr/ADR-0003-board-3d-hybrid.md](doc/adr/ADR-0003-board-3d-hybrid.md) — 盤面の描画を3Dハイブリッド（傾けたカメラ＋2Dアセット）に
- [doc/adr/ADR-0004-logo-typeface-ofl.md](doc/adr/ADR-0004-logo-typeface-ofl.md) — ロゴの書体を OFL のフォントから選ぶ（EB Garamond）
- [doc/adr/ADR-0005-site-hosting-cloudflare-workers.md](doc/adr/ADR-0005-site-hosting-cloudflare-workers.md) — サイトの配信に Cloudflare Workers を使う
