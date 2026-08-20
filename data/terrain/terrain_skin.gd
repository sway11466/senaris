extends RefCounted
class_name TerrainSkin
## 地形の見た目＋識別（表示名・タイル画像・回転可否）。性能(TerrainType)とは分離。
## 詳細 → doc/gdd/units.md §1（skin_id 方式）, doc/backlog.md refactoring-2
##
## 1つの性能(terrain_type)に複数のスキンがぶら下がる（草地/砂地/雪原…の別見た目）。
## skin→type は1:1（skin が決まれば性能も一意）。どのセルにどの skin を敷くかはステージ側が決める
## （ステージJSON の terrain_skins＝座標→skin_id の差分列挙。未指定は type の既定スキン）。
##
## 画像は autowire 規約＝assets/terrain/{skin_id}.png（変種は hex_board が _2/_3 を連番プローブ）。
## 見た目データなので domain には持ち込まない（案P＝presentation 専用）。

const CONNECT_LINE := "line"  ## 線の地形（柵）。端が盤の縁に来たら、その先へまっすぐ伸ばす
const CONNECT_AREA := "area"  ## 面の地形（道）。盤の外は縁のマスがそのまま続いているものとして扱う

## オブジェクトの置き方（→ doc/gdd/terrain.md）。足場のスキンはこの列を持たない（空）。
const PLACE_STANDEE := "standee"  ## カメラに正対する立ち絵の板（既定の置き方）
const PLACE_PANEL := "panel"      ## 辺に沿ってワールドに立てた板（柵）。向きは connect の繋がりが出す
const PLACE_FLAT := "flat"        ## 水平の板（橋）。自分のタイル絵を自分の高さに敷く
const PLACEMENTS := [PLACE_STANDEE, PLACE_PANEL, PLACE_FLAT]

## 同じ絵が隣り合ったときの見え方を散らす手段（→ orientable）。絵が向きを持つほど使える手が減る。
## 値は「何をしてよいか」をそのまま並べる＝名前を読めば効く操作が分かる。
const ORIENT_NONE := "none"        ## 何もしない。向きが意味を持つ絵（道・壁）とオブジェクト全部
const ORIENT_FLIP_X := "flip_x"    ## 左右反転だけ
const ORIENT_FLIP_Y := "flip_y"    ## 上下反転だけ
const ORIENT_FLIP_XY := "flip_xy"  ## 上下反転＋左右反転・回転なし
const ORIENT_FULL := "full"        ## 60°回転＋上下反転＋左右反転。向きの無い自然地形（平地・森）
const ORIENTS := [ORIENT_NONE, ORIENT_FLIP_X, ORIENT_FLIP_Y, ORIENT_FLIP_XY, ORIENT_FULL]

var skin_id: String        ## スキンID（主キー。ステージはこれで見た目を指定）
var terrain_type: String   ## 紐づく性能(TerrainType)のid
var name: String           ## 表示名（例: 平地 / 雪原）
## 座標ハッシュで見た目をどこまで散らしてよいか（ORIENT_* のどれか）。絵の向きが持つ意味で決まる。
var orientable: String
## 隣の同スキンと繋がる地形の繋がり方。空/false＝繋がらない、line＝線（柵）、area＝面（道）。
## line/area なら向きの組み合わせ別タイル（_c000000〜_c111111）を引く。この2つで違うのは盤の縁の
## 扱いだけで、タイルの命名も枚数も同じ（→ doc/art/terrain.md §3）。
var connect: String
## 繋がる相手の skin_id（空白区切り・自分自身は常に含む）。既定の空＝同じスキンとだけ繋がる。
## 片方向で書ける＝川に橋を書き、橋に川を書かなければ「川は橋へ帯を伸ばすが、橋は川へ伸びない」に
## なる。橋の下を川がくぐるのはこの非対称で作る（→ doc/art/terrain.md §3.7）。
var connect_to: PackedStringArray
var elevation: float       ## 見た目の高さ（ワールド単位・TILE=1）。負も可（水面など）。段差辺には側面スカートが付く
## 駒の足元の高さ（ワールド単位・TILE=1）。elevation と同じ座標系で、駒の立ち絵だけがこの高さに立つ。
## elevation より低ければ地形に沈む（森＝木々の間の地面）、高ければ浮く（水面の上を飛ぶ）。
var floor: float
## 行・列の基準高さ（盤の高さ）を足さないか。true＝elevation / floor が絶対高さになる。
## 水面のように、盤の傾斜に乗らず一定の高さを保つスキンが使う（→ doc/gdd/terrain.md 盤の高さ）。
var ignore_board_height: bool
## オブジェクトの置き方（PLACE_* のどれか）。足場のスキンはこの列を持たない（空）。
var placement: String
## オブジェクトの立ち絵を、ヘックス中心からどれだけ手前へ置くか（ワールド単位・TILE=1・正＝手前）。
## 駒（+0.6）と同じ向きで、それより小さくしておけば同じマスでも駒が手前に立つ。足場のスキンは空。
## 大きさのほうはここで読まない＝map_scale は絵の書き出し専用（→ doc/art/terrain.md）。
var object_foot_z: float
var grid: bool             ## ヘックスの枠線を引くか。駒が入れない地形は引かないほうが一つの塊として読める
## 盤に敷くときの下地。地面を絵に焼き込まず、描画時に下地の上へ自分の絵を重ねる（→ doc/art/terrain.md §3.6）。
var map_ground: String     ## 下に敷くスキンID。空＝敷かない＝1枚絵で完結する従来のタイル
## 戦闘演出の地面に敷くスキンID（→ doc/tech/combat_scene.md）。空＝自分自身で敷き詰める（既定）。
## タイルの絵をそのまま敷けないスキン（オブジェクト・線地形）が下地を指す。
var combat_ground: String

static func from_dict(d: Dictionary) -> TerrainSkin:
	var s := TerrainSkin.new()
	s.skin_id = String(d.get("skin_id", ""))
	s.terrain_type = String(d.get("terrain_type", ""))
	s.name = String(d.get("name", ""))
	# 知らない値（旧データの bool true/false・打ち間違い）は「散らさない」に倒す。勝手に回して
	# 絵が倒れるより、散らないほうが害が小さい。String() は bool を受けないので先に型を見る。
	var o: Variant = d.get("orientable", ORIENT_NONE)
	s.orientable = String(o) if typeof(o) == TYPE_STRING and o in ORIENTS else ORIENT_NONE
	# 知らない値（旧データの bool true/false・打ち間違い）は「繋がらない」に倒す。false が真になる
	# 事故を防ぐ。String() は bool を受けないので、文字列かどうかを先に見る。
	var c: Variant = d.get("connect", "")
	s.connect = String(c) if typeof(c) == TYPE_STRING and c in [CONNECT_LINE, CONNECT_AREA] else ""
	var ct: Variant = d.get("connect_to", "")
	s.connect_to = String(ct).split(" ", false) if typeof(ct) == TYPE_STRING else PackedStringArray()
	s.elevation = float(d.get("elevation", 0.0))
	s.floor = float(d.get("floor", 0.0))
	s.ignore_board_height = bool(d.get("ignore_board_height", false))
	# 置き方はオブジェクトだけが持つ。未知の値（打ち間違い）は空に倒し、描く側が立ち絵（既定）で
	# 扱う＝何も出ないより、立ち絵で出るほうが不備に気づける。
	var pl: Variant = d.get("placement", "")
	s.placement = String(pl) if typeof(pl) == TYPE_STRING and pl in PLACEMENTS else ""
	s.object_foot_z = float(d.get("object_foot_z", 0.0))
	s.grid = bool(d.get("grid", true))
	s.map_ground = String(d.get("map_ground", ""))
	s.combat_ground = String(d.get("combat_ground", ""))
	return s

## 戦闘演出の地面に敷くスキンID（空なら自分自身＝敷き詰め）。
func combat_ground_id() -> String:
	return combat_ground if combat_ground != "" else skin_id

## 盤で下に敷くスキンID（空＝敷かない＝自分の絵だけで完結する従来のタイル）。
func map_ground_id() -> String:
	return map_ground

## 隣の other と繋がって見えるか（自分から見た片方向の判定）。自分と同じスキンは常に繋がる。
func connects_with(other: TerrainSkin) -> bool:
	if other == null:
		return false
	return other.skin_id == skin_id or other.skin_id in connect_to

## タイル画像（基本）のパス。ファイル名は skin_id 規約（変種 _2/_3 は描画側が連番で拾う）。
func image_path() -> String:
	return "res://assets/terrain/%s.png" % skin_id

## 接続タイル（connect=true 用）のパス。柵や道は「どの辺で隣と繋がっているか」で絵が変わる。
## connected は Hex.DIRECTIONS 順の6要素（true＝その方向の隣も同じスキン）で、そのまま 0/1 の
## 6桁になる＝assets/terrain/{skin_id}_c{6桁}.png。無ければ描画側が image_path() に落ちる。
## 一式は tools/gen_connect_tiles.ps1 が原画1枚から生成する（→ doc/art/terrain.md）。
func connected_image_path(connected: Array) -> String:
	var bits := ""
	for c in connected:
		bits += "1" if bool(c) else "0"
	return "res://assets/terrain/%s_c%s.png" % [skin_id, bits]

## 座標ハッシュで見た目を散らす対象か（none 以外）。呼び出し側はこれで orient() を呼ぶか決める。
func orients() -> bool:
	return orientable != ORIENT_NONE

## 60°回転してよいか。立てて描いた物がある絵は回すと倒れるので full だけ。
func rotates() -> bool:
	return orientable == ORIENT_FULL

## 左右反転してよいか。上下も左右も正六角形を自分自身に写すので、
## 絵が六角形に収まっていればどれを掛けてもはみ出さない。
func flips_horizontally() -> bool:
	return orientable in [ORIENT_FLIP_X, ORIENT_FLIP_XY, ORIENT_FULL]

## 上下反転してよいか。
func flips_vertically() -> bool:
	return orientable in [ORIENT_FLIP_Y, ORIENT_FLIP_XY, ORIENT_FULL]

## 繋がる地形か（line または area）。向きの組み合わせ別タイルを引くかの判定に使う。
func connects() -> bool:
	return connect == CONNECT_LINE or connect == CONNECT_AREA

## 面の地形か。盤の縁の扱いだけがこれで変わる（→ doc/art/terrain.md §3.5）。
func connects_as_area() -> bool:
	return connect == CONNECT_AREA

## 線（connect=line）を盤の縁で切らないための補正。connected / on_board はどちらも
## Hex.DIRECTIONS 順の6要素。繋がっている隣が1つだけのマスは、その反対側が盤の外なら、そちらへも
## 腕を伸ばす＝柵が盤の外へ続いて見える（地図の外側にも世界が続いている扱い）。
## 隣が2つ以上あるマスには効かせない。外周に沿って走る柵が、外向きの腕を櫛のように生やすため。
## 面（connect=area）はこれを使わない。面は「盤の外＝縁のマスの続き」として隣を引く（呼び出し側）。
static func extend_off_board(connected: Array, on_board: Array) -> Array:
	var count := 0
	var only := -1
	for i in 6:
		if bool(connected[i]):
			count += 1
			only = i
	if count != 1:
		return connected
	var opposite := (only + 3) % 6  # Hex.DIRECTIONS は i と i+3 が反対向き
	if bool(on_board[opposite]):
		return connected
	var extended := connected.duplicate()
	extended[opposite] = true
	return extended

## 側面（スカート）画像のパス。置いてあれば段差の側面に貼られ、無ければ既定の粒ノイズ＋断面色になる。
## 横は隣の辺へ連続するので左右シームレス必須。縦は高さ全体に1回だけ張られる（elevation で伸縮する）。
func side_image_path() -> String:
	return "res://assets/terrain/%s_side.png" % skin_id
