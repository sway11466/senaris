# テスト方針

自動テストの方針。レイヤー構成と「純ロジックはテスト対象」の設計動機は [architecture.md](architecture.md) を参照。

## 目的

- 自動テストの目的は開発の持続可能性＝速く信頼できるフィードバックを保ち、変更（リファクタリング・バランス調整）を怖くなくすること（t-wada の整理を背骨にする）。
- テストが保証するのは「コードが意図どおり動くか」まで。「その意図が面白いか」は保証しない＝面白さ・手触りの検証はプレイテストで行う。
- 実装詳細ではなく振る舞い（公開API）をテストする。テストの書きにくさは設計の警報として扱う＝純ロジック分離（domain / data のノード非依存）が崩れていないかを疑う。

## レイヤー別の線引き

| レイヤー | 自動テスト | 対象 |
|---|---|---|
| domain | 必須 | 純ロジックをエンジン起動なしの黒箱で（戦闘・包囲・支援・移動・ヘックス・AI・陣形・占領 ほか） |
| data | 必須 | CSV正本→JSON生成の整合・カタログ読込。欠損・不正はデータのバグとして開発時に落とす（architecture.md のバリデーション方針） |
| application | 対象 | コマンド実行・ステージ組み立て（StageLoader）・キャンペーン進行判定 |
| infrastructure | 対象 | セーブの読み書き（progress_store） |
| presentation | 原則対象外 | 見た目・入力・カメラは自動テストしない。tests/manual の使い捨てスクリプト（ヘッドレス再現・スクショ）と目視・プレイテストで補う |

## 運用

- 新機能はテストと同時に足す。ルールを先に言える機能（戦闘式・陣形レシピ等）はテストファーストでよい。
- バグ修正は再現テストを先に書き、落ちることを確認してから直す。
- 触って調整中の領域（AIの手触り・カメラ等）はテスト後追いでよい。仕様が固まった時点でテストに固定する。
- 全件グリーンを保つ。落ちたテストの放置や skip での恒久回避はしない。

## 実行方法

GUT 9.7.0 を `addons/gut` に vendoring。対象は `.gutconfig.json` で指定（`tests/unit/` 配下・`test_*.gd`）。

```
godot --headless --path . --import        # 初回・class_name 追加後
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
```

- 単一ファイルだけ回す場合は `-gtest=res://tests/unit/test_xxx.gd` を足す。
- GUT のバージョンは Godot 本体に追従が必要（起動時に非互換警告が出たら推奨版へ上げる）。

## CI

GitHub Actions（`.github/workflows/tests.yml`）が main への push と pull request で全テストを実行する。ubuntu-latest に Godot 4.7-stable（Linux headless）を導入し、`--import` のあと上記コマンドを回す。テスト失敗は GUT の exit code で赤になる。class_name 未インポート等の早期終了は exit 0 になるため、ログの「All tests passed」検査で偽グリーンを防ぐ。

## 現状の構成（2026-07 時点）

- `tests/unit/` — 31本。domain（combat / pierce / support / surround / air_combat / movement / hex / ai / formation / capture / transport / turn / victory / battle_state）・data（data_integrity / csv_util / 各カタログ / unit_type / skin 系 / i18n / dialogue）・application（command_actions / stage_loader / campaign_progress / campaign_catalog）・infrastructure（progress_store）。
- `tests/manual/` — 使い捨てスクリプト置き場（セレクト画面のヘッドレス再現・スクショ）。自動実行の対象外。
- 手動での機能確認は機能別のデバッグステージ（`data/stages/debug-*/`）を使う。カテゴリ内訳・未実装TODO → [debug-stages.md](debug-stages.md)。
