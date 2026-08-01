extends RefCounted
class_name CombatEffect
## 攻撃エフェクト1種（斬撃・矢・聖光…）。スキンではなく武器の種類ごとに1つで、
## 複数スキンが同じものを共有する（味方とゴブリンで同じ斬撃を使う）。
## 仕様 → doc/tech/combat_scene.md「攻撃エフェクト」／作画 → doc/art/units.md §3.4

## 出し方。絵とは別の属性で、同じ絵を別の出し方に回せる。
const KIND_IMPACT := "impact"          ## 被弾側の隊列に重ねて拡大フェード（斬撃・近接の魔法）
const KIND_PROJECTILE := "projectile"  ## 攻撃側から被弾側へ飛び、着弾で消える（矢・投石・遠隔の魔法）
const KINDS := [KIND_IMPACT, KIND_PROJECTILE]

var effect_id: String  ## エフェクトID（主キー。unit_skin.csv の combat_effect が指す）
var name: String       ## 表示名（斬撃（小）/矢 …。人が読む用）
var kind: String = KIND_IMPACT

static func from_dict(d: Dictionary) -> CombatEffect:
	var e := CombatEffect.new()
	e.effect_id = String(d.get("effect_id", ""))
	e.name = String(d.get("name", ""))
	var k := String(d.get("kind", ""))
	e.kind = k if KINDS.has(k) else KIND_IMPACT  # 未知値は重ねる側へ倒す（飛ばすより事故が小さい）
	return e

## 絵の置き場（規約で解決＝カタログにパスを書かない）。無ければ演出側が既定のスパークに落とす。
func image_path() -> String:
	return "res://assets/effects/%s.png" % effect_id if effect_id != "" else ""

func is_projectile() -> bool:
	return kind == KIND_PROJECTILE
