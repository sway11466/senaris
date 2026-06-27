# Senaris ドキュメント索引

ヘックス制ターン戦術 SLG（ファンタジー）Senaris の設計・運用ドキュメント。

## 全体

- [concepts.md](concepts.md) — プロダクトコンセプト（何を・なぜ・面白さの核）
- [project-overview.md](project-overview.md) — 目的・ロードマップ・配布計画・進め方の制約
- [monetization.md](monetization.md) — 体験版/製品版・DLC・有料データ保護・販売チャネル
- [art.md](art.md) — 画像／アート準備
- [naming_decision_senaris.md](naming_decision_senaris.md) — タイトル名「Senaris」の決定

## ゲームデザイン — `gdd/`

- [gdd/combat.md](gdd/combat.md) — 戦闘解決（補正チェーン・陣形）
- [gdd/units.md](gdd/units.md) — ユニット性能設計・対応表
- [gdd/map.md](gdd/map.md) — 拠点・占領・ステージ
- [gdd/world.md](gdd/world.md) — 世界観・設定

## 技術設計 — `tech/`（Technical Design Document）

- [tech/architecture.md](tech/architecture.md) — レイヤー／モジュール構成・依存ルール
- [tech/gamesystem.md](tech/gamesystem.md) — ゲームシステム仕様（セーブ ほか）

## 意思決定記録 — `adr/`

- [adr/ADR-0001-adopt-godot.md](adr/ADR-0001-adopt-godot.md) — ゲームエンジンに Godot 4 を採用
- [adr/ADR-0002-paid-data-protection.md](adr/ADR-0002-paid-data-protection.md) — 有料データの保護（署名＋pck 暗号化）
