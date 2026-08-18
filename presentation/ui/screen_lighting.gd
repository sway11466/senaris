extends CanvasLayer
class_name ScreenLighting
## 画面全体の明暗を一手に引き受ける共通基盤（暗幕＋加護の光）。
## 「暗くする」を場面ごとに別実装しない＝濃さ・フェード・重ね掛けの管理をここに集約する。
## 層の並び（番号が大きいほど前面）：
##    0 盤・HUD・ターン板 … 暗転で沈む側
##   40 本層（暗幕 → 加護の光の順。光は幕より前＝暗転中も縁の光が生きる）
##   45 前面パネル層（main.tscn の Front＝InfoPanel・ターンバナー・会話・陣形カットイン）… 沈まない側
##   46 セレクト（ステージ外の全画面メニュー＝ステージの画面一式を前面パネルごと覆う）
##   50 戦闘/スキルの窓（CombatStage）
##   55 戦果票 ／ 60 勝利イラスト ／ 70 タイトル
## 暗転は dim(owner)/undim(owner) の重ね掛け＝会話と戦闘が続けて起きても消し合わない
## （旧 main._set_scrim の tween 競合事故を、所有者の集合で仕組みとして防ぐ）。

const LAYER := 40
const DIM_COLOR := Color(0, 0, 0, 0.5)  # 暗幕の濃さ（全場面共通）
const FADE_SEC := 0.2                   # 出し入れのフェード（唐突に暗転しない）
const BLEED := 32.0  # 画面揺れで縁に明るい隙間が覗かないよう、幕は画面より広く敷く

var _scrim: ColorRect
var _aura: AuraOverlay
var _owners := {}  # 暗転を掛けている主の instance_id -> クリックを吸うか(bool)。空＝明るい
var _tween: Tween = null

func _ready() -> void:
	layer = LAYER
	_scrim = ColorRect.new()
	_scrim.color = DIM_COLOR
	_scrim.modulate.a = 0.0
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.hide()
	add_child(_scrim)
	_aura = AuraOverlay.new()
	_aura.name = "AuraOverlay"
	add_child(_aura)
	_fit()
	get_viewport().size_changed.connect(_fit)

func _fit() -> void:
	var vp := get_viewport().get_visible_rect().size
	_scrim.position = Vector2(-BLEED, -BLEED)
	_scrim.size = vp + Vector2(BLEED, BLEED) * 2.0
	if _aura.visible:
		_aura.fit_to(vp)

## 暗転を掛ける。owner は掛けた主（会話＝main・戦闘＝CombatStage 等）。
## block_input=true なら幕より下（盤・HUD）へのクリックも吸う（会話の盤ロックとの二重ガード）。
## 前面パネル層（45）より上には効かない＝会話パネルや InfoPanel の操作は通る。
func dim(owner: Object, block_input := false) -> void:
	_owners[owner.get_instance_id()] = block_input
	_apply()

## owner の暗転を明ける。他の主が残っていれば暗いまま（重ね掛け）。
func undim(owner: Object) -> void:
	_owners.erase(owner.get_instance_id())
	_apply()

func _apply() -> void:
	var on := not _owners.is_empty()
	_scrim.mouse_filter = (
		Control.MOUSE_FILTER_STOP if _owners.values().has(true) else Control.MOUSE_FILTER_IGNORE)
	if _tween != null and _tween.is_valid():
		_tween.kill()  # フェード中の掛け直し・明け直しは現在の明るさから続ける
	if on:
		_scrim.show()
	_tween = create_tween()
	_tween.tween_property(_scrim, "modulate:a", 1.0 if on else 0.0, FADE_SEC)
	if not on:
		_tween.tween_callback(_scrim.hide)

## 加護の光（ホーリーアリア等の陣営全体バフ）。暗幕より前＝暗転中も縁の光が生きる。
func aura_play(color: Color) -> void:
	_aura.play(color, get_viewport().get_visible_rect().size)

func aura_stop() -> void:
	_aura.stop()
