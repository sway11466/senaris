extends RefCounted
class_name UiFont
## 日本語の字を出すフォントを名指しする（presentation/ui）。起動時に1回だけ当てる。
##
## Godot が内蔵するフォントはラテン文字しか持たない＝日本語の字が来るたび、OS に「この字を
## 持つフォントをくれ」と問い合わせが行く。問い合わせは字を組むたびに走るので、日本語の本文は
## ラベル1枚あたり数 ms かかり、文字数の多い画面（ゲーム内マニュアル）で待ちになる。
## 名指ししておけば問い合わせが消える（2026-09-23 実測：同じ30枚で 630ms → 380ms）。
##
## 内蔵フォントは置き換えず、その後ろに繋ぐ＝英字は今までどおり内蔵フォントで出て、内蔵に
## 無い字（日本語）だけこの並びから取る。並びは日本語 Windows に載っている順で、どれも無い
## 環境では従来どおり OS 任せのフォールバックに落ちる（見た目はその環境しだい・従来と同じ）。

## 探す家族名。先に在るものが使われる。
const FAMILIES := ["Yu Gothic UI", "Meiryo", "MS Gothic"]

## 太さ。700＝Bold。いま OS が返してくる face（Yu Gothic Bold）と同じ太さを指す
## ＝名指しにしても字の太さが変わらない。
const WEIGHT := 700

static func apply() -> void:
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(FAMILIES)
	sys.font_weight = WEIGHT
	var chain: Array[Font] = [sys]
	ThemeDB.fallback_font.fallbacks = chain
