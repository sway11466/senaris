extends RefCounted
class_name Formation
## 陣形スキル（純ロジック・Node非依存）。配置レシピの検出とダメージ計算。
## 発動＝プレイヤーの明示操作／参加ユニットは行動完了（適用は FormationResolver）。
## Combat と同じく非破壊（盤は書き換えない）＝検出・威力の計算だけを担う。
## 詳細 → doc/gdd/formations.md, doc/gdd/combat.md §2
##
## ①トリニティノヴァ(area)＋③ディバインジャッジメント(single)＝ダメージ系／②グレイス(buff)＝状態補正（乗算・全体・持続）。
## 3レシピとも解禁済み（IMPLEMENTED_EFFECTS）。buff は BattleState が状態補正エントリを積む（doc/gdd/combat.md）。
##
## 【暫定の戦闘セマンティクス（数値チューニングは formations.md §未決）】
## - 威力＝発動者1体の実効攻撃力（兵数×攻撃力×レベル×包囲×地形）を面の各ヘックスに当てる。間接扱い＝melee=false で支援は乗らない。
## - 防御側は包囲が乗る（surround_factor）。貫通は発動者(caster)の性質を使う（①魔法兵0.5／③聖職0）。
## - 対象は面内の全ユニット（敵味方問わず＝フレンドリーファイア。誤爆＝配置の読み合い）。ただし参加者は全員除外（発動側は自分たちの術で焼けない）。
## - 参加者は Lv+1（撃破が1体でもあれば+2・空撃ちは0）＝適用は FormationResolver。

## スキル定義（当面ハードコード。将来 CSV/JSON 化）。
## caster_skins＝発動者になれるスキン ／ member_skins＝残りの参加者のスキン。
## 照合は skin_id（未指定なら type_id へフォールバック）＝ _matches。詳細 → doc/gdd/formations.md
## shape: "triangle"（count 体が相互隣接）／"escort"（発動者に count-1 体が隣接・メンバー同士は不問）／
##        "cluster"（count 体以上の隣接クラスタ）／"spotter"（参加者の形ではなく対象の周りを見る＝
##        斥候が着弾先に隣接し、発動者はその着弾先を射程に収めている）／
##        "line"（cluster の直線版＝発動者を含む一直線に count 体以上が途切れず連なる）。
## effect: "area"（中心＋周囲6の7hex）／"single"／"buff"。
## impact_motion: 着弾の絵の届き方。"drop"（既定＝真上から降りる）／"fly"（射手から飛ぶ）。single のみ。
## impact_rain: 面の全ヘックスに着弾の絵を降らせる本数（1ヘックスあたり）。省略＝0＝被弾した駒に
##        1枚ずつ落とす共通の形。⑥＝矢の雨。詳細 → doc/gdd/formations.md ⑥
## range_from: "any"（参加者のどれからでも射程判定）／"caster"（発動者から）。
## range_from_stats: 射程を固定値 "range" ではなく参加者の性能から引く（固定の "range" とは排他）。
##        "caster"（④＝発動者の通常射程・下限〜上限）／"max_plus"（⑨＝参加者の射程上限の最大＋range_plus・下限なし）。
## attack_from_stats: 威力のユニット攻撃力を発動者1体ではなく参加者から引く。省略＝発動者（設計原則2）。
##        "max_plus"（⑨＝参加者の攻撃力の最大＋attack_plus。兵数・レベル・包囲・地形は発動者のもの）。
## category: クロニクルの陣形スキル章の束ね（表Aの「分類」・CATEGORIES のどれか）。ユニットスキルは持たない。
## 陣形スキルの並びは表Aの行順に揃える＝クロニクルのカードの並び。詳細 → doc/gdd/chronicle.md 陣形スキル
## 分類（category）に書ける値＝表Aの「分類」列（弓攻撃／魔法攻撃／特殊攻撃／強化／弱体化／その他／敵）。
const CATEGORIES := ["bow", "magic", "special", "buff", "debuff", "other", "enemy"]

const SKILLS := {
	# name は開発用メモ。画面表示は tr("skill.{id}.name")（正本 data/i18n/skills.csv）で解決する。
	"trinity_nova": {
		"name": "トリニティノヴァ",
		"category": "magic",
		"caster_skins": ["wizard", "witch"],
		"member_skins": ["wizard", "witch"],
		"shape": "triangle",
		"count": 3,
		"effect": "area",
		"radius": 1,
		"range": 5,
		"range_from": "any",
	},
	"grace": {
		"name": "グレイス",
		"category": "buff",
		"caster_skins": ["cleric", "priest", "bishop", "paladin"],
		"member_skins": ["cleric", "priest", "bishop", "paladin"],
		"shape": "cluster",
		"count": 5,
		"effect": "buff",
		"buff_op": "mul",
		# 最低人数（count）で成立したときの補正。参加者が count を超えた1体ごとに buff_value_per_extra を
		# 足す＝5体 ×1.30／6体 ×1.35／8体 ×1.45。人数を集めた判断が報われる形（頭数が増えるほど
		# 消費だけ増える、を避ける）。人数で伸びるのはこのレシピだけ。詳細 → doc/gdd/formations.md ②
		"buff_value": 1.3,
		"buff_value_per_extra": 0.05,
		"buff_fx": "aura",  # 盤全体の見た目（外周から差し込む金の光）。詳細 → doc/gdd/formations.md
		"duration_turns": 1,  # 自軍ターン1回＋間の敵ターン＝1ターン。詳細 → doc/gdd/map.md 用語・ターン
	},
	"divine_judgment": {
		"name": "ディバインジャッジメント",
		"category": "special",
		"caster_skins": ["paladin"],
		"member_skins": ["cleric", "priest", "bishop"],
		"shape": "escort",
		"count": 3,
		"effect": "single",
		"range": 10,
		"range_from": "caster",
	},
	"trick_shot": {
		"name": "トリックショット",
		"category": "bow",
		"caster_skins": ["archer", "hunter", "elf"],  # スリンガー系は投石なので対象外
		# 先頭のシーフがクロニクルの図と未解放の黒塗りの代表（doc/gdd/chronicle.md 陣形スキル）。
		"member_skins": ["thief", "halfling", "ninja", "kunoichi"],
		"shape": "spotter",
		"count": 2,
		"effect": "single",
		# 射程は弓兵の通常射程そのもの（下限〜上限）＝レシピは固定値を持たない。
		"range_from_stats": "caster",
		"range_from": "caster",
		# 斥候が張り付いて見つけた弱点を射抜く＝魔法兵と同じ貫通が矢に乗る（弓の素は0）。
		"pierce_override": 0.5,
		# 矢のレシピは通常攻撃と同じく相手で対空／対地を切り替える（設計原則3の例外）。
		"attack_vs": "target",
		# 着弾の絵は射手のヘックスから飛んでくる（③の「真上から降りる」と別）。
		"impact_motion": "fly",
		# カットインの絵は発動者（アーチャー／ハンター／エルフ）ごとに1枚＝{skill_id}_{skin}.png。
		# 他のスキルはスキルごと1枚。→ doc/gdd/formations.md 発動の演出
		"cutin_per_caster": true,
	},
	"shield_wall": {
		"name": "シールドウォール",
		"category": "buff",
		# 歩兵（ノービスは見習いのため対象外）。味方の歩兵スキンが増えたらここに足す＝足し忘れは
		# tests/small/data/test_data_integrity.gd が unit_skin.csv と突き合わせて落とす。
		"caster_skins": ["fighter", "vanguard", "knight", "dwarf"],
		"member_skins": ["fighter", "vanguard", "knight", "dwarf"],
		"shape": "line",
		"count": 3,
		"effect": "buff",
		# 列に並んだ参加者だけに乗る（陣営全体の②グレイスと違い、他の味方には効かない）。
		"buff_scope": "participants",
		"buff_op": "mul",
		"buff_target": "defense",  # 防御だけ（攻撃は変わらない）
		# 最低人数（count）で ×1.15。1体増えるごとに +0.05＝4体 ×1.20／5体 ×1.25。
		# 効果は薄くてよい＝3体で森（防 ×1.2）に立つ程度。本体は「列から動けない」代償のほう。
		# 詳細 → doc/gdd/formations.md ⑤
		"buff_value": 1.15,
		"buff_value_per_extra": 0.05,
		"buff_fx": "wall",  # 盤の見た目（列の駒の足元の光）。空＝見た目なし
		"duration_turns": 1,  # 自軍ターン1回＋間の敵ターン＝1ターン。詳細 → doc/gdd/map.md 用語・ターン
		"range_from": "any",  # 列のどの駒からでも発動できる（着弾は無いので対象は取らない）
	},
	"arrow_rain": {
		"name": "アローレイン",
		"category": "bow",
		"caster_skins": ["archer", "hunter", "elf"],  # スリンガー系は投石なので対象外（④と同じ）
		"member_skins": ["archer", "hunter", "elf"],
		"shape": "triangle",
		"count": 3,
		"effect": "area",
		# 中心＋周囲6＋その外周12＝19ヘクス。①の面（7ヘクス）より一回り広く、参加者以外の味方は焼ける。
		"radius": 2,
		# 射程は発動者の通常射程＝誰が号令をかけるかで届く距離が変わる（アーチャー3／ハンター4／エルフ5）。
		# 起点は3体のどれからでもよい。詳細 → doc/gdd/formations.md ⑥
		"range_from_stats": "caster",
		"range_from": "any",
		# 矢のレシピは通常攻撃と同じく相手で対空／対地を切り替える（設計原則3の例外）。
		"attack_vs": "target",
		# 着弾は面の19ヘックスすべてに矢を3本ずつ降らせる（駒に1枚落とす共通の形ではない）。
		"impact_rain": 3,
	},
	"magic_arrow": {
		"name": "マジックアロー",
		"category": "magic",
		"caster_skins": ["archer", "hunter", "elf"],  # 矢を放つのは弓＝発動は弓兵から。スリンガー系は投石なので対象外
		"member_skins": ["wizard", "witch"],  # メイジは見習いのため対象外
		"shape": "escort",
		"count": 2,
		"effect": "single",
		# 射程は2体の射程上限の長い方＋1（アーチャー／ハンター＋ウィザード＝5、エルフかウィッチが居れば6）。
		# 下限は無し＝隣接にも撃てる。詳細 → doc/gdd/formations.md ⑨
		"range_from_stats": "max_plus",
		"range_plus": 1,
		"range_from": "caster",
		# 威力は2体の攻撃力の大きい方＋10（合算はしない＝設計原則2の唯一の例外）。相手が飛行なら対空値で
		# 大きい方を取る＝地上ではウィザード40＋10、空ではエルフ60＋10 と主役が入れ替わる。
		"attack_from_stats": "max_plus",
		"attack_plus": 10,
		"pierce_override": 0.5,  # 魔法が矢に貫通を持ち寄る
		"attack_vs": "target",
		"impact_motion": "fly",  # ④と同じ＝光を纏った矢が射手のヘックスから飛んでくる
		# カットインの絵は④と同じく発動者（アーチャー／ハンター／エルフ）ごとに1枚＝{skill_id}_{skin}.png。
		"cutin_per_caster": true,
	},
	# ユニットスキル＝参加者が発動者だけ(shape="solo")・効果を味方1体に乗せる(buff_scope="unit")。
	# 仕組みは陣形と共通で、カタログだけ分けている。詳細 → doc/gdd/skills.md
	"pixie_dust": {
		"name": "ピクシーダスト",
		"caster_skins": ["pixie"],
		"member_skins": [],
		"shape": "solo",
		"count": 1,
		"effect": "buff",
		"buff_scope": "unit",
		"buff_op": "add",  # 実効攻防への加算（レベル・包囲・地形の補正は乗らない）
		# 発動したピクシー1兵あたりの加算量。発動時の残兵数を掛けた値を焼き込む＝以後ピクシーが
		# 損耗しても倒されても、掛かった補正は変わらない。詳細 → doc/gdd/skills.md
		"buff_value_per_troop": 10.0,
		"buff_target": "both",
		"buff_fx": "dust",  # 盤の見た目（掛かっている駒の足元を光らせる）。空＝見た目なし
		"duration_turns": 3,  # 発動側ターン3回ぶん。詳細 → doc/gdd/skills.md
		"range": 1,  # 自分(0)＋隣接(1)
		"range_from": "caster",
	},
	"purify": {
		"name": "ピュリファイ",
		"caster_skins": ["cleric", "priest", "bishop"],
		"member_skins": [],
		"shape": "solo",
		"count": 1,
		# 状態補正を積むのではなく落とす＝値を持たない。詳細 → doc/gdd/skills.md
		"effect": "cleanse",
		"buff_scope": "unit",  # 対象1体（自分＋隣接）
		"buff_side": "ally",
		"range": 1,
		"range_from": "caster",
	},
	"dread_touch": {
		"name": "ドレッドタッチ",
		"caster_skins": ["ghost"],
		"member_skins": [],
		"shape": "solo",
		"count": 1,
		"effect": "buff",
		"buff_scope": "unit",
		"buff_side": "enemy",  # 対象は敵1体（ピクシーダストは味方＝"ally"）。詳細 → doc/gdd/skills.md
		"buff_op": "add",
		# ピクシーダストと同じ形の負値＝発動時のゴーストの残兵数を掛けて焼き込む（満員8体で -80）。
		"buff_value_per_troop": -10.0,
		"buff_target": "both",
		"buff_fx": "dread",
		"buff_kind": "debuff",  # 強化か弱体か。ピュリファイが落とす対象・盤の見た目。値の符号からは判断しない
		"duration_turns": 3,  # 発動側ターン3回ぶん。詳細 → doc/gdd/skills.md
		"range": 1,
		"range_from": "caster",
	},
	"venom_fang": {
		"name": "ヴェノムファング",
		"caster_skins": ["rock_serpent"],
		"member_skins": [],
		"shape": "solo",
		"count": 1,
		"effect": "buff",
		"buff_scope": "unit",
		"buff_side": "enemy",
		"buff_op": "mul",
		# 固定係数 0.9＝1本で攻防10%減。重ねると掛け合わさる（2本で0.81・3本で0.73）。
		# ドレッドタッチの残兵依存（add）と違い、兵数に依らない。詳細 → doc/gdd/skills.md
		"buff_value": 0.9,
		"buff_target": "both",
		"buff_fx": "venom",
		"buff_kind": "debuff",
		"duration_turns": 3,  # 発動側ターン3回ぶん。詳細 → doc/gdd/skills.md
		"range": 1,
		"range_from": "caster",
	},
	"poison_sting": {
		"name": "ポイズンスティング",
		"caster_skins": ["scorpion"],
		"member_skins": [],
		"shape": "solo",
		"count": 1,
		# 補正値を積むのではなく、持続の間ターン開始に兵数を減らす。攻防には触らない
		# （補正チェーンに参加しない）＝ヴェノムファングの上位版ではなく別軸。詳細 → doc/gdd/skills.md
		"effect": "dot",
		"buff_scope": "unit",
		"buff_side": "enemy",
		"dot_troops": 1,  # 対象側のターン開始ごとに減る兵数
		"buff_fx": "venom",
		"buff_kind": "debuff",
		"duration_turns": 3,  # 発動側ターン3回ぶん＝合計3減る。詳細 → doc/gdd/skills.md
		"range": 1,
		"range_from": "caster",
		"combat_effect": "thrust",  # 当面は刺突の汎用（毒色は絵に持たせない）
	},
	"slime_split": {
		"name": "スライムスプリット",
		"caster_skins": ["slime"],
		"member_skins": [],
		"shape": "solo",
		"count": 1,
		# 駒を盤に追加する効果。状態補正ではない。対象選択なし（隣接する空きマスへ自動配置）。
		# 発動者の複製を1体生成し、兵数は発動時点の発動者の兵数を引き継ぐ。max_troops は type の既定値。
		# 詳細 → doc/gdd/skills.md
		"effect": "spawn",
		"range": 0,  # 自分の隣接に分裂で出る＝対象選択は不要
		"range_from": "caster",
		"charge_turns": 3,  # 盤に出た直後は撃てない。3ターン溜めてから発動。詳細 → doc/gdd/skills.md
	},
}

## 適用まで実装済みの効果。未対応はメニューに出さない。
const IMPLEMENTED_EFFECTS := ["area", "single", "buff", "cleanse", "spawn", "dot"]

## 「発動者の位置を仮定しない」番兵（盤の外）。available_for / can_target / targetable_cells の
## from_hex に渡さなければこれ＝発動者は盤の上の実位置に居るものとして判定する。
const NO_HEX := Vector2i(1 << 30, 1 << 30)

## そのスキルがユニットスキル（単独発動＝shape "solo"）か。カタログ上の区別で、仕組みは共通。
## 演出・効果音の出し分けが読む（陣形はカットインあり／ユニットスキルは音だけ）。
static func is_unit_skill(skill_id: String) -> bool:
	var r: Dictionary = SKILLS.get(skill_id, {})
	return String(r.get("shape", "")) == "solo"

## unit が持つユニットスキル（単独発動スキル）の id 一覧。盤の状況（対象の有無・行動済み）には
## 依らない＝「この駒は何を撃てる駒か」。情報パネルの能力タブが説明を並べるのに読む。
## いま撃てるかは available_for が見る（→ doc/gdd/uiux.md ユニット情報パネル）。
static func unit_skills_of(unit: Unit) -> Array[String]:
	var out: Array[String] = []
	if unit == null:
		return out
	for rid in SKILLS:
		var r: Dictionary = SKILLS[rid]
		if String(r["shape"]) != "solo" or not (r["effect"] in IMPLEMENTED_EFFECTS):
			continue
		if _matches(unit, r["caster_skins"]):
			out.append(rid)
	return out

## 選択中 unit が発動できる、盤上で成立済みのスキル選択肢一覧（読み取りのみ・非破壊）。
## 各要素＝ FormationOption（スキルの値＋参加者。対象が要るか等の判断もそこに持つ）。
## from_hex＝発動者がそこに居ると仮定して成立を見る（移動を確定する前のコマンドメニュー用）。
## 発動者は移動してから発動してよい＝隣接の判定は移動先で行う。詳細 → doc/gdd/formations.md
static func available_for(state: BattleState, unit: Unit, from_hex := NO_HEX) -> Array[FormationOption]:
	var out: Array[FormationOption] = []
	if unit == null:
		return out
	var caster_pos := unit.pos if from_hex == NO_HEX else from_hex
	for rid in SKILLS:
		var r: Dictionary = SKILLS[rid]
		if not _caster_can_offer(state, unit, rid, r):
			continue
		match String(r["shape"]):
			"triangle":
				for members in _triangle_sets(state, unit, r, caster_pos):
					out.append(FormationOption.from_skill(rid, r, [unit, members[0], members[1]]))
			"escort":
				for members in _escort_sets(state, unit, r, caster_pos):
					out.append(FormationOption.from_skill(rid, r, [unit] + members))
			"spotter":
				for members in _spotter_sets(state, unit, r, caster_pos):
					out.append(FormationOption.from_skill(rid, r, [unit, members[0]]))
			"solo":
				# spawn は隣接に空きマス（盤内かつ駒が居ない）が無ければ成立しない
				if String(r["effect"]) == "spawn" and not _spawn_has_room(state, caster_pos):
					continue
				out.append(FormationOption.from_skill(rid, r, [unit]))  # ユニットスキル＝発動者だけで成立
			"cluster":
				var members := _cluster(state, unit, r, caster_pos)
				if not members.is_empty():
					var ordered: Array = [unit]  # 発動者を先頭に（caster_id 用）
					for m in members:
						if m.handle != unit.handle:
							ordered.append(m)
					out.append(FormationOption.from_skill(rid, r, ordered))
			"line":
				# 軸ごとに1件＝十字に並んでいれば2通りの列から選べる（クラスタは1件）。
				for run in _line_runs(state, unit, r, caster_pos):
					out.append(FormationOption.from_skill(rid, r, [unit] + run))
	return out

## 選択中 unit が発動できるスキルを、レシピ単位に1つずつまとめた一覧（読み取りのみ・非破壊）。
## 行動メニューはこれを並べる＝成立する組が複数あっても同じ名前の項目を並べない。組ごとに1つ
## 要る側（敵AI・撮影ツール）は available_for を使う。
## 参加者は choices_for → member_candidates → option_of の順で確定する。
## 詳細 → doc/gdd/uiux.md 陣形スキルの参加者を選ぶ
static func choices_for(state: BattleState, unit: Unit, from_hex := NO_HEX) -> Array[FormationChoice]:
	var out: Array[FormationChoice] = []
	if unit == null:
		return out
	var caster_pos := unit.pos if from_hex == NO_HEX else from_hex
	for rid in SKILLS:
		var r: Dictionary = SKILLS[rid]
		if not _caster_can_offer(state, unit, rid, r):
			continue
		var c := FormationChoice.new()
		c.skill = rid
		c.caster_id = unit.handle
		c.min_count = int(r.get("count", 1))
		match String(r["shape"]):
			"triangle":
				_fill_fixed(c, _triangle_sets(state, unit, r, caster_pos))
			"escort":
				_fill_fixed(c, _escort_sets(state, unit, r, caster_pos))
			"spotter":
				# 相方は着弾先が決まってから絞る＝先に着弾先を選ぶ段へ進む
				c.target_first = true
				_fill_fixed(c, _spotter_sets(state, unit, r, caster_pos))
			"solo":
				if String(r["effect"]) == "spawn" and not _spawn_has_room(state, caster_pos):
					continue
				c.member_sets = [[] as Array[int]]  # 発動者だけで成立＝選ぶ余地の無い組が1つ
			"cluster":
				c.variable_count = true
				for m in _cluster(state, unit, r, caster_pos):
					if m.handle != unit.handle:
						c.pool.append(m.handle)
			"line":
				# 候補は軸ごとの列の和集合（十字なら両方の腕が出る）。どの軸へ伸ばすかは
				# 1体目を選んだ時点で決まる＝以後は列の両端の外側だけが候補になる。
				c.variable_count = true
				var seen := {}
				for run in _line_runs(state, unit, r, caster_pos):
					for m in run:
						if not seen.has(m.handle):
							seen[m.handle] = true
							c.pool.append(m.handle)
		if c.member_sets.is_empty() and c.pool.is_empty():
			continue  # 組が1つも無い＝そのスキルは成立していない
		out.append(c)
	return out

## いま追加で選べる参加者（駒番号）。chosen＝確定済みの参加者（発動者は含めない）。
## 人数が固定のスキルは「chosen を含む組の残り」＝1体目を確定すると2体目の候補が絞られる。
## 人数が可変のスキルは形を保つ駒だけ＝発動者か確定済みに隣接するものを端から伸ばす
## （`line`（⑤）が入るときは、ここに一直線の条件が加わる → doc/gdd/formations.md 実装方針）。
static func member_candidates(state: BattleState, choice: FormationChoice, chosen: Array[int],
		from_hex := NO_HEX) -> Array[int]:
	var out: Array[int] = []
	if choice == null:
		return out
	if choice.variable_count:
		var caster := state.unit_by_handle(choice.caster_id)
		if caster == null:
			return out
		# 一直線の形（⑤）は「隣接していれば伸ばせる」では足りない＝列の両端の外側だけを出す。
		if String(SKILLS[choice.skill].get("shape", "")) == "line":
			return _line_candidates(state, choice, chosen,
					caster.pos if from_hex == NO_HEX else from_hex)
		var anchors: Array[Vector2i] = [caster.pos if from_hex == NO_HEX else from_hex]
		for h in chosen:
			var cu := state.unit_by_handle(h)
			if cu != null:
				anchors.append(cu.pos)
		for h in choice.pool:
			if h in chosen:
				continue
			var u := state.unit_by_handle(h)
			if u == null:
				continue
			for a in anchors:
				if Hex.distance(u.pos, a) == 1:
					out.append(h)
					break
		return out
	var seen := {}
	for s in choice.member_sets:
		if not _contains_all(s, chosen):
			continue
		for h in s:
			var hid := int(h)
			if hid in chosen or seen.has(hid):
				continue
			seen[hid] = true
			out.append(hid)
	return out

## chosen（発動者を除く確定済みの参加者）で発動できるか。
## 人数が可変のスキルは最低人数以上、固定のスキルは人数ちょうど。
static func can_activate(choice: FormationChoice, chosen: Array[int]) -> bool:
	if choice == null:
		return false
	var n := chosen.size() + 1  # 発動者を足す
	if choice.variable_count:
		return n >= choice.min_count
	return n == choice.min_count

## 確定した参加者から FormationOption を組む（先頭＝発動者）。発動の直前に1度だけ呼ぶ。
static func option_of(state: BattleState, choice: FormationChoice, chosen: Array[int]) -> FormationOption:
	if choice == null:
		return null
	var caster := state.unit_by_handle(choice.caster_id)
	if caster == null:
		return null
	var units: Array = [caster]
	for h in chosen:
		var u := state.unit_by_handle(h)
		if u == null:
			return null
		units.append(u)
	return FormationOption.from_skill(choice.skill, SKILLS[choice.skill], units)

## いま撃てる先があるか（メニュー項目を無効化するかの判断）。対象の要らないスキルは常に true。
## 射程の起点に参加者を含むスキル（range_from "any"）があるので、候補の組ごとに見て1つでも
## 撃てれば有効にする＝どの組で撃つかは参加者選びの段で決まる。
static func choice_has_target(state: BattleState, choice: FormationChoice, from_hex := NO_HEX) -> bool:
	for members in _probe_sets(choice):
		var o := option_of(state, choice, members)
		if o == null:
			continue
		if not o.needs_target():
			return true
		if not targetable_cells(state, o, from_hex).is_empty():
			return true
	return false

## target を着弾中心としたときの効果プレビュー（純ロジック・非破壊）。
## 対象ごとの hit 内訳（HitDetail。target_id に対象の駒番号）を返す。適用は FormationResolver。
static func preview(state: BattleState, option: FormationOption, target: Vector2i) -> Dictionary:
	var hits: Array = []
	var participants := option.participants
	for hx in blast_cells(option, target):
		var victim := state.unit_at(hx)
		if victim != null and not (victim.handle in participants):
			hits.append(_formation_hit(state, option, victim))
	return {"skill": option.skill, "hits": hits}

## 着弾する面＝効果が及ぶヘックス（駒の有無によらない）。着弾の無いもの（バフ・解除）は空。
## 盤の演出が「どこに当たったか」を光らせるのに使う。詳細 → doc/gdd/formations.md 発動の演出
static func blast_cells(option: FormationOption, target: Vector2i) -> Array[Vector2i]:
	match option.effect:
		FormationOption.Effect.AREA:
			return Hex.within_range(target, option.radius)
		FormationOption.Effect.SINGLE:
			return [target] as Array[Vector2i]
	return [] as Array[Vector2i]

## target が発動条件の射程内か（"any"＝参加者のどれか／"caster"＝発動者から）。
## from_hex＝発動者がそこに居ると仮定する（移動を確定する前の判定）。省略すると盤の実位置。
static func can_target(state: BattleState, option: FormationOption, target: Vector2i, from_hex := NO_HEX) -> bool:
	if not option.needs_target():
		return true
	var caster_id := option.caster_id
	var caster := state.unit_by_handle(caster_id)
	var within := false
	if option.range_from == FormationOption.RangeFrom.ANY:
		for pid in option.participants:
			var p := state.unit_by_handle(int(pid))
			if p == null:
				continue
			var ppos := from_hex if (from_hex != NO_HEX and p.handle == caster_id) else p.pos
			if option.in_range(Hex.distance(ppos, target)):
				within = true
				break
	elif from_hex != NO_HEX:
		within = option.in_range(Hex.distance(from_hex, target))
	else:
		within = caster != null and option.in_range(Hex.distance(caster.pos, target))
	if not within:
		return false
	# ④トリックショット＝着弾先に斥候（相方）が張り付いていること。参加者の形ではなく対象の周りを
	# 見る唯一の形で、相方は移動しない＝盤の実位置で測る。詳細 → doc/gdd/formations.md ④
	if option.shape == FormationOption.Shape.SPOTTER:
		if option.participants.size() < 2:
			return false
		var spotter := state.unit_by_handle(option.participants[1])
		if spotter == null or Hex.distance(spotter.pos, target) != 1:
			return false
	# 単体を狙うスキル（③④）は敵の駒だけを選べる＝空撃ちも同士討ちもさせない。面に巻き込まれるのと
	# 狙って撃てるのは別で、誤射は面（①⑥）だけの話。詳細 → doc/gdd/formations.md 共通ルール
	if option.effect == FormationOption.Effect.SINGLE:
		var v := _unit_at_assumed(state, caster, from_hex, target)
		return v != null and caster != null and v.team != caster.team
	# 対象1体のスキルは駒の居るhexだけ＝空撃ちさせない。味方に掛けるもの（ピクシーダスト）は発動者
	# 自身も選べ、敵を弱らせるもの（ドレッドタッチ）は敵だけを選べる。詳細 → doc/gdd/skills.md
	if option.scope == FormationOption.Scope.UNIT:
		var u := _unit_at_assumed(state, caster, from_hex, target)
		if u == null or caster == null:
			return false
		var same_team := u.team == caster.team
		if option.side == FormationOption.Side.ENEMY:
			return not same_team
		if not same_team:
			return false
		# 解除（ピュリファイ）は落とすものが無ければ撃てない＝弱体の掛かっていない味方は対象に
		# ならない。撃てる先が無ければメニューは項目を無効化する。詳細 → doc/gdd/skills.md ③
		if option.effect == FormationOption.Effect.CLEANSE:
			return state.debuff_count(u) > 0
		return true
	return true

## option の着弾中心に選べるhex（発動条件の射程内・盤上）。空＝いま撃てる先が無い＝コマンド
## メニューでは項目を無効化する（→ doc/gdd/uiux.md 「できない操作は選べない」）。
## from_hex＝発動者がそこに居ると仮定する（移動を確定する前のメニュー判定）。省略すると実位置。
## 絞り込み（射程・陣営・駒が居るか）は can_target が全部持つ＝ここには二重に書かない。
## single（単体狙撃）は敵の駒が居るhexだけ、area（面）は地面にも撃てる。
static func targetable_cells(state: BattleState, option: FormationOption, from_hex := NO_HEX) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not option.needs_target():
		return out
	for h in _in_range_cells(state, option, from_hex):
		if can_target(state, option, h, from_hex):
			out.append(h)
	return out

## 参加者が決まる前に着弾先を選ぶスキル（④spotter）で、選べる着弾先。候補の組それぞれで見た
## targetable_cells の和集合＝どれかの斥候で撃てるhexを全部出す。相方は着弾先を選んでから決まる。
## 詳細 → doc/gdd/uiux.md 陣形スキルの参加者を選ぶ
static func choice_targetable_cells(state: BattleState, choice: FormationChoice,
		from_hex := NO_HEX) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	for members in _probe_sets(choice):
		var o := option_of(state, choice, members)
		if o == null:
			continue
		for h in targetable_cells(state, o, from_hex):
			if not seen.has(h):
				seen[h] = true
				out.append(h)
	return out

## 着弾先を決めたあとに選べる相方（駒番号）。その着弾先を撃てる組の参加者だけを返す。
## 1体なら選ぶ余地が無いのでそのまま発動、複数なら相方を選ぶ段を挟む。
static func members_for_target(state: BattleState, choice: FormationChoice, target: Vector2i,
		from_hex := NO_HEX) -> Array[int]:
	var out: Array[int] = []
	for members in _probe_sets(choice):
		var o := option_of(state, choice, members)
		if o == null or not can_target(state, o, target, from_hex):
			continue
		for h in members:
			if not (h in out):
				out.append(h)
	return out

# --- 内部 ---

## unit がレシピの候補スキン列に当てはまるか。照合は skin_id、未指定なら type_id へフォールバック。
## 見た目が違えば別ユニット＝種別が同じでもゴブリンでグレイスは成立しない。
## 詳細 → doc/gdd/formations.md
static func _matches(unit: Unit, skins: Array) -> bool:
	var key := unit.skin_id if unit.skin_id != "" else unit.type_id
	return key in skins

## unit がそのスキルの発動者として名乗れるか（形は見ない）。available_for と choices_for の共通の門。
static func _caster_can_offer(state: BattleState, unit: Unit, rid: String, r: Dictionary) -> bool:
	if not (r["effect"] in IMPLEMENTED_EFFECTS):
		return false
	if not _matches(unit, r["caster_skins"]):
		return false
	# 参加資格は陣形もユニットスキルも「行動を使い切っていない」（待機・攻撃済みでない）。
	# 行ける先が無いだけの駒は参加できる＝発動に移動先も攻撃相手も要らない。
	if not state.has_action_left(unit.handle):
		return false
	# チャージが必要なスキルは、溜まっていなければ不成立。詳細 → doc/gdd/skills.md
	var ct := int(r.get("charge_turns", 0))
	return ct == 0 or state.get_charge(unit.handle, rid) >= ct

## 分裂（spawn）の置き先＝caster_pos の隣に盤内の空きマスがあるか。
static func _spawn_has_room(state: BattleState, caster_pos: Vector2i) -> bool:
	for nb in Hex.neighbors(caster_pos):
		if state.in_field(nb) and state.unit_at(nb) == null:
			return true
	return false

## 人数が固定のスキルの候補（Unit の組の列挙）を FormationChoice へ移す。
## member_sets＝組ごとの駒番号／pool＝どれかの組に出てくる駒すべて（メニューのホバーで光らせる）。
static func _fill_fixed(c: FormationChoice, sets: Array) -> void:
	var seen := {}
	for s in sets:
		var ids: Array[int] = []
		for u in s:
			ids.append(u.handle)
			if not seen.has(u.handle):
				seen[u.handle] = true
				c.pool.append(u.handle)
		c.member_sets.append(ids)

## s が chosen の駒をすべて含むか（確定済みと矛盾しない組の絞り込み）。
static func _contains_all(s: Array, chosen: Array[int]) -> bool:
	for h in chosen:
		if not (h in s):
			return false
	return true

## 撃てる先があるかを試す参加者の組。固定は候補の組ぜんぶ、可変は候補全員（射程の起点が最も多い）。
static func _probe_sets(choice: FormationChoice) -> Array:
	if choice == null:
		return []
	if choice.variable_count:
		return [choice.pool.duplicate()]
	var out: Array = []
	for s in choice.member_sets:
		var ids: Array[int] = []
		for h in s:
			ids.append(int(h))
		out.append(ids)
	return out

## from_hex に発動者が居ると仮定したときの hex の駒。移動を確定する前は盤の上の発動者がまだ
## 元のマスに立っているので、そこを空として読み替える（自分に掛けるスキルの対象判定に効く）。
static func _unit_at_assumed(state: BattleState, caster: Unit, from_hex: Vector2i, hex: Vector2i) -> Unit:
	if caster != null and from_hex != NO_HEX:
		if hex == from_hex:
			return caster
		if hex == caster.pos:
			return null
	return state.unit_at(hex)

## 射程内かつ盤上のhex（重複なし）。起点は "any" なら参加者ぜんぶ／"caster" なら発動者だけ。
static func _in_range_cells(state: BattleState, option: FormationOption, from_hex: Vector2i) -> Array[Vector2i]:
	var rng := option.max_range
	var caster_id := option.caster_id
	var origins: Array[Vector2i] = []
	if option.range_from == FormationOption.RangeFrom.ANY:
		for pid in option.participants:
			var p := state.unit_by_handle(int(pid))
			if p != null:
				origins.append(from_hex if (from_hex != NO_HEX and p.handle == caster_id) else p.pos)
	elif from_hex != NO_HEX:
		origins.append(from_hex)
	else:
		var caster := state.unit_by_handle(caster_id)
		if caster != null:
			origins.append(caster.pos)
	var seen := {}
	var out: Array[Vector2i] = []
	for o in origins:
		for h in Hex.within_range(o, rng):
			# 下限のあるレシピ（④＝弓兵の通常射程）は懐のhexを落とす
			if not seen.has(h) and state.in_field(h) and option.in_range(Hex.distance(o, h)):
				seen[h] = true
				out.append(h)
	return out

## caster（caster_pos に居るものとする）に隣接する member_skins の候補（同陣営・未行動）。
## caster_pos は移動先のこともある＝発動者だけ仮の位置で測る。
static func _adjacent_members(state: BattleState, caster: Unit, r: Dictionary, caster_pos: Vector2i) -> Array:
	var cand: Array[Unit] = []
	for u in state.units():
		if u.handle == caster.handle or u.team != caster.team or not state.has_action_left(u.handle):
			continue
		if not _matches(u, r["member_skins"]):
			continue
		if Hex.distance(u.pos, caster_pos) == 1:
			cand.append(u)
	return cand

## ①トリニティノヴァ＝三角形。caster に隣接する候補のうち、互いにも隣接する2体組を全列挙。
static func _triangle_sets(state: BattleState, caster: Unit, r: Dictionary, caster_pos: Vector2i) -> Array:
	var cand := _adjacent_members(state, caster, r, caster_pos)
	var sets: Array = []
	for i in cand.size():
		for j in range(i + 1, cand.size()):
			if Hex.distance(cand[i].pos, cand[j].pos) == 1:
				sets.append([cand[i], cand[j]])
	return sets

## レシピのメンバー候補（同陣営・未行動・スキン一致）を位置によらず全部集める。
## 位置で絞る形（triangle/escort/cluster）は発動者からの距離で、spotter は対象からの距離で絞る。
static func _member_pool(state: BattleState, caster: Unit, r: Dictionary) -> Array:
	var cand: Array[Unit] = []
	for u in state.units():
		if u.handle == caster.handle or u.team != caster.team or not state.has_action_left(u.handle):
			continue
		if _matches(u, r["member_skins"]):
			cand.append(u)
	return cand

## ④トリックショット＝対象の周りを見る形。斥候が「発動者の射程に入っている駒」に張り付いていれば
## 組になる（弓兵と斥候は隣り合わなくてよい）。組は斥候1体ごとに1つで、着弾先はあとから選ぶ。
## 発動者は caster_pos に居るものとして射程を測る（移動先のこともある）。
static func _spotter_sets(state: BattleState, caster: Unit, r: Dictionary, caster_pos: Vector2i) -> Array:
	var sets: Array = []
	for m in _member_pool(state, caster, r):
		if _spotter_has_mark(state, caster, m, caster_pos):
			sets.append([m])
	return sets

## 斥候 m の隣に「発動者の射程（下限〜上限）に入っている敵」が居るか＝その斥候で1発撃てるか。
## 単体を狙うスキルは敵しか選べない（can_target）ので、成立の判定も敵だけを数える。
static func _spotter_has_mark(state: BattleState, caster: Unit, m: Unit, caster_pos: Vector2i) -> bool:
	for nb in Hex.neighbors(m.pos):
		if not state.in_field(nb):
			continue
		var v := state.unit_at(nb)
		if v == null or v.team == caster.team:
			continue
		var d := Hex.distance(caster_pos, nb)
		if d >= caster.min_range and d <= caster.attack_range:
			return true
	return false

## 発動者を中心に、隣接する count-1 体。メンバー同士の隣接は問わない（発動者を挟んで左右対称でも
## 成立する）＝caster に隣接する候補から count-1 体の組を全列挙。
## ③ディバインジャッジメント＝2体組／⑨マジックアロー＝1体（隣接する魔法兵ごとに1組）。
static func _escort_sets(state: BattleState, caster: Unit, r: Dictionary, caster_pos: Vector2i) -> Array:
	var cand := _adjacent_members(state, caster, r, caster_pos)
	var need := int(r["count"]) - 1
	var sets: Array = []
	if need == 1:
		for m in cand:
			sets.append([m])
	elif need == 2:
		for i in cand.size():
			for j in range(i + 1, cand.size()):
				sets.append([cand[i], cand[j]])
	else:
		assert(false, "Formation: escort の人数 %d は未対応（2 か 3）" % int(r["count"]))
	return sets

## caster を含む member_skins の隣接連結成分（同陣営・未行動）を返す。size < count なら空＝不成立。
## ②グレイス＝占領兵が count 体以上「固まっていれば」成立（形は不問）。参加者＝クラスタ全員。
## caster は caster_pos に居るものとする（移動先のこともある）＝探索は位置で持ち回る。
static func _cluster(state: BattleState, caster: Unit, r: Dictionary, caster_pos: Vector2i) -> Array:
	var seen := {caster.handle: caster}
	var frontier: Array[Vector2i] = [caster_pos]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_back()
		for u in state.units():
			if seen.has(u.handle) or u.team != caster.team or not state.has_action_left(u.handle):
				continue
			if not _matches(u, r["member_skins"]):
				continue
			if Hex.distance(u.pos, cur) == 1:
				seen[u.handle] = u
				frontier.append(u.pos)
	if seen.size() < int(r["count"]):
		return []
	return seen.values()

## ⑤シールドウォール＝一直線。発動者の居るヘックスから3軸それぞれに、条件に合う駒が途切れる
## まで両方向へ伸ばし、発動者を含めて count 体に届いた軸を1本の列として返す。
## 戻り＝軸ごとの参加者（発動者は含めない・端から端の並び）。十字なら2本返る。
## caster は caster_pos に居るものとする（移動先のこともある）＝_cluster と同じ流儀。
static func _line_runs(state: BattleState, caster: Unit, r: Dictionary, caster_pos: Vector2i) -> Array:
	var by_pos := {}
	for u in _member_pool(state, caster, r):
		by_pos[u.pos] = u
	var runs: Array = []
	# 6方向は3軸の表裏＝前半3つで軸を数え、往復して列を伸ばす。
	for axis in 3:
		var dir := Hex.direction(axis)
		var members: Array = []
		var p := caster_pos - dir
		while by_pos.has(p):
			members.push_front(by_pos[p])
			p -= dir
		p = caster_pos + dir
		while by_pos.has(p):
			members.append(by_pos[p])
			p += dir
		if members.size() + 1 >= int(r["count"]):  # 発動者ぶんを足す
			runs.append(members)
	return runs

## ⑤の参加者の候補＝いまの列（発動者＋確定済み）の両端の外側にある駒だけ。
## 1体も確定していないうちは発動者の隣ぜんぶ＝どの軸へ伸ばすかを1体目が決める。
## 途中を飛ばす選び方も、折れ線になる選び方もここで落ちる。
static func _line_candidates(state: BattleState, choice: FormationChoice, chosen: Array[int],
		caster_pos: Vector2i) -> Array[int]:
	var out: Array[int] = []
	var seg: Array[Vector2i] = [caster_pos]  # 確定済みは動かない＝盤の実位置で測る
	for h in chosen:
		var u := state.unit_by_handle(h)
		if u == null:
			return out
		seg.append(u.pos)
	var ends: Array[Vector2i] = []
	if seg.size() == 1:
		ends = Hex.neighbors(caster_pos)
	else:
		# 一直線で途切れない並びなので、最も離れた2つが列の端になる。
		var a := seg[0]
		var b := seg[1]
		var span := 0
		for i in seg.size():
			for j in range(i + 1, seg.size()):
				var d := Hex.distance(seg[i], seg[j])
				if d > span:
					span = d
					a = seg[i]
					b = seg[j]
		var dir := (b - a) / span  # 端から端は軸方向の整数倍＝割り切れる
		ends = [b + dir, a - dir]
	for cell in ends:
		var u := state.unit_at(cell)
		if u == null or u.handle in chosen or not (u.handle in choice.pool):
			continue
		out.append(u.handle)
	return out

## victim 1体への陣形ダメージ内訳（発動者1体の実効攻撃力・間接扱い）。非破壊。
## 威力＝発動者(caster)1体ぶんの実効攻撃力を面内の各ヘックスに当てる（合算しない）。
## 面の広さ（最大7hex）そのものが強み。合算は割合式が飽和してオーバーキルのため見送り（旧feature-11）。
## 参加3体は発動コスト＝行動完了で消費し、威力には積まない。
static func _formation_hit(state: BattleState, option: FormationOption, victim: Unit) -> HitDetail:
	var caster := state.unit_by_handle(option.caster_id)
	# 内訳ごと渡す（total だけでなく係数も）＝スキルレポートが戦闘レポートと同じ表を出せる。
	var atk := _skill_attack_breakdown(state, caster, option, victim)
	# 防御側: 包囲は乗る（victim の surround が入る）／貫通は発動者の性質かレシピの上書き／支援なし。
	var df := _skill_defense_breakdown(state, victim, caster, option)
	var hit := Combat.hit_from_breakdowns(atk, df, victim.troops)
	hit.target_id = victim.handle
	return hit

## 発動者の実効攻撃力の内訳＝陣形スキル用の係数の受け渡し（式の本体は Combat.attack_breakdown_from）。
## 通常戦闘（Combat.attack_breakdown）との違いはここに全部書く:
##   攻撃力＝相手によらず対地値（atk_air 0 の発動者でも飛行の敵に同じ威力で通る）／支援なし（間接扱い）。
##   矢のレシピ（attack_vs "target"＝④⑥⑨）だけは通常攻撃と同じく相手で対空／対地を切り替える。
##   ⑨は攻撃力だけを参加者から引く（attack_from_stats）＝兵数・レベル・包囲・地形は発動者のもの。
## レベル・包囲・地形・状態補正は通常戦闘と同じ集め方。詳細 → doc/gdd/formations.md 設計原則3
static func _skill_attack_breakdown(state: BattleState, caster: Unit, option: FormationOption,
		victim: Unit) -> StatBreakdown:
	var sf := state.status_aggregate(caster, "attack")  # 状態補正（バフ/デバフ）の合成 {mul, add}
	var vs_air := option.attack_vs == "target" and victim.is_aerial()
	var b := Combat.attack_breakdown_from(
		caster.troops,
		_skill_attack_stat(state, caster, option, victim),
		Combat.level_factor(caster),
		Combat.surround_factor(state, caster),
		TerrainType.attack_factor(state.terrain_at(caster.pos)),
		0.0,  # 支援なし
		float(sf["mul"]), float(sf["add"]))
	b.vs_aerial = vs_air  # レポートが対空値で撃ったことを出せる（常に対地のレシピは false）
	b.melee = false
	return b

## 威力に使うユニット攻撃力（兵1体あたり）。既定は発動者1体の値（設計原則2＝参加者ぶんを合算しない）。
## ⑨マジックアロー（attack_from_stats "max_plus"）だけは参加者の最大＋attack_plus＝地上ではウィザード
## 40＋10、空ではエルフ 60＋10 と、相手によって主役が入れ替わる。合算ではないので2人・単体でも壊れない。
## 対空／対地の切り替え（attack_vs）は参加者それぞれに掛ける。詳細 → doc/gdd/formations.md ⑨
static func _skill_attack_stat(state: BattleState, caster: Unit, option: FormationOption, victim: Unit) -> int:
	var by_target := option.attack_vs == "target"
	var stat := caster.attack_against(victim) if by_target else caster.unit_attack
	if option.attack_from_stats != "max_plus":
		return stat
	for pid in option.participants:
		var p := state.unit_by_handle(int(pid))
		if p == null:
			continue
		stat = maxi(stat, p.attack_against(victim) if by_target else p.unit_attack)
	return stat + option.attack_plus

## 被弾側の実効防御力の内訳＝陣形スキル用の係数の受け渡し（式の本体は Combat.defense_breakdown_from）。
## 通常戦闘（Combat.defense_breakdown）との違いはここに全部書く:
##   支援なし（間接扱い）／貫通はレシピが上書きしていればその値、なければ発動者の pierce。
## レベル・包囲・地形・状態補正は通常戦闘と同じ集め方。詳細 → doc/gdd/formations.md ④
static func _skill_defense_breakdown(state: BattleState, victim: Unit, caster: Unit,
		option: FormationOption) -> StatBreakdown:
	var sf := state.status_aggregate(victim, "defense")  # 状態補正（バフ/デバフ）の合成 {mul, add}
	var pierce := option.pierce_override if option.pierce_override >= 0.0 else caster.pierce
	var b := Combat.defense_breakdown_from(
		victim.troops,
		victim.unit_defense,
		Combat.level_factor(victim),
		Combat.surround_factor(state, victim),
		TerrainType.defense_factor(state.terrain_at(victim.pos)),
		0.0,  # 支援なし
		pierce,
		float(sf["mul"]), float(sf["add"]))
	b.melee = false
	return b
