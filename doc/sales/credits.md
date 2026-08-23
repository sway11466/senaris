# クレジット・第三者権利（正本）

本作が頒布するもののうち他人の成果物はどれか、制作に使った主要な製品は何か、それぞれ何の義務があるかを出所単位でまとめる。ゲーム内のクレジット画面（[backlog.md](../backlog.md) feature-46）と、ストアページに載せる表記は、ここを正本にする。

義務が無い製品も載せる。ライセンスが求めていなくても、作品を成り立たせている製品には作者への敬意として名前を残す。

## 読み方・更新ルール

権利の記録は2層に分かれる。

- 正本（このファイル）＝出所単位。ライセンスと義務を持つ。ひとつのバンドルから何本素材を取り出しても1行のまま。
- 素材台帳＝素材単位。出典のファイル名・切り出し秒・音量・レシピといった、制作を再現するための情報を持つ。
  - BGM → [../../assets/bgm-src/credits.md](../../godot/assets/bgm-src/credits.md)（方針は [bgm.md](../audio/bgm.md)）
  - 効果音 → [../../assets/sfx-src/credits.md](../../godot/assets/sfx-src/credits.md)（方針は [sfx.md](../audio/sfx.md)）

素材を足したら素材台帳に1行足す。出所そのものが新しく増えたときだけ、あわせて正本にも1行足す。

表の列の意味は次のとおり。

- 頒布：製品ビルドに含まれるか。「含む」＝ファイルそのものが入る。「出力を含む」＝製品は入らないが、それで作ったものが入る。「道具」＝制作に使うだけで製品には入らない。「除外」＝リポジトリにはあるが製品ビルドから外す。
- 義務：頒布に伴ってこちらが負う作業。道具と除外には義務が生じない。
- 根拠：ライセンスを確認したリポジトリ内のファイル。空欄はまだ裏を取っていない＝[backlog.md](../backlog.md) feature-54 で潰す。

## ライセンス別の一覧

### MIT

| 製品 | 用途 | 頒布 | 義務 | 根拠 |
|---|---|---|---|---|
| Godot Engine | ゲームエンジン | 含む | ライセンス文の表示（同梱サードパーティを含む） | |
| GUT | テストフレームワーク | 除外 | なし | `godot/addons/gut/LICENSE.md` |
| fontTools | ロゴの SVG 生成（EB Garamond のパス化） | 道具 | なし | |

### Apache License 2.0

| 製品 | 用途 | 頒布 | 義務 | 根拠 |
|---|---|---|---|---|
| Rock Salt（Font Diner, Inc DBA Sideshow） | セレクト画面のボード名・クリア済みの印 | 含む | ライセンス文の同梱と著作権表記 | `godot/assets/fonts/RockSalt-LICENSE.txt`・TTF の name テーブル |
| OpenCV | 画像処理スクリプト | 道具 | なし | |

Rock Salt は `.ttf` が `.godot/imported/*.fontdata` に変換されて製品ビルドに入る。ライセンス文（`RockSalt-LICENSE.txt`）は Godot がリソースとして扱わない素のファイルなので、何もしないと pck に入らず、フォントだけ入ってライセンス文が無い形になる。ビルド出力の exe と同じ階層に `THIRD-PARTY-LICENSES.txt` を置いて渡す（[backlog.md](../backlog.md) feature-10）。

### SIL Open Font License

| 製品 | 用途 | 頒布 | 義務 | 根拠 |
|---|---|---|---|---|
| EB Garamond | タイトルロゴの文字 | 含まない（パス化するのでフォントは残らない） | なし | `godot/assets/promo-src/logo/fonts/OFL.txt`・[ADR-0004](../adr/ADR-0004-logo-typeface-ofl.md) |
| Anonymous Pro / Courier Prime / Lobster Two | GUT の同梱フォント | 除外 | なし | `godot/addons/gut/fonts/OFL.txt` |

### GPL 系

| 製品 | 用途 | 頒布 | 義務 | 根拠 |
|---|---|---|---|---|
| MuseScore Studio | 曲・楽音系の効果音の作曲と編曲 | 道具 | なし | |
| Inkscape | ロゴまわりの SVG 編集（[logo.md](../art/logo.md)） | 道具 | なし | |

### LGPL 系

| 製品 | 用途 | 頒布 | 義務 | 根拠 |
|---|---|---|---|---|
| FFmpeg | 音の切り出し・変換・書き出し | 道具 | なし | |

### ImageMagick License

| 製品 | 用途 | 頒布 | 義務 | 根拠 |
|---|---|---|---|---|
| ImageMagick | 画像の生成スクリプト全般（`godot/tools/gen_*.ps1`） | 道具 | なし | |

### BSD 3-Clause

| 製品 | 用途 | 頒布 | 義務 | 根拠 |
|---|---|---|---|---|
| NumPy | 画像処理スクリプト | 道具 | なし | |

### MIT-CMU

| 製品 | 用途 | 頒布 | 義務 | 根拠 |
|---|---|---|---|---|
| Pillow | 画像処理スクリプト | 道具 | なし | |

### 各社の独自規約

| 製品 | 用途 | 頒布 | 義務 | 根拠 |
|---|---|---|---|---|
| Sonniss GDC Game Audio Bundle | 効果音の物音系・`title` の酒場のざわめき | 含む | 表記不要。再配布不可・AI学習不可のため元の `.wav` はリポジトリに入れない | [sonniss.md](../audio/sonniss.md) |
| Muse Sounds ／ MS Basic | 曲・楽音系の効果音の音源 | 出力を含む | | |
| Google Gemini（Nano Banana・AI Studio） | ユニット・地形・扉・扉絵ほかの絵 | 出力を含む | Steam の提出時に AI 生成コンテンツを開示（[monetization.md](monetization.md)） | |

### 自作

| 製品 | 用途 | 頒布 | 義務 | 根拠 |
|---|---|---|---|---|
| 自作物 | 曲・楽音系の効果音・絵の仕上げ・盤面のルールとデータ | 含む | なし | |

## ゲーム内クレジットに出すもの

頒布物に入るもの（義務があるもの）、第三者の出力が含まれるもの、制作に使った道具を載せる。表記文が指定されているライセンスは、指定文をそのまま使い、自己流に言い換えない。

- Godot Engine。ライセンス文は実行時に `Engine.get_license_text()` で取れるので、画面に流し込む。同梱サードパーティの分も `Engine.get_copyright_info()` に入っている
- Rock Salt。`Copyright (c) 2010 by Font Diner, Inc DBA Sideshow.` と、Apache License 2.0 の下で使っている旨。ライセンス全文は `THIRD-PARTY-LICENSES.txt` で渡す
- Sonniss GDC Game Audio Bundle。表記義務は無いが、効果音の土台なので名前を残す
- Muse Sounds ／ MS Basic
- Google Gemini。AI 生成の開示はストア側の手続きが本体だが、画面にも出す
- 制作に使った道具（MuseScore Studio・Inkscape・FFmpeg・ImageMagick・NumPy・Pillow・OpenCV・fontTools）。義務は無いが、本書冒頭の方針（義務が無い製品も載せる）を画面にも通す。義務のある表記と混ざらないよう末尾にまとめ、一段小さく置く

Godot はライセンス全文を画面に載せる。`Engine.get_license_text()` の中身をそのまま流す＝ MIT の「ライセンス文の表示」を画面だけで満たせる（同梱ファイル `THIRD-PARTY-LICENSES.txt` は配布ビルドの話で、[backlog.md](../backlog.md) feature-10 待ち）。長いのでスクロールする領域に入れる。

## ストアページに出すもの

ストアページに要るのは、表記文が指定されているライセンスと、ストア側の手続き（Steam の AI 生成コンテンツ開示）だけ。頒布物に対してだけ義務があり指定文を持たないライセンスは、ストアページに載せる必要がない。Apache 2.0 の Rock Salt がこれに当たる（ライセンス文の同梱とゲーム内クレジットで足りる）。

## 製品ビルドから外すもの

次は開発専用で、製品ビルドに含めない。含めてしまうとそれぞれのライセンス義務が発生する。除外の設定は [backlog.md](../backlog.md) feature-10。

- `godot/addons/gut/`（GUT 本体と同梱フォント）
- `godot/tools/`（自作の開発ツール一式）
- デバッグ用ステージ（`godot/data/stages/debug*/`）
