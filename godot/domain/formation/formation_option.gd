extends RefCounted
class_name FormationOption
## 盤上で成立した陣形スキル／ユニットスキルの選択肢1つ（Formation.available_for の1要素）。
## スキル（Formation.SKILLS）の値と参加ユニットを持ち、「対象を選ぶか」「着弾があるか」
## 「駒の居るhexしか選べないか」の判断をここに閉じる＝読む側が効果の文字列を比べない。
## 純データ・Node非依存。盤は書き換えない（適用は FormationResolver）。
## 詳細 → doc/gdd/formations.md, doc/gdd/skills.md

## 効果の種類。SKILLS の "effect" と1対1（EFFECT_IDS）。
enum Effect { AREA, SINGLE, BUFF, CLEANSE, SPAWN, DOT }
## 参加者の並び方。SKILLS の "shape" と1対1（SHAPE_IDS）。SOLO＝ユニットスキル。
## SPOTTER（④）だけは参加者の形ではなく対象の周りを見る＝斥候が着弾先に隣接している。
enum Shape { TRIANGLE, ESCORT, SOLO, CLUSTER, SPOTTER }
## 効果の掛かる範囲。陣営全体（グレイス）か対象1体（ユニットスキル）か。SKILLS の "buff_scope"。
enum Scope { TEAM, UNIT }
## 対象1体のとき、味方に掛けるか敵に掛けるか。SKILLS の "buff_side"。
enum Side { ALLY, ENEMY }
## 射程の起点。発動者からか、参加者のどれからでもか。SKILLS の "range_from"。
enum RangeFrom { CASTER, ANY }

const EFFECT_IDS := {
	"area": Effect.AREA, "single": Effect.SINGLE, "buff": Effect.BUFF,
	"cleanse": Effect.CLEANSE, "spawn": Effect.SPAWN, "dot": Effect.DOT,
}
const SHAPE_IDS := {
	"triangle": Shape.TRIANGLE, "escort": Shape.ESCORT, "solo": Shape.SOLO, "cluster": Shape.CLUSTER,
	"spotter": Shape.SPOTTER,
}
const SCOPE_IDS := { "team": Scope.TEAM, "unit": Scope.UNIT }
const SIDE_IDS := { "ally": Side.ALLY, "enemy": Side.ENEMY }
const RANGE_FROM_IDS := { "caster": RangeFrom.CASTER, "any": RangeFrom.ANY }

var skill: String             ## スキルID（SKILLS のキー。表示名・音・絵の規約解決に使う）
var name: String              ## 開発用メモ（画面表示は tr("skill.{id}.name")）
var caster_id: int            ## 発動者の駒番号（participants の先頭）
var participants: Array[int]  ## 参加する駒番号。先頭＝発動者
var effect: Effect
var shape: Shape
var scope: Scope
var side: Side
var max_range: int            ## 射程上限（ヘックス数）
var min_range: int            ## 射程下限（ヘックス数）。0＝下限なし（隣接にも撃てる）
var range_from: RangeFrom
var radius: int               ## 面攻撃の半径（AREA のみ）
## 威力に使うユニット攻撃力の選び方。"ground"＝常に対地値（既定。設計原則3）／"target"＝相手が
## 飛行なら対空値・地上なら対地値（矢のレシピ＝④⑥⑨の例外）。詳細 → doc/gdd/formations.md 設計原則3
var attack_vs: String
## レシピが上書きする防御貫通率。負＝上書きしない（発動者の pierce をそのまま使う）。
## ④トリックショット＝斥候が見つけた弱点を射抜く 0.5。詳細 → doc/gdd/formations.md ④
var pierce_override: float
## 威力のユニット攻撃力の引き方。""＝発動者1体の値（既定・設計原則2）／"max_plus"＝参加者の最大＋attack_plus
## （⑨マジックアロー＝2体の大きい方＋10。合算はしない）。詳細 → doc/gdd/formations.md ⑨
var attack_from_stats: String
var attack_plus: int
## 演出シーンで使うエフェクトID。空＝発動者スキンの combat_effect へ落ちる（presentation が解決）。
## エフェクトの単位を「誰が撃ったか」ではなく「何を撃ったか」にする列＝ピュリファイはクレリックが撃っても
## ビショップが撃っても同じ絵になる。陣形の盤の着弾はこれを見ない（レシピ専用の絵を規約解決する）。
## 詳細 → doc/gdd/skills.md 実装方針, doc/gdd/formations.md 発動の演出
var combat_effect: String
var charge_turns: int         ## 発動に要するチャージ量。0＝溜め不要

# --- 状態補正（BUFF）・継続ダメージ（DOT）の値。それ以外の効果では使わない ---
var buff_kind: String         ## 強化か弱体か（StatusMod.KIND_BUFF / KIND_DEBUFF）。BUFF と DOT で有効
var buff_op: String           ## "mul" / "add"
var buff_value: float
var buff_value_per_troop: float  ## 発動者の残兵1体あたりの値。0＝兵数に依らない
var buff_value_per_extra: float  ## 基準人数（min_count）を超えた参加者1体あたりの加算。0＝人数に依らない
var min_count: int            ## スキルが成立する最低人数（SKILLS の "count"）
var buff_fx: String           ## 盤の見た目。空＝見た目なし
var buff_target: String       ## "attack" / "defense" / "both"
var duration_turns: int
var dot_troops: int           ## 対象側のターン開始ごとに減る兵数（DOT のみ）

## スキル定義 r（Formation.SKILLS[rid]）と参加ユニット（先頭＝発動者）から選択肢を組む。
static func from_skill(rid: String, r: Dictionary, units: Array) -> FormationOption:
	var o := FormationOption.new()
	o.skill = rid
	o.name = String(r["name"])
	o.caster_id = units[0].handle
	var ids: Array[int] = []
	for u in units:
		ids.append(u.handle)
	o.participants = ids
	o.effect = _id_to_enum(EFFECT_IDS, String(r["effect"]), "effect")
	o.shape = _id_to_enum(SHAPE_IDS, String(r["shape"]), "shape")
	# 対象の絞り込みは効果の種類と独立に載せる（積む buff も落とす cleanse も同じ選び方をする）。既定は陣営全体。
	o.scope = _id_to_enum(SCOPE_IDS, String(r.get("buff_scope", "team")), "buff_scope")
	# 対象1体のスキルが味方向きか敵向きか（Formation.can_target の絞り込み）。既定は味方。
	o.side = _id_to_enum(SIDE_IDS, String(r.get("buff_side", "ally")), "buff_side")
	o.max_range = int(r.get("range", 0))
	o.min_range = 0
	# 射程をレシピの固定値ではなく参加者の性能から引くレシピ。固定の "range" とは排他。
	#   "caster"（④）＝弓兵の通常射程（下限〜上限）がそのままスキルの射程になる。
	#   "max_plus"（⑨）＝参加者の射程上限の長い方＋range_plus。下限は無し（隣接にも撃てる）。
	# 詳細 → doc/gdd/formations.md ④⑨
	match String(r.get("range_from_stats", "")):
		"caster":
			o.max_range = units[0].attack_range
			o.min_range = units[0].min_range
		"max_plus":
			var longest := 0
			for u in units:
				longest = maxi(longest, u.attack_range)
			o.max_range = longest + int(r.get("range_plus", 0))
			o.min_range = 0
	o.range_from = _id_to_enum(RANGE_FROM_IDS, String(r.get("range_from", "caster")), "range_from")
	o.radius = int(r.get("radius", 0))
	o.attack_vs = String(r.get("attack_vs", "ground"))
	o.pierce_override = float(r.get("pierce_override", -1.0))
	o.attack_from_stats = String(r.get("attack_from_stats", ""))
	o.attack_plus = int(r.get("attack_plus", 0))
	o.combat_effect = String(r.get("combat_effect", ""))
	o.charge_turns = int(r.get("charge_turns", 0))
	if o.effect == Effect.BUFF:
		# 強化か弱体か。値の符号から推測しない＝レシピが明示する（省略＝強化）。
		o.buff_kind = String(r.get("buff_kind", StatusMod.KIND_BUFF))
		o.buff_op = String(r.get("buff_op", "mul"))
		o.buff_value = float(r.get("buff_value", 1.0))
		o.buff_value_per_troop = float(r.get("buff_value_per_troop", 0.0))
		o.buff_value_per_extra = float(r.get("buff_value_per_extra", 0.0))
		o.min_count = int(r.get("count", 1))
		o.buff_fx = String(r.get("buff_fx", ""))
		o.buff_target = String(r.get("buff_target", "both"))
		o.duration_turns = int(r.get("duration_turns", 1))
	elif o.effect == Effect.DOT:
		# 弱体であることは明示する＝ピュリファイが落とす対象・盤の見た目・敵AIの stack 条件が読む。
		o.buff_kind = String(r.get("buff_kind", StatusMod.KIND_DEBUFF))
		o.buff_fx = String(r.get("buff_fx", ""))
		o.dot_troops = int(r.get("dot_troops", 1))
		o.duration_turns = int(r.get("duration_turns", 1))
	return o

## SKILLS の文字列を enum に引く。SKILLS はコード内の定数なので、無い文字列は書き間違い＝止める。
static func _id_to_enum(table: Dictionary, id: String, key: String) -> int:
	assert(table.has(id), "FormationOption: SKILLS の %s '%s' は未定義" % [key, id])
	return int(table[id])

## effect の SKILLS 文字列。発動結果（FormationResolver の "skill"）に載せて presentation が読む。
func effect_id() -> String:
	return EFFECT_IDS.find_key(effect)

## ユニットスキル（発動者1体で成立）か。陣形スキルとの区別はカタログ上のもので仕組みは共通。
## メニューの表示ラベルの出し分けが読む。詳細 → doc/gdd/formations.md
func is_unit_skill() -> bool:
	return shape == Shape.SOLO

## 距離 d が射程に入るか（下限 min_range 〜 上限 max_range）。下限を持たないレシピは 0〜上限。
func in_range(d: int) -> bool:
	return d >= min_range and d <= max_range

## 着弾（面か1体への損害）があるか。無いもの（状態補正・解除・分裂）は盤を揺らさない。
func has_impact() -> bool:
	return effect == Effect.AREA or effect == Effect.SINGLE

## 発動に着弾中心／掛ける相手の指定が要るか。陣営全体の補正と分裂は要らない＝即発動。
func needs_target() -> bool:
	return has_impact() or scope == Scope.UNIT

## 対象は駒の居るhexだけか（単体狙撃と対象1体のスキル）。面攻撃は地面にも撃てる。
## 盤は該当する駒に攻撃と同じ頭上マーカーを出す。
func targets_unit() -> bool:
	return effect == Effect.SINGLE or scope == Scope.UNIT

## 敵AIの stack 条件が見る種類。解除（"cleanse"）／弱体（StatusMod.KIND_DEBUFF）／強化（KIND_BUFF）。
## 判別はレシピのフラグから＝値の符号からは決めない。詳細 → doc/gdd/ai.md stack 条件
func stack_kind() -> String:
	if effect == Effect.CLEANSE:
		return "cleanse"
	if buff_kind == StatusMod.KIND_DEBUFF:
		return StatusMod.KIND_DEBUFF
	return StatusMod.KIND_BUFF
