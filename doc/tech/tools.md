# 開発ツール（`tools/`）

`tools/` に置いた開発用の道具の索引。使い方と仕様は、その道具が仕える doc にある。ここは「何があるか・どう起動するか・詳細はどこか」だけを持つ。仕様をここに書き足すと各 doc と食い違うので書かない。

ツールを足したらここに1行足す。製品ビルドには含めない（export preset の除外対象 → [../backlog.md](../backlog.md)）。

## 画面ツール（Godot のシーン）

起動は下記コマンド。Godot エディタでシーンを開いて F6（指定シーンを実行）でも同じ。

| ツール | 何をする道具か | 起動 | 詳細 |
|---|---|---|---|
| `sound_check` | BGMと効果音を組み合わせて鳴らす。曲の音量差・ループの継ぎ目・効果音の被りを聴く | `godot --path . res://tools/sound_check/sound_check.tscn` | [../audio/bgm.md](../audio/bgm.md) ／ [../audio/sfx.md](../audio/sfx.md) |
| `image_check` | 画像を並べて見比べる。ユニットの頭身と、地形タイルの継ぎ目・反復 | `godot --path . res://tools/image_check/image_check.tscn` | [../art/units.md](../art/units.md) ／ [../art/terrain.md](../art/terrain.md) |
| `map_editor` | ステージJSONを盤面で編集する（地形・見た目スキン・ユニット・拠点・勝敗条件）。盤は実機と同じスキン画像で描く（画像が無いスキンは色と文字）。地形は塗り方をペン／ベタ塗りで切り替え（Ctrl+Z で直前の1操作を取り消し）。「ステージ」モードで盤の中身（地形・スキン・駒・拠点）をまとめてずらせる＝盤を広げたあと左上に描いたものを寄せ直せる（左右は2列単位。奇数列ずらすと odd-q の列の偶奇が入れ替わって形が崩れるため）。「勝敗」モードで常時ルールを含む勝利・敗北条件の一覧を見て、拠点クリックで防衛対象（奪われたら敗北）を指定できる。「イベント」モードで増援（指定ターンに盤へ加わる駒・搭載駒つき）をリストで編集できる。会話と未知キーは温存 | `godot --path . res://tools/map_editor/map_editor.tscn` | [../gdd/map.md](../gdd/map.md) |
| `combat_sim` | 戦闘計算シミュレータ。式は本体を呼ぶ＝画面の数字が実戦の数字 | `godot --path . res://tools/combat_sim/combat_sim.tscn` | [../gdd/combat.md](../gdd/combat.md) |
| `capture_board3d` | 盤だけをステージ単体で表示してPNG保存する（セレクト・HUD・会話を挟まない） | `godot --path . res://tools/capture_board3d.tscn -- <出力PNG> [ステージjsonのres://パス]` | [../adr/ADR-0003-board-3d-hybrid.md](../adr/ADR-0003-board-3d-hybrid.md) |

## 生成スクリプト

素材を「制作元」から「ゲーム用」へ変換する。いずれもリポジトリ直下で走らせる。

| ツール | 何をする道具か | 起動 | 詳細 |
|---|---|---|---|
| `gen_unit_map.ps1` | ユニットの master から map 画像（384四方・透過・64色）を書き出す | `powershell -File tools\gen_unit_map.ps1 <skin_id> … \| all` | [../art/units.md](../art/units.md) |
| `gen_unit_combat.ps1` | ユニットの master から combat 立ち絵（512四方・下端揃え・透過）を書き出す | `powershell -File tools\gen_unit_combat.ps1 <skin_id> … \| all` | [../art/units.md](../art/units.md) |
| `gen_effect.ps1` | 攻撃エフェクトの master をトリムして長辺512に収める（大小は `combat_effect.csv` の `scale` が持つので余白は焼かない） | `powershell -File tools\gen_effect.ps1 <effect_id> … \| all` | [../art/units.md](../art/units.md) |
| `gen_formation_impact.ps1` | 陣形スキルの盤の着弾エフェクトの master をトリムして長辺512に収める（絵は下向きに描く＝盤では回さない） | `powershell -File tools\gen_formation_impact.ps1 <recipe_id> … \| all` | [../art/keyvisual.md](../art/keyvisual.md) |
| `gen_terrain_tile.ps1` | 元絵をフラットトップのヘックスに切り抜いて地形タイルにする（2枚目以降は variant）。`-Object` はヘックスではなく立ち絵として書き出す（倍率は terrain_skin.csv の `map_scale`） | `powershell -File tools\gen_terrain_tile.ps1 <name> <src1> <src2> …` | [../art/terrain.md](../art/terrain.md) |
| `gen_connect_tiles.ps1` | 線方式（柵）の接続タイル64通りを、直線1枚の元絵から生成する＝腕を6方向に回して重ねる。`-NoBase` で地面を焼かず透過のまま書き出す | `powershell -File tools\gen_connect_tiles.ps1 <name> <src> -ArmFrom … -ArmTo … -BandX … -BandW … -PostHalf … [-NoBase]` | [../art/terrain.md](../art/terrain.md) |
| `gen_area_tiles.ps1` | 面方式（道）の接続タイル64通りを、全面テクスチャ1枚から生成する＝同じ絵をマスクで抜き、繋がらない側を隣の素材で覆う。`-CutTransparent` で覆わず透過のまま残す（下地を替えて使い回す＝石畳と橋） | `powershell -File tools\gen_area_tiles.ps1 <name> <src> -BandX … -BandW … -Bite … [-CutTransparent]` | [../art/terrain.md](../art/terrain.md) |
| `gen_sfx.ps1` | MuseScore の .wav から効果音 .ogg を作る（無音トリム・変換・ピーク実測）。音量は揃えず測って報告だけする。基準から外れていれば警告を出す | `powershell -File tools\gen_sfx.ps1 <sfx_id> …` | [../audio/sfx.md](../audio/sfx.md) |
| `gen_bgm.ps1` | MuseScore の .wav から BGM .ogg を作る（楽譜からループ長を算出・残響の折り返し・変換・loop=true でインポート） | `powershell -File tools\gen_bgm.ps1 <track_id> … [-Stinger] [-LoopSec <秒>]` | [../audio/bgm.md](../audio/bgm.md) |
| `gen_terrain_tiles.gd` | 地形タイルのプレースホルダ（ベタ塗りヘックス）を生成する | `godot --headless --script res://tools/gen_terrain_tiles.gd` | [../art/terrain.md](../art/terrain.md) |
| `logo/trace_sword.py` | 剣の黒シルエット PNG を SVG のパスに変換する（溝・柄頭の輪・巻きの隙間は穴として残る） | `uv run --no-project --with pillow --with numpy --with potracer python tools/logo/trace_sword.py` | [../art/promo.md](../art/promo.md) |
| `logo/build_logo.py` | タイトルロゴの SVG を組む（盤と同じカメラで7ヘックスを投影し、剣を刺し、EB Garamond をパス化して配置）。暗背景版・明背景版・小サイズ版と、開発元名を足した起動スプラッシュ版を書き出す | `uv run --no-project --with fonttools python tools/logo/build_logo.py` | [../art/promo.md](../art/promo.md) |
| `rasterize_svg.gd` | SVG を PNG にする（Godot 内蔵の ThorVG。マスクも描ける） | `godot --headless --script res://tools/rasterize_svg.gd -- <in.svg> <out.png> [倍率]` | [../art/menu.md](../art/menu.md) |

ループ長は `gen_bgm.ps1` が `.mscz` から算出する（小節数×1小節の拍数÷テンポ）。繰り返し記号やアウフタクトのある譜面はこの式が当たらないので、その時だけ `-LoopSec` で秒数を渡す。

## 使い捨ての検証スクリプト

盤や演出を実機で確かめたいときは、`tests/manual/` に SceneTree スクリプトを一時的に置いて走らせ、確認したら消す。恒久的に使う道具になった時点で `tools/` へ移し、この索引に載せる。
