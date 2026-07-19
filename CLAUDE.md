# CLAUDE.md

**Senaris** — Nectaris（Military Madness）系のヘックス制ターン戦術 SLG を、ファンタジー舞台でオリジナル化した趣味プロジェクト。生産で拡大せず、与えられた戦力を盤面で噛み合わせて勝つ。コンセプト詳細 → [doc/concepts.md](doc/concepts.md)

## 開発上の制約（重要）

- **実装着手はオーナーの明示的な許可後。** 設計・ドキュメント作業は随時OK。
- **git 操作は都度許可を取る。**
- ブランチは **main**（master は使わない）。

## 技術スタック

- **エンジン**: Godot 4（GDScript・型付き）。盤は3Dハイブリッド描画＝2Dアセット流用（[doc/adr/ADR-0003-board-3d-hybrid.md](doc/adr/ADR-0003-board-3d-hybrid.md)）。テストは GUT。
- **レイヤー**: `presentation → application → domain → data` の一方向依存。`domain` / `data` は Godot ノード非依存（純ロジック）。詳細 → [doc/tech/architecture.md](doc/tech/architecture.md)
- **配布**: まず Steam（PC）。モバイルは後回し。

## ドキュメント

### 全体

- [doc/concepts.md](doc/concepts.md) — プロダクトコンセプト（何を・なぜ・面白さの核）
- [doc/backlog.md](doc/backlog.md) — 「必要になったら着手」する作業の置き場

### ゲームデザイン — `gdd/`

- [doc/gdd/combat.md](doc/gdd/combat.md) — 戦闘解決（補正チェーン・陣形スキル）
- [doc/gdd/formations.md](doc/gdd/formations.md) — 陣形スキル（レシピ・カタログ）
- [doc/gdd/units.md](doc/gdd/units.md) — ユニット性能設計・対応表
- [doc/gdd/movement.md](doc/gdd/movement.md) — 移動タイプ・地形コスト・reachable
- [doc/gdd/map.md](doc/gdd/map.md) — 拠点・占領・ステージ・用語・戦力供給モデル
- [doc/gdd/stage_select.md](doc/gdd/stage_select.md) — ステージセレクト（カードUI・解放条件・クリア記録・冒険譚マニフェスト）
- [doc/gdd/ai.md](doc/gdd/ai.md) — 敵AI（思考パターン＝軸の組み合わせ・部隊割り当て）
- [doc/gdd/uiux.md](doc/gdd/uiux.md) — UI/UX 操作モデル（選択→移動→コマンド・デバイス別操作・カメラ）
- [doc/gdd/world.md](doc/gdd/world.md) — 世界観・設定

### 冒険譚（キャンペーン） — `campaign/`

共通の制作方針は [doc/campaign/authoring.md](doc/campaign/authoring.md)。各冒険譚は `gdd/` の仕様を土台にし、関係する箇所だけ本文でリンクする。

- [doc/campaign/roadmap.md](doc/campaign/roadmap.md) — キャンペーン全体の難易度帯・制作状況（一覧・入口）
- [doc/campaign/authoring.md](doc/campaign/authoring.md) — 冒険譚の制作方針（共通：会話パート・書式 ほか）
- [doc/campaign/tutorial1-goblin-raid.md](doc/campaign/tutorial1-goblin-raid.md) — チュートリアル１「ゴブリンの襲撃」全7ステージ（基礎：移動・地形・包囲・支援・間接・占領・釣り）
- [doc/campaign/tutorial2-undead-rush.md](doc/campaign/tutorial2-undead-rush.md) — チュートリアル２「アンデッドの群れ」全7ステージ（陣形スキル・輸送・魔法兵／ボス＝ネクロマンサー）
- [doc/campaign/tutorial3-dragon-hunt.md](doc/campaign/tutorial3-dragon-hunt.md) — チュートリアル３「竜狩り」（飛行・対空／継承carryover／中立拠点／回復拠点・泉／ボス＝ドラゴン）

### 技術設計 — `tech/`（Technical Design Document）

- [doc/tech/architecture.md](doc/tech/architecture.md) — レイヤー／モジュール構成・依存ルール
- [doc/tech/gamesystem.md](doc/tech/gamesystem.md) — ゲームシステム仕様（セーブ ほか）
- [doc/tech/combat_scene.md](doc/tech/combat_scene.md) — 戦闘演出シーン（左右固定・兵数→隊列・シェイク/フラッシュ/攻撃エフェクト）
- [doc/tech/testing.md](doc/tech/testing.md) — テスト方針（目的・レイヤー別の線引き・運用・実行方法）
- [doc/tech/i18n.md](doc/tech/i18n.md) — 多言語対応（対応言語・翻訳CSV運用・キー命名・表示名の扱い）
- [doc/tech/debug-stages.md](doc/tech/debug-stages.md) — デバッグステージ一覧（機能別6カテゴリ・既存/未実装TODO）

### アート — `art/`（Art Bible）

- [doc/art/direction.md](doc/art/direction.md) — アートの全体方針（絵柄・陣営配色・共通メソッド）
- [doc/art/units.md](doc/art/units.md) — ユニットの見た目方針（共通ルール・陣営ごと・制作スペック・STYLE）
- [doc/art/terrain.md](doc/art/terrain.md) — 地形タイルの方針（TERRAIN STYLE・切り抜き・反復対策）
- [doc/art/keyvisual.md](doc/art/keyvisual.md) — 扉絵・キービジュアルの方針（ILLUST STYLE・透かし対策）
- [doc/art/menu.md](doc/art/menu.md) — メニュー画面の材質（木壁・依頼ボード・羊皮紙・ナインパッチ）
- [doc/art/overview.md](doc/art/overview.md) — 画像スロット仕様（`map`/`combat`）

### サウンド — `audio/`（Audio Bible）

- [doc/audio/bgm.md](doc/audio/bgm.md) — BGM（制作方針＝二段構え・MuseScore・トラックライブラリ＝ムード別に使い回し・管理運用＝autowire／ステージJSON指定・状態切替・権利台帳）
- [doc/audio/tracks.md](doc/audio/tracks.md) — トラック設計ノート（各曲の狙い・音楽的設計・参考にした語法・調整の勘所）

### 販売・ブランド — `sales/`

- [doc/sales/monetization.md](doc/sales/monetization.md) — 体験版/製品版・DLC・有料データ保護・販売チャネル
- [doc/sales/naming_decision_senaris.md](doc/sales/naming_decision_senaris.md) — タイトル名「Senaris」の決定

### 意思決定記録 — `adr/`

- [doc/adr/ADR-0001-adopt-godot.md](doc/adr/ADR-0001-adopt-godot.md) — ゲームエンジンに Godot 4 を採用
- [doc/adr/ADR-0002-paid-data-protection.md](doc/adr/ADR-0002-paid-data-protection.md) — 有料データの保護（署名＋pck 暗号化）
- [doc/adr/ADR-0003-board-3d-hybrid.md](doc/adr/ADR-0003-board-3d-hybrid.md) — 盤面の描画を3Dハイブリッド（傾けたカメラ＋2Dアセット）に
