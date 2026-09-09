extends RefCounted
class_name StageRenames
## 既存の冒険譚のステージを冒険譚名付きの名前へ改名したときの、旧→新の対応表
## （doc/tech/gamesystem.md §版と移行）。出回っているセーブ（demo-v0.1.0 / v0.1.1）は
## 旧名で書かれているので、この表は製品版以降も残る恒久のもの。
## ファイル名（中断セーブの stage_path）・ステージID（進捗と中断セーブのキー）・
## 翻訳キーの接頭辞（中断セーブが持つ冒険譚名／ステージ名）の3層をそれぞれ持つ。
## 引けない名前は素通しで返す＝改名していない冒険譚・デバッグステージはそのまま。

## 旧パス → 新パス。中断セーブの meta.stage_path（版によらず旧名で書かれている）。
const PATHS := {
	"res://data/stages/tutorial1-goblin-raid/st1.json": "res://data/stages/tutorial1-goblin-raid/goblin-raid-st1.json",
	"res://data/stages/tutorial1-goblin-raid/st2.json": "res://data/stages/tutorial1-goblin-raid/goblin-raid-st2.json",
	"res://data/stages/tutorial1-goblin-raid/st3.json": "res://data/stages/tutorial1-goblin-raid/goblin-raid-st3.json",
	"res://data/stages/tutorial1-goblin-raid/st4.json": "res://data/stages/tutorial1-goblin-raid/goblin-raid-st4.json",
	"res://data/stages/tutorial1-goblin-raid/st5.json": "res://data/stages/tutorial1-goblin-raid/goblin-raid-st5.json",
	"res://data/stages/tutorial1-goblin-raid/st6.json": "res://data/stages/tutorial1-goblin-raid/goblin-raid-st6.json",
	"res://data/stages/tutorial1-goblin-raid/st7.json": "res://data/stages/tutorial1-goblin-raid/goblin-raid-st7.json",
	"res://data/stages/tutorial2-undead-rush/st1.json": "res://data/stages/tutorial2-undead-rush/undead-rush-st1.json",
	"res://data/stages/tutorial2-undead-rush/st2.json": "res://data/stages/tutorial2-undead-rush/undead-rush-st2.json",
	"res://data/stages/tutorial2-undead-rush/st3.json": "res://data/stages/tutorial2-undead-rush/undead-rush-st3.json",
	"res://data/stages/tutorial2-undead-rush/st4.json": "res://data/stages/tutorial2-undead-rush/undead-rush-st4.json",
	"res://data/stages/tutorial2-undead-rush/st5.json": "res://data/stages/tutorial2-undead-rush/undead-rush-st5.json",
	"res://data/stages/tutorial2-undead-rush/st6.json": "res://data/stages/tutorial2-undead-rush/undead-rush-st6.json",
	"res://data/stages/tutorial2-undead-rush/st7.json": "res://data/stages/tutorial2-undead-rush/undead-rush-st7.json",
	"res://data/stages/tutorial3-dragon-hunt/st1.json": "res://data/stages/tutorial3-dragon-hunt/dragon-hunt-st1.json",
	"res://data/stages/tutorial3-dragon-hunt/st2.json": "res://data/stages/tutorial3-dragon-hunt/dragon-hunt-st2.json",
	"res://data/stages/tutorial3-dragon-hunt/st3.json": "res://data/stages/tutorial3-dragon-hunt/dragon-hunt-st3.json",
	"res://data/stages/tutorial3-dragon-hunt/st4.json": "res://data/stages/tutorial3-dragon-hunt/dragon-hunt-st4.json",
	"res://data/stages/tutorial3-dragon-hunt/st5.json": "res://data/stages/tutorial3-dragon-hunt/dragon-hunt-st5.json",
	"res://data/stages/tutorial3-dragon-hunt/st6.json": "res://data/stages/tutorial3-dragon-hunt/dragon-hunt-st6.json",
	"res://data/stages/tutorial3-dragon-hunt/st7.json": "res://data/stages/tutorial3-dragon-hunt/dragon-hunt-st7.json",
	"res://data/stages/bounty1-goblin-horde/st1.json": "res://data/stages/bounty1-goblin-horde/goblin-horde-st1.json",
	"res://data/stages/bounty1-goblin-horde/st2.json": "res://data/stages/bounty1-goblin-horde/goblin-horde-st2.json",
}

## 「冒険譚ID/旧ステージID」 → 新ステージID。進捗（cleared / ranks / times / story）と
## 中断セーブの meta.stage_id。冒険譚ID自体は変えていないので、旧IDの重なり（どの冒険譚も st1）を
## 冒険譚IDで解く。
const STAGE_IDS := {
	"tutorial1-goblin-raid/st1": "goblin-raid-st1",
	"tutorial1-goblin-raid/st2": "goblin-raid-st2",
	"tutorial1-goblin-raid/st3": "goblin-raid-st3",
	"tutorial1-goblin-raid/st4": "goblin-raid-st4",
	"tutorial1-goblin-raid/st5": "goblin-raid-st5",
	"tutorial1-goblin-raid/st6": "goblin-raid-st6",
	"tutorial1-goblin-raid/st7": "goblin-raid-st7",
	"tutorial2-undead-rush/st1": "undead-rush-st1",
	"tutorial2-undead-rush/st2": "undead-rush-st2",
	"tutorial2-undead-rush/st3": "undead-rush-st3",
	"tutorial2-undead-rush/st4": "undead-rush-st4",
	"tutorial2-undead-rush/st5": "undead-rush-st5",
	"tutorial2-undead-rush/st6": "undead-rush-st6",
	"tutorial2-undead-rush/st7": "undead-rush-st7",
	"tutorial3-dragon-hunt/st1": "dragon-hunt-st1",
	"tutorial3-dragon-hunt/st2": "dragon-hunt-st2",
	"tutorial3-dragon-hunt/st3": "dragon-hunt-st3",
	"tutorial3-dragon-hunt/st4": "dragon-hunt-st4",
	"tutorial3-dragon-hunt/st5": "dragon-hunt-st5",
	"tutorial3-dragon-hunt/st6": "dragon-hunt-st6",
	"tutorial3-dragon-hunt/st7": "dragon-hunt-st7",
	"bounty1-goblin-horde/st1": "goblin-horde-st1",
}

## 旧翻訳キーの接頭辞 → 新接頭辞。campaigns.csv・dialogue.csv を冒険譚名の語へ改名したので、
## セーブが翻訳キーのまま持つ冒険譚名（campaign_title）・ステージ名（stage_title）も読み替える。
const KEY_PREFIXES := {
	"t1.": "goblin-raid.",
	"t2.": "undead-rush.",
	"t3.": "dragon-hunt.",
	"b1.": "goblin-horde.",
}

## 中断セーブの meta.stage_path を新しいファイル名へ。
static func path(old: String) -> String:
	return String(PATHS.get(old, old))

## 進捗・中断セーブのステージIDを新しいIDへ。冒険譚IDで絞ってから引く。
static func stage_id(campaign_id: String, old: String) -> String:
	return String(STAGE_IDS.get("%s/%s" % [campaign_id, old], old))

## 翻訳キーの接頭辞を新しい語へ（後ろのセグメントはそのまま）。
static func tr_key(old: String) -> String:
	for prefix in KEY_PREFIXES:
		if old.begins_with(prefix):
			return String(KEY_PREFIXES[prefix]) + old.substr(String(prefix).length())
	return old

## 中断セーブの meta のうち、ステージIDと翻訳キーを読み替える。stage_path はここに含めない
## ＝v2 の変換がそのパスでステージJSONを開くので、変換より前（migrate の入口）で直すため。
## 体験版の印の表（demo-v0.1.0_digests.json）は旧IDのままなので、必ず印を引いた後に通す。
static func meta(src: Dictionary) -> Dictionary:
	var out := src.duplicate()
	var campaign := String(out.get("campaign_id", ""))
	if out.has("stage_id"):
		out["stage_id"] = stage_id(campaign, String(out["stage_id"]))
	if out.has("campaign_title"):
		out["campaign_title"] = tr_key(String(out["campaign_title"]))
	if out.has("stage_title"):
		out["stage_title"] = tr_key(String(out["stage_title"]))
	return out
