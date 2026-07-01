# Senaris ドキュメント索引

ヘックス制ターン戦術 SLG（ファンタジー）Senaris の設計・運用ドキュメント。

## 全体

- [concepts.md](concepts.md) — プロダクトコンセプト（何を・なぜ・面白さの核）
- [backlog.md](backlog.md) — 「必要になったら着手」する作業の置き場

## ゲームデザイン — `gdd/`

- [gdd/combat.md](gdd/combat.md) — 戦闘解決（補正チェーン・陣形スキル）
- [gdd/formations.md](gdd/formations.md) — 陣形スキル（レシピ・カタログ）
- [gdd/units.md](gdd/units.md) — ユニット性能設計・対応表
- [gdd/movement.md](gdd/movement.md) — 移動タイプ・地形コスト・reachable
- [gdd/map.md](gdd/map.md) — 拠点・占領・ステージ・用語・戦力供給モデル
- [gdd/ai.md](gdd/ai.md) — 敵AI（思考パターン＝軸の組み合わせ・部隊割り当て）
- [gdd/uiux.md](gdd/uiux.md) — UI/UX 操作モデル（選択→移動→コマンド・デバイス別操作・カメラ）
- [gdd/world.md](gdd/world.md) — 世界観・設定

## 冒険譚（キャンペーン） — `campaign/`

共通の制作方針は [campaign/authoring.md](campaign/authoring.md)。各冒険譚は `gdd/` の仕様を土台にし、関係する箇所だけ本文でリンクする。

- [campaign/authoring.md](campaign/authoring.md) — 冒険譚の制作方針（共通：会話パート・書式 ほか）
- [campaign/tutorial1-goblin-raid.md](campaign/tutorial1-goblin-raid.md) — チュートリアル１「ゴブリンの襲撃」（仮）骨子・全7ステージ（基礎：移動・地形・包囲・支援・間接・占領・釣り）
- [campaign/tutorial2-undead-rush.md](campaign/tutorial2-undead-rush.md) — チュートリアル２「アンデッド・ラッシュ」（仮）骨子・全7ステージ（陣形スキル・輸送・魔法兵／ボス＝ネクロマンサー）

## 技術設計 — `tech/`（Technical Design Document）

- [tech/architecture.md](tech/architecture.md) — レイヤー／モジュール構成・依存ルール
- [tech/gamesystem.md](tech/gamesystem.md) — ゲームシステム仕様（セーブ ほか）

## アート — `art/`（Art Bible）

- [art/overview.md](art/overview.md) — 画像／アート準備

## 販売・ブランド — `sales/`

- [sales/monetization.md](sales/monetization.md) — 体験版/製品版・DLC・有料データ保護・販売チャネル
- [sales/naming_decision_senaris.md](sales/naming_decision_senaris.md) — タイトル名「Senaris」の決定

## 意思決定記録 — `adr/`

- [adr/ADR-0001-adopt-godot.md](adr/ADR-0001-adopt-godot.md) — ゲームエンジンに Godot 4 を採用
- [adr/ADR-0002-paid-data-protection.md](adr/ADR-0002-paid-data-protection.md) — 有料データの保護（署名＋pck 暗号化）
