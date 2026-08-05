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
| `slash_s` | 斬撃（小）のエフェクト | Sonniss GDC 2026 / 344 Audio - Historical Weapons Vol. 2 `WEAPSwrd_Sword Slide Cuts, Metallic, Impact CM4 2` | wav 192kHz/24bit | 商用可・改変可・表記不要／再配布不可・AI学習不可 | 8.46〜9.06秒を切り出し、-1.3 dB。slash_s_recipe.txt |
| `slash_m` | 斬撃（中）のエフェクト | Sonniss GDC 2026 / David Dumais Audio - Melee Weapons Pack 2 `METLFric_SWING SCRAPE ... Long Blade 14` | wav 96kHz/24bit | 同上 | 切り出しなし、-5.8 dB。slash_m_recipe.txt |
| `holy` | 聖光のエフェクト | Sonniss GDC 2026 / Cinematic Sound Design - User Interface `Button Arp Twinkle` | wav 96kHz/24bit | 同上 | 切り出しなし、-6.7 dB。holy_recipe.txt |
| `magic_bolt` | 魔弾のエフェクト | Sonniss GDC 2026 / 344 Audio - Elemental Palette Designed Vol. 1 `WINDDsgn_Wind, Rush, Whoosh, Long x5 01` | wav 96kHz/24bit | 同上 | 飛翔のみ（0.02〜0.60秒・着弾を落とす）、+6.1 dB。magic_bolt_recipe.txt |
| `slash_l` | 斬撃（大）のエフェクト | Sonniss GDC 2020 / David Dumais Audio - Weapon Sounds - Weapon Swings `MeleeSwingsPack_96khz_Mono_DesignedSwings12` | wav 96kHz/16bit | 同上 | 切り出しなし、-6.8 dB。slash_l_recipe.txt |
| `arrow_hit` | 矢の着弾 | Sonniss GDC 2020 / SmartSoundFX – Medieval `BOW Arrow Hit 05` | wav 48kHz/24bit | 同上 | 切り出しなし、-7.6 dB。arrow_hit_recipe.txt |
| `arrow_bone_hit` | 呪いの矢の着弾（矢と同一素材） | 同上 | 同上 | 同上 | 切り出しなし、-7.6 dB。arrow_bone_hit_recipe.txt |
| `stone_hit` | 投石の着弾 | Sonniss GDC 2020 / PMSFX - Rocky Impacts `PM_RI_Source_92 Rocks Impact Hit Single Stone` | wav 192kHz/24bit | 同上 | 切り出しなし、-8.3 dB。stone_hit_recipe.txt |
| `move_ground` | 足音（重）。ground 系の移動 | Sonniss GDC 2020 / PMSFX - STEPS Dry Grass & Shrubs `PM_SDGS_186 Footstep Step Dry Grass Shrubs Pine Needles Meadow` | wav 192kHz/24bit | 同上 | 切り出しなし、+1.8 dB。move_ground_recipe.txt |
| `arrow` | 矢の発射 | Sonniss GDC 2019 / Rock The Speakerbox - Melee `MELEE - CK - ROPE WHOOSH Fast Light 01` | wav 96kHz/24bit | 同上 | 6テイク中の6本目（7.465〜8.057秒）、-4.7 dB。arrow_recipe.txt |
| `arrow_bone` | 呪いの矢の発射（矢と同一素材） | 同上 | 同上 | 同上 | 同上、-4.7 dB。arrow_bone_recipe.txt |
| `stone` | 投石の発射（同ライブラリの別テイク） | 同上 | 同上 | 同上 | 3本目（2.981〜3.754秒）、-2.9 dB。stone_recipe.txt |
| `punch` | 徒手の一撃 | Sonniss GDC 2019 / Rock The Speakerbox - Melee `MELEE - DESIGNED - HEADBUTT Crack` | wav 96kHz/24bit | 同上 | 4テイク中の2本目（1.662〜2.541秒）、-10.0 dB。punch_recipe.txt |
| `curse` | 呪い | Sonniss GDC 2019 / Sound Spark LLC – Magic Spells, Buffs and Attacks `Dark_Spell_Life_Tap_03` | wav 96kHz/24bit | 同上 | 切り出しなし、-7.0 dB。curse_recipe.txt |
| `magic_bolt_hit` | 魔弾の着弾 | Sonniss GDC 2020 / David Dumais Audio - Magic Sound FX Pack 1 `Magic_Explosion_Short19` | wav 44.1kHz/24bit | 同上 | 切り出しなし、-8.5 dB。magic_bolt_hit_recipe.txt |
| `claw` | 爪痕 | Sonniss GDC 2017 / Double Trouble Audio - Medieval Armor and Impacts `Plate_Impact_Hard_02` | wav 96kHz/24bit | 同上 | 切り出しなし、-8.6 dB。claw_recipe.txt |
| `cmb_hit_none` | 弾き返す音（損害0） | Sonniss GDC 2017 / Double Trouble Audio - Medieval Armor and Impacts `Weapon_Impact_Parry_01` | wav 96kHz/24bit | 同上 | 切り出しなし、-8.7 dB。cmb_hit_none_recipe.txt |
| `move_light_foot` | 足音（軽）。light_foot の移動 | Sonniss GDC 2017 / Tovusound - Edward Foleyart Add-On Extended Footsteps `169_Foley_Footsteps_Grass_Sneaker_Walk_Fast_Run_Jog_Close` | wav 96kHz/24bit | 同上 | 歩きの1歩（0.976〜1.29秒）、+8.9 dB。狙いは -12 dBFS。move_light_foot_recipe.txt |
| `map_capture` | 占領成立（布の層） | Sonniss GDC 2026 / Epic Stock Media - Fantasy Game 2 `CLOTHFlp_Action Inventory Open Flip Cloth Canvas Bag Slide Light 02` | wav 96kHz/24bit | 同上 | 未着手 |

「改変度」は書き出し（切り出し・音量調整・ogg 化）を済ませた時点で埋める。
