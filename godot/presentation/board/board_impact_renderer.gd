extends Node3D
class_name BoardImpactRenderer
## 陣形スキル／ユニットスキルの着弾演出（hex_board_3d.gd から切り出し）。
## 面の光 → 被弾した駒を1体ずつ（エフェクト→フラッシュ→兵数、撃破はフェード）。
## 単体対象のスキル（ディバインジャッジメント・トリックショット）だけ専用シーケンス（ため→絵が届く→残光）＝_play_single_target。
## 絵の届き方はレシピの impact_motion で分かれる＝真上から降りる（ディバインジャッジメント）／射手から飛ぶ（トリックショット）。
## このノード自身が一時的な演出メッシュ（着弾の光・駒に重ねるエフェクト）の入れ物になる。
## オーバーレイの作り直しで消えない層＝hex_board_3d の旧 _fx_root に相当する。
## 詳細 → doc/gdd/formations.md 発動の演出

## 着弾演出が終わった（打ち切りでも必ず発行＝待ち手を取り残さない）。
signal impact_finished

const TILE := HexBoard3D.TILE

# --- 着弾演出のタイミングと色 ---
# 揺れ→面の光→被弾した駒を1体ずつ。
const COLOR_FORMATION_HIT := Color(1.00, 0.82, 0.40)  # 着弾した面の光（金）
const HIT_LEAD_SEC := 0.10        # 揺れてから面が光るまでの間（同時に出すと1つの衝撃に潰れる）
const HIT_CELL_RISE := 0.07       # 面の光の立ち上がり
const HIT_CELL_SETTLE := 0.18     # 立ち上がりから居座りの濃さへ落とすまで
const HIT_CELL_HOLD := 0.16       # 同・居座り（この間に駒の処理が進む）
const HIT_CELL_FADE := 0.32       # 同・引き
const HIT_CELL_ALPHA := 0.34      # 同・立ち上がりの濃さ（加算合成。これ以上は地形が白く飛ぶ）
const HIT_CELL_ALPHA_HOLD := 0.13 # 同・居座りの濃さ。駒に重ねるエフェクトを埋もれさせない
const HIT_STEP_SEC := 0.13        # 駒1体ぶんの間隔＝何体が受けたのかを数えられる範囲で詰める
const HIT_DROP_SEC := 0.16        # 駒に落とすエフェクトの落下時間（着弾＝ここで駒が反応する）
const HIT_DROP_FROM := TILE * 2.0 # 同・落とし始める高さ（駒の頭より上）
const HIT_BURST_SEC := 0.18       # 同・着弾して弾けて消えるまで
const HIT_BURST_TILES := 2.2      # 同・大きさの基準（scale 1.0 でヘックス幅の何倍か）
const HIT_BURST_OPEN := 1.35      # 同・着弾で開く倍率
const HIT_FLASH_SEC := 0.14       # 被弾フラッシュ（立ち絵を白く飛ばす）の片道
const HIT_FLASH_GAIN := 2.2       # 同・明るさの倍率
const HIT_FADE_SEC := 0.22        # 撃破された駒が消えるまで
## 決着のとどめ（この着弾で勝ちが確定する回）＝落下・駒送り・撃破フェードの尺に掛ける
## スロー倍率。仕様 → doc/gdd/uiux.md 決着の合図。値は実機で詰める前提の初期値。
const FINISH_STRETCH := 2.2
const FINISH_CELL_HOLD := 0.5     # 決着の光（本拠占領のとどめ＝1マスだけ長めに光らせる）の居座り

# --- 面に降らせる型のスキル専用（アローレイン）---
# 共通の「被弾した駒に1枚落とす」ではなく、面の全ヘックスに矢を何本も降らせる。
# 散らし方は乱数ではなくヘックスと何本目から引いた固定値＝同じ盤なら毎回同じ降り方になる。
const RAIN_TILES := 1.1        # 矢1本の大きさ（長辺がヘックス幅の何倍か）
const RAIN_DROP_SEC := 0.22    # 1本の落下時間
const RAIN_FADE_SEC := 0.12    # 着いてから消えるまで
const RAIN_RING_SEC := 0.10    # 中心から1輪ぶん外れるごとの遅れ（中心から外へ降る）
const RAIN_GAP_SEC := 0.07     # 同じヘックスに降る矢どうしの間隔
const RAIN_JITTER_SEC := 0.05  # 同・間隔の散らし幅
const RAIN_SCATTER := 0.55     # ヘックス内の落ち先の散らし幅（ヘックス幅に対する割合）

# --- 発動者から列ごとに広げる型のスキル専用（ドラゴンブレス。レシピの impact_spread）---
# 発動者から近い列から順に、面のヘクスへ火を1つずつ付ける。駒は自分のヘクスに火が付いた瞬間に反応する。
const SPREAD_STEP_SEC := 0.22  # 火が次の列へ広がる間隔（ドラゴンブレス。3列で約0.45秒）
const FLAME_TILES := 1.3       # 火1つの大きさ（長辺がヘックス幅の何倍か）
const FLAME_RISE_SEC := 0.14   # 足元から立ち上がるまで
const FLAME_HOLD_SEC := 0.30   # 燃えている間（この間に被弾フラッシュ・撃破フェードが進む）
const FLAME_FADE_SEC := 0.25   # 引き

# --- 発動の印（着弾の無いレシピ専用＝シールドウォール）---
# 着弾が無いレシピは盤で何も起きないので、誰に効いたのかが読めない。参加者の駒に絵を1枚ずつ
# 重ねて、端から順に立てて短く消す。盤は解決した時点で更新済み＝印は出来上がった盤の上に乗る。
const MARK_TILES := 1.25      # 絵の大きさ（長辺がヘックス幅の何倍か）。駒より一回り大きい
const MARK_ALPHA := 0.85      # 濃さ。駒を完全には隠さない
const MARK_STEP_SEC := 0.08   # 参加者どうしの間隔＝列に沿って1枚ずつ立つ（左から右へ）
const MARK_RISE_SEC := 0.16   # 開いて出るまで
const MARK_RISE_FROM := 0.55  # 同・開き始めの倍率
const MARK_HOLD_SEC := 0.46   # 置いておく時間
const MARK_FADE_SEC := 0.30   # 引き

# --- 単体対象のスキル専用（ディバインジャッジメント・トリックショット）---
# 単体対象＝面の広さで見せられないぶん、1発の重さ（絵の大きさと時間）で見せる。
# 共通の「落として弾ける」より、ため→ゆっくり降りる→立ったまま残る、で長く見せる。
const SINGLE_CHARGE_SEC := 0.30        # ため＝対象ヘクスが光ってから絵が降り始めるまで（狙われた間）
const SINGLE_CHARGE_ALPHA_HOLD := 0.22 # ための光の居座りの濃さ（共通より強め。白飛びしない範囲）
const SINGLE_DROP_SEC := 0.65          # 絵の降下時間（共通の落下より遅く＝何が降りてきたか見える）
const SINGLE_DROP_FROM := TILE * 10.0  # 降下開始の高さ（着地位置からの上乗せ）。絵の裾が画面の上端より
                                       # 外から入ってくる高さ＝「真上から落ちてくる」に見える
const SINGLE_WIDTH_TILES := 1.6        # 絵の幅（ヘックス幅の何倍か）。縦長の絵なので幅基準で釣り合わせる
const SINGLE_HOLD_SEC := 0.40          # 着弾後に絵を立たせておく時間（この間に被弾フラッシュ・撃破フェードが進む）
const SINGLE_FADE_SEC := 0.40          # 絵の引き

# --- 飛んでくる絵（トリックショット。レシピの impact_motion "fly"）---
# 射手のヘックスから対象のヘックスへ絵を走らせる。真上から降ろすディバインジャッジメントと違い、どこから撃ったのかが
# 盤に出る＝供出した弓兵が読める。絵は地面に寝かせて進行方向へ回す（→ doc/gdd/formations.md 発動の演出）。
const FLY_SEC := 0.26                  # 飛翔時間。矢なので降下（ディバインジャッジメント）より速い＝一瞬で届く
const FLY_ARC := TILE * 0.7            # 弧の高さ（中間で一番高い）。真っ直ぐ滑らせると滑走に見える
const FLY_HEIGHT := TILE * 0.55        # 地面からの高さ（駒の胸のあたり）
const FLY_TILES := 1.5                 # 絵の大きさ（長辺がヘックス幅の何倍か）
const FLY_HOLD_SEC := 0.16             # 着弾後に刺さったまま置く時間（ディバインジャッジメントの残光より短い）

# --- 発動者が消えて帰る（バックスタブ。レシピの return_to_origin）---
# 刺した位置で駒が消え、斬撃が出て、移動開始位置に現れる＝「刺して消える」を盤で見せる。
# 消える／現れるの尺は撃破のフェード（HIT_FADE_SEC）と揃える。

# --- 戦闘の一撃（戦闘窓を開かない手＝設定「戦闘の演出」の盤面のみ。doc/gdd/settings.md）---
# 攻撃側の武器エフェクト（戦闘窓と同じ CombatEffect）を盤に出す。矢や投石は攻撃側の駒から被弾側へ
# 飛び、斬撃は被弾側の駒の上で弾ける。着弾で被弾側が反応し（フラッシュ・撃破はフェード）、
# 反撃があれば逆向きに同じ流れ。どの駒が誰を殴ったかが盤だけで読める。
const STRIKE_TILES := 2.0        # 重ねる型の絵の大きさ（scale 1.0 でヘックス幅の何倍か。陣形の着弾と同程度＝盤では小さいと埋もれる）
const STRIKE_SEC := 0.36         # 同・弾けて消えるまで（戦闘窓の 0.30 より少し長く＝盤では絵が小さい）
const STRIKE_OPEN := 1.5         # 同・弾ける倍率
const STRIKE_FLY_TILES := 1.5    # 飛ぶ型の絵の大きさ（長辺がヘックス幅の何倍か。トリックショットと同じ）
const COUNTER_GAP_SEC := 0.40    # 着弾から反撃が放たれるまでの間（重ねる型の絵が消える頃）
const COMBAT_TAIL_SEC := 0.30    # 最後の着弾から盤を作り直すまで（フラッシュ・撃破フェードを見せ切る）

# --- 外部依存（setup で注入）---
var _unit_renderer: BoardUnitRenderer
var _overlay_mesh: ArrayMesh
var _elev_fn: Callable        # (hex: Vector2i) -> float（標高）
var _in_board_fn: Callable    # (hex: Vector2i) -> bool（盤内判定）
var _state: BattleState
var _sync_fn: Callable        # () -> void（盤の見た目を作り直す）
var _set_locked_fn: Callable  # (v: bool) -> void（入力ロック）

# --- 着弾演出の状態 ---
var _impact_gen := 0            # 世代。ステージが変わったら増やす＝await の先で打ち切る
var _impact_pending := false    # 着弾待ち＝盤の作り直しを保留している（撃たれる前の姿のまま置く）
var _impact_lock := false       # 演出の間だけ入力を止めた＝終わったら元へ戻す
var _impact_tex := {}           # skill_id -> Texture2D|null（駒に重ねる着弾の絵）
var _mark_tex := {}             # skill_id -> Texture2D|null（参加者に重ねる発動の印の絵）
var _effect_tex := {}           # effect_id -> Texture2D|null（戦闘の武器エフェクトの絵）
var _skin_catalog := {}         # type_id -> { ally:[UnitSkin], enemy:[UnitSkin] }。武器エフェクトを引く
var _finisher := false          # 次の着弾を決着のとどめ（スロー）として見せる＝main が勝ち確定後に立てる
var _speed := 1.0               # 尺に掛ける速さ（1.0＝等速。盤面の演出「高速」で上がる）
var _skip := false              # 着弾を見せず結果だけ（盤面の演出 OFF）


func setup(unit_renderer: BoardUnitRenderer, overlay_mesh: ArrayMesh,
		elev_fn: Callable, in_board_fn: Callable, p_state: BattleState,
		sync_fn: Callable, set_locked_fn: Callable, skin_catalog: Dictionary = {}) -> void:
	_skin_catalog = skin_catalog
	_unit_renderer = unit_renderer
	_overlay_mesh = overlay_mesh
	_elev_fn = elev_fn
	_in_board_fn = in_board_fn
	_state = p_state
	_sync_fn = sync_fn
	_set_locked_fn = set_locked_fn


## 着弾を待つ状態にする。陣形の解決時に hex_board_3d が呼ぶ。
## 盤面の演出の設定（doc/gdd/settings.md）。speed＝待ちと動きの尺に掛ける速さ、skip＝見せずに結果だけ。
func set_fx(speed: float, skip: bool) -> void:
	_speed = speed
	_skip = skip

func set_pending(v: bool) -> void:
	_impact_pending = v


## 着弾演出が進行中か（盤が撃たれる前の姿を保持している間）。
func is_impacting() -> bool:
	return _impact_pending


## 次の着弾を決着のとどめとして見せる（スロー）。勝ちが確定した回だけ main→hex_board 経由で立つ。
func set_finisher(v: bool) -> void:
	_finisher = v


func finisher_armed() -> bool:
	return _finisher


## 決着の光＝1マスだけ長めに光らせる（本拠占領のとどめ。着弾の面の光と同じ材料）。
func flash_finisher_cell(hex: Vector2i) -> void:
	_flash_cells([hex], FINISH_CELL_HOLD)


## 決着が割り込んだとき、着弾演出が終わっても入力ロックを解除しないようにする。
## hex_board_3d._on_battle_finished から呼ばれる。
func cancel_unlock() -> void:
	_impact_lock = false


## ステージ再ロード時の初期化。進行中の演出を打ち切り、子ノード（一時メッシュ）を全て消す。
func reset() -> void:
	_impact_gen += 1
	_impact_pending = false
	_impact_lock = false
	_finisher = false
	for c in get_children():
		remove_child(c)
		c.free()


## 着弾を見せる：面の光 → 被弾した駒を1体ずつ（エフェクト→フラッシュ→兵数、撃破はフェード）。
## 画面全体の揺れは main が持つ（盤だけを揺らしても画面全体にはならない）。
## 着弾が無いもの（バフ・解除）は光らせず盤を更新するだけ＝呼び出し側で分岐しなくていい。
## is_locked は呼び出し元の現在のロック状態（演出終了後に元に戻すか判定するため）。
func play(result: SkillResult, is_locked: bool) -> void:
	if not _impact_pending:
		# 着弾の無いもの（バフ・解除）＝盤は解決した時点で更新済み。誰に効いたのかが
		# 盤に出ないので、印を持つレシピ（シールドウォール）は参加者に1枚ずつ重ねてから抜ける。
		await _play_mark(result)
		return
	if _skip:
		_end_impact()  # 盤面の演出 OFF＝光もフラッシュも出さず、撃たれた後の盤を作り直すだけ
		_sync_fn.call()
		return
	# 面に降らせる型（アローレイン）は、当たった駒が居なくても雨は降る＝先に分ける。
	var rain := int(Formation.SKILLS.get(result.skill, {}).get("impact_rain", 0))
	if rain > 0:
		var rain_tex := _impact_texture(result.skill)
		if rain_tex != null:
			await _play_rain(result, rain_tex, is_locked, rain)
			return
	# 発動者から列ごとに広げる型（ドラゴンブレス）。当たった駒が居なくても火は広がる＝先に分ける。
	# 絵が無くてもヘクスの光だけが同じ順に広がる。
	if bool(Formation.SKILLS.get(result.skill, {}).get("impact_spread", false)):
		await _play_spread(result, _impact_texture(result.skill), is_locked)
		return
	var hits := result.hits
	if hits.is_empty():
		await _flash_cells_only(result.cells, is_locked)
		return
	# 単体対象のスキル（ディバインジャッジメント・トリックショット）は共通の3段では見せ場が無いので専用シーケンスへ。判定はレシピの
	# 効果から引く＝スキルIDを並べない。絵が無ければ共通へ落とす（面の光と被弾フラッシュだけ）。
	if String(Formation.SKILLS.get(result.skill, {}).get("effect", "")) == "single":
		var single_tex := _impact_texture(result.skill)
		if single_tex != null:
			await _play_single_target(result, single_tex, is_locked)
			return
	var gen := _impact_gen
	# 決着のとどめ＝落下・駒送り・撃破フェードをスローで見せる（面の光の居座りも同じだけ伸ばす）。
	var st := FINISH_STRETCH if _finisher else 1.0
	_impact_lock = not is_locked
	_set_locked_fn.call(true)  # 演出中に盤を触らせない（別の作り直しが割り込むと消えかけの駒が飛ぶ）
	await _wait(HIT_LEAD_SEC)  # 揺れと同時に光らせない＝1つの衝撃に潰れる
	if gen != _impact_gen:
		_end_impact()
		return
	await _vanish_caster(result, st)  # 戻すレシピだけ＝専用の絵が無くても消えて帰る筋は同じ
	if gen != _impact_gen:
		_end_impact()
		return
	var center := result.center
	# 面の光は駒の処理が終わるまで保たせる＝どの範囲の中で起きているのかが見えたまま進む。
	_flash_cells(result.cells, HIT_CELL_HOLD + (HIT_DROP_SEC + HIT_STEP_SEC * float(hits.size())) * st)
	var tex := _impact_texture(result.skill)
	# 着弾中心に近い駒から外へ。同距離は id 順＝毎回同じ順で出る（見え方が揺れない）。
	var order := hits.duplicate()
	order.sort_custom(func(a: SkillHit, b: SkillHit) -> bool:
		var da := Hex.distance(a.hex, center)
		var db := Hex.distance(b.hex, center)
		return da < db if da != db else a.target_id < b.target_id)
	for i in order.size():
		_hit_unit(order[i], tex, st)
		# 最後の1発は落ちて当たって消えるまで待ってから盤を作り直す（消えかけの駒を飛ばさない）。
		await _wait((HIT_STEP_SEC if i < order.size() - 1 else HIT_DROP_SEC + maxf(HIT_BURST_SEC, HIT_FADE_SEC)) * st)
		if gen != _impact_gen:
			_end_impact()
			return
	await _appear_caster(result, st)  # 発動者を戻すレシピ（バックスタブ）だけ＝他は素通り
	if gen != _impact_gen:
		_end_impact()
		return
	_end_impact()
	_sync_fn.call()


## 戦闘の結果を盤で見せる：攻撃側の一撃 → 被弾側の反応 → 反撃があれば逆向き → 盤を作り直す。
## 戦闘窓を開かない手だけ hex_board_3d が呼ぶ（設定「戦闘の演出」）。盤面の演出 OFF は結果だけ。
## 待ちは陣形の着弾と同じく世代で打ち切る＝ステージが変われば途中でも戻る。
func play_combat(result: AttackResult, is_locked: bool) -> void:
	if not _impact_pending:
		return
	if _skip:
		_end_impact()  # 盤面の演出 OFF＝一撃も被弾も出さず、殴られた後の盤を作り直すだけ
		_sync_fn.call()
		return
	var gen := _impact_gen
	var st := FINISH_STRETCH if _finisher else 1.0
	_impact_lock = not is_locked
	_set_locked_fn.call(true)  # 演出中に盤を触らせない（陣形の着弾と同じ流儀）
	var a := result.attacker
	var d := result.defender
	await _wait(_strike(a, d, result.damage() + d.shield_lost(), st))
	if gen != _impact_gen:
		_end_impact()
		return
	if result.has_counter():
		await _wait(COUNTER_GAP_SEC * st)
		if gen != _impact_gen:
			_end_impact()
			return
		await _wait(_strike(d, a, result.retaliation() + a.shield_lost(), st))
		if gen != _impact_gen:
			_end_impact()
			return
	await _wait(COMBAT_TAIL_SEC * st)
	if gen != _impact_gen:
		_end_impact()
		return
	_end_impact()
	_sync_fn.call()


## 一撃を放つ。by＝殴る側、comb＝殴られる側（戦闘後の姿を持つ＝撃破かどうかはここから読む）。
## 飛ぶ型は by の駒から comb の駒へ飛ばし、重ねる型は comb の駒の上でその場で弾けさせる。
## 音は戦闘窓と同じ規約（発射＝effect_id・着弾＝{effect_id}_hit・損害なし＝弾かれた音）。
## 返り値＝放ってから着弾するまでの秒数（重ねる型は放った瞬間が着弾＝0）。stretch は決着のスロー。
func _strike(by: UnitSnapshot, comb: UnitSnapshot, dmg: int, stretch: float) -> float:
	var gen := _impact_gen
	var eff := _effect_of(by)
	var tex := _effect_texture(eff)
	var killed := comb.is_killed()
	var uid := comb.handle
	var on_land := func() -> void:
		if gen != _impact_gen:
			return
		if eff != null:
			if dmg <= 0:
				SfxPlayer.play_sfx(CombatStage.SFX_DEFLECT)
			else:
				SfxPlayer.play_sfx("%s_hit" % eff.effect_id if eff.is_projectile() else eff.effect_id)
		_land_unit(uid, killed, stretch)
	if tex == null:
		# 絵が無い＝殴られたヘックスだけを光らせる（穴が開かない。陣形の着弾と同じ落とし方）
		_flash_cells([comb.pos], HIT_BURST_SEC * stretch)
		on_land.call()
		return 0.0
	if eff.is_projectile():
		SfxPlayer.play_sfx(eff.effect_id)  # 発射。損害によらず武器固有
		_spawn_flying_impact(by.pos, comb.pos, tex, on_land, stretch, STRIKE_FLY_TILES * eff.scale)
		return FLY_SEC * stretch
	# 絵は「右へ向かう一撃」で描く約束＝殴る側が右に居るときだけ水平反転する（戦闘窓と同じ規約）
	var mirror := Hex.to_pixel(by.pos, TILE).x > Hex.to_pixel(comb.pos, TILE).x
	_spawn_strike(comb.pos, tex, mirror, STRIKE_TILES * eff.scale, on_land, stretch)
	return 0.0


## 毒で兵数が減る瞬間（ターン開始）：駒の上に毒の絵（effect_id）を浮かべ、着いた瞬間に兵数を
## 減った値へ組み直してフラッシュする。盤は減る前の兵数を hold したまま待っている＝ここで外す。
## 返り値＝見せ終えるまでの秒数。絵が無ければマスを光らせるだけ。詳細 → doc/gdd/skills.md ポイズンスティング
func play_dot_tick(uid: int, hex: Vector2i, effect_id: String) -> float:
	var eff := CombatEffectCatalog.by_id(effect_id)
	var tex := _effect_texture(eff)
	var on_land := func() -> void:
		_unit_renderer.release_troops(uid)
		if eff != null:
			SfxPlayer.play_sfx(eff.effect_id)
		_land_unit(uid, false)
	if tex == null:
		_flash_cells([hex], HIT_BURST_SEC)
		on_land.call()
		return HIT_BURST_SEC
	_spawn_strike(hex, tex, false, STRIKE_TILES * eff.scale, on_land)
	return maxf(STRIKE_SEC, HIT_FLASH_SEC * 2.0)


## 殴る側の武器エフェクト。スキン未設定・未定義IDなら null（絵は無い扱い）。
func _effect_of(comb: UnitSnapshot) -> CombatEffect:
	var skin := SkinCatalog.resolve(_skin_catalog, comb.skin_id, comb.type_id, comb.team)
	if skin == null:
		return null
	return CombatEffectCatalog.by_id(skin.combat_effect)


## 武器エフェクトの絵（キャッシュ）。置き場は CombatEffect が規約で決める。無ければ null。
func _effect_texture(eff: CombatEffect) -> Texture2D:
	if eff == null:
		return null
	if _effect_tex.has(eff.effect_id):
		return _effect_tex[eff.effect_id]
	var p := eff.image_path()
	var tex := load(p) as Texture2D if p != "" and ResourceLoader.exists(p) else null
	_effect_tex[eff.effect_id] = tex
	return tex


## 重ねる型の一撃：殴られる駒の上に絵を1枚置き、開きながら消す（戦闘窓の _spawn_burst と同じ動き）。
## 放った瞬間が着弾＝置いてすぐ on_land を呼ぶ。
func _spawn_strike(hex: Vector2i, tex: Texture2D, mirror: bool, tiles: float, on_land: Callable, stretch := 1.0) -> void:
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.no_depth_test = true      # 駒より手前に出す（_spawn_burst と同じ扱い）
	spr.render_priority = 6
	spr.flip_h = mirror
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	spr.pixel_size = (tiles * TILE) / maxf(longest, 1.0)
	var p := Hex.to_pixel(hex, TILE)
	spr.position = Vector3(p.x, _elev_fn.call(hex) + TILE * 0.9, p.y + BoardUnitRenderer.SPRITE_FOOT_Z)
	spr.scale = Vector3.ONE * 0.5
	add_child(spr)
	on_land.call()
	var tw := _tween()
	tw.set_parallel(true)  # 開きながら消える
	tw.tween_property(spr, "scale", Vector3.ONE * STRIKE_OPEN, STRIKE_SEC * stretch)
	tw.tween_property(spr, "modulate:a", 0.0, STRIKE_SEC * stretch)
	tw.chain().tween_callback(spr.queue_free)


## 面に降らせる型のスキル専用（アローレイン）：面の全ヘックスに矢を per_hex 本ずつ降らせる。
## 落ちる順は中心から外へ（輪ごと）。被弾した駒は、自分のマスに最初の1本が着いた瞬間に反応する
## ＝共通シーケンスの「駒に1枚落として1体ずつ送る」は使わない。詳細 → doc/gdd/formations.md アローレイン
func _play_rain(result: SkillResult, tex: Texture2D, is_locked: bool, per_hex: int) -> void:
	var gen := _impact_gen
	var st := FINISH_STRETCH if _finisher else 1.0
	_impact_lock = not is_locked
	_set_locked_fn.call(true)  # 演出中に盤を触らせない（共通シーケンスと同じ流儀）
	await _wait(HIT_LEAD_SEC)  # 揺れと同時に降らせない＝1つの衝撃に潰れる
	if gen != _impact_gen:
		_end_impact()
		return
	var center := result.center
	var victims := {}  # ヘックス → そこで被弾した駒
	for h in result.hits:
		victims[h.hex] = h
	var rings := 0
	for c in result.cells:
		rings = maxi(rings, Hex.distance(Vector2i(c), center))
	# 最後の1本が落ちきるまで＝輪の遅れ＋同ヘックス内の間隔＋散らし＋落下
	var span := RAIN_RING_SEC * float(rings) + RAIN_GAP_SEC * float(per_hex - 1) 		+ RAIN_JITTER_SEC + RAIN_DROP_SEC
	var tail := maxf(RAIN_FADE_SEC, HIT_FADE_SEC)
	_flash_cells(result.cells, HIT_CELL_HOLD + (span + tail) * st)
	for c in result.cells:
		var hex := Vector2i(c)
		if not _in_board_fn.call(hex):
			continue
		var ring := float(Hex.distance(hex, center))
		var hit: SkillHit = victims.get(hex)
		for i in per_hex:
			var delay := RAIN_RING_SEC * ring + RAIN_GAP_SEC * float(i) 				+ RAIN_JITTER_SEC * _rain_noise(hex, i, 0)
			var off := Vector2(_rain_noise(hex, i, 1) - 0.5, _rain_noise(hex, i, 2) - 0.5) 				* (TILE * RAIN_SCATTER)
			# 駒の反応は1本目が着いた瞬間だけ（3本ぶん反応させると兵数バーを3回組み直す）。
			var on_land := Callable()
			if hit != null and i == 0:
				on_land = func() -> void:
					if gen == _impact_gen:
						_land_unit(hit.target_id, hit.killed, st)
			_spawn_rain_arrow(hex, off, tex, delay * st, on_land, st)
	await _wait((span + tail) * st)
	if gen != _impact_gen:
		_end_impact()
		return
	_end_impact()
	_sync_fn.call()


## 発動者から列ごとに広げる型のスキル専用（ドラゴンブレス）：発動者から近い列から順に、面のヘクスへ
## 火を1つずつ付ける（1列目 → 2列目 → 3列目）。被弾した駒は自分のヘクスに火が付いた瞬間に反応する
## ＝共通シーケンスの「駒に1枚落として1体ずつ送る」は使わない。tex が null ならヘクスの光だけが広がる。
## 詳細 → doc/gdd/skills.md ドラゴンブレス
func _play_spread(result: SkillResult, tex: Texture2D, is_locked: bool) -> void:
	var gen := _impact_gen
	var st := FINISH_STRETCH if _finisher else 1.0
	_impact_lock = not is_locked
	_set_locked_fn.call(true)  # 演出中に盤を触らせない（共通シーケンスと同じ流儀）
	await _wait(HIT_LEAD_SEC)  # 揺れと同時に火を付けない＝1つの衝撃に潰れる
	if gen != _impact_gen:
		_end_impact()
		return
	var origin := result.caster.pos if result.caster != null else result.center
	var victims := {}  # ヘクス → そこで被弾した駒
	for h in result.hits:
		victims[h.hex] = h
	var waves := {}  # 発動者からの距離 → その列のヘクス
	for c in result.cells:
		var hex := Vector2i(c)
		if _in_board_fn.call(hex):
			var d := Hex.distance(hex, origin)
			if not waves.has(d):
				waves[d] = []
			waves[d].append(hex)
	var dists := waves.keys()
	dists.sort()
	var tail := maxf(FLAME_RISE_SEC + FLAME_HOLD_SEC + FLAME_FADE_SEC, HIT_FADE_SEC)
	for i in dists.size():
		# 光は最後の列が燃え尽きるまで保たせる＝面が見えたまま広がる。
		var left := SPREAD_STEP_SEC * float(dists.size() - 1 - i) + tail
		_flash_cells(waves[dists[i]], HIT_CELL_HOLD + left * st)
		for hex in waves[dists[i]]:
			if tex != null:
				_spawn_flame(hex, tex, st)
			var hit: SkillHit = victims.get(hex)
			if hit != null:
				_land_unit(hit.target_id, hit.killed, st)
		await _wait((SPREAD_STEP_SEC if i < dists.size() - 1 else tail) * st)
		if gen != _impact_gen:
			_end_impact()
			return
	_end_impact()
	_sync_fn.call()


## 火を1つ、ヘクスの上に付ける。足元から立ち上がって燃え、少し置いてから引く。
func _spawn_flame(hex: Vector2i, tex: Texture2D, stretch := 1.0) -> void:
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.no_depth_test = true      # 駒より手前に出す（_spawn_burst と同じ扱い）
	spr.render_priority = 6
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	spr.pixel_size = (FLAME_TILES * TILE) / maxf(longest, 1.0)
	var height := float(tex.get_height()) * spr.pixel_size
	var p := Hex.to_pixel(hex, TILE)
	var foot := Vector3(p.x, _elev_fn.call(hex), p.y + BoardUnitRenderer.SPRITE_FOOT_Z)
	# 絵の下端をヘクスの足元に留めたまま縦に伸ばす＝下から立ち上がる（中心基準の拡大を持ち上げで打ち消す）。
	var grow := func(k: float) -> void:
		spr.scale = Vector3(1.0, k, 1.0)
		spr.position = foot + Vector3(0.0, height * k * 0.5, 0.0)
	grow.call(0.2)
	add_child(spr)
	var tw := _tween()
	tw.tween_method(grow, 0.2, 1.0, FLAME_RISE_SEC * stretch).set_ease(Tween.EASE_OUT)
	tw.tween_interval(FLAME_HOLD_SEC * stretch)
	tw.tween_property(spr, "modulate:a", 0.0, FLAME_FADE_SEC * stretch)
	tw.tween_callback(spr.queue_free)


## 矢を1本、ヘックスの上から落とす。delay 秒待ってから落ち始め、着いたら on_land（あれば）を
## 呼んで、その場で短く消える（共通の「開きながら消える」はしない＝矢は弾けない）。
## off＝ヘックスの中心からの落ち先のずれ（盤の平面上）。
func _spawn_rain_arrow(hex: Vector2i, off: Vector2, tex: Texture2D, delay: float,
		on_land: Callable, stretch := 1.0) -> void:
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.no_depth_test = true      # 駒より手前に出す（_spawn_burst と同じ扱い）
	spr.render_priority = 6
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	spr.pixel_size = (RAIN_TILES * TILE) / maxf(longest, 1.0)
	var p := Hex.to_pixel(hex, TILE)
	var land := Vector3(p.x + off.x, _elev_fn.call(hex) + TILE * 0.9,
		p.y + off.y + BoardUnitRenderer.SPRITE_FOOT_Z)
	spr.position = land + Vector3(0, HIT_DROP_FROM, 0)
	spr.visible = false  # 出番まで隠す（待っている間ぶら下がって見えない）
	add_child(spr)
	var tw := _tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void: spr.visible = true)
	tw.tween_property(spr, "position", land, RAIN_DROP_SEC * stretch).set_ease(Tween.EASE_IN)
	if not on_land.is_null():
		tw.tween_callback(on_land)
	tw.tween_property(spr, "modulate:a", 0.0, RAIN_FADE_SEC * stretch)
	tw.tween_callback(spr.queue_free)


## 毎回同じだが規則性の見えない 0〜1 の値。ヘックスの座標・何本目・用途(salt) から引く
## ＝乱数を使わない。同じ面に撃てば毎回同じ降り方になる（見え方が揺れない）。
static func _rain_noise(hex: Vector2i, i: int, salt: int) -> float:
	var h := (hex.x * 73856093) ^ (hex.y * 19349663) ^ (i * 83492791) ^ (salt * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


## 単体対象のスキル専用：ため（対象ヘクスの光）→ スキルの絵が届いて着弾 → 残光 → 引き。
## 届き方はレシピの impact_motion で分かれる："drop"（既定・ディバインジャッジメント＝真上からゆっくり降りる）／
## "fly"（トリックショット＝射手のヘックスから飛んでくる）／"strike"（バックスタブ＝対象の駒に重ねて
## その場で弾ける）。被弾の処理（フラッシュ・兵数・撃破フェード）はどれも絵が着いた瞬間に共通の _land_hit で起こす。
## 発動者を戻すレシピ（バックスタブ）は、絵の前に駒を消し、絵が引いてから移動開始位置に現し直す
## ＝刺して消える。詳細 → doc/gdd/formations.md バックスタブ
func _play_single_target(result: SkillResult, tex: Texture2D, is_locked: bool) -> void:
	var gen := _impact_gen
	# 決着のとどめ＝絵の到達・残光・撃破フェードをスローで見せる（ためはそのまま）。
	var st := FINISH_STRETCH if _finisher else 1.0
	var hit: SkillHit = result.hits[0]
	# 射手の位置が要る＝取れなければ真上から降ろす（穴は開かない）。
	var motion := _impact_motion(result)
	if motion == "fly" and result.caster == null:
		motion = "drop"
	var reach := SINGLE_DROP_SEC + SINGLE_HOLD_SEC
	var tail := SINGLE_FADE_SEC  # 絵が引くまでの上乗せ。重ねる型は開きながら消えるので持たない
	if motion == "fly":
		reach = FLY_SEC + FLY_HOLD_SEC
	elif motion == "strike":
		reach = STRIKE_SEC
		tail = 0.0
	_impact_lock = not is_locked
	_set_locked_fn.call(true)  # 共通シーケンスと同じ流儀＝演出中に盤を触らせない
	await _wait(HIT_LEAD_SEC)
	if gen != _impact_gen:
		_end_impact()
		return
	await _vanish_caster(result, st)  # 戻すレシピだけ＝刺した位置で駒が消える
	if gen != _impact_gen:
		_end_impact()
		return
	var hex := hit.hex
	# ための光は絵が引き始めるまで居座らせる＝どこへ来るのか・来ているのかが見えたまま進む。
	_flash_cells([hex], SINGLE_CHARGE_SEC + reach * st - HIT_CELL_RISE - HIT_CELL_SETTLE,
		HIT_CELL_ALPHA, SINGLE_CHARGE_ALPHA_HOLD)
	await _wait(SINGLE_CHARGE_SEC)
	if gen != _impact_gen:
		_end_impact()
		return
	var on_land := func() -> void:
		if gen == _impact_gen:
			_land_hit(hit, st)
	match motion:
		"fly":
			_spawn_flying_impact(result.caster.pos, hex, tex, on_land, st)
		"strike":
			# 絵は「右へ向かう一撃」で描く約束＝撃った側が右に居るときだけ反転する（戦闘の一撃と同じ規約）。
			var from_pos := result.caster.pos if result.caster != null else hex
			var mirror := Hex.to_pixel(from_pos, TILE).x > Hex.to_pixel(hex, TILE).x
			_spawn_strike(hex, tex, mirror, STRIKE_TILES, on_land, st)
		_:
			_spawn_falling_impact(hex, tex, on_land, st)
	await _wait((reach + tail) * st)
	if gen != _impact_gen:
		_end_impact()
		return
	await _appear_caster(result, st)  # 移動開始位置に現れる（バックスタブ）
	if gen != _impact_gen:
		_end_impact()
		return
	_end_impact()
	_sync_fn.call()


## 発動者を戻すレシピ（バックスタブ）の前半＝刺した位置で駒を消す。戻す先は SkillResult が持つ
## （domain が盤を戻した先）。戻さないレシピは何もしない。
## 盤の状態はもう戻った先で確定している＝演出が途中で切れても嘘にはならない（移動アニメと同じ
## 「状態は即確定・見た目は後追い」の流儀）。詳細 → doc/gdd/formations.md バックスタブ
func _vanish_caster(result: SkillResult, stretch := 1.0) -> void:
	if result.caster_returned_to == Formation.NO_HEX:
		return
	var node: Node3D = _unit_renderer.get_unit_node(result.caster_id)
	if node == null:
		return
	_unit_renderer.forget_unit(result.caster_id)  # 追跡から外す＝この駒は消し、帰りで組み直す
	_fade_out_unit(node, stretch)
	await _wait(HIT_FADE_SEC * stretch)


## 同・後半＝移動開始位置に駒を組み直して浮かび上がらせる。盤の状態はもう戻った先なので、
## 組み直せばそのマスに立つ。戻さないレシピは何もしない。
func _appear_caster(result: SkillResult, stretch := 1.0) -> void:
	if result.caster_returned_to == Formation.NO_HEX:
		return
	var u := _state.unit_by_handle(result.caster_id)
	if u == null:
		return
	_fade_in_unit(_unit_renderer.build_unit_node(u), stretch)
	await _wait(HIT_FADE_SEC * stretch)


## 組んだばかりの駒を透明から立ち上げる（_fade_out_unit の裏返し）。立ち絵と札だけを動かし、
## 影・バー・輪は共有材質なのでそのまま出す（材質のアルファを触ると他の駒まで薄くなる）。
func _fade_in_unit(node: Node3D, stretch := 1.0) -> void:
	var tw := _tween()
	tw.set_parallel(true)
	for c in node.get_children():
		if c is Sprite3D:
			var spr := c as Sprite3D
			spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED  # discard のままでは薄くならない
			var base := spr.modulate.a
			spr.modulate.a = 0.0
			tw.tween_property(spr, "modulate:a", base, HIT_FADE_SEC * stretch)
		elif c is Label3D:
			var lab := c as Label3D
			var lbase := lab.modulate.a
			lab.modulate.a = 0.0
			tw.tween_property(lab, "modulate:a", lbase, HIT_FADE_SEC * stretch)


## そのスキルの絵の届き方（レシピの impact_motion）。既定は真上から降りる "drop"。
## "fly"＝射手のヘックスから飛ぶ／"strike"＝対象の駒に重ねてその場で弾ける（バックスタブ＝
## 発動者は刺した直後に消えるので、飛ばす起点が残らない）。
func _impact_motion(result: SkillResult) -> String:
	return String(Formation.SKILLS.get(result.skill, {}).get("impact_motion", "drop"))


## 着弾は無いが光らせる面がある（スライムの分裂で出た位置・駒の居ない面への着弾）。
## 光の立ち上がりを見せてから盤を作り直す＝分裂で出た駒は光の後に現れる（→ doc/gdd/skills.md スライムスプリット）。
## 面が無いもの（バフ・解除）は光らせず盤を更新するだけ。引きの光は作り直しに重なって消えていく。
func _flash_cells_only(cells: Array, is_locked: bool) -> void:
	if cells.is_empty():
		_end_impact()
		_sync_fn.call()
		return
	var gen := _impact_gen
	_impact_lock = not is_locked
	_set_locked_fn.call(true)  # 光の間だけ盤を触らせない（play と同じ流儀）
	await _wait(HIT_LEAD_SEC)
	if gen != _impact_gen:
		_end_impact()
		return
	_flash_cells(cells, HIT_CELL_HOLD)
	await _wait(HIT_CELL_RISE + HIT_CELL_SETTLE + HIT_CELL_HOLD)
	if gen != _impact_gen:
		_end_impact()
		return
	_end_impact()
	_sync_fn.call()


## 着弾の無いレシピの発動の印＝参加者の駒に絵を1枚ずつ重ね、少し置いてから消す。
## 出る順は盤の左から右へ（参加者を選んだ順ではない）＝列に沿って1枚ずつ立つように見せる。
## 絵が無いレシピ（グレイスほか）は何も出さずに戻る＝呼び出し側で分岐しなくていい。
## 盤面の演出 OFF も出さない。詳細 → doc/gdd/formations.md 発動の演出
func _play_mark(result: SkillResult) -> void:
	if _skip or result.participants.is_empty():
		return
	# 地帯（マジックシールド）の印は効果範囲のヘックスに出したまま持続する＝盤（_sync_zones）が
	# 受け持つ。ここで参加者の駒にも出すと二重になる。詳細 → doc/gdd/formations.md マジックシールド
	if String(Formation.SKILLS.get(result.skill, {}).get("buff_scope", "")) == "zone":
		return
	var tex := mark_texture(result.skill)
	if tex == null:
		return
	var cells: Array[Vector2i] = []
	for pid in result.participants:
		var u := _state.unit_by_handle(pid)
		if u != null:
			cells.append(u.pos)
	if cells.is_empty():
		return
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var pa := Hex.to_pixel(a, TILE)
		var pb := Hex.to_pixel(b, TILE)
		return pa.x < pb.x if not is_equal_approx(pa.x, pb.x) else pa.y < pb.y)
	for i in cells.size():
		_spawn_mark(cells[i], tex, MARK_STEP_SEC * float(i))
	await _wait(MARK_STEP_SEC * float(cells.size() - 1)
		+ MARK_RISE_SEC + MARK_HOLD_SEC + MARK_FADE_SEC)


## 発動の印を1枚、駒に重ねる。delay 秒待ってから小さく開いて出て、置いたあと引く。
func _spawn_mark(hex: Vector2i, tex: Texture2D, delay: float) -> void:
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.no_depth_test = true      # 駒より手前に出す（着弾の絵と同じ扱い）
	spr.render_priority = 6
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	spr.pixel_size = (MARK_TILES * TILE) / maxf(longest, 1.0)
	var p := Hex.to_pixel(hex, TILE)
	spr.position = Vector3(p.x, _elev_fn.call(hex) + TILE * 0.9, p.y + BoardUnitRenderer.SPRITE_FOOT_Z)
	spr.scale = Vector3.ONE * MARK_RISE_FROM
	spr.visible = false  # 出番まで隠す（待っている間ぶら下がって見えない）
	add_child(spr)
	var tw := _tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		spr.modulate.a = MARK_ALPHA
		spr.visible = true)
	tw.tween_property(spr, "scale", Vector3.ONE, MARK_RISE_SEC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(MARK_HOLD_SEC)
	tw.tween_property(spr, "modulate:a", 0.0, MARK_FADE_SEC)
	tw.tween_callback(spr.queue_free)


## 発動の印の絵（キャッシュ）。スキルIDで規約解決する＝assets/formations/{skill_id}_mark.png。
## 盤の結界の印（HexBoard3D._sync_zones）も同じ絵を同じ引き方で使う＝置き場を二重に持たない。
## カットイン（{skill_id}.png）・着弾（{skill_id}_impact.png）と同じ置き場で接尾辞だけが違う。
## 盤では回さない＝絵は正面・直立で描く。無ければ null＝印を出さない。
func mark_texture(skill_id: String) -> Texture2D:
	if skill_id.is_empty():
		return null
	if _mark_tex.has(skill_id):
		return _mark_tex[skill_id]
	var p := "res://assets/formations/%s_mark.png" % skill_id
	var tex := load(p) as Texture2D if ResourceLoader.exists(p) else null
	_mark_tex[skill_id] = tex
	return tex


## 着弾演出の後始末＝保留を解き、止めた入力を戻し、待っている側（main）へ知らせる。
## 決着が割り込んだ場合は _impact_lock が下りている＝解錠しない。
func _end_impact() -> void:
	_impact_pending = false
	_finisher = false  # とどめは1回きり＝次の着弾へ持ち越さない
	if _impact_lock:
		_set_locked_fn.call(false)
		_impact_lock = false
	impact_finished.emit()


## 被弾した駒1体ぶん。エフェクトが上から落ちきった瞬間に駒が反応する
## （撃破ならその場でフェードアウト、生き残りは新しい兵数で組み直して光らせる）。
## stretch＝尺に掛ける倍率（決着のとどめのスロー。通常は1.0）。
func _hit_unit(hit: SkillHit, tex: Texture2D, stretch := 1.0) -> void:
	var gen := _impact_gen
	var on_land := func() -> void:
		if gen == _impact_gen:
			_land_hit(hit, stretch)
	_spawn_burst(hit.hex, tex, on_land, stretch)


func _land_hit(hit: SkillHit, stretch := 1.0) -> void:
	_land_unit(hit.target_id, hit.killed, stretch)


## 殴られた駒の反応。撃破ならその場でフェードアウト、生き残りは新しい兵数で組み直して光らせる。
## 陣形の着弾と戦闘の一撃の両方から使う（state は解決済み＝組み直せば減った値が出る）。
func _land_unit(uid: int, killed: bool, stretch := 1.0) -> void:
	var node: Node3D = _unit_renderer.get_unit_node(uid)
	if node == null:
		return
	if killed:
		_unit_renderer.forget_unit(uid)
		_fade_out_unit(node, stretch)
		return
	# 兵数バーは組み立て時に焼くので、減った値を出すには組み直すのが早い（state は解決済み）。
	_unit_renderer.remove_unit(uid)
	var u := _state.unit_by_handle(uid)
	if u != null:
		_flash_unit(_unit_renderer.build_unit_node(u))


## 被弾フラッシュ＝立ち絵を一瞬白く飛ばして戻す。行動終了の暗さ（modulate）を基準に掛ける。
func _flash_unit(node: Node3D) -> void:
	for c in node.get_children():
		if not (c is Sprite3D):
			continue
		var spr := c as Sprite3D
		var base := spr.modulate
		var hot := Color(base.r * HIT_FLASH_GAIN, base.g * HIT_FLASH_GAIN, base.b * HIT_FLASH_GAIN, base.a)
		var tw := _tween()
		tw.tween_property(spr, "modulate", hot, HIT_FLASH_SEC)
		tw.tween_property(spr, "modulate", base, HIT_FLASH_SEC)


## 撃破された駒を消す。立ち絵は薄くして消し、影・バー・輪は共有材質なので隠すだけにする
## （材質のアルファを触ると、同じ色を使う他の駒まで一緒に薄くなる）。
## stretch＝尺に掛ける倍率（決着のとどめ＝最後の1体はゆっくり消える）。
func _fade_out_unit(node: Node3D, stretch := 1.0) -> void:
	var tw := _tween()
	tw.set_parallel(true)
	for c in node.get_children():
		if c is Sprite3D:
			var spr := c as Sprite3D
			spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED  # discard のままでは薄くならない
			tw.tween_property(spr, "modulate:a", 0.0, HIT_FADE_SEC * stretch)
		elif c is Label3D:
			tw.tween_property(c, "modulate:a", 0.0, HIT_FADE_SEC * stretch)
		elif c is Node3D:
			(c as Node3D).hide()
	tw.chain().tween_callback(node.queue_free)


## 着弾した面を光らせる。駒の居ない空ヘックスも光らせる＝面の広さが伝わる。
## 盤の外へはみ出したヘックスは出さない。材質は1枚ごとに作る（アルファを個別に動かすため）。
## 濃さは呼び出し側で選べる（ディバインジャッジメントのためは居座りを強めに出す）。
func _flash_cells(cells: Array, hold: float,
		alpha_rise := HIT_CELL_ALPHA, alpha_hold := HIT_CELL_ALPHA_HOLD) -> void:
	for c in cells:
		var hex := Vector2i(c)
		if not _in_board_fn.call(hex):
			continue
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(COLOR_FORMATION_HIT, 0.0)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # 地形の上に載せる（塗り潰さない）
		var mi := MeshInstance3D.new()
		mi.mesh = _overlay_mesh
		mi.material_override = m
		var p := Hex.to_pixel(hex, TILE)
		mi.position = Vector3(p.x, _elev_fn.call(hex) + 0.05, p.y)
		add_child(mi)
		# 立ち上がりで一度強く光らせ、駒を処理している間は薄く居座らせる（面は見えたまま・
		# 駒に重ねるエフェクトは埋もれない）。最後に引く。
		var tw := _tween()
		tw.tween_property(m, "albedo_color:a", alpha_rise, HIT_CELL_RISE)
		tw.tween_property(m, "albedo_color:a", alpha_hold, HIT_CELL_SETTLE)
		tw.tween_interval(hold)
		tw.tween_property(m, "albedo_color:a", 0.0, HIT_CELL_FADE)
		tw.tween_callback(mi.queue_free)


## 駒に当てるエフェクト1発。スキル専用の絵を駒の真上から落として当てる。
## 落ちきった時点で on_land を呼ぶ＝駒の反応（フラッシュ・兵数・撃破）はそこに揃う。
## 絵が無いときは、そのヘックスだけを濃く光らせる＝穴が開かない。
## stretch＝尺に掛ける倍率（決着のとどめのスロー。通常は1.0）。
func _spawn_burst(hex: Vector2i, tex: Texture2D, on_land: Callable, stretch := 1.0) -> void:
	if tex == null:
		_flash_cells([hex], HIT_BURST_SEC * stretch)
		on_land.call()
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.no_depth_test = true      # 駒より手前に出す（足元の地形や後列に潜り込ませない）
	spr.render_priority = 6
	# 大きさの基準は長辺。倍率は持たず、絵の側を枠いっぱいに描いて釣り合わせる。
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	spr.pixel_size = (HIT_BURST_TILES * TILE) / maxf(longest, 1.0)
	var p := Hex.to_pixel(hex, TILE)
	var land := Vector3(p.x, _elev_fn.call(hex) + TILE * 0.9, p.y + BoardUnitRenderer.SPRITE_FOOT_Z)
	spr.position = land + Vector3(0, HIT_DROP_FROM, 0)
	add_child(spr)
	var tw := _tween()
	tw.tween_property(spr, "position", land, HIT_DROP_SEC * stretch).set_ease(Tween.EASE_IN)  # 落下＝加速
	tw.tween_callback(on_land)
	tw.set_parallel(true)  # 着弾＝開きながら消える
	tw.tween_property(spr, "scale", Vector3.ONE * HIT_BURST_OPEN, HIT_BURST_SEC * stretch)
	tw.tween_property(spr, "modulate:a", 0.0, HIT_BURST_SEC * stretch)
	tw.chain().tween_callback(spr.queue_free)


## スキルの絵を1枚、射手のヘックスから対象のヘックスへ飛ばす。着いた瞬間に on_land を呼ぶ。
## 絵は地面に寝かせて（法線を上へ向けて）進行方向へ回す＝真上から見た形で右向き（+X）に描いた絵が
## そのまま飛ぶ向きになる。駒と同じ板看板（ビルボード）にすると、どの方向へ飛んでも同じ絵が出て
## 向きが読めないため、ここだけ寝かせる。詳細 → doc/gdd/formations.md 発動の演出
## stretch＝尺に掛ける倍率（決着のとどめのスロー。通常は1.0）。tiles＝絵の大きさ（長辺がヘックス幅の何倍か）。
func _spawn_flying_impact(from_hex: Vector2i, to_hex: Vector2i, tex: Texture2D,
		on_land: Callable, stretch := 1.0, tiles := FLY_TILES) -> void:
	var a := Hex.to_pixel(from_hex, TILE)
	var b := Hex.to_pixel(to_hex, TILE)
	var start := Vector3(a.x, _elev_fn.call(from_hex) + FLY_HEIGHT, a.y)
	var land := Vector3(b.x, _elev_fn.call(to_hex) + FLY_HEIGHT, b.y)
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	spr.shaded = false
	spr.transparent = true
	spr.double_sided = true
	spr.no_depth_test = true      # 駒より手前に出す（_spawn_burst と同じ扱い）
	spr.render_priority = 6
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	spr.pixel_size = (tiles * TILE) / maxf(longest, 1.0)
	# 寝かせる（-90度）＋進行方向へ回す。絵の右が +X なので、向き (dx, dz) への角は atan2(-dz, dx)。
	var d := land - start
	spr.rotation = Vector3(-PI * 0.5, atan2(-d.z, d.x), 0.0)
	spr.position = start
	add_child(spr)
	# 弧を描いて飛ぶ＝真っ直ぐ滑らせると地を這っているように見える。頂点は中間。
	var fly := func(t: float) -> void:
		spr.position = start.lerp(land, t) + Vector3(0.0, FLY_ARC * sin(PI * t), 0.0)
	var tw := _tween()
	tw.tween_method(fly, 0.0, 1.0, FLY_SEC * stretch).set_ease(Tween.EASE_OUT)  # 手を離れた直後が速い
	tw.tween_callback(on_land)
	tw.tween_interval(FLY_HOLD_SEC * stretch)  # 刺さったまま少し置く
	tw.tween_property(spr, "modulate:a", 0.0, SINGLE_FADE_SEC * stretch)
	tw.tween_callback(spr.queue_free)


## スキルの絵を1枚。幅基準で大きく出し（縦長の絵＝長辺基準だと痩せる）、上からゆっくり降ろして
## 着地の瞬間に on_land を呼ぶ。着地後もしばらく立たせてから引く＝共通の「弾けて消える」とは別の見せ方。
## stretch＝尺に掛ける倍率（決着のとどめのスロー。通常は1.0）。
func _spawn_falling_impact(hex: Vector2i, tex: Texture2D, on_land: Callable, stretch := 1.0) -> void:
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.no_depth_test = true      # 駒より手前に出す（_spawn_burst と同じ扱い）
	spr.render_priority = 6
	spr.pixel_size = (SINGLE_WIDTH_TILES * TILE) / float(maxi(tex.get_width(), 1))
	var height := float(tex.get_height()) * spr.pixel_size
	var p := Hex.to_pixel(hex, TILE)
	# Sprite3D の原点は絵の中央＝絵の裾が地面に着く高さへ中心を置く。
	var land := Vector3(p.x, _elev_fn.call(hex) + height * 0.5, p.y + BoardUnitRenderer.SPRITE_FOOT_Z)
	spr.position = land + Vector3(0, SINGLE_DROP_FROM, 0)
	add_child(spr)
	var tw := _tween()
	tw.tween_property(spr, "position", land, SINGLE_DROP_SEC * stretch).set_ease(Tween.EASE_IN)  # 降下＝加速
	tw.tween_callback(on_land)
	tw.tween_interval(SINGLE_HOLD_SEC * stretch)
	tw.tween_property(spr, "modulate:a", 0.0, SINGLE_FADE_SEC * stretch)
	tw.tween_callback(spr.queue_free)


## 着弾に使う絵（キャッシュ）。スキルIDで規約解決する＝assets/formations/{skill_id}_impact.png。
## カットイン（{skill_id}.png）と同じ置き場・同じ規約で、接尾辞だけが違う。
## 盤でしか使わないので絵は最初から下向きに描く＝ここで回さない。
## 無ければ null＝絵を出さず面の光だけで済ませる（武器の攻撃エフェクトへは落とさない。
## 借り物を落とすと剣の弧が天から降ってくる）。詳細 → doc/gdd/formations.md 発動の演出
func _impact_texture(skill_id: String) -> Texture2D:
	if skill_id.is_empty():
		return null
	if _impact_tex.has(skill_id):
		return _impact_tex[skill_id]
	var p := "res://assets/formations/%s_impact.png" % skill_id
	var tex := load(p) as Texture2D if ResourceLoader.exists(p) else null
	_impact_tex[skill_id] = tex
	return tex


## 待ちと動きは同じ速さで縮める（高速）＝待ちだけ縮めると絵が終わる前に次へ進む。
func _wait(sec: float) -> void:
	if is_inside_tree():
		await get_tree().create_timer(sec / _speed).timeout


func _tween() -> Tween:
	var tw := create_tween()
	tw.set_speed_scale(_speed)
	return tw
