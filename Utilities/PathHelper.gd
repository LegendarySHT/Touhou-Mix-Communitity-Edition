## 平台路径助手（纯静态工具类）
## 集中管理跨平台文件路径逻辑，所有组件统一通过此类获取基础路径
## 
## 设计原则：
##   - 纯静态方法，无需实例化，不依赖任何 Manager
##   - 在 Logger / ConfigManager / FileSystemManager 之前即可使用
##   - Android 平台使用外部可见路径 /storage/emulated/0/Android/data/<包名>/files/
##   - 其他平台保持使用 user://
##
## 使用方式：
##   var charts_dir = PathHelper.get_charts_dir()
##   var config_path = PathHelper.get_user_config_path()
##   PathHelper.ensure_dir_exists(charts_dir)

class_name PathHelper

## Android 包名（硬编码，与 export_presets.cfg 中一致）
const PACKAGE_NAME = "com.touhoumix.ce"

# ============ 平台判断 ============

## 是否运行在 Android 平台
static func is_android() -> bool:
	return OS.has_feature("android")

# ============ 基础路径 ============

## 获取基础目录（平台自适应，每次实时计算，不缓存）
## Android: /storage/emulated/0/Android/data/com.touhoumix.ce/files/
## 其他平台: user://
static func get_base_dir() -> String:
	if is_android():
		return "/storage/emulated/0/Android/data/%s/files/" % PACKAGE_NAME
	else:
		return "user://"

## 获取 files 子目录（所有用户数据的根）
## Android: /storage/emulated/0/Android/data/com.touhoumix.ce/files/
## 其他平台: user://files/
static func get_files_dir() -> String:
	if is_android():
		return get_base_dir()
	else:
		return get_base_dir().path_join("files") + "/"

# ============ 各资源目录 ============

## 谱面目录
static func get_charts_dir() -> String:
	return get_files_dir() + "Charts/"

## 皮肤目录
static func get_skins_dir() -> String:
	return get_files_dir() + "Skins/"

## 粒子目录（用户粒子包，外部导入放这里）
static func get_particles_dir() -> String:
	return get_files_dir() + "Particles/"

## 人物目录（用户自定义人物，外部导入放这里）
static func get_charas_dir() -> String:
	return get_files_dir() + "Charas/"

## 内置皮肤配置覆盖目录
## res:// 在导出后为只读，内置皮肤的修改持久化到此目录
static func get_builtin_skin_config_dir() -> String:
	return get_files_dir() + "Skins/builtin_skin_config/"

## 音源目录
static func get_soundfont_dir() -> String:
	return get_files_dir() + "Soundfont/"

## 背景图目录
static func get_background_dir() -> String:
	return get_files_dir() + "BackgroundImage/"

## 日志目录
static func get_logs_dir() -> String:
	return get_files_dir() + "Logs/"

## 设置目录
static func get_settings_dir() -> String:
	return get_files_dir() + "Settings/"

# ============ 特定文件路径 ============

## 用户配置文件路径
static func get_user_config_path() -> String:
	return get_files_dir() + "settings.ini"

# ============ 目录操作工具 ============

## 确保目录存在（不存在则递归创建）
## 支持 user:// 和 Android 绝对路径
## 返回: true 表示目录已存在或创建成功
static func ensure_dir_exists(dir_path: String) -> bool:
	if DirAccess.dir_exists_absolute(dir_path):
		return true
	
	var error = DirAccess.make_dir_recursive_absolute(dir_path)
	if error == OK:
		return true
	else:
		push_error("[PathHelper] Failed to create directory: %s (Error: %d)" % [dir_path, error])
		return false

## 检查文件是否存在（兼容所有路径格式）
static func file_exists(file_path: String) -> bool:
	return FileAccess.file_exists(file_path)

## 检查目录是否存在（兼容所有路径格式）
static func dir_exists(dir_path: String) -> bool:
	return DirAccess.dir_exists_absolute(dir_path)

# ============ 路径转换工具 ============

## 将 user://files/ 前缀的路径转换为当前平台的实际路径
## 用于兼容旧代码中可能残留的 user:// 路径
static func resolve_user_path(path: String) -> String:
	if is_android() and path.begins_with("user://"):
		# 将 user:// 替换为 Android 外部存储基础路径
		return path.replace("user://", get_base_dir())
	return path

## 获取调试信息字符串（用于日志输出）
static func get_debug_info() -> String:
	var info = "[PathHelper] Platform: %s\n" % OS.get_name()
	info += "[PathHelper] Base dir: %s\n" % get_base_dir()
	info += "[PathHelper] Files dir: %s\n" % get_files_dir()
	info += "[PathHelper] Is Android: %s\n" % str(is_android())
	if is_android():
		info += "[PathHelper] User data dir: %s\n" % OS.get_user_data_dir()
		info += "[PathHelper] Package: %s\n" % PACKAGE_NAME
	return info
