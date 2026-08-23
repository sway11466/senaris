extends CanvasLayer
class_name CombatStage
## 演出の舞台。窓・暗幕・地面・隊列・立ち絵・兵量バー・エフェクト・スキップを持つ。
## 「誰がいつ何をするか」＝進行は持たない。進行は継承側が play() として足す：
##   戦闘 → CombatScene（ため→着弾→反撃→幕引き）
##   ユニットスキル → SkillScene（ため→発動→幕引き。兵量は動かない）
## 仕様 → doc/tech/combat_scene.md
## 窓は盤エリア（UiLayout.board_area）の中央に置き、右の InfoPanel は隠さない＝
## 補正チェーンなどの詳細内訳を演出と同時に読める（演出=結果／右パネル=根拠）。
## 暗転は共通基盤（ScreenLighting・層40）に頼む＝_open で掛け、_close_now で明ける。
## InfoPanel は前面パネル層（45）で幕より前に浮くので暗くならない。本層（50）は窓だけを持つ。
## 状態は持たず play() のたびに引数から導出して描く。

signal finished  # 演出が閉じた（自動クローズ or クリック）。AIターンのテンポ制御が待つ。

const POS := [  # 散開スキャッター隊列（x:奥0→前1／y:上0→下1）。並び順=重心から近い順で兵数少でも中央に寄る。combat_scene.md
	# x で3列に分かれる（後列 0.12/0.23/0.34・中列 0.45/0.55・前列 0.66/0.77/0.88）。
	# 後列は y を大きく（画面下へ）、前列は y を小さく（画面上へ）取って、地面の傾きで寝ていた
	# 隊列を起こす＝3列が斜めに潰れず、前後の重なりが減る。
	Vector2(0.23, 0.62), Vector2(0.45, 0.36), Vector2(0.55, 0.68), Vector2(0.77, 0.42),
	Vector2(0.66, 0.10), Vector2(0.34, 0.94), Vector2(0.12, 0.30), Vector2(0.88, 0.74),
]
const SINGLE_POS := Vector2(0.50, 0.55)  # single（複製しない駒）の立ち位置。隊列の重心あたりに1体だけ置く
const SINGLE_SCALE := 1.4  # single だけ一段大きく描く（隊列8体ぶんの面積を1体で受けるので、等倍だと画が空く）
const MAX_TROOPS := 8  # 兵量バーの目盛り数＝戦闘ルールの上限（doc/gdd/combat.md）。POS の枠数と同じ
const GROUND_BLEED := 8.0  # 地面を窓より外へ広げる量（シェイクで縁が覗かないように）
const CORNER_RADIUS := 0.09   # 窓の角を丸める半径（短辺に対する比）
const CORNER_SEGMENTS := 6    # 角の四分円の分割数。これ未満だと円弧の折れが見える
## 水平線の高さ（窓の高さに対する比）。奥の背景を持つステージだけ引く。固定値＝ステージや
## 地形で動かさない。重ね絵の下端（FEATURE_BOTTOM）より0.08上に置く＝守り手側に建つ塊が
## 水平線に胴を横切られない。絵の中で奥に建つ建物は土台が下端より少し上（町で0.04）なので、
## すぐ上（0.40）だと奥の土台の下に背景が覗く。
const HORIZON := 0.36
const HAZE_COLOR := Color(0.05, 0.06, 0.09)  # 奥に敷く靄の色（わずかに寒色＝空気遠近）
const EDGE_COLOR := Color(0, 0, 0, 0.55)  # 窓の縁取り
const EDGE_WIDTH := 2.0
## 地面（3D）は左右それぞれの駒の地形スキンで組む。タイル画像が引けないスキンのための下地色（守り手の
## 地形で1色）＝どの地形かは分かるが「絵が無い」ことも分かる。仕様 → doc/tech/combat_scene.md
const TERRAIN_COLOR := {  # terrain_type.csv の id と同順・全型
	"road": Color(0.62, 0.56, 0.45), "plain": Color(0.56, 0.71, 0.42),
	"wasteland": Color(0.71, 0.55, 0.40), "rampart": Color(0.54, 0.56, 0.60),
	"river": Color(0.38, 0.50, 0.62), "wall": Color(0.52, 0.54, 0.58),
	"plateau": Color(0.72, 0.65, 0.42), "forest": Color(0.30, 0.49, 0.28),
	"bush": Color(0.50, 0.60, 0.35), "bedrock": Color(0.60, 0.55, 0.47),
	"fence": Color(0.55, 0.55, 0.58), "trap": Color(0.45, 0.42, 0.40),
	"prop": Color(0.56, 0.50, 0.54), "rubble": Color(0.52, 0.50, 0.45),
	"rock": Color(0.58, 0.54, 0.50), "building": Color(0.60, 0.48, 0.40),
	"fort": Color(0.54, 0.57, 0.62), "keepout": Color(0.32, 0.32, 0.35),
}
const TEAM_COLOR := { 0: Color(0.18, 0.48, 0.84), 1: Color(0.86, 0.29, 0.29) }
const LEAD_IN := 0.95     # 突入から最初の着弾までの「ため」（秒）
## 幕開け・幕引き。開きは動きで「場面が切り替わった」と知らせ、閉じは静かに溶かす（非対称）。
## 開きに使う時間は LEAD_IN の内側で消化する＝ためが短くなるだけで演出全体は伸びない。
## 尺は「動いたと読める」下限で決める。0.15 あたりだと動きではなく切り替わりに見えて、何が
## 起きたか分からない（実機で確認）。
const OPEN_WIPE := 0.28   # 窓が上下に開くまで（秒）
const OPEN_SLIDE := 0.24  # 窓が開ききってから隊列が中央へ寄り切るまで（秒）
const SLIDE_DX := 0.07    # 隊列の入り幅（窓内寸の幅に対する比）。外側から中央（激突点）へ寄る
const WIPE_MIN := 0.06    # 閉じた窓の高さ（等倍に対する比）。0 にすると縁取りが潰れて描画が荒れる
const CLOSE_FADE := 0.45  # 幕引きのフェード（秒）。EASE_IN＝最初ゆっくり薄れ、最後にすっと消える
## 損害0のときに鳴らす音。武器によらず常にこれ1つ（doc/audio/sfx.md 命中音）。
const SFX_DEFLECT := "cmb_hit_none"

## 飛び道具が攻撃側から被弾側へ届くまで（秒）。この間ぶん着弾＝損害表示も遅れる。
## 飛ぶ距離は窓の幅の約0.7倍あるので、0.2 だと 3500px/秒＝12フレームしか映らず「飛んだ」と読めない。
## 重ねる型の 0.30 よりやや長いあたりが下限。
const FLIGHT := 0.45
const BURST := 0.30       # 重ねるエフェクトの拡大フェード時間（秒）
const STAGGER := 0.025    # エフェクト1発ごとの時差（秒）。同時に出すと1枚の大きな絵に見えて斉射・乱戦にならない
const FIG_H := 0.41   # 立ち絵の高さ（窓内寸の高さに対する比）。描くのは立ち絵PNGの正方キャンバス全体で、
                      # 駒ごとの大小はその中の余白として焼き込んである（→ doc/art/units.md 3.3）。つまり
                      # tools/gen_unit_combat.ps1 の $Canvas と対で、片方を変えたら同じ倍率でもう片方も直す
                      # （512→704 に広げたぶん 0.30→0.41）。実機で詰める値。
const FIG_SCALE := 0.95  # 全図で一定の拡大率（列で変えず＝サイズを揃える。旧前列サイズ相当）
# 地形の重ね絵（奥＝守り手側の背景）。いずれも窓内寸に対する比。
## 守り手側の半面いっぱいに渡る帯として置く（大きさを絵の中の余白で持たせない）。塊を1個
## 浮かべると、絵の端がどこにも接がらず宙に浮く＝背景として成立しないため。外側の端は窓の外へ
## 抜け、内側の端だけが画の中で終わる＝絵はその向きに描いて、反対の陣営では左右反転して使う。
const FEATURE_W := 0.5        # 帯の幅。守り手側の半面
const FEATURE_BOTTOM := 0.44  # 下端。隊列の頭（約0.24）に少し被る＝奥に建っていると読める
# 本人の後ろの1枚（rear）は駒の立ち絵と同じ物差し＝駒と同じ幅のキャンバスを、上端を駒のキャンバスの
# 上端に揃えて置く。大小・後ろへの引き・足元より下への垂れは絵のキャンバスの余白が持つ（駒と同じ。
# tools/gen_terrain_tile.ps1 -CombatRear / -RearShift / -RearDrop が焼き込む）＝ここに定数を持たない。
# 兵量バー（窓内寸に対する比）。両陣営に常時出す＝隊列が減る駒もバーだけの駒も損害の読み方を揃える。
const BAR_W := 0.30
const BAR_H := 0.028
const BAR_Y := 0.90
const BAR_FALL := 0.35  # 目盛りが減っていく時間（秒）
const BAR_BG := Color(0, 0, 0, 0.50)
const BAR_EDGE := Color(0, 0, 0, 0.65)

var _skins := {}
var _terrain_skins := {}  # Vector2i -> skin_id（ステージの見た目差分。地面のスキン解決に使う）
var _state: BattleState = null  # 盤の状態（main が結線）。重ね絵を出すとき拠点の持ち主を引く
var _backdrop_id := ""        # 奥の背景の絵ID（ステージが持つ・空＝水平線を引かない）
var _haze_alpha := 0.0        # 靄の最奥（水平線）での濃さ（ステージが持つ・bind_haze で入る。0＝掛けない）
var _backdrop: TextureRect    # 奥の背景（地面の上・重ね絵の下）。水平線から上に敷く1枚
var _root: Control        # 全画面の入力キャッチ（モーダル）
var _screen: ScreenLighting = null  # 画面の明暗の共通基盤（main が結線）。_open で暗転・_close_now で明ける
var _panel: Control       # 中央のモーダル窓（角を丸めた横長の矩形。中身のクリップ元も兼ねる）
var _edge: Control        # 窓の縁取り（窓の上に重ねて描く＝地面に線が隠れない）
var _bg := Color(0.35, 0.38, 0.34)  # 窓の下地色（地形色。地面が敷けないときに見える）
var _inner: Control       # 窓の中身（地面＋図＋エフェクト）。シェイク対象
var _ground: CombatGround3D  # 地面（3D・盤と同じ地形タイル）
var _haze: TextureRect       # 奥を落とす縦グラデ（タイルの繰り返しを目立たせない）
var _feature: Control        # 奥の重ね絵（地面の上・立ち絵の下）。守り手側に建つ塊
var _feature_front: Control  # 手前の重ね絵（立ち絵の上・バーの下）。窓の全幅に渡る帯
var _fig := { "L": null, "R": null }  # 各サイドの図レイヤ（Control）
var _bar := { "L": null, "R": null }  # 各サイドの兵量バー（Control・立ち絵の上に重ねる）
var _bar_val := { "L": 0.0, "R": 0.0 }   # バーの表示値（減少をアニメさせるので float）
var _bar_team := { "L": 0, "R": 1 }      # バーの色（陣営）
var _bar_tween := { "L": null, "R": null }  # 減少アニメ（連戦で前の戦闘のぶんが残らないよう都度 kill）
var _shown := { "L": 0, "R": 0 }  # いま隊列に並んでいる数。エフェクトの発数はこれに合わせる（絵と食い違わせない）
var _mirror := { "L": false, "R": false }  # その側の立ち絵を水平反転するか（→ _face_mirror）
var _fx: Control                       # フラッシュ・エフェクト・損害数
var _area: Vector2        # 窓の内寸（レイアウト基準）
var _tween: Tween
var _anim: Tween   # 幕開け・幕引きのアニメ（進行 _tween とは別。連戦で前のぶんが残らないよう都度 kill）
var _closing := false  # 幕引きのフェード中。この間はもう進行しない（クリックで飛ばせる）
var _gen := 0  # play 世代（連続戦闘で古い自動クローズを無効化）

func _ready() -> void:
	_build()

## ノードツリーを1度だけ組む（_ready 前に play が来ても安全なよう遅延生成にも対応）。
func _build() -> void:
	if _root != null:
		return
	layer = 50  # 盤・HUD より前面
	_root = Control.new()
	# 入力キャッチも盤エリアだけ（矩形は _layout が決める）＝右の戦闘レポートのタブは演出中も押せる。
	# 盤エリア内のクリック＝スキップ。
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	add_child(_root)
	# 中央のモーダル窓。角丸の形を自分で描き、それをマスクに中身（地面・立ち絵・エフェクト）を
	# 切り抜く＝角の外には盤の暗幕が覗く。シェイクのはみ出しもここで止まる。
	_panel = Control.new()
	_panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_window)
	_root.add_child(_panel)
	_inner = Control.new()  # 窓の中身（シェイク対象）
	_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_inner)
	# 地面はシェイク対象（_inner）の中＝立ち絵と一緒に揺れる（背景だけ止まって見えない）。
	_ground = CombatGround3D.new()
	_inner.add_child(_ground)
	# 奥の背景は地面の上・靄と地形の重ね絵の下＝拠点の屋根は背景に抜ける。靄より後面だが、
	# 背景があるときは靄を水平線から下へ動かすので、背景そのものは靄を受けない。
	_backdrop = TextureRect.new()
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.visible = false
	_inner.add_child(_backdrop)
	# 靄は地面（と背景）だけに掛ける。地形の重ね絵より後面＝重ね絵は靄を受けない。
	# かつては重ね絵を靄の下に置いていた（靄より前だと周りの地面より明るく浮く＝実測で14ポイント差）が、
	# 背景を置くと靄は水平線で一番濃くなるので、水平線をまたぐ塊の足元だけが暗い帯で割れる。
	# そちらのほうが目に付くので、重ね絵は靄より前に出す。
	_haze = TextureRect.new()
	_haze.texture = _make_haze()
	_haze.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_haze.stretch_mode = TextureRect.STRETCH_SCALE
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.add_child(_haze)
	_feature = Control.new()
	_feature.set_anchors_preset(Control.PRESET_FULL_RECT)
	_feature.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.add_child(_feature)
	for side in ["L", "R"]:
		var f := Control.new()
		f.set_anchors_preset(Control.PRESET_FULL_RECT)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inner.add_child(f)
		_fig[side] = f
	# 手前の重ね絵は立ち絵より前面＝前列の足元に被って額縁になる。バーより後面に置くので、
	# 帯が兵量バーを隠すことはない。
	_feature_front = Control.new()
	_feature_front.set_anchors_preset(Control.PRESET_FULL_RECT)
	_feature_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.add_child(_feature_front)
	# バーは立ち絵より前面（隊列に隠れない）／エフェクトより後面（フラッシュは上から被せる）。
	for side in ["L", "R"]:
		var b := Control.new()
		b.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.draw.connect(_draw_bar.bind(side))
		_inner.add_child(b)
		_bar[side] = b
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.add_child(_fx)
	# 縁取りは窓の外（クリップの外側）に置く＝線が中身に半分食われない。
	_edge = Control.new()
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.draw.connect(_draw_edge)
	_root.add_child(_edge)
	visible = false

## 窓を盤エリア（右の情報ボックスを除く）の中央に配置し、内寸 _area を確定する（play のたびに再計算）。
## 入力キャッチ（_root）も盤エリアに絞る＝右の InfoPanel のタブ操作は演出中も効く。
func _layout() -> void:
	var vp := Vector2(1152, 648)
	var v := get_viewport()
	if v != null:
		vp = v.get_visible_rect().size
	var board := UiLayout.board_area(vp)
	_root.position = board.position
	_root.size = board.size
	_area = Vector2(min(board.size.x * 0.90, 740.0), min(board.size.y * 0.62, 520.0))
	_panel.size = _area
	_panel.position = ((board.size - _area) * 0.5).round()
	# 地面と靄は窓より少し大きく取る＝シェイクで縁に窓の下地が覗かない。
	# アンカーに任せず直に置く（_layout 直後に地面を組むので、親のサイズ反映を待てない）。
	var bleed := Vector2(GROUND_BLEED, GROUND_BLEED)
	_ground.position = -bleed
	_ground.size = _area + bleed * 2.0
	_haze.position = -bleed
	_haze.size = _area + bleed * 2.0
	_layout_backdrop(bleed)
	_edge.position = _panel.position
	_edge.size = _area
	# 幕開けのワイプは窓と縁取りを縦に潰した状態から開く。中心を軸にする＝上下へ割れて見える。
	_panel.pivot_offset = _area * 0.5
	_edge.pivot_offset = _area * 0.5
	_panel.queue_redraw()
	_edge.queue_redraw()

## 奥の背景（水平線から上に敷く1枚）を置き直し、靄の掛かる範囲を合わせる。
## 背景があるステージだけ水平線を引く＝靄は水平線から下に掛け直す（背景まで靄で潰さない）。
## 背景が無ければ今までどおり＝水平線を引かず、靄は窓の全高に掛かる。
func _layout_backdrop(bleed: Vector2) -> void:
	var tex := _backdrop_texture()
	_backdrop.texture = tex
	_backdrop.visible = tex != null
	if tex == null:
		return
	# 下端を水平線に置き、幅は窓（はみ出しぶんを含む）に合わせる。高さは絵の縦横比が決める。
	# 上に余ったぶんは窓が切る＝比率が足りない絵は上に隙間が出る（→ doc/art/backdrop.md）。
	var w := _area.x + bleed.x * 2.0
	var horizon := _area.y * HORIZON
	var h := w * (float(tex.get_height()) / float(maxi(tex.get_width(), 1)))
	# 下端は水平線を1px またがせる。ぴたり合わせると、どちらにも覆われない行が1本残って
	# 素の地面が明るいまま抜ける（実測：窓を横切る明るい線が出た）。
	_backdrop.position = Vector2(-bleed.x, horizon - h)
	_backdrop.size = Vector2(w, h + 1.0)
	_haze.position = Vector2(-bleed.x, horizon)
	_haze.size = Vector2(w, _area.y + bleed.y - horizon)

## 奥の背景のPNG（assets/backdrop/{id}.png）。ステージが書いていなければ null。
func _backdrop_texture() -> Texture2D:
	if _backdrop_id.is_empty():
		return null
	var path := "res://assets/backdrop/%s.png" % _backdrop_id
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func bind(skins: Dictionary) -> void:
	_skins = skins

## 奥の背景の絵ID（ステージが持つ）。空＝水平線を引かない。ステージごとに変わるので
## load_stage が呼ぶ（地形スキンと同じ出どころ）。
func bind_backdrop(backdrop_id: String) -> void:
	_backdrop_id = backdrop_id

## 靄の最奥での濃さ（ステージが持つ・0〜1）。屋外は濃く（0.80 前後）、洞窟は薄く（0.30 前後）。
## 靄のテクスチャはこの値で作るので、変わったら作り直す。
func bind_haze(alpha: float) -> void:
	_haze_alpha = clampf(alpha, 0.0, 1.0)
	if _haze != null:
		_haze.texture = _make_haze()

## 画面の明暗の共通基盤（main が結線）。舞台の開閉に合わせて暗転を掛け外しする。
func bind_screen(screen: ScreenLighting) -> void:
	_screen = screen

## ステージの地形の見た目差分（座標→skin_id）。地面をどのスキンで組むかの解決に使う。
## ステージごとに変わるので load_stage が呼ぶ（盤の bind と同じ出どころ）。
func bind_terrain_skins(terrain_skins: Dictionary) -> void:
	_terrain_skins = terrain_skins

## 盤の状態。重ね絵を「誰が持っている拠点か」で選ぶのに使う。占領で変わるので、
## 読むのは開くたび＝ここでは参照だけ持つ（ステージごとに作り直すので load_stage が呼ぶ）。
func bind_state(state: BattleState) -> void:
	_state = state

## 舞台を開く。ground＝重ね絵を出す側の駒（戦闘は守り手／スキルは対象）、ground_side＝その駒を
## 置く側、other＝反対側の駒。地面は左右半分に分け、それぞれの駒のマスのスキンで敷く。
## 進行（誰がいつ動くか）は継承側の play() が持つ。ここは幕が上がるところまで。
func _open(ground: Dictionary, ground_side: String, other: Dictionary) -> void:
	_gen += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _anim != null and _anim.is_valid():
		_anim.kill()
	if _closing:
		_close_now()  # 前の幕引きの途中で次が来たら畳んでおく＝finished を待つ側を取り残さない
	_clear(_fx)
	_layout()
	_bg = TERRAIN_COLOR.get(String(ground.get("terrain", "")), Color(0.35, 0.38, 0.34))
	_panel.queue_redraw()
	var skin := _ground_skin_of(ground)
	var other_skin := _ground_skin_of(other)
	if ground_side == "L":
		_ground.build(skin, other_skin)
	else:
		_ground.build(other_skin, skin)
	_clear(_feature)
	_clear(_feature_front)
	# 重ね絵は左右それぞれ自分の側の駒のマスのスキンから引く（地面を左右で分けるのと同じ理屈）。
	# 中央の継ぎ目だけは1本しか立てられないので、守り手側に絵があればそれ、無ければ攻め手側の絵。
	var other_side := "R" if ground_side == "L" else "L"
	var line_done := false
	if skin != null:
		line_done = _add_features(skin, ground_side, _base_team_of(ground), _slot_pos(ground_side, _lead_pos(ground)), true)
	if other_skin != null:
		_add_features(other_skin, other_side, _base_team_of(other), _slot_pos(other_side, _lead_pos(other)), not line_done)
	if _screen != null:
		_screen.dim(self)  # 暗転は共通基盤（フェードはあちら持ち）。窓のワイプとほぼ同時に走る
	_start_open_anim()

## 幕開け：窓が上下に開く → 両軍の隊列が外側から中央へ寄る（暗転は _open が共通基盤に頼んでいる）。
## 隊列は _open の直後（同フレーム）に _render_side が組むので、ここで先に図レイヤを外へ置いておける。
## バーと地形の重ね絵は動かさない＝窓に属する表示なので、隊列と一緒に流れると窓が滑って見える。
func _start_open_anim() -> void:
	var dx := _size().x * SLIDE_DX
	_root.modulate.a = 1.0
	_panel.scale.y = WIPE_MIN
	_edge.scale.y = WIPE_MIN
	_fig["L"].position.x = -dx
	_fig["R"].position.x = dx
	visible = true
	_anim = create_tween()
	_anim.set_parallel(true)
	_anim.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_anim.tween_property(_panel, "scale:y", 1.0, OPEN_WIPE)
	_anim.tween_property(_edge, "scale:y", 1.0, OPEN_WIPE)
	_anim.tween_property(_fig["L"], "position:x", 0.0, OPEN_SLIDE).set_delay(OPEN_WIPE)
	_anim.tween_property(_fig["R"], "position:x", 0.0, OPEN_SLIDE).set_delay(OPEN_WIPE)

## 片側の重ね絵を出す（奥＝back／本人の後ろ＝rear／中央の継ぎ目＝line／手前＝front）。その側の駒の
## マスのスキンから引き、置いてある絵だけを出す＝無ければ何も重ねない（地面だけ）。中央は with_line の
## ときだけ立て、立てたら true を返す（両側から1本ずつ立てない）。
## 3Dの帯には混ぜない＝奥へ行くほど縮む帯の倍率と靄を受けないので、いつも同じ大きさで読める。
## 仕様 → doc/tech/combat_scene.md
func _add_features(skin: TerrainSkin, side: String, team: int, lead: Vector2, with_line: bool) -> bool:
	var line_done := false
	var back := _feature_texture(skin, "back", team)
	if back != null:
		# その側の半面に渡す帯。幅で合わせ、高さは絵の縦横比が決める（横幅が決まっている以上、
		# 縦を別に指定すると絵が歪む）。隊列の頭が下辺に少し被る高さに置く＝前後関係が出る。
		var vp := _size()
		var bottom := vp.y * FEATURE_BOTTOM
		var w := vp.x * FEATURE_W
		var h := w * (float(back.get_height()) / float(maxi(back.get_width(), 1)))
		if h > bottom:   # 上が窓から出る絵は、出ない大きさまで縮める（屋根を切らない）
			w *= bottom / h
			h = bottom
		var x := 0.0 if side == "L" else vp.x - w
		var rect := _feature_rect(back, Vector2(x, bottom - h), Vector2(w, h))
		rect.flip_h = side == "R"  # 絵は左陣営向きに描く＝外側（窓の端）へ抜ける側を左に
		_feature.add_child(rect)
	var rear := _feature_texture(skin, "rear", team)
	if rear != null:
		# その側の本人の真後ろに立てる1枚（玉座など）。奥の帯と違い窓の端に寄せず、本人の
		# 立ち位置（lead＝先頭スロットの中心x・足元y）に、駒と同じ正方キャンバスを同じ大きさで置く
		# （_add_figure と同じ式）。立ち絵より下のレイヤー＝本人も従者も手前に出る。
		# キャンバスは幅で駒と同じ倍率に合わせ、上端を駒のキャンバスの上端に揃える。高さが幅を
		# 超えるぶん（-RearDrop）は足元の線より下へ垂れる＝絵側で「足元より下」を持てる。
		var rw := _size().y * FIG_H * FIG_SCALE
		var rh := rw * (float(rear.get_height()) / float(maxi(rear.get_width(), 1)))
		var rrect := _feature_rect(rear, Vector2(lead.x - rw * 0.5, lead.y - rw), Vector2(rw, rh))
		rrect.flip_h = side == "R"  # 絵は左陣営向きに描く＝物が右（戦場の方）を向く
		_feature.add_child(rrect)
	var line := _feature_texture(skin, "line", team) if with_line else null
	if line != null:
		# 中央の継ぎ目（両隊列の間）に立てる1枚。柵や城壁を「壁越しの対峙」の絵にする。
		# 手前（下）から奥（上）へ走るので窓の全高に渡し、幅は絵の縦横比が決める。
		# 立ち絵より下のレイヤー＝隊列は柵の手前に出る。奥は靄が受けて沈む。
		var vp1 := _size()
		var lw := vp1.y * (float(line.get_width()) / float(maxi(line.get_height(), 1)))
		_feature.add_child(_feature_rect(line, Vector2(vp1.x * 0.5 - lw * 0.5, 0.0), Vector2(lw, vp1.y)))
		line_done = true
	var front := _feature_texture(skin, "front", team)
	if front != null:
		# 手前の帯＝足元に散らかる物。その側の半面の下辺に接地させ、高さは絵の縦横比が決める。
		# 絵は左半面用に描き、右半面では左右反転する。立ち絵より前面＝前列の足元に被って額縁になる。
		var vp2 := _size()
		var fw := vp2.x * 0.5
		var fh := fw * (float(front.get_height()) / float(maxi(front.get_width(), 1)))
		var fx := 0.0 if side == "L" else fw
		var frect := _feature_rect(front, Vector2(fx, vp2.y - fh), Vector2(fw, fh))
		frect.flip_h = side == "R"
		_feature_front.add_child(frect)
	return line_done

## 重ね絵のPNG（assets/terrain/{skin_id}_combat_{back|line|front}.png）。置いていなければ null。
## 盤の立ち絵は使わない＝戦闘は近景で要る絵が違う（→ doc/art/terrain.md）。絵を置けば出る。
## 占領されている拠点は、所有チーム別の絵があればそれを使う＝盤のタイルと同じ作法
## （{skin_id}_team{N}_combat_{slot}.png を置けば切り替わり、置かなければ中立の絵のまま）。
func _feature_texture(skin: TerrainSkin, slot: String, team: int) -> Texture2D:
	if team >= 0:
		var tp := "res://assets/terrain/%s_team%d_combat_%s.png" % [skin.skin_id, team, slot]
		if ResourceLoader.exists(tp):
			return load(tp) as Texture2D
	var path := "res://assets/terrain/%s_combat_%s.png" % [skin.skin_id, slot]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

## その駒が立っているマスにある拠点の所属チーム。拠点でない/中立/盤が未結線なら -1。
## 拠点は数個なので線形で足りる（盤の board_terrain_renderer と同じ引き方）。
func _base_team_of(comb: Dictionary) -> int:
	if _state == null:
		return -1
	var pos: Variant = comb.get("pos")
	if typeof(pos) != TYPE_VECTOR2I:
		return -1
	for b in _state.bases():
		if b.hex == pos:
			return b.team
	return -1

## 重ね絵1枚ぶんの TextureRect（位置と大きさは呼び出し側が決める）。
func _feature_rect(tex: Texture2D, pos: Vector2, size2: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = size2
	tr.position = pos
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## 隊列スロットに収まる兵量（1〜8）。値をそのまま信じず枠内に丸める。
func _troops_of(comb: Dictionary) -> int:
	return clampi(int(comb.get("troops_before", 1)), 1, POS.size())

func _other_side(side: String) -> String:
	return "R" if side == "L" else "L"

## 片側の隊列＋兵量バーを count 兵ぶんで描き直す。animate=true は着弾時（バーが減っていく）。
## 並べ方はスキンの combat_lineup：single は複製せず1体だけ（馬車・ドラゴン級＝兵として数えない駒）。
func _render_side(side: String, comb: Dictionary, count: int, animate: bool = false) -> void:
	var layer: Control = _fig[side]
	_clear(layer)
	var team := int(comb.get("team", 0))
	_shown[side] = count
	_mirror[side] = _face_mirror(side, team)
	_set_bar(side, count, team, animate)
	var skin := _skin_of(comb)
	if skin != null and skin.is_single_figure():
		# 1体だけ＝損害で絵が減らないので、減り方は兵量バーが受け持つ。
		var at := _slot_pos(side, SINGLE_POS)
		_add_figure(layer, at.x, at.y, FIG_SCALE * SINGLE_SCALE, _texture_for(comb), team, comb, _mirror[side])
		return
	var texs := _textures_for(comb, count)  # スロットごとの絵（先頭＝本人・以降は従者）
	var figs := []
	for i in count:
		var at := _slot_pos(side, POS[i])
		figs.append({ "cx": at.x, "feet": at.y, "s": FIG_SCALE, "tex": texs[i] })
	figs.sort_custom(func(u, v): return u["feet"] < v["feet"])  # 手前（下）を後に＝前面
	for f in figs:
		_add_figure(layer, f["cx"], f["feet"], f["s"], f["tex"], team, comb, _mirror[side])

## その側の立ち絵を水平反転するか。立ち絵は向きを陣営に焼き込んである（プレイヤー＝右向き／
## 敵＝左向き）ので、陣営が左右に分かれる戦闘では反転は要らない。同陣営どうしが並ぶ
## ユニットスキルの演出では片側が中央に背を向けるので、そちらだけ反転する。
## 仕様 → doc/tech/combat_scene.md ユニットスキルの演出
func _face_mirror(side: String, team: int) -> bool:
	return (team != 0) if side == "L" else (team == 0)

## 隊列の正規化座標（x:奥0→前1／y:上0→下1）→ 窓内の (中心x, 足元y)。
## 敵側は x を反転して中央（激突点）へ正対させる。地面の傾きぶん、前ほど足元を下げる。
func _slot_pos(side: String, p: Vector2) -> Vector2:
	var vp := _size()
	var cx := (vp.x * 0.06 + p.x * vp.x * 0.36) if side == "L" else (vp.x * 0.94 - p.x * vp.x * 0.36)
	var feet := vp.y * 0.38 + p.y * vp.y * 0.42 + p.x * vp.y * 0.16
	return Vector2(cx, feet)

## 兵量バーを count へ更新。animate なら現在値からアニメで落とす（着弾の手応え）。
## 開幕は snap＝前の戦闘の値から動かない（連戦で前のバーが残らないよう既存アニメは kill）。
func _set_bar(side: String, count: int, team: int, animate: bool) -> void:
	_bar_team[side] = team
	var prev: Tween = _bar_tween[side]
	if prev != null and prev.is_valid():
		prev.kill()
	if not animate:
		_set_bar_val(side, float(count))
		return
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _set_bar_val(side, v), float(_bar_val[side]), float(count), BAR_FALL)
	_bar_tween[side] = tw

func _set_bar_val(side: String, v: float) -> void:
	_bar_val[side] = v
	var c: Control = _bar[side]
	if c != null:
		c.queue_redraw()

## 兵量バー（8分割の刻み＝隊列8スロットと同じ数え方）。表示パターンに関わらず両陣営に常時出す。
## 仕様 → doc/tech/combat_scene.md「兵量バー」
func _draw_bar(side: String) -> void:
	var c: Control = _bar[side]
	if c == null:
		return
	var vp := _size()
	var w := vp.x * BAR_W
	var h := vp.y * BAR_H
	var cx := vp.x * 0.24 if side == "L" else vp.x * 0.76
	var origin := Vector2(cx - w * 0.5, vp.y * BAR_Y)
	var gap := 2.0
	var cell := (w - gap * (MAX_TROOPS - 1)) / MAX_TROOPS
	var col: Color = TEAM_COLOR.get(int(_bar_team[side]), Color(0.5, 0.5, 0.5))
	var val := float(_bar_val[side])
	for i in MAX_TROOPS:
		var slot := Rect2(Vector2(origin.x + i * (cell + gap), origin.y), Vector2(cell, h))
		c.draw_rect(slot, BAR_BG)  # 空の枠も見せる＝最大8のうち今いくつかが読める
		var f := clampf(val - float(i), 0.0, 1.0)
		if f > 0.0:
			c.draw_rect(Rect2(slot.position, Vector2(cell * f, h)), col.lightened(0.15))
		c.draw_rect(slot, BAR_EDGE, false, 1.0)

func _add_figure(layer: Control, cx: float, feet: float, s: float, tex: Texture2D, team: int, comb: Dictionary, mirror: bool = false) -> void:
	var vp := _size()
	var w := vp.y * FIG_H * s
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tr.custom_minimum_size = Vector2(w, w)
		tr.size = Vector2(w, w)
		tr.position = Vector2(cx - w * 0.5, feet - w)
		if mirror:
			# ピボットを絵の中心に置いてから反転＝位置がずれない（既定は左上基準）。
			tr.pivot_offset = Vector2(w, w) * 0.5
			tr.scale.x = -1.0
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(tr)
	else:
		var panel := ColorRect.new()
		panel.color = TEAM_COLOR.get(team, Color(0.5, 0.5, 0.5))
		panel.size = Vector2(w * 0.7, w * 0.85)
		panel.position = Vector2(cx - w * 0.35, feet - w * 0.85)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lbl := Label.new()
		lbl.text = _placeholder_label(comb)
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", int(max(11.0, w * 0.22)))
		panel.add_child(lbl)
		layer.add_child(panel)

## 隊列スロットごとの立ち絵。先頭は必ず本人で、2体目以降は従者（スキンの retainers）を
## 順に巡回して割り当てる。retainers が空なら全部本人＝従来どおりの見た目。
## ボス＋手下の一団を、絵を足さずに既存スキンの組み合わせで作るための仕組み。仕様 → doc/tech/combat_scene.md
func _textures_for(comb: Dictionary, count: int) -> Array:
	var own := _texture_for(comb)
	var skin := _skin_of(comb)
	var list: Array = skin.retainers if skin != null else []
	var out := []
	for i in count:
		if i == 0 or list.is_empty():
			out.append(own)
		else:
			out.append(_retainer_texture(String(list[(i - 1) % list.size()]), own))
	return out

## 従者1体ぶんの立ち絵。スキンが引けない／絵が無い場合は本人の絵で埋める（穴を空けない）。
func _retainer_texture(skin_id: String, fallback: Texture2D) -> Texture2D:
	var s: UnitSkin = SkinCatalog.skin_by_id(_skins, skin_id)
	if s == null:
		return fallback
	var tex := _skin_texture(s)
	return tex if tex != null else fallback

func _texture_for(comb: Dictionary) -> Texture2D:
	var skin := _skin_of(comb)
	return _skin_texture(skin) if skin != null else null

## スキンの立ち絵。combat スロット優先、無ければ map 画像を流用（本番アートが来るまでの繋ぎ）。
func _skin_texture(skin: UnitSkin) -> Texture2D:
	var p := skin.image("combat")
	if p == "":
		p = skin.image("map")
	if p != "" and ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

## 本人（先頭スロット）の隊列内の正規化座標。single は1体の立ち位置、それ以外は隊列の先頭。
func _lead_pos(comb: Dictionary) -> Vector2:
	var s := _skin_of(comb)
	return SINGLE_POS if (s != null and s.is_single_figure()) else POS[0]

func _skin_of(comb: Dictionary) -> UnitSkin:
	return SkinCatalog.resolve(_skins, String(comb.get("skin_id", "")), String(comb["type_id"]), int(comb["team"]))

func _placeholder_label(comb: Dictionary) -> String:
	var skin := _skin_of(comb)
	return skin.combat_label() if skin != null else String(comb.get("type_id", "?"))

## 窓の形＝角を丸めた横長の矩形（左上から時計回り）。中身のクリップ形状も縁取りもこれ1つで決まる。
## 角の四分円は折れ線で近似する＝返す形は多角形のままなので、塗り（マスク）も枠線も同じ点列で描ける。
## 陣形スキルのカットイン（FormationCutin）も同じ窓の形を使うので static で公開する。
static func window_shape(sz: Vector2) -> PackedVector2Array:
	var r := minf(sz.x, sz.y) * CORNER_RADIUS
	# 各角の円の中心。左上→右上→右下→左下＝画面座標（y は下向き）で時計回り。
	var centers := [
		Vector2(r, r), Vector2(sz.x - r, r), Vector2(sz.x - r, sz.y - r), Vector2(r, sz.y - r),
	]
	var pts := PackedVector2Array()
	for i in 4:
		var c: Vector2 = centers[i]
		var a0 := PI + i * PI * 0.5  # 左上なら 180°（左辺との接点）から始めて 270°（上辺との接点）へ
		for j in CORNER_SEGMENTS + 1:
			var a := a0 + PI * 0.5 * (float(j) / float(CORNER_SEGMENTS))
			pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

## 窓の下地（地形色）。この描画がそのまま中身のクリップ形状になる（CLIP_CHILDREN_AND_DRAW）。
func _draw_window() -> void:
	_panel.draw_colored_polygon(window_shape(_panel.size), _bg)

## 窓の縁取り（角丸の枠）。閉じるため始点を末尾にもう一度足す。
func _draw_edge() -> void:
	var pts := window_shape(_edge.size)
	pts.append(pts[0])
	_edge.draw_polyline(pts, EDGE_COLOR, EDGE_WIDTH, true)

## 地面の材料になる地形スキン。ステージの見た目差分を優先し、無ければ地形の既定スキン。
## pos が来ない古いデータでも既定スキンには落ちる（平地/雪原の別は付かないが地面は出る）。
func _ground_skin_of(comb: Dictionary) -> TerrainSkin:
	var pos: Variant = comb.get("pos")
	var skin_id := ""
	if typeof(pos) == TYPE_VECTOR2I:
		skin_id = String(_terrain_skins.get(pos, ""))
	return TerrainSkinCatalog.resolve(skin_id, String(comb.get("terrain", "")))

## 奥（画面上）を落とす縦グラデ。距離感を出しつつ、遠くのタイルの繰り返しを目立たせない。
## 立ち絵より下のレイヤーに敷くので、隊列は暗くならず地面だけが奥へ沈む。
func _make_haze() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.30, 0.78])
	g.colors = PackedColorArray([
		Color(HAZE_COLOR, _haze_alpha),          # 最奥
		Color(HAZE_COLOR, _haze_alpha * 0.55),   # 中景（落ち方を緩めて帯にしない）
		Color(HAZE_COLOR, 0.0),                 # 手前は素通し
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 8
	t.height = 128
	return t

func _flash(side: String, col: Color = Color(1, 1, 1, 0.55)) -> void:
	var vp := _size()
	var r := ColorRect.new()
	r.color = col
	r.size = Vector2(vp.x * 0.5, vp.y)
	r.position = Vector2(0 if side == "L" else vp.x * 0.5, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.28)
	tw.tween_callback(r.queue_free)

## 放つ側のエフェクト定義。スキン未設定・未定義IDなら null＝既定のスパークで出す。
func _effect_of(comb: Dictionary) -> CombatEffect:
	var skin := _skin_of(comb)
	if skin == null:
		return null
	return CombatEffectCatalog.by_id(skin.combat_effect)

func _is_projectile(comb: Dictionary) -> bool:
	var e := _effect_of(comb)
	return e != null and e.is_projectile()

## エフェクト1個ぶんのノード。絵が置かれていなければ既定のスパーク（星）を描く＝穴が開かない。
## 大きさは「被弾側の立ち絵1体ぶんの幅 × カタログの scale」。絵は余白を切り詰めて作る約束なので、
## 大小の差は画像ではなく scale で付ける（切り詰めた絵をそのまま並べると全部同じ幅になる）。
func _effect_node(eff: CombatEffect) -> Node2D:
	var tex: Texture2D = null
	if eff != null:
		var p := eff.image_path()
		if p != "" and ResourceLoader.exists(p):
			tex = load(p) as Texture2D
	if tex == null:
		var star := Polygon2D.new()
		star.polygon = _star_points(26.0, 11.0)
		star.color = Color(0.98, 0.78, 0.29)
		return star
	var s := Sprite2D.new()
	s.texture = tex
	# 基準は長辺。幅で揃えると、縦長の斬撃が縦にはみ出し、横長の矢と釣り合わない。
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	if longest > 0.0:
		s.scale = Vector2.ONE * (_size().y * FIG_H * FIG_SCALE * eff.scale / longest)
	return s

## 重ねる型を1発：受ける側のスロットの上で拡大しながら消える。
## 絵は「右へ向かう一撃」で描く約束なので、左を殴るとき（＝放つ側が右）だけ水平反転する。
## 飛ぶ型と同じ向きの規約＝どちらも1枚で両陣営に使える。
func _spawn_burst(at: Vector2, mirror: bool, eff: CombatEffect, delay: float, gen: int) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		if gen != _gen:
			return
		var node := _effect_node(eff)
		node.position = at
		if mirror:
			node.scale.x = -node.scale.x
		var base := node.scale
		node.scale = base * 0.4
		_fx.add_child(node)
		var t2 := create_tween()
		t2.set_parallel(true)
		t2.tween_property(node, "scale", base * 1.6, BURST)
		t2.tween_property(node, "modulate:a", 0.0, BURST)
		t2.chain().tween_callback(node.queue_free))

## 飛ぶ型を1発：放った側のスロットから受ける側のスロットへ飛び、着弾で消える。
## 絵は右向きに描く約束なので、左へ飛ぶときだけ水平反転する（1枚で両陣営に使える）。
func _spawn_fly(from: Vector2, to: Vector2, eff: CombatEffect, delay: float, gen: int) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		if gen != _gen:
			return
		var node := _effect_node(eff)
		node.position = from
		if to.x < from.x:
			node.scale.x = -node.scale.x
		_fx.add_child(node)
		var t2 := create_tween()
		t2.tween_property(node, "position", to, FLIGHT)
		t2.tween_callback(node.queue_free))

## その側の上に浮かび上がって消える文字（損害数・補正量）。縁の色で意味を分ける。
## top は出だしの高さ（窓内寸に対する比）。複数行の補正量は隊列に被るので、呼ぶ側が上へ逃がす。
func _float_label(side: String, text: String, outline: Color, top: float = 0.30) -> void:
	var vp := _size()
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", int(vp.y * 0.09))
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	lbl.add_theme_color_override("font_outline_color", outline)
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cx := vp.x * 0.28 if side == "L" else vp.x * 0.72
	lbl.position = Vector2(cx - vp.x * 0.06, vp.y * top)
	_fx.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", vp.y * (top - 0.10), 0.55)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.55).set_delay(0.15)
	tw.chain().tween_callback(lbl.queue_free)

func _shake() -> void:
	var tw := create_tween()
	tw.tween_property(_inner, "position", Vector2(-6, 3), 0.05)
	tw.tween_property(_inner, "position", Vector2(5, -2), 0.05)
	tw.tween_property(_inner, "position", Vector2(-3, -1), 0.05)
	tw.tween_property(_inner, "position", Vector2.ZERO, 0.05)

func _star_points(outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		var ang := PI * i / 4.0
		var rad := outer if i % 2 == 0 else inner
		pts.append(Vector2(cos(ang) * rad, sin(ang) * rad))
	return pts

func _on_root_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if _closing:
			# 幕引きの最中のクリック＝余韻も飛ばす（連打で待たされない）
			if _anim != null and _anim.is_valid():
				_anim.kill()
			_close_now()
		else:
			_dismiss()  # クリックで即スキップ

## 幕引きを始める。演出はここで止まり、あとは薄れて消えるだけ。
## finished はフェードが終わってから出す＝盤は幕が引き切るまで動かない。
func _dismiss() -> void:
	if not visible or _closing:
		return  # 二重クローズ（クリック＋自動）で finished を重ねない
	_closing = true
	_gen += 1  # 進行中の自動クローズ・飛来中のエフェクトを無効化
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_anim = create_tween()
	_anim.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_anim.tween_property(_root, "modulate:a", 0.0, CLOSE_FADE)
	_anim.tween_callback(_close_now)

## 実際に消す。フェード完了とスキップの両方から来るので、見た目の後始末はここに集約する。
func _close_now() -> void:
	if not visible:
		return
	_closing = false
	_inner.position = Vector2.ZERO
	_root.modulate.a = 1.0
	visible = false
	if _screen != null:
		_screen.undim(self)  # 暗転を明ける（窓が消えてから共通基盤のフェードで戻る）
	finished.emit()

func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()

func _size() -> Vector2:
	return _area if _area != Vector2.ZERO else Vector2(980, 560)  # 窓の内寸（レイアウト基準）
