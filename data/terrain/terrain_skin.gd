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

static func from_dict(d: Dictionary) -> TerrainSkin:
	var s := TerrainSkin.new()
	s.skin_id = String(d.get("skin_id", ""))
	s.terrain_type = String(d.get("terrain_type", ""))
	s.name = String(d.get("name", ""))
	s.orientable = bool(d.get("orientable", false))
	return s

## タイル画像（基本）のパス。ファイル名は skin_id 規約（変種 _2/_3 は描画側が連番で拾う）。
func image_path() -> String:
	return "res://assets/terrain/%s.png" % skin_id
