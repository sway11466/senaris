extends RefCounted
class_name FormationChoice
## 行動メニュー1項目ぶん＝1つのスキルについて、盤で成立している参加者の候補をまとめたもの
## （Formation.choices_for の1要素）。組ごとに1つ返す available_for との違いはレシピ単位に畳んで
## あること＝同じ名前の項目が組の数だけ並ばない。
## 純データ・Node非依存。参加者が確定したら Formation.option_of で FormationOption へ変える。
## 詳細 → doc/gdd/formations.md 共通ルール, doc/gdd/uiux.md 陣形スキルの参加者を選ぶ

var skill: String            ## スキルID（Formation.SKILLS のキー）
var leader_id: int           ## 発動者の駒番号
var variable_count: bool     ## 人数が可変か（cluster・line）。false＝固定（member_sets が候補の組）
## 参加者より先に着弾先を選ぶか（④spotter）。相方は着弾先に隣接する駒の中から決まるので、
## 順が逆になる＝着弾先 → （複数いるときだけ）相方。詳細 → doc/gdd/uiux.md 陣形スキルの参加者を選ぶ
var target_first: bool
var min_count: int           ## 成立に要る最低人数（発動者を含む＝SKILLS の "count"）
## 人数が固定のスキルの候補の組（発動者を除く参加者の駒番号）。可変のスキルでは空。
var member_sets: Array = []
## 参加者になりうる駒すべて（発動者を除く）。メニューのホバーで光らせる集合。
var pool: Array[int] = []

## 参加者を選ぶ段を挟むか。選ぶ余地が無ければ飛ばす＝固定で組が1つ、可変で候補が最低人数ちょうど。
## 詳細 → doc/gdd/uiux.md 陣形スキルの参加者を選ぶ
func needs_choice() -> bool:
	if variable_count:
		return pool.size() + 1 > min_count
	return member_sets.size() > 1

## 選ぶ余地が無いときの参加者（発動者を除く）。needs_choice() が false のときだけ意味を持つ。
func forced_members() -> Array[int]:
	if variable_count:
		return pool.duplicate()
	var out: Array[int] = []
	if member_sets.is_empty():
		return out
	for h in member_sets[0]:
		out.append(int(h))
	return out
