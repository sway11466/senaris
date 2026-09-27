extends RefCounted
class_name ChronicleStyle
## クロニクル画面で章をまたいで使う色・文字サイズ・寸法。仕様 → doc/gdd/chronicle.md
##
## 画面（ChronicleScreen）と各章（ChronicleChapter の子孫）の両方が読む。どちらかの中に置くと
## 参照が双方向になるので、何にも依存しないここに集める。

const FADE_SEC := 0.25

const UI_GRAY := Color(0.82, 0.82, 0.82)
const ACCENT := Color(0.90, 0.82, 0.62)
const DIM_GRAY := Color(0.45, 0.45, 0.45)  # 未解放の枠（？のテキスト）
const FRAME_COLOR := Color(0.82, 0.82, 0.82, 0.75)
const FRAME_WIDTH := 2

const TITLE_FONT_SIZE := 24
const HEAD_FONT_SIZE := 20
const BODY_FONT_SIZE := 16
const COUNT_FONT_SIZE := 14
const DETAIL_FONT_SIZE := 15

const EDGE := 48          # 画面の左右の余白
const TOC_WIDTH := 200    # 左の目次の幅
const PANE_GAP := 32      # 目次と中身の間
const HEAD_GAP := 14      # 見出しと中身の間・上段と下段の間
const CATEGORY_GAP := 20  # カテゴリ間の余白
const ITEM_GAP := 6       # アイテム間の余白
const ITEM_HEIGHT := 36   # アイテム1行の高さ

## カードの格子（ユニット章・陣形スキル章）。1段の枚数と縦横比は章ごとに違うので章が持つ。
const CARD_GAP := 12
const CARD_PAD := 10           # 紙の縁と絵の間
const CARD_NAME_FONT_SIZE := 14  # 絵の下の名前
const CARD_NAME_H := 26        # 名前の行の高さ（紙はこのぶん絵より高い）
const CARD_DIM := 0.78         # 未解放のカードの紙の明るさ
const SCROLLBAR_ALLOW := 16.0  # 縦スクロールバーのぶん幅を引く（出た瞬間に折り返さないため）
const SILHOUETTE := Color(0.0, 0.0, 0.0, 0.92)  # 未解放の黒塗り
const CARD_SUMMARY_H := 32     # 冒険譚のカードの名前の下のサマリーの行（下端の紙の縁のぶん余白を含む）

## タブ（冒険譚の戦果／物語／設定集）。マニュアルのタブと同じ手つき＝木の板に、選んでいるものだけ細枠。
const TAB_GAP := 6
const TAB_HEIGHT := 30
const TAB_FONT_SIZE := 15
const FRAME_PAD := 3

## 会話／イベント（冒険譚の会話を本のページに流す）。
const EVENTS_TALK_GAP := 14    # 会話と会話の間
const EVENTS_LINE_GAP := 6     # 行と行の間（詰めて並べる）
const EVENTS_FACE_SIZE := 40   # 顔の小さな絵の枠

## 拡大カード（格子のカードを押すと手前に開く1枚）。
const EXPAND_SCRIM := Color(0.02, 0.02, 0.03, 0.72)
const EXPAND_WIDTH := 760.0
const EXPAND_ART_HEIGHT := 200.0
const EXPAND_PAD := 24
