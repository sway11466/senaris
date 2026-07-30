# 開発ツール（`tools/`）

`tools/` に置いた開発用の道具の索引。使い方と仕様は、その道具が仕える doc にある。ここは「何があるか・どう起動するか・詳細はどこか」だけを持つ。仕様をここに書き足すと各 doc と食い違うので書かない。

ツールを足したらここに1行足す。製品ビルドには含めない（export preset の除外対象 → [../backlog.md](../backlog.md)）。

## 画面ツール（Godot のシーン）

起動は下記コマンド。Godot エディタでシーンを開いて F6（指定シーンを実行）でも同じ。

| ツール | 何をする道具か | 起動 | 詳細 |
|---|---|---|---|
| `sound_check` | BGMと効果音を組み合わせて鳴らす。曲の音量差・ループの継ぎ目・効果音の被りを聴く | `godot --path . res://tools/sound_check/sound_check.tscn` | [../audio/bgm.md](../audio/bgm.md) ／ [../audio/sfx.md](../audio/sfx.md) |
| `image_check` | 画像を並べて見比べる。ユニットの頭身と、地形タイルの継ぎ目・反復 | `godot --path . res://tools/image_check/image_check.tscn` | [../art/units.md](../art/units.md) ／ [../art/terrain.md](../art/terrain.md) |
| `map_editor` | ステージJSONを盤面で編集する（地形・見た目スキン・ユニット・拠点）。地形は塗り方をペン／ベタ塗りで切り替え（Ctrl+Z で直前の1操作を取り消し）。会話と未知キーは温存 | `godot --path . res://tools/map_editor/map_editor.tscn` | [../gdd/map.md](../gdd/map.md) |
| `combat_sim` | 戦闘計算シミュレータ。式は本体を呼ぶ＝画面の数字が実戦の数字 | `godot --path . res://tools/combat_sim/combat_sim.tscn` | [../gdd/combat.md](../gdd/combat.md) |
| `capture_board3d` | 盤だけをステージ単体で表示してPNG保存する（セレクト・HUD・会話を挟まない） | `godot --path . res://tools/capture_board3d.tscn -- <出力PNG> [ステージjsonのres://パス]` | [../adr/ADR-0003-board-3d-hybrid.md](../adr/ADR-0003-board-3d-hybrid.md) |

## 生成スクリプト

素材を「制作元」から「ゲーム用」へ変換する。いずれもリポジトリ直下で走らせる。

| ツール | 何をする道具か | 起動 | 詳細 |
|---|---|---|---|
| `gen_unit_map.ps1` | ユニットの master から map 画像（384四方・透過・64色）を書き出す | `powershell -File tools\gen_unit_map.ps1 <skin_id> … \| all` | [../art/units.md](../art/units.md) |
| `gen_unit_combat.ps1` | ユニットの master から combat 立ち絵（512四方・下端揃え・透過）を書き出す | `powershell -File tools\gen_unit_combat.ps1 <skin_id> … \| all` | [../art/units.md](../art/units.md) |
| `gen_terrain_tile.ps1` | 元絵をフラットトップのヘックスに切り抜いて地形タイルにする（2枚目以降は variant） | `powershell -File tools\gen_terrain_tile.ps1 <name> <src1> <src2> …` | [../art/terrain.md](../art/terrain.md) |
| `gen_sfx.ps1` | MuseScore の .wav から効果音 .ogg を作る（無音トリム・ピーク -3dBFS 揃え・変換） | `powershell -File tools\gen_sfx.ps1 <sfx_id> …` | [../audio/sfx.md](../audio/sfx.md) |
| `gen_terrain_tiles.gd` | 地形タイルのプレースホルダ（ベタ塗りヘックス）を生成する | `godot --headless --script res://tools/gen_terrain_tiles.gd` | [../art/terrain.md](../art/terrain.md) |

BGM には生成スクリプトが無い。ループ加工と Ogg 変換を ffmpeg のコマンドで直に行う（[../audio/bgm.md](../audio/bgm.md) §制作ワークフロー）。

## 使い捨ての検証スクリプト

盤や演出を実機で確かめたいときは、`tests/manual/` に SceneTree スクリプトを一時的に置いて走らせ、確認したら消す。恒久的に使う道具になった時点で `tools/` へ移し、この索引に載せる。
