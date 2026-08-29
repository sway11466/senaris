# 開発ツール（`godot/tools/`）

`godot/tools/` に置いた開発用の道具の索引。使い方と仕様は、その道具が仕える doc にある。ここは「何があるか・どう起動するか・詳細はどこか」だけを持つ。仕様をここに書き足すと各 doc と食い違うので書かない。

ツールを足したらここに1行足す。配布ビルドには含めない（除外の設定 → [build.md](build.md)）。

## 画面ツール（Godot のシーン）

起動は下記コマンド。Godot エディタでシーンを開いて F6（指定シーンを実行）でも同じ。

| ツール | 何をする道具か | 起動 | 詳細 |
|---|---|---|---|
| `sound_check` | BGMと効果音を組み合わせて鳴らす。曲の音量差・ループの継ぎ目・効果音の被りを聴く | `godot --path godot res://tools/sound_check/sound_check.tscn` | [../audio/bgm.md](../audio/bgm.md) ／ [../audio/sfx.md](../audio/sfx.md) |
| `image_check` | 画像を並べて見比べる。ユニットの頭身と、地形タイルの継ぎ目・反復 | `godot --path godot res://tools/image_check/image_check.tscn` | [../art/units.md](../art/units.md) ／ [../art/terrain.md](../art/terrain.md) |
| `map_editor` | ステージJSONを盤面で編集する（地形・見た目スキン・ユニット・拠点・勝敗条件）。盤は実機と同じスキン画像で描く（画像が無いスキンは色と文字）。地形は塗り方をペン／ベタ塗りで切り替え（Ctrl+Z で直前の1操作を取り消し）。地形の分類は先頭が「基本地形」＝各地形タイプの素のスキンを横断で並べたもの（盤の下地を分類を切り替えずに塗れる）。「ステージ」モードで盤の中身（地形・スキン・駒・拠点）をまとめてずらせる＝盤を広げたあと左上に描いたものを寄せ直せる（左右は2列単位。奇数列ずらすと odd-q の列の偶奇が入れ替わって形が崩れるため）。「勝敗」モードで常時ルールを含む勝利・敗北条件の一覧を見て、拠点クリックで防衛対象（奪われたら敗北）を指定できる。「イベント」モードで増援（指定ターンに盤へ加わる駒・搭載駒つき）をリストで編集できる。会話と未知キーは温存 | `godot --path godot res://tools/map_editor/map_editor.tscn` | [../gdd/map.md](../gdd/map.md) |
| `combat_sim` | 戦闘計算シミュレータ。式は本体を呼ぶ＝画面の数字が実戦の数字 | `godot --path godot res://tools/combat_sim/combat_sim.tscn` | [../gdd/combat.md](../gdd/combat.md) |
| `capture_board3d` | 盤だけをステージ単体で表示してPNG保存する（セレクト・HUD・会話を挟まない） | `godot --path godot res://tools/capture_board3d.tscn -- <出力PNG> [ステージjsonのres://パス]` | [../adr/ADR-0003-board-3d-hybrid.md](../adr/ADR-0003-board-3d-hybrid.md) |
| `marketing/shot_stage` | marketing用スクリーンショット。盤を実機の見た目で表示し、駒を選択して移動範囲が出た状態を高解像度PNGで保存する（HUD・会話なし・盤全体をフィット・ロケール英語固定） | `godot --path godot res://tools/marketing/shot_stage.tscn -- <出力PNG> <ステージjsonのres://パス> [--select <col,row>] [--size <WxH>]` | [../sales/marketing.md](../sales/marketing.md) |
| `marketing/shot_screen` | marketing用スクリーンショット。`main.tscn` をそのまま起動し、タイトルだけ伏せて撮る＝実機の画面まるごと（盤＋HUD＋情報パネル＋ターン板＋ロゴ）。`--attack` で攻撃を、`--formation` で陣形スキルを1回通し、演出中を連写する（出力先はフォルダ扱い）。`--talk` は intro の会話を指定行数だけ進めて撮る。`--select-screen` は盤ではなく酒場の冒険譚選択を開いて撮り、`--fresh` を足すと進捗を空の別ファイルに差し替える（焼き印が絵に重ならない・手元の進捗は触らない）。ロケール英語固定 | `godot --path godot res://tools/marketing/shot_screen.tscn -- <出力PNG> <ステージjsonのres://パス> [--select <col,row>] [--frame <c1,r1,c2,r2>] [--attack <c1,r1,c2,r2>] [--formation <recipe> --leader <c,r> --target <c,r>] [--talk <行数>] [--select-screen] [--fresh] [--size <WxH>] [--count <枚数>] [--interval <秒>]` | [../sales/marketing.md](../sales/marketing.md) |
| `marketing/shot_combat` | marketing用スクリーンショット。戦闘演出を1回再生し、演出中を一定間隔で連写してPNG保存する（実機と同じ結線＝盤＋暗転＋演出窓。連番から良い瞬間を選ぶ） | `godot --path godot res://tools/marketing/shot_combat.tscn -- <出力フォルダ> <ステージjsonのres://パス> --attacker <col,row> --target <col,row> [--size <WxH>] [--count <枚数>] [--interval <秒>]` | [../sales/marketing.md](../sales/marketing.md) |

## 生成スクリプト

素材を「制作元」から「ゲーム用」へ変換する。いずれもリポジトリ直下で走らせる。

| ツール | 何をする道具か | 起動 | 詳細 |
|---|---|---|---|
| `gen_unit_map.ps1` | ユニットの master から map 画像（384四方・透過・64色）を書き出す | `powershell -File godot\tools\gen_unit_map.ps1 <skin_id> … \| all` | [../art/units.md](../art/units.md) |
| `gen_unit_combat.ps1` | ユニットの master から combat 立ち絵（512四方・下端揃え・透過）を書き出す | `powershell -File godot\tools\gen_unit_combat.ps1 <skin_id> … \| all` | [../art/units.md](../art/units.md) |
| `gen_effect.ps1` | 攻撃エフェクトの master をトリムして長辺512に収める（大小は `combat_effect.csv` の `scale` が持つので余白は焼かない） | `powershell -File godot\tools\gen_effect.ps1 <effect_id> … \| all` | [../art/units.md](../art/units.md) |
| `gen_formation_impact.ps1` | 陣形スキルの盤の着弾エフェクトの master をトリムして長辺512に収める（絵は下向きに描く＝盤では回さない） | `powershell -File godot\tools\gen_formation_impact.ps1 <recipe_id> … \| all` | [../art/keyvisual.md](../art/keyvisual.md) |
| `gen_terrain_tile.ps1` | 元絵をフラットトップのヘックスに切り抜いて地形タイルにする（2枚目以降は variant）。`-Object` はヘックスではなく立ち絵として書き出す（幅はヘックス幅比＝terrain_skin.csv の `map_scale`） | `powershell -File godot\tools\gen_terrain_tile.ps1 <name> <src1> <src2> …` | [../art/terrain.md](../art/terrain.md) |
| `gen_connect_tiles.ps1` | 線方式（柵）の接続タイル64通りを、直線1枚の元絵から生成する＝腕を6方向に回して重ねる。`-NoBase` で地面を焼かず透過のまま書き出す | `powershell -File godot\tools\gen_connect_tiles.ps1 <name> <src> -ArmFrom … -ArmTo … -BandX … -BandW … -PostHalf … [-NoBase]` | [../art/terrain.md](../art/terrain.md) |
| `gen_area_tiles.ps1` | 面方式（道）の接続タイル64通りを、全面テクスチャ1枚から生成する＝同じ絵をマスクで抜き、繋がらない側を隣の素材で覆う。`-CutTransparent` で覆わず透過のまま残す（下地を替えて使い回す） | `powershell -File godot\tools\gen_area_tiles.ps1 <name> <src> -BandX … -BandW … -Bite … [-CutTransparent]` | [../art/terrain.md](../art/terrain.md) |
| `gen_bridge_tiles.ps1` | 橋の12タイル（幅の役4種×軸3種）を、床板テクスチャ1枚＋欄干の帯1枚から合成する。`-CombatFront` で戦闘の手前の帯も12スキンぶん複製 | `powershell -File godot\tools\gen_bridge_tiles.ps1 <name> -Deck <src> -DeckX … -DeckW … -Rail <src> -RailX … -RailY … -RailW … -RailH … [-CombatFront <png>]` | [../art/terrain.md](../art/terrain.md) §3.7 |
| `gen_sfx.ps1` | MuseScore の .wav から効果音 .ogg を作る（無音トリム・変換・ピーク実測）。音量は揃えず測って報告だけする。基準から外れていれば警告を出す | `powershell -File godot\tools\gen_sfx.ps1 <sfx_id> …` | [../audio/sfx.md](../audio/sfx.md) |
| `gen_bgm.ps1` | MuseScore の .wav から BGM .ogg を作る（楽譜からループ長を算出・残響の折り返し・変換・loop=true でインポート） | `powershell -File godot\tools\gen_bgm.ps1 <track_id> … [-Stinger] [-LoopSec <秒>]` | [../audio/bgm.md](../audio/bgm.md) |
| `gen_terrain_tiles.gd` | 地形タイルのプレースホルダ（ベタ塗りヘックス）を生成する | `godot --headless --script res://tools/gen_terrain_tiles.gd` | [../art/terrain.md](../art/terrain.md) |
| `logo/trace_sword.py` | 剣の黒シルエット PNG を SVG のパスに変換する（溝・柄頭の輪・巻きの隙間は穴として残る） | `uv run --no-project --with pillow --with numpy --with potracer python tools/logo/trace_sword.py` | [../art/logo.md](../art/logo.md) |
| `logo/trace_staff.py` | 杖の黒シルエット画像を SVG のパスに変換する（渦の抜けは穴として残る） | `uv run --no-project --with pillow --with numpy --with potracer python tools/logo/trace_staff.py` | [../art/logo.md](../art/logo.md) |
| `logo/build_logo.py` | タイトルロゴの SVG を組む（盤と同じカメラで7ヘックスを投影し、剣と杖をクロスさせて刺し、EB Garamond をパス化して配置）。暗背景版・明背景版・小サイズ版、開発元名を足した起動スプラッシュ版、文字を落としたアプリアイコン版を書き出す | `uv run --no-project --with fonttools python tools/logo/build_logo.py` | [../art/logo.md](../art/logo.md) |
| `marketing/build_lineup.py` | ユニットの戦闘立ち絵を横一列に向かい合わせで並べたPNGを組む（左＝プレイヤー陣営＝右向き・右＝敵陣営＝左向き。反転しない） | `uv run --no-project --with pillow python godot/tools/marketing/build_lineup.py --left <skin,…> --right <skin,…> -o <png>` | [../sales/marketing.md](../sales/marketing.md) |
| `keyvisual/build_keyvisual.py` | キービジュアルを組む。小＝ロゴの盤常設版と赤竜の立ち絵を地の上に置く（4倍で組んでから縮小、寸法は `SPECS`）／中＝生成した1枚絵にフル版ロゴを重ねる（位置は `M_SPEC`。ロゴの PNG は `rasterize_svg.gd` で SVG から焼いた中間物） | `uv run --no-project --with pillow python tools/keyvisual/build_keyvisual.py` | [../sales/marketing.md](../sales/marketing.md) |
| `keyvisual/build_wanted_card.py` | 手配書の貼り紙の絵（card スロット）を組む。ユニットのマスター絵から顔を切り、`WANTED` を手前に重ねる（紙は敷かない＝背景は透明。下の羊皮紙が地になる） | `uv run --no-project --with pillow python godot/tools/keyvisual/build_wanted_card.py --skin <skin_id> --src <units-src の陣営フォルダ> -o <png>` | [../art/keyvisual.md](../art/keyvisual.md) |
| `logo/build_icon.ps1` | アプリアイコンを焼く（`build_icon.gd` で各寸法の PNG にし、ImageMagick で `.ico` に束ねる） | `powershell -ExecutionPolicy Bypass -File godot	ools\logouild_icon.ps1` | [../art/icon.md](../art/icon.md) |
| `logo/build_icon.gd` | アイコンの SVG を各寸法ちょうどの PNG に焼く（48px 以下は1枚版・64px 以上は7枚版）。見え方の確認用に暗い地と明るい地へ並べた1枚も出す | `godot --headless --path godot --script res://tools/logo/build_icon.gd` | [../art/icon.md](../art/icon.md) |
| `rasterize_svg.gd` | SVG を PNG にする（Godot 内蔵の ThorVG。マスクも描ける） | `godot --headless --script res://tools/rasterize_svg.gd -- <in.svg> <out.png> [倍率]` | [../art/menu.md](../art/menu.md) |

ループ長は `gen_bgm.ps1` が `.mscz` から算出する（小節数×1小節の拍数÷テンポ）。繰り返し記号やアウフタクトのある譜面はこの式が当たらないので、その時だけ `-LoopSec` で秒数を渡す。

## ビルド

配布ビルドを作る道具。設計と手順は [build.md](build.md)。

| ツール | 何をする道具か | 起動 | 詳細 |
|---|---|---|---|
| `build/build.ps1` | 配布ビルドを作る（エクスポート → ライセンス文を添える → 出力の中身を一覧） | `powershell -File godot	oolsuilduild.ps1 <プリセット名>` | [build.md](build.md) |
| `build/gen_export_filters.gd` | 収録リスト（`build/contents.json`）から必要な素材を導出し、除外フィルタを `export_presets.cfg` へ書き出す。落としたものの一覧も出す | `godot --headless --path godot --script res://tools/build/gen_export_filters.gd` | [build.md](build.md) |
| `build/gen_licenses.gd` | 配布物に添えるライセンス文を組む（Godot のライセンスAPI＋素材の隣の LICENSE／NOTICE）。書き出し先は `assets/licenses/` | `godot --headless --path godot --script res://tools/build/gen_licenses.gd` | [build.md](build.md) |

## 使い捨ての検証スクリプト

盤や演出を実機で確かめたいときは、`godot/tests/manual/` に SceneTree スクリプトを一時的に置いて走らせ、確認したら消す。恒久的に使う道具になった時点で `godot/tools/` へ移し、この索引に載せる。
