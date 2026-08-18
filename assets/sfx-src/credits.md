# 効果音 権利・ライセンス台帳

本作（Steam・商用）で使う効果音の出自を素材ごとに記録する。方針 → [../../doc/audio/sfx.md](../../doc/audio/sfx.md) の「権利・ライセンス台帳」。
他者の権利を侵さないための管理なので、素材を追加したら必ずここに1行足す。書式は BGM の台帳（[../bgm-src/credits.md](../bgm-src/credits.md)）に揃える。

権利の記録は2層で、ここは素材単位の層。出所単位でライセンスと義務を持つ正本は [../../doc/sales/credits.md](../../doc/sales/credits.md)。出所そのものが新しく増えたときは、正本にも1行足す。

記載項目は sfx_id（用途）／出典／入手形式／ライセンス（商用可否・改変可否・クレジット表記の要否）／改変度。

## 自作素材

楽音系は MuseScore で自作する。原本の `.mscz` を同じディレクトリに置き、`tools/gen_sfx.ps1` で `assets/sfx/{sfx_id}.ogg` に変換する。

| sfx_id | 用途 | 出典 | 入手形式 | ライセンス | 改変度 |
|---|---|---|---|---|---|
| `ui_confirm` | 確定・決定・選択 | 自作 | MuseScore（MS Basic 音源） | 自作物＝商用可・改変可・表記不要 | 全部自作 |
| `ui_cancel` | 戻る・キャンセル | 自作 | MuseScore（MS Basic 音源） | 自作物＝商用可・改変可・表記不要 | 全部自作 |
| `ui_denied` | 操作の否定（できない） | 自作 | MuseScore（MS Basic 音源） | 自作物＝商用可・改変可・表記不要 | 全部自作 |
| `ui_hover` | ホバー強調・文字送り | 自作 | MuseScore（MS Basic 音源） | 自作物＝商用可・改変可・表記不要 | 全部自作 |
| `map_turn_player` | 自軍ターン開始 | 自作 | MuseScore（MS Basic 音源） | 自作物＝商用可・改変可・表記不要 | 全部自作 |
| `map_turn_enemy` | 敵ターン開始 | 自作 | MuseScore（MS Basic 音源） | 自作物＝商用可・改変可・表記不要 | 全部自作 |
| `holy_aria` | ホーリーアリアの発動 | 自作 | MuseScore（MS Basic 音源） | 自作物＝商用可・改変可・表記不要 | 全部自作 |
| `map_capture` | 占領成立（鐘の層） | 自作 | MuseScore（MS Basic 音源） | 自作物＝商用可・改変可・表記不要 | 全部自作。原本 map_capture_bell.mscz。布と重ねる |

## 第三者素材

物音系（足音・攻撃・命中など）はオーケストラ音源では出ないため外部調達する（[../../doc/audio/sfx.md](../../doc/audio/sfx.md) の調達方針）。クレジット表記が必要なものは指定文をそのまま転記する（自己流に変えない）。表記先は Steam ページとゲーム内クレジット。

素材プールは Sonniss GDC Game Audio Bundle（[../../doc/audio/sonniss.md](../../doc/audio/sonniss.md)）。全年共通で商用可・改変可・表記不要だが、再配布不可のため元の `.wav` はリポジトリに入れない（`assets/sfx-src/**/*.wav` は .gitignore 済み）。AI 学習への利用も禁止されている。

| sfx_id | 用途 | 出典 | 入手形式 | ライセンス | 改変度 |
|---|---|---|---|---|---|
| `slash_s` | 斬撃（小）のエフェクト | Sonniss GDC 2026 / 344 Audio - Historical Weapons Vol. 2 `WEAPSwrd_Sword Slide Cuts, Metallic, Impact CM4 2` | wav 192kHz/24bit | 商用可・改変可・表記不要／再配布不可・AI学習不可 | 8.46〜9.06秒を切り出し、-1.3 dB。slash_s_recipe.txt |
| `slash_m` | 斬撃（中）のエフェクト | Sonniss GDC 2026 / David Dumais Audio - Melee Weapons Pack 2 `METLFric_SWING SCRAPE ... Long Blade 14` | wav 96kHz/24bit | 同上 | 切り出しなし、-5.8 dB。slash_m_recipe.txt |
| `holy` | 聖光のエフェクト | Sonniss GDC 2026 / Cinematic Sound Design - User Interface `Button Arp Twinkle` | wav 96kHz/24bit | 同上 | 切り出しなし、-6.7 dB。holy_recipe.txt |
| `purify` | ピュリファイの発動（聖職） | 同上 | 同上 | 同上 | `holy` と同一の切り出し（切り出しなし）、-6.7 dB。purify_recipe.txt |
| `magic_bolt` | 魔弾のエフェクト | Sonniss GDC 2026 / 344 Audio - Elemental Palette Designed Vol. 1 `WINDDsgn_Wind, Rush, Whoosh, Long x5 01` | wav 96kHz/24bit | 同上 | 飛翔のみ（0.02〜0.60秒・着弾を落とす）、+6.1 dB。magic_bolt_recipe.txt |
| `slash_l` | 斬撃（大）のエフェクト | Sonniss GDC 2020 / David Dumais Audio - Weapon Sounds - Weapon Swings `MeleeSwingsPack_96khz_Mono_DesignedSwings12` | wav 96kHz/16bit | 同上 | 切り出しなし、-6.8 dB。slash_l_recipe.txt |
| `arrow_hit` | 矢の着弾 | Sonniss GDC 2020 / SmartSoundFX – Medieval `BOW Arrow Hit 05` | wav 48kHz/24bit | 同上 | 切り出しなし、-7.6 dB。arrow_hit_recipe.txt |
| `arrow_bone_hit` | 呪いの矢の着弾（矢と同一素材） | 同上 | 同上 | 同上 | 切り出しなし、-7.6 dB。arrow_bone_hit_recipe.txt |
| `arrow_bolt_hit` | 太矢の着弾（矢と同一素材） | 同上 | 同上 | 同上 | 切り出しなし、-7.6 dB。arrow_bolt_hit_recipe.txt |
| `arrow_crossbow_hit` | クロスボウの矢の着弾（矢と同一素材） | 同上 | 同上 | 同上 | 切り出しなし、-7.6 dB。arrow_crossbow_hit_recipe.txt |
| `stone_hit` | 投石の着弾 | Sonniss GDC 2020 / PMSFX - Rocky Impacts `PM_RI_Source_92 Rocks Impact Hit Single Stone` | wav 192kHz/24bit | 同上 | 切り出しなし、-8.3 dB。stone_hit_recipe.txt |
| `move_ground` | 足音（重）。ground 系の移動 | Sonniss GDC 2020 / PMSFX - STEPS Dry Grass & Shrubs `PM_SDGS_186 Footstep Step Dry Grass Shrubs Pine Needles Meadow` | wav 192kHz/24bit | 同上 | 切り出しなし、+1.8 dB。move_ground_recipe.txt |
| `arrow` | 矢の発射 | Sonniss GDC 2019 / Rock The Speakerbox - Melee `MELEE - CK - ROPE WHOOSH Fast Light 01` | wav 96kHz/24bit | 同上 | 6テイク中の6本目（7.465〜8.057秒）、-4.7 dB。arrow_recipe.txt |
| `arrow_bone` | 呪いの矢の発射（矢と同一素材） | 同上 | 同上 | 同上 | 同上、-4.7 dB。arrow_bone_recipe.txt |
| `stone` | 投石の発射（同ライブラリの別テイク） | 同上 | 同上 | 同上 | 3本目（2.981〜3.754秒）、-2.9 dB。stone_recipe.txt |
| `arrow_bolt` | 太矢の発射（バリスタ・同ファイルの別テイク） | 同上 | 同上 | 同上 | 4本目（4.575〜5.060秒）、-5.1 dB。arrow_bolt_recipe.txt |
| `arrow_crossbow` | クロスボウの矢の発射（ハンター・太矢と同一素材） | 同上 | 同上 | 同上 | 同上、-5.1 dB。arrow_crossbow_recipe.txt |
| `punch` | 徒手の一撃 | Sonniss GDC 2019 / Rock The Speakerbox - Melee `MELEE - DESIGNED - HEADBUTT Crack` | wav 96kHz/24bit | 同上 | 4テイク中の2本目（1.662〜2.541秒）、-10.0 dB。punch_recipe.txt |
| `curse` | 呪い | Sonniss GDC 2019 / Sound Spark LLC – Magic Spells, Buffs and Attacks `Dark_Spell_Life_Tap_03` | wav 96kHz/24bit | 同上 | 切り出しなし、-7.0 dB。curse_recipe.txt |
| `curse_wisp` | 呪いの燐気（ゴースト） | Sonniss GDC 2020 / Fox Audio Post-Production - Ghost Whoosh `SFX_Ghost_Whoosh_Male_03` | wav 96kHz/24bit | 同上 | 山の頭から（1.30〜2.10秒）、-6.0 dB。curse_wisp_recipe.txt |
| `dread_touch` | ドレッドタッチの発動（ゴースト） | 同上 | 同上 | 同上 | `curse_wisp` と同一の切り出し（1.30〜2.10秒）、-6.0 dB。dread_touch_recipe.txt |
| `magic_bolt_hit` | 魔弾の着弾 | Sonniss GDC 2020 / David Dumais Audio - Magic Sound FX Pack 1 `Magic_Explosion_Short19` | wav 44.1kHz/24bit | 同上 | 切り出しなし、-8.5 dB。magic_bolt_hit_recipe.txt |
| `claw` | 爪痕 | Sonniss GDC 2017 / Double Trouble Audio - Medieval Armor and Impacts `Plate_Impact_Hard_02` | wav 96kHz/24bit | 同上 | 切り出しなし、-8.6 dB。claw_recipe.txt |
| `cmb_hit_none` | 弾き返す音（損害0） | Sonniss GDC 2017 / Double Trouble Audio - Medieval Armor and Impacts `Weapon_Impact_Parry_01` | wav 96kHz/24bit | 同上 | 切り出しなし、-8.7 dB。cmb_hit_none_recipe.txt |
| `menu_slide` | 難易度帯ボードを繰る | Sonniss GDC 2026 / Epic Stock Media - Fantasy Game 2 `CLOTHFlp_Action Inventory Open Flip Cloth Canvas Bag Slide Light 02` | wav 96kHz/24bit | 同上 | 切り出しなし、-7.9 dB。menu_slide_recipe.txt。`map_capture` と同じ収録を共用 |
| `map_board` | 輸送への乗車・降車 | Sonniss GDC 2019 / Rock The Speakerbox - Melee `MELEE - DESIGNED - HEADBUTT Crack` | wav 96kHz/24bit | 同上 | 4テイク中の4本目（5.286〜6.219秒）、-9.0 dB。map_board_recipe.txt。`punch` と同じ収録を共用 |
| `move_flight` | 羽ばたき。flight の移動 | Sonniss GDC 2020 / Systematic-Sound - Sound Themes - Modern Cloth Foley 01 `SFX CLOTH Foley Jacket Synthetic Soft Shell Whoosh Flutter` | wav 96kHz/24bit | 同上 | 7テイク中3本目の中心（5.94〜6.36秒）、-9.0 dB。move_flight_recipe.txt |
| `trinity_spell` | トリニティスペルの発射 | Sonniss GDC 2018 / Gamemaster Audio - Magic and Spell Sounds `water_blast_projectile_spell_03` | wav 96kHz/24bit | 同上 | 切り出しなし、-9.0 dB。trinity_spell_recipe.txt |
| `trinity_spell_hit` | トリニティスペルの着弾 | Sonniss GDC 2020 / David Dumais Audio - Spells Magic 1 `Magic_Spells_Impact_Creation20` | wav 96kHz/24bit | 同上 | 切り出しなし、-9.0 dB。trinity_spell_hit_recipe.txt |
| `divine_judgment` | ディバインジャッジメントの発動 | Sonniss GDC 2026 / Epic Stock Media - Anime Game `DSGNStngr_Power Up Bright Positive Successful Light Saturation Crash Shimmer 05` | wav 96kHz/24bit | 同上 | 切り出しなし、-8.0 dB。divine_judgment_recipe.txt |
| `divine_judgment_hit` | ディバインジャッジメントの着弾 | Sonniss GDC 2019 / Airborne Sound - Crisis Accents `Impact,Sound Design,Hit,Chime,Resonant Hit,Chime Accent,Tinkle,Fast` | wav 96kHz/24bit | 同上 | 頭から 1.90 秒（末尾 0.10 秒フェード）、-8.9 dB。divine_judgment_hit_recipe.txt |
| `move_light_foot` | 足音（軽）。light_foot の移動 | Sonniss GDC 2017 / Tovusound - Edward Foleyart Add-On Extended Footsteps `169_Foley_Footsteps_Grass_Sneaker_Walk_Fast_Run_Jog_Close` | wav 96kHz/24bit | 同上 | 歩きの1歩（0.976〜1.29秒）、+8.9 dB。狙いは -12 dBFS。move_light_foot_recipe.txt |
| `move_float` | 浮遊。ピクシー・ゴースト・レイスの移動 | 同上（同じ収録の別の1歩） | 同上 | 同上 | 歩きの1歩（1.620〜1.940秒）、+6.2 dB。move_float_recipe.txt |
| `move_propeller` | プロペラ。飛空艇の移動 | Sonniss GDC 2020 / Systematic-Sound - Sound Themes - Modern Cloth Foley 01 `SFX CLOTH Foley Jacket Synthetic Soft Shell Whoosh Flutter` | wav 96kHz/24bit | 同上 | `move_flight` と同一の切り出し（5.94〜6.36秒）、-9.0 dB。鳴らす間隔だけで別物にする。move_propeller_recipe.txt |
| `map_capture` | 占領成立（布の層） | Sonniss GDC 2026 / Epic Stock Media - Fantasy Game 2 `CLOTHFlp_Action Inventory Open Flip Cloth Canvas Bag Slide Light 02` | wav 96kHz/24bit | 同上 | 切り出しなし、0.45秒遅らせて -8.3 dB。鐘（自作）と重ねる。map_capture_recipe.txt |
| `cannonball` | 砲弾の発射（飛空艇） | Sonniss GDC 2016 / Fascinated Sound - The Gun Locker SFX Pack `Automatic Cannon - MK44 - 03 - Single Shot with Report 03` | wav 96kHz/24bit | 同上 | 発砲だけ（0.24〜2.05秒・立ち上がりの手前を落とす）、-9.0 dB。cannonball_recipe.txt |
| `cannonball_hit` | 砲弾の着弾（同じ収録の後半） | 同上 | 同上 | 同上 | Report だけ（2.18〜3.05秒）、-8.0 dB。cannonball_hit_recipe.txt。1本に発砲と着弾が両方入っている |
| `fire_breath` | 竜の火炎の息（レッドドラゴン） | Sonniss GDC 2018 / Soundrangers - Whooshes And Transitions `torch_whoosh_20` | wav 96kHz/24bit | 同上 | 切り出し（0.05〜1.10秒・末尾 0.25 秒フェード）、-6.5 dB。fire_breath_recipe.txt |
| `scream_female` | 会話で鳴らす女性の悲鳴 | Sonniss GDC 2017 / Soundopolis - Halloween 101 `SH101_Human_Female_Scream_Alien_OtherWorldly_Fienup_002` | wav 96kHz/24bit | 同上 | 切り出しなし、-5.9 dB。scream_female_recipe.txt |
| `scream` | 魔法の悲鳴（マンドラゴラ） | Sonniss GDC 2015 / SoundMorph - Bloody Nightmare `Bloody Nightmare - Horror Impacts - Robotic Scream` | wav 96kHz/24bit | 同上 | 頭から（0.10〜1.60秒・末尾 0.40 秒フェード）、-6.8 dB。scream_recipe.txt |
| `venom_fang` | ヴェノムファングの発動（ロックサーペント。顎と同一素材） | Sonniss GDC 2015 / Mattia Cellotto - Crunch Mode `Celery,Bite,Crunch,Slow,Bone,Break,Stick,Creak,Various07` | wav 96kHz/24bit | 同上 | `bite` と同一の切り出し（0.18〜0.62秒）、-5.5 dB。venom_fang_recipe.txt |
| `pixie_dust` | ピクシーダストの発動（ピクシー。魔法の粉と同一素材） | Sonniss GDC 2026 / Cinematic Sound Design - User Interface `Interface Plucks Happy` | wav 96kHz/24bit | 同上 | `magic_dust` と同一の切り出し（切り出しなし）、-5.5 dB。pixie_dust_recipe.txt |
| `bite` | 大蛇の顎（ロックサーペント・ワイアーム） | Sonniss GDC 2015 / Mattia Cellotto - Crunch Mode `Celery,Bite,Crunch,Slow,Bone,Break,Stick,Creak,Various07` | wav 96kHz/24bit | 同上 | 2つの山（0.18〜0.62秒・前後にフェード）、-5.5 dB。bite_recipe.txt |
| `pincer` | 大鋏（スコーピオン。斬撃（中）と同一素材） | Sonniss GDC 2026 / David Dumais Audio - Melee Weapons Pack 2 `METLFric_SWING SCRAPE ... Long Blade 14` | wav 96kHz/24bit | 同上 | `slash_m` と同一の切り出し（切り出しなし）、-5.8 dB。pincer_recipe.txt |
| `spore` | 胞子の発射（マタンゴ）。着弾音は持たない | Sonniss GDC 2024 / Justsoundeffects - Steampunk Gadgets `AIRBrst_Steam Release Short 03_JSE_SG_Mono` | wav 96kHz/24bit | 同上 | 5テイク中の5本目（7.15〜7.70秒・前後にフェード）、-2.9 dB。spore_recipe.txt |
| `magic_dust` | 魔法の粉の発射（ピクシー）。着弾音は持たない | Sonniss GDC 2026 / Cinematic Sound Design - User Interface `Interface Plucks Happy` | wav 96kHz/24bit | 同上 | 切り出しなし、-5.5 dB。magic_dust_recipe.txt |
| `fire_ball` | 火球の発射（オークメイジ） | Sonniss GDC 2026 / Epic Stock Media - Elemental Mutation Whooshes and Impacts `FIREWhsh_Whoosh Fire Deep Growl Monster Saturated Crisp 03` | wav 96kHz/24bit | 同上 | 山の頭から（0.55〜1.10秒・前後にフェード）、-8.0 dB。fire_ball_recipe.txt |
| `fire_ball_hit` | 火球の着弾（魔弾と同一素材） | Sonniss GDC 2020 / David Dumais Audio - Magic Sound FX Pack 1 `Magic_Explosion_Short19` | wav 44.1kHz/24bit | 同上 | `magic_bolt_hit` と同一の切り出し（切り出しなし）、-8.5 dB。fire_ball_hit_recipe.txt |
| `quake` | 坑道が抜ける地響き（冒険譚3 st3 の会話） | Sonniss GDC 2020 / Stefano Cremona - Explosions `DeepExplosion02` | wav 96kHz/24bit | 同上 | 頭から 3.40 秒（2.90 秒からフェード）、-9.0 dB。quake_recipe.txt |

「改変度」は書き出し（切り出し・音量調整・ogg 化）を済ませた時点で埋める。
