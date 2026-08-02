# 効果音 権利・ライセンス台帳

本作（Steam・商用）で使う効果音の出自を素材ごとに記録する。方針 → [../../doc/audio/sfx.md](../../doc/audio/sfx.md) の「権利・ライセンス台帳」。
他者の権利を侵さないための管理なので、素材を追加したら必ずここに1行足す。書式は BGM の台帳（[../bgm-src/credits.md](../bgm-src/credits.md)）に揃える。

記載項目は sfx_id（用途）／出典／入手形式／ライセンス（商用可否・改変可否・クレジット表記の要否）／改変度。

## 自作素材

楽音系は MuseScore で自作する。原本の `.mscz` を同じディレクトリに置き、`tools/gen_sfx.ps1` で `assets/sfx/{sfx_id}.ogg` に変換する。

| sfx_id | 用途 | 出典 | 入手形式 | ライセンス | 改変度 |
|---|---|---|---|---|---|
| `ui_confirm` | 確定・決定・選択 | 自作 | MuseScore（MS Basic 音源） | 自作物＝商用可・改変可・表記不要 | 全部自作 |
| `ui_cancel` | 戻る・キャンセル | 自作 | MuseScore（MS Basic 音源） | 自作物＝商用可・改変可・表記不要 | 全部自作 |
| `ui_denied` | 操作の否定（できない） | 自作 | MuseScore（MS Basic 音源） | 自作物＝商用可・改変可・表記不要 | 全部自作 |
| `ui_hover` | ホバー強調・文字送り | 自作 | MuseScore（MS Basic 音源） | 自作物＝商用可・改変可・表記不要 | 全部自作 |

## 第三者素材

物音系（足音・攻撃・命中など）はオーケストラ音源では出ないため外部調達する（[../../doc/audio/sfx.md](../../doc/audio/sfx.md) の調達方針）。クレジット表記が必要なものは指定文をそのまま転記する（自己流に変えない）。表記先は Steam ページとゲーム内クレジット。

素材プールは Sonniss GDC Game Audio Bundle（[../../doc/audio/sonniss.md](../../doc/audio/sonniss.md)）。全年共通で商用可・改変可・表記不要だが、再配布不可のため元の `.wav` はリポジトリに入れない（`assets/sfx-src/**/*.wav` は .gitignore 済み）。AI 学習への利用も禁止されている。

| sfx_id | 用途 | 出典 | 入手形式 | ライセンス | 改変度 |
|---|---|---|---|---|---|
| `slash_s` | 斬撃（小）のエフェクト | Sonniss GDC 2026 / 344 Audio - Historical Weapons Vol. 2 `WEAPSwrd_Sword Slide Cuts, Metallic, Impact CM4 2` | wav 192kHz/24bit | 商用可・改変可・表記不要／再配布不可・AI学習不可 | 未着手 |
| `slash_m` | 斬撃（中）のエフェクト | Sonniss GDC 2026 / David Dumais Audio - Melee Weapons Pack 2 `METLFric_SWING SCRAPE ... Long Blade 14` | wav 96kHz/24bit | 同上 | 未着手 |
| `map_capture` | 占領成立（布の層） | Sonniss GDC 2026 / Epic Stock Media - Fantasy Game 2 `CLOTHFlp_Action Inventory Open Flip Cloth Canvas Bag Slide Light 02` | wav 96kHz/24bit | 同上 | 未着手 |

「改変度」は書き出し（切り出し・音量調整・ogg 化）を済ませた時点で埋める。
