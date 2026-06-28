@tool
class_name MiniaudioAndroidExportPlugin extends EditorExportPlugin

## miniaudio Android 导出插件
## 将编译好的 libminiaudio_bridge.so 打包到 APK 中
##
## 机制: 通过 _get_android_libraries 返回 AAR 文件路径,
## Godot gradle 构建会自动将其包含到 APK 的 lib/<abi>/ 目录
##
## AAR 文件结构:
##   libminiaudio_bridge-debug.aar (或 -release.aar)
##     └── jni/
##         └── arm64-v8a/
##             └── libminiaudio_bridge.so

const ADDON_PATH: String = "res://addons/miniaudio"
# AAR 文件名前缀 (与 build_android.ps1 中保持一致: miniaudio_bridge-debug.aar)
const AAR_NAME: String = "miniaudio_bridge"

func _supports_platform(platform) -> bool:
	return platform is EditorExportPlatformAndroid

func _get_android_libraries(platform, debug: bool) -> PackedStringArray:
	var suffix: String = "-debug" if debug else "-release"
	var aar_path: String = "%s/libs/android/%s%s.aar" % [ADDON_PATH, AAR_NAME, suffix]
	print("[miniaudio] _get_android_libraries called: debug=%s, aar_path=%s" % [debug, aar_path])
	if FileAccess.file_exists(aar_path):
		print("[miniaudio] AAR found, returning path: %s" % aar_path)
		return PackedStringArray([aar_path])
	# 回退: 尝试无后缀版本 (debug/release 共用)
	var generic_path: String = "%s/libs/android/%s.aar" % [ADDON_PATH, AAR_NAME]
	if FileAccess.file_exists(generic_path):
		print("[miniaudio] AAR found (generic), returning path: %s" % generic_path)
		return PackedStringArray([generic_path])
	push_warning("[miniaudio] AAR 文件不存在: %s (请参考编译说明生成)" % aar_path)
	push_warning("[miniaudio] 请运行 addons/miniaudio/native/build_android.bat 生成 AAR 文件")
	return PackedStringArray()

func _get_name() -> String:
	return "miniaudio"
