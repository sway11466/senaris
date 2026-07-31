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

var skin_id: String        ## スキンID（主キー。ステージはこれで見た目を指定）
var terrain_type: String   ## 紐づく性能(TerrainType)のid
var name: String           ## 表示名（例: 平地 / 雪原）
var orientable: bool       ## 座標ハッシュで回転60°×左右反転してよいか（向きの無い自然地形＝true）
var connect: bool          ## 隣の同スキンと繋がる線地形か（柵・道）。true なら向きの組み合わせ別タイルを引く
var elevation: float       ## 見た目の高さ（ワールド単位・TILE=1）。0で平ら。段差辺には側面スカートが付く
var sprite_sink: float     ## 立ち絵だけタイル上面より沈める量（植生の厚み）。elevation と同値で足元が地面と揃う
var grid: bool             ## ヘックスの枠線を引くか。駒が入れない地形は引かないほうが一つの塊として読める
## 戦闘演出の地面の作り方（→ doc/tech/combat_scene.md）。マップ絵をそのまま敷いて組む。
var combat_ground: String  ## 下地に敷くスキンID。空＝自分自身で敷き詰める（既定）
var combat_layout: String  ## 自分の絵の置き方。fill(既定・空も同じ) / line(隊列の間を横断) / center(中央1マス)

static func from_dict(d: Dictionary) -> TerrainSkin:
	var s := TerrainSkin.new()
	s.skin_id = String(d.get("skin_id", ""))
	s.terrain_type = String(d.get("terrain_type", ""))
	s.name = String(d.get("name", ""))
	s.orientable = bool(d.get("orientable", false))
	s.connect = bool(d.get("connect", false))
	s.elevation = float(d.get("elevation", 0.0))
	s.sprite_sink = float(d.get("sprite_sink", 0.0))
	s.grid = bool(d.get("grid", true))
	s.combat_ground = String(d.get("combat_ground", ""))
	s.combat_layout = String(d.get("combat_layout", ""))
	return s

## 戦闘演出の地面で、自分の絵をどう置くか（空を fill に畳んだ値）。
func combat_placement() -> String:
	return combat_layout if combat_layout != "" else "fill"

## 戦闘演出の地面の下地スキンID（空なら自分自身＝敷き詰め）。
func combat_ground_id() -> String:
	return combat_ground if combat_ground != "" else skin_id

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

## 盤の縁で線を切らないための補正。connected / on_board はどちらも Hex.DIRECTIONS 順の6要素。
## 繋がっている隣が1つだけのマスは、その反対側が盤の外なら、そちらへも腕を伸ばす＝柵や道が
## 盤の外へ続いて見える（地図の外側にも世界が続いている扱い）。
## 隣が2つ以上あるマスには効かせない。外周に沿って走る柵が、外向きの腕を櫛のように生やすため。
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
