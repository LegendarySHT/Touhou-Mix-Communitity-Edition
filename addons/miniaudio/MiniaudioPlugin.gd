@tool
class_name MiniaudioPlugin extends EditorPlugin

## miniaudio 插件入口
## 注册 Android 导出插件, 将 libminiaudio_bridge.so 打包到 APK

var android_export_plugin: MiniaudioAndroidExportPlugin = MiniaudioAndroidExportPlugin.new()

func _enter_tree() -> void:
	add_export_plugin(android_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(android_export_plugin)
