# Senaris ドキュメント索引

ヘックス制ターン戦術 SLG（ファンタジー）Senaris の設計・運用ドキュメント。

## 全体

- [concepts.md](concepts.md) — プロダクトコンセプト（何を・なぜ・面白さの核）
- [project-overview.md](project-overview.md) — 目的・ロードマップ・配布計画・進め方の制約
- [world.md](world.md) — 世界観・設定
- [art.md](art.md) — 画像／アート準備
- [naming_decision_senaris.md](naming_decision_senaris.md) — タイトル名「Senaris」の決定

## 設計 — `design/`

- [design/architecture.md](design/architecture.md) — レイヤー／モジュール構成・依存ルール
- [design/combat.md](design/combat.md) — 戦闘解決（補正チェーン・陣形）
- [design/units.md](design/units.md) — ユニット性能設計・対応表
- [design/map.md](design/map.md) — 拠点・占領・ステージ

## ゲームシステム — `gamesystem/`

- [gamesystem/save.md](gamesystem/save.md) — セーブ仕様
- [gamesystem/monetization.md](gamesystem/monetization.md) — 体験版/製品版・DLC・有料データ保護

## 意思決定記録 — `adr/`

- [adr/ADR-0001-adopt-godot.md](adr/ADR-0001-adopt-godot.md) — ゲームエンジンに Godot 4 を採用
- [adr/ADR-0002-paid-data-protection.md](adr/ADR-0002-paid-data-protection.md) — 有料データの保護（署名＋pck 暗号化）
