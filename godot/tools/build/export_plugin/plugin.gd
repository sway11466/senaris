@tool
extends EditorPlugin
## 書き出しプラグインの登録だけを行う EditorPlugin。中身は contents_export_plugin.gd。
## 仕様 → doc/tech/build.md 冒険譚の途中まで収録する

const ContentsExportPlugin := preload("res://tools/build/export_plugin/contents_export_plugin.gd")

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = ContentsExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
