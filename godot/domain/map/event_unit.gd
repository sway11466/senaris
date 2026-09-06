extends RefCounted
class_name EventUnit
## イベント（増援）で盤に出す駒1体と、その搭乗者（純データ）。搭乗は同陣営で、輸送ユニットにだけ乗る。
## 駒は StageLoader が採番と性能の解決を済ませて作り、発火まで盤には居ない。詳細 → doc/gdd/map.md イベント

var unit: Unit
var passengers: Array[Unit] = []
