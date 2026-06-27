# CLAUDE.md

**Senaris** — Nectaris（Military Madness）系のヘックス制ターン戦術 SLG を、ファンタジー舞台でオリジナル化した趣味プロジェクト。生産で拡大せず、与えられた戦力を盤面で噛み合わせて勝つ。コンセプト詳細 → [doc/concepts.md](doc/concepts.md)

## 開発上の制約（重要）

- **実装着手はオーナーの明示的な許可後。** 設計・ドキュメント作業は随時OK。
- **git 操作は都度許可を取る。**
- ブランチは **main**（master は使わない）。

## 技術スタック

- **エンジン**: Godot 4（GDScript・型付き / 2D）。テストは GUT。
- **レイヤー**: `presentation → application → domain → data` の一方向依存。`domain` / `data` は Godot ノード非依存（純ロジック）。詳細 → [doc/design/architecture.md](doc/design/architecture.md)
- **配布**: まず Steam（PC）。モバイルは後回し。

## ドキュメント

索引は [doc/README.md](doc/README.md)。主要ファイル:

| 分類 | ファイル |
|---|---|
| コンセプト | [doc/concepts.md](doc/concepts.md) |
| 運用・ロードマップ | [doc/project-overview.md](doc/project-overview.md) |
| 戦闘（補正チェーン・陣形） | [doc/design/combat.md](doc/design/combat.md) |
| ユニット性能・対応表 | [doc/design/units.md](doc/design/units.md) |
| 拠点・占領・ステージ | [doc/design/map.md](doc/design/map.md) |
| アーキテクチャ | [doc/design/architecture.md](doc/design/architecture.md) |
| セーブ仕様 | [doc/gamesystem/save.md](doc/gamesystem/save.md) |
| マネタイズ・データ保護 | [doc/gamesystem/monetization.md](doc/gamesystem/monetization.md) |
| 世界観 | [doc/world.md](doc/world.md) |
| アート準備 | [doc/art.md](doc/art.md) |
| 命名の決定 | [doc/naming_decision_senaris.md](doc/naming_decision_senaris.md) |
| 意思決定記録 | [doc/adr/](doc/adr/) |
