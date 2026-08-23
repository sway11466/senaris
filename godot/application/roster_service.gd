extends RefCounted
class_name RosterService
## 名簿（パーティ）の更新規則。仕様 → doc/gdd/map.md（名簿）／doc/tech/gamesystem.md（セーブ）
##
## 名簿は「盤上の生存者リスト」ではなく「いま誰が仲間か」の在籍者一覧。
## - 載るのは actor を持つ駒だけ。名前のない雑兵は同一性を持たないので名簿の対象外＝持ち越さず、
##   各ステージが配給する（部隊ごと持ち越したくなったら actor を振る）。
## - 在籍者は兵力ゼロで失っても troops:0 のまま在籍し続ける＝戦線離脱であって死亡ではない。
##   盤には出ないが会話には出る（出欠は名簿だけで決まる）。
## - 加入は帰属先で判定する＝クリア時に recruited_team が自軍の駒を名簿に加える。中立のまま取り逃した／
##   敵に先に取られた駒は帰属が自軍にならないので載らない。一度味方が解放していれば、その後に拠点ごと
##   奪われて捕虜のままクリアしても載る（帰属は確定後に動かないため）。
##
## 純ロジック（Godot ノード非依存）。永続化は infrastructure/save/roster_store.gd。

## 盤の「いま自軍に在籍している名前つきの駒」を直列化して返す（盤上・拠点の控え・輸送の搭乗をすべて拾う）。
## 判定は team ではなく帰属先＝敵に拠点ごと奪われて出撃できない捕虜も自軍として数える。
## actor の無い駒は名簿の対象外＝ここで落とす（持ち越さない）。
static func collect(state: BattleState) -> Array:
	var out: Array = []
	for u in state.units():
		if _enrolled(u):
			out.append(u.to_dict())
		for p in state.passengers(u.id):  # 搭乗中の駒は units() に居ない
			if _enrolled(p as Unit):
				out.append((p as Unit).to_dict())
	for b in state.bases():
		for gu in b.garrison:
			if _enrolled(gu as Unit):
				out.append((gu as Unit).to_dict())
	return out

## 名簿に載る駒か（自軍に帰属していて、かつ名前つき）。
static func _enrolled(u: Unit) -> bool:
	return u.recruited_team == 0 and u.actor != ""

## クリア時の名簿を作る。previous＝前ステージ終了時の名簿、state＝決着した盤。
## 在籍者は名簿の並び順を保ち、更新するのはこの盤に出た者だけ。出た者が盤から消えていれば
## troops:0 の離脱として残し、そもそも出番の無かった者は前の状態のまま据え置く（別の隊として
## 待機している＝失ってはいない。詳細 → doc/gdd/map.md 名簿の更新）。
## 続けて、新たに加わった仲間（勧誘・そのステージで合流した名前つきの駒）を盤の順で加える。
static func update_after_clear(previous: Array, state: BattleState) -> Array:
	var current := collect(state)
	var current_by_actor := {}
	for i in current.size():
		var a := String((current[i] as Dictionary).get("actor", ""))
		if a != "" and not current_by_actor.has(a):
			current_by_actor[a] = i
	var consumed := {}
	var out: Array = []
	for e in previous:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var a := String((e as Dictionary).get("actor", ""))
		if a == "":
			continue  # 名前のない駒は名簿に載らない（手編集で紛れ込んだ場合の保険）
		if current_by_actor.has(a):
			var i: int = current_by_actor[a]
			out.append(current[i])
			consumed[i] = true
		elif state.has_sortied(a):
			var lost: Dictionary = (e as Dictionary).duplicate(true)
			lost["troops"] = 0  # 出たのに盤から消えた＝戦線離脱。在籍は続く（会話には出る）
			out.append(lost)
		else:
			out.append((e as Dictionary).duplicate(true))  # 出番なし＝据え置き
	for i in current.size():
		if not consumed.has(i):
			out.append(current[i])  # 新規加入（勧誘・合流）
	return out
