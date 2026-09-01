## 编辑器插件壳：注册 AndroidRuntimeInject 导出插件
## 背景：官方 Godot 4.7.1 编辑器的导出预设 Plugins 列表中没有 "Godot AndroidRuntime" 选项，
## 但 AndroidRuntimePlugin 类本身已编译在 godot-lib aar 中（每个 gradle 构建都携带）。
## GodotPluginRegistry 按 AndroidManifest 中 "org.godotengine.plugin.v2.*" 前缀的
## meta-data 反射实例化插件，因此只需在导出清单注入一条 meta-data 即可启用。
@tool
extends EditorPlugin

const EXPORT_PLUGIN_SCRIPT := preload("export_plugin.gd")

var _export_plugin: EditorExportPlugin

func _enter_tree() -> void:
	_export_plugin = EXPORT_PLUGIN_SCRIPT.new()
	add_export_plugin(_export_plugin)
	print("[AndroidRuntimeInject] export plugin registered")

func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
