extends RefCounted
class_name SkillCast
## 効果対象が1体のユニットスキルの演出用内訳（純データ）。発動前に撮る＝戦闘の detail と同じ流儀。
## 兵数は動かないので、発動者・対象とも troops_after は troops_before と同じ＝戦闘の器と揃える。
## 演出シーン（SkillScene）が絵と文言を、スキルレポートが掛かり先を読む。
## 詳細 → doc/tech/combat_scene.md ユニットスキルの演出

var recipe: String          ## レシピID（音の規約解決に使う）
var name: String            ## 開発用メモの表示名
var effect: String          ## 効果の RECIPES 文字列（"buff" / "cleanse" / "dot" …）
var combat_effect: String   ## エフェクトID。空＝発動者スキンの combat_effect へ落ちる
var caster: UnitSnapshot
var target: UnitSnapshot

# --- 効果の値（効果の種類ごとに埋まる） ---
var op: String = "mul"        ## BUFF: "mul" / "add"
var value: float = 0.0        ## BUFF: 焼き込んだ補正値
var buff_target: String = "both"  ## BUFF: "attack" / "defense" / "both"
var kind: String = ""         ## BUFF / DOT: 強化か弱体か（StatusMod.KIND_*）
var cleansed: int = 0         ## CLEANSE: 落とした弱体の本数
var dot_troops: int = 0       ## DOT: 対象側のターン開始ごとに減る兵数
