# プラットフォーム層

対象：販売チャネルごとの機能（所有権チェック・実績・Stats）の切り替え方と、本体から見た口
役割：「本体はチャネルを知らずに呼ぶだけ」を成り立たせる構造を記録する

チャネルと版の判定そのものは [build.md](build.md)（`BuildInfo`）、実績と計測の方針は [../sales/monetization.md](../sales/monetization.md) 実績・計測、保存ファイルの共通の扱いは [gamesystem.md](gamesystem.md) セーブ。

---

## 狙い

本体（application と presentation）は、所有権チェック・実績・Stats をチャネル非依存の口で呼ぶだけにする。どのチャネルのビルドでもその口が正しく動き、エディタ実行でも実績の動作が確かめられる。

チャネルごとの分岐を本体に散らすと、チャネルを足すたびに本体のあちこちを直すことになり、直し漏れはそのチャネルのビルドでしか表に出ない。分岐は1か所に集め、本体からは見えない形にする。

## 切り替えの鍵

鍵は `BuildInfo.channel()` と `BuildInfo.edition()` の2つだけ。これ以外（環境変数・コマンドライン引数・設定ファイル）では切り替えない。鍵が増えると、手元で動いたものと配ったものが違う組み合わせで動く。

アダプターはチャネルと1対1で、次の5つ。

| アダプター | 選ばれる条件 |
|---|---|
| steam | `channel() == "steam"` かつ `edition() == "full"` |
| steam-demo | `channel() == "steam"` かつ `edition() == "demo"` |
| itch | `channel() == "itch"`（版を問わない） |
| booth | `channel() == "booth"`（版を問わない） |
| dev | `channel() == "dev"`（エディタ実行・タグを書き忘れたビルド） |

版で分かれるのは Steam だけ。Steam は体験版と製品版で AppID が別で、実績の扱いも違う（下の「体験版からの引き継ぎ」）。itch と booth は体験版でも製品版でも振る舞いが同じ。

「その他」のまとめ枠やフォールバックは作らない。知らないチャネルが来たら起動時にエラーで止める（`BuildInfo` が返すチャネルを増やしたのにアダプターを足し忘れた、が黙って別の振る舞いにならない）。itch と booth と dev の中身は今は同じだが、共通化せず別々に持つ。チャネルごとに事情が変わったとき、そのアダプターだけを直せば済む。

アダプターを選ぶ場所は1か所（`Platform.for_build()`）。起動時に `main` が1回呼び、出来た口を本体へ渡す。本体のどこからも `BuildInfo.channel()` を見て機能を分岐させない。

## アダプターと部品

アダプターは薄い。機能ごとの部品を選んで束ねるだけで、中身の処理は持たない。

部品は機能ごとに作り、複数のアダプターで使い回す。

| 部品 | 機能 | 中身 |
|---|---|---|
| 常に所有 | 所有権チェック | どの `content_id` にも `true` を返す |
| Steam DLC | 所有権チェック | `content_id` を DLC の AppID に引き、Steam に問い合わせる |
| 実績ファイル | 実績の保管庫 | 実績専用ファイルに読み書きする |
| Steamworks 実績 | 実績の保管庫 | Steamworks の API で読み書きする。ローカルに持たない |
| Stats なし | Stats | 何もしない |
| Steam Stats | Stats | Steam に送る |

`content_id` と DLC の AppID の対応は Steam DLC の部品が持つ。本体は AppID を知らない。

## チャネル×機能

| 機能 | steam | steam-demo | itch / booth / dev |
|---|---|---|---|
| 所有権チェック | Steam DLC | 常に所有 | 常に所有 |
| 実績の保管庫 | Steamworks 実績 | 実績ファイル（製品版で Steam へ） | 実績ファイル |
| Stats | Steam Stats | Steam Stats | Stats なし |

- 所有権チェック：itch と booth は「買った人だけが製品版を落とせる」売り方なので、手元にある製品版は所有しているとみなしてよい。体験版に DLC の冒険譚は入らない（[build.md](build.md) 収録リスト）ので、steam-demo の常に所有は解放に効かない。
- 実績：実績はゲーム本体の機能で、Steam はその保管先の1つ。Steam 以外のチャネルでも実績は解除され、記録が残る。
- Stats：送るのは Steam だけ。ほかのチャネルには送り先が無く、自前で集計もしない（[../sales/monetization.md](../sales/monetization.md) 計測＝自前サーバーへのテレメトリはやらない）。

## 本体が見る口

本体が触るのは次の3つだけ。どれもチャネルを問わず同じ形で呼べる。

| 口 | 呼び方 | 返すもの |
|---|---|---|
| 所有権チェック | `owns(content_id) -> bool` | その追加コンテンツを持っているか |
| 実績の保管庫 | `unlock(id)` | なし。解除済みなら何もしない |
| | `is_unlocked(id) -> bool` | 解除済みか |
| | `unlocked_ids() -> PackedStringArray` | 解除済みの実績の一覧 |
| Stats | `add(stat_id, amount := 1)` | なし |

- 実績の `id` は Steamworks の管理画面に登録する API 名と同じ文字列を使う。チャネルごとの読み替え表は持たない＝実績ファイルに残る名前と Steam 側の名前が一致し、引き継ぎで変換が要らない。
- `unlock` は何度呼んでもよい。発火点で「もう解除したか」を確かめずに呼べる。
- Stats は加算だけを持つ。計測で見たいのはステージの開始数とクリア数で、どれも数え上げになる（[../sales/monetization.md](../sales/monetization.md) 計測）。

## 実績ファイル

実績の保管庫を Steam 以外に置くチャネル（steam-demo・itch・booth・dev）が使う。

- 置き場：`user://achievements.json`（置き場は `SavePaths` が持つ。[gamesystem.md](gamesystem.md) 置き場）
- 形式：`{ "version": 1, "unlocked": ["<実績ID>", …] }`。並びは解除した順
- 扱い：ほかの保存ファイルと同じく、版を持ち、上書きの前に世代を残し、読めないファイルは退避して「解除なし」で起動する（[gamesystem.md](gamesystem.md) 版と移行・バックアップ）

進捗セーブとは別のファイルにする。

- 実績は進捗から導けない。ランクの記録は上書きされうるし、セーブを消しても実績は消えないのが実績の性格。
- 体験版から製品版へ引き継ぐのは実績だけで、進捗の引き継ぎとは経路が違う。同じファイルに入れると、片方だけを渡す口を作ることになる。

解除した時刻は持たない。Steamworks の API に時刻を指定して実績を立てる口が無く、引き継いだ時点の時刻になるため、持っても使い道が無い。

## 体験版からの引き継ぎ

Steam 体験版（steam-demo）は実績を Steam に立てない（Valve の推奨。[../sales/monetization.md](../sales/monetization.md) 体験版の実績）。体験版で解除した実績は実績ファイルに溜まる。

製品版（steam）は起動のたびに実績ファイルを探し、あればその中の実績を Steamworks に立てる。製品版は実績ファイルに書かない＝読むだけ。

- 「初回起動」を判定しない。立て済みの実績を立て直しても何も起きないので、毎回流し込めば初回の判定が要らず、購入後に体験版をもう一度遊んだぶんも次の起動で拾える。
- 体験版と製品版は同じ `user://` を使う（プロジェクト名が同じ）。同じ PC なら何もしなくても製品版から実績ファイルが見える。別の PC へは Steam Cloud で運ぶ。

## Steam の初期化に失敗したとき

steam と steam-demo は、起動時に Steamworks を初期化できなければ「Steam から起動してください」と出して終了する。Steam 無しで遊べる状態にすると、実績と所有権チェックが黙って効かないビルドになる。

## 置き場

`godot/infrastructure/platform/` に置く。`BuildInfo` と同じ階層で、外界（ストア）との境界にあたる。

GodotSteam（Steamworks を GDScript から呼ぶアドオン）に触るのは Steam の部品だけ。ほかの部品・アダプター・本体は GodotSteam を知らない。

## テスト

GUT は Steam 実装を通さない。見るのはアダプターの選択（チャネルと版の組み合わせごとに、どのアダプターが選ばれるか・知らないチャネルで止まるか）と、Steam 以外の部品の挙動（実績ファイルの読み書き・壊れたファイル・常に所有・Stats なし）。実績ファイルのテストは `SavePaths` をその回だけのディレクトリへ向ける（[testing.md](testing.md)）。

Steam の部品は、Steam クライアントを起動して手で確かめる（[../backlog.md](../backlog.md) feature-40 の進め方）。
