# テスト方針

自動テストの方針。レイヤー構成と「純ロジックはテスト対象」の設計動機は [architecture.md](architecture.md) を参照。

## 目的

- 自動テストの目的は開発の持続可能性＝速く信頼できるフィードバックを保ち、変更（リファクタリング・バランス調整）を怖くなくすること（t-wada の整理を背骨にする）。
- テストが保証するのは「コードが意図どおり動くか」まで。「その意図が面白いか」は保証しない＝面白さ・手触りの検証はプレイテストで行う。
- 実装詳細ではなく振る舞い（公開API）をテストする。テストの書きにくさは設計の警報として扱う＝純ロジック分離（domain / data のノード非依存）が崩れていないかを疑う。

## テストサイズ

分類の軸は層でも粒度でもなく、テストが使う資源と隔離の強さ（Google のテストサイズ）。「ユニット／結合／e2e」という呼び名は人によって指すものが違うので使わない。

| サイズ | 使ってよい資源 | このプロジェクトでの該当 |
|---|---|---|
| Small | 単一プロセス。ファイルI/O・ネットワーク・待ち（sleep・フレーム待ち）は使わない。ただし同梱データ（`res://`）の読み込みは可 | domain・data の純ロジック（戦闘・移動・AI・陣形・CSV整合 ほか） |
| Medium | 単一マシン。ファイルI/O・シーンツリー・フレーム待ちを使ってよい。通信は localhost まで | 永続化（`user://` を読み書き）、`main.tscn` を立ち上げて下の層まで通すもの |
| Large | 制約なし（複数マシン・外部サービス） | 作らない。外部サービスに依存するものが無い |

- Small を既定とし、Medium にするのは資源が本当に要るときだけ。Medium が増えるほど全件実行の回転が落ちる。
- 置き場はサイズで分ける＝`godot/tests/small/` と `godot/tests/medium/`。さらにその下を対象のレイヤー（domain / data / application / infrastructure / tools / presentation）で割る。どのサイズかを名前や本文で宣言せず、置いた場所が宣言になる。
- 実ファイルを触る Medium は、使ったファイルを必ず片付ける。セーブを書き換えるものはプレイヤーの実セーブを触らない＝置き場（`SavePaths`）をその回だけのディレクトリへ向けてから立ち上げ、終わったら消す（[gamesystem.md](gamesystem.md) §置き場）。退避して戻す形は採らない。途中で止まった回に戻す者がいなくなる。

## 自動テストで捕まらないもの

層ごとのテストとサイズの線を引いても、次の3つは残る。

- 配線 — ノードの組み立て順・依存の注入・シグナル接続・`.tscn` の中身。これは Medium で自動化できる＝`main.tscn` を立ち上げ、内部メソッドを入口にして下の層まで通す（入力と画面遷移は入口にしない）。
- 絵づら・手触り — レイアウト・タイミング・操作感。目視とプレイテストに残す。
- エンジンの実挙動 — フォーカス・入力・描画。目視に残す。

実機での目視確認は「UI から目的の処理に到達しているか」までとする。到達した先の値や分岐が正しいかは層ごとのテストが見るので、実機で見ても分かることが増えない。到達を見るときは、落ちないことを到達の証拠にしない（何もしないコードも落ちない）＝記録や状態の変化で見る。

## レイヤー別の線引き

| レイヤー | 自動テスト | 対象 |
|---|---|---|
| domain | 必須 | 純ロジックをエンジン起動なしの黒箱で（戦闘・包囲・支援・移動・ヘックス・AI・陣形・占領 ほか） |
| data | 必須 | CSV正本→JSON生成の整合・カタログ読込。欠損・不正はデータのバグとして開発時に落とす（architecture.md のバリデーション方針） |
| application | 対象 | コマンド実行・ステージ組み立て（StageLoader）・キャンペーン進行判定 |
| infrastructure | 対象 | セーブの読み書き（progress_store） |
| tools | 対象 | マップエディタの入出力（非編集キーの温存・StageLoader が読める JSON の書き出し） |
| presentation | 原則対象外 | 絵づら・入力・操作感は自動テストしない。ただしヘッドレスで構造・数値を検証できるもの（メッシュ生成の純関数・レンダラーのノード構成・カメラの位置決め）は対象。配線は Medium で固定する（上記）。残りは `godot/tests/manual/` の使い捨てスクリプト（ヘッドレス再現・スクショ）と目視・プレイテストで補う |

## 運用

- 新機能はテストと同時に足す。ルールを先に言える機能（戦闘式・陣形レシピ等）はテストファーストでよい。
- バグ修正は再現テストを先に書き、落ちることを確認してから直す。
- 触って調整中の領域（AIの手触り・カメラ等）はテスト後追いでよい。仕様が固まった時点でテストに固定する。
- 全件グリーンを保つ。落ちたテストの放置や skip での恒久回避はしない。
- テストが製品コードの `push_error` / `push_warning` を誘発するときは `assert_push_error` / `assert_push_warning`（同一文言が複数なら `assert_push_warning_count`）で宣言する。宣言のない WARNING/ERROR がログに出ない状態を保つと、出た1行がそのまま異常の合図になる。push_error は GUT が未宣言だとテストを落とす（`failure_error_types` の既定）が、push_warning は落ちないので書き忘れに注意。

## 実行方法

GUT 9.7.0 を `godot/addons/gut` に vendoring。対象は `.gutconfig.json` で指定（`godot/tests/small/` と `godot/tests/medium/` の配下・`test_*.gd`）。

```
godot --headless --path godot --import        # 初回・class_name 追加後
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
```

- 単一ファイルだけ回す場合は `-gtest=res://tests/small/<レイヤー>/test_xxx.gd` を足す。
- GUT のバージョンは Godot 本体に追従が必要（起動時に非互換警告が出たら推奨版へ上げる）。

## CI

GitHub Actions（`.github/workflows/tests.yml`）が main への push と pull request で全テストを実行する。ubuntu-latest に Godot 4.7-stable（Linux headless）を導入し、`--import` のあと上記コマンドを回す。テスト失敗は GUT の exit code で赤になる。class_name 未インポート等の早期終了は exit 0 になるため、ログの「All tests passed」検査で偽グリーンを防ぐ。

## 構成

- `godot/tests/small/<レイヤー>/`・`godot/tests/medium/<レイヤー>/` — 1話題1ファイルで `test_<話題>.gd`。レイヤーは domain（戦闘・移動・AI・陣形・占領・輸送・ターン・勝敗・盤の状態）／data（CSV正本→JSON生成の整合・各カタログ・多言語）／application（試合進行・コマンド・ステージ読込・キャンペーン進行・決着時の記録）／infrastructure（永続化）／tools（マップエディタの入出力）／presentation（盤の描画・カメラの構造・起動から勝利までの導線）。どの話題があるかはディレクトリが正本＝ここに一覧を持たない。
- `godot/tests/manual/` — 使い捨てスクリプト置き場（セレクト画面のヘッドレス再現・スクショ）。自動実行の対象外。
- 手動での機能確認は機能別のデバッグステージ（`godot/data/stages/debug-*/`）を使う。カテゴリ内訳 → [debug-stages.md](debug-stages.md)。
