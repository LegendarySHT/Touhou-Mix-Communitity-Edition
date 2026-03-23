## 统一配置管理器（单例）
## 集中管理所有INI/JSON配置文件的读取和写入，内部自动维护当前活跃配置
## 
## 新API使用方式（推荐）：
##   ConfigManager.instance.load_and_set_current(ConfigManager.DEFAULT_CONFIG_PATH)
##   var lane_count = ConfigManager.instance.get_int("Lane", "lane_count", 12)
##   ConfigManager.instance.set_value_and_notify("Lane", "lane_count", 16)
##
## 兼容旧API（传入config参数）：
##   var config = ConfigManager.instance.load_config(ConfigManager.DEFAULT_CONFIG_PATH)
##   var lane_count = ConfigManager.instance.get_int("Lane", "lane_count", 12, config)
##
## 配置变更通知：
##   EventBus.instance.config_changed.connect(_on_config_changed)
##   func _on_config_changed(key: String, section: String, value: Variant):
##       print("配置已更改: [%s] %s = %s" % [section, key, value])

class_name ConfigManager
extends Node

# ============ 单例实现 ============

static var instance: ConfigManager:
	get:
		if _instance == null:
			_instance = ConfigManager.new()
			_instance.add_to_group("singletons")
		return _instance

static var _instance: ConfigManager = null

func _init() -> void:
	if _instance != null:
		push_error("ConfigManager is a singleton, use ConfigManager.instance instead")
		return

# ============ 配置路径 ============

## 默认配置文件路径（项目内置）
const DEFAULT_CONFIG_PATH = "res://Resources/Config/config.ini"

## 用户配置文件路径（通过 PathHelper 动态获取，兼容 Android 外部存储）
## 使用 getter 确保运行时才求值
static var USER_CONFIG_PATH: String:
	get: return PathHelper.get_user_config_path()

## 音源文件目录（通过 PathHelper 动态获取）
static var SOUNDFONT_DIR: String:
	get: return PathHelper.get_soundfont_dir()

## 配置版本号
const CONFIG_VERSION = "1.0.0"

# ============ 内部状态 ============

## 配置缓存 - 避免重复解析同一文件
var configs: Dictionary = {}

## 当前活跃的配置（合并了用户配置和默认配置）
var _current_config: Dictionary = {}

# ============ 核心配置加载方法 ============

## 加载INI配置文件
## 若缓存中存在则直接返回，否则解析文件并缓存
## Android 平台特殊处理：res:// 路径资源在 PCK 包中
func load_config(file_path: String) -> Dictionary:
	# 检查缓存
	if configs.has(file_path):
		return configs[file_path]
	
	var content: String = ""
	
	# Android 平台 res:// 路径需要特殊处理
	if file_path.begins_with("res://"):
		# 检查资源是否存在于 PCK 包中
		if not FileAccess.file_exists(file_path):
			push_error("Config file not found in PCK: %s" % file_path)
			GameLogger.instance.error("Config file not found in PCK: %s [Check export settings]" % file_path, "ConfigManager")
			return {}
		
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			var error_code = FileAccess.get_open_error()
			push_error("Failed to open config from PCK: %s (Error: %d)" % [file_path, error_code])
			GameLogger.instance.error("Failed to open PCK config [%s] with error code %d" % [file_path, error_code], "ConfigManager")
			if file:
				file.close()
			return {}
		
		if file.get_length() == 0:
			GameLogger.instance.warning("Config file in PCK is empty: %s" % file_path, "ConfigManager")
			file.close()
			return {}
		
		content = file.get_as_text()
		file.close()
		GameLogger.instance.info("Config loaded from PCK: %s (size: %d bytes)" % [file_path, content.length()], "ConfigManager")
	else:
		# user:// 路径的常规加载
		if not FileAccess.file_exists(file_path):
			GameLogger.instance.warning("Config file not found in user://: %s" % file_path, "ConfigManager")
			return {}
		
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			var error_code = FileAccess.get_open_error()
			push_error("Failed to load config: %s (Error: %d)" % [file_path, error_code])
			GameLogger.instance.error("Failed to open user config [%s] with error code %d" % [file_path, error_code], "ConfigManager")
			return {}
		
		content = file.get_as_text()
		file.close()
		GameLogger.instance.info("Config loaded from user://: %s" % file_path, "ConfigManager")
	
	if content.is_empty():
		push_error("Config content is empty: %s" % file_path)
		GameLogger.instance.error("Config file is empty: %s" % file_path, "ConfigManager")
		return {}
	
	var result = _parse_ini(content)
	
	if result.is_empty():
		GameLogger.instance.warning("Config parsed to empty dictionary: %s" % file_path, "ConfigManager")
	
	# 缓存结果
	configs[file_path] = result
	
	return result

## 加载配置文件并设置为当前活跃配置
## 优先加载用户配置，如果不存在或为空则加载默认配置
## 然后用默认配置补充缺失的部分
func load_and_set_current(_file_path: String = "") -> Dictionary:
	# 清除缓存以确保读取最新的文件内容
	configs.clear()
	
	var user_config = {}
	var default_config = {}
	
	# 优先加载用户配置
	if FileAccess.file_exists(USER_CONFIG_PATH):
		user_config = load_config(USER_CONFIG_PATH)
		if not user_config.is_empty():
			GameLogger.instance.info("User configuration loaded from %s" % USER_CONFIG_PATH, "ConfigManager")
		else:
			GameLogger.instance.warning("User configuration file is empty, will use default", "ConfigManager")
	else:
		GameLogger.instance.info("User configuration file not found at %s, will use default" % USER_CONFIG_PATH, "ConfigManager")
	
	# 加载默认配置用于补充
	default_config = load_config(DEFAULT_CONFIG_PATH)
	if default_config.is_empty():
		push_error("Failed to load default configuration")
		return {}
	
	# 合并配置：用户配置优先，默认配置补充缺失部分
	_current_config = merge_with_defaults(user_config, default_config)
	
	# 调试：打印当前配置的部分内容
	var section_count = _current_config.size()
	GameLogger.instance.info("Current configuration initialized with %d sections" % section_count, "ConfigManager")
	
	return _current_config

## 解析INI格式
func _parse_ini(content: String) -> Dictionary:
	var result: Dictionary = {}
	var current_section: String = ""
	
	for line in content.split("\n"):
		line = line.strip_edges()
		
		# 跳过空行和注释
		if line.is_empty() or line.begins_with("#"):
			continue
		
		# 处理段标题
		if line.begins_with("[") and line.ends_with("]"):
			current_section = line.substr(1, line.length() - 2)
			result[current_section] = {}
			continue
		
		# 处理键值对
		if "=" in line:
			var parts = line.split("=", true, 1)
			var key = parts[0].strip_edges()
			var value = parts[1].strip_edges()
			
			# 移除引号
			if value.begins_with("\"") and value.ends_with("\""):
				value = value.substr(1, value.length() - 2)
			
			if not current_section.is_empty():
				result[current_section][key] = value
	
	return result

# ============ 配置读取方法 ============

## 获取配置值（使用当前活跃配置或指定配置）
## 简化用法：get_value("Audio", "master_volume", 80)
## 兼容用法：get_value("Audio", "master_volume", 80, some_config)
func get_value(section: String, key: String, default: Variant = "", config: Variant = null) -> Variant:
	if config == null or not (config is Dictionary):
		config = _current_config
	
	if config.has(section) and config[section].has(key):
		return config[section][key]
	
	GameLogger.instance.warning("Config key not found: [%s] %s, using default value: %s" % [section, key, str(default)], "ConfigManager")
	return default

## 获取整数值
func get_int(section: String, key: String, default: int = 0, config: Variant = null) -> int:
	var value = get_value(section, key, str(default), config)
	return int(value)

## 获取浮点值
func get_float(section: String, key: String, default: float = 0.0, config: Variant = null) -> float:
	var value = get_value(section, key, str(default), config)
	return float(value)

## 获取布尔值
func get_bool(section: String, key: String, default: bool = false, config: Variant = null) -> bool:
	var value = get_value(section, key, str(default), config).to_lower()
	return value in ["true", "1", "yes"]

func get_string(section: String, key: String, default: String = "", config: Variant = null) -> String:
	return str(get_value(section, key, default, config))

# ============ 配置写入方法 ============

## 设置配置值并发送变更通知（使用当前活跃配置或指定配置）
## 简化用法：set_value_and_notify("Audio", "master_volume", 80)
## 兼容用法：set_value_and_notify("Audio", "master_volume", 80, some_config)
func set_value_and_notify(section: String, key: String, value: Variant, config: Variant = null) -> void:
	if config == null:
		config = _current_config
	
	if not config.has(section):
		config[section] = {}
	
	var old_value = config[section].get(key, null)
	config[section][key] = value
	
	# 只有当值确实改变时才发送通知
	# 使用字符串比较避免类型不匹配错误（例如 "0" vs 0）
	var old_value_str = str(old_value) if old_value != null else ""
	var new_value_str = str(value)
	
	if old_value_str != new_value_str:
		if EventBus.instance != null:
			EventBus.instance.config_changed.emit(key, section, value)
		GameLogger.instance.info("Config changed: [%s] %s = %s" % [section, key, str(value)], "ConfigManager")

## 设置单个配置值（不发送通知）
## 用于批量修改配置后再统一保存，避免发送过多信号
func set_value(section: String, key: String, value: Variant, config: Variant = null) -> void:
	if config == null:
		config = _current_config
	
	if not config.has(section):
		config[section] = {}
	config[section][key] = value

## 保存配置到INI文件
func save_config(file_path: String, config: Variant = null) -> bool:
	if config == null:
		config = _current_config
	
	var content = _serialize_ini(config)
	
	# 确保目标目录存在（Android 外部存储路径可能首次使用时不存在）
	var dir_path = file_path.get_base_dir()
	PathHelper.ensure_dir_exists(dir_path)
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to save config: %s (Error: %d)" % [file_path, FileAccess.get_open_error()])
		return false
	
	file.store_string(content)
	file.close()
	
	# 清除该文件的缓存，避免后续加载读到旧缓存
	# 同时更新为最新的配置
	configs[file_path] = config
	if file_path == USER_CONFIG_PATH:
		_current_config = config
	
	GameLogger.instance.info("Config saved to: %s" % file_path, "ConfigManager")
	return true

## 序列化配置字典为INI格式
func _serialize_ini(config: Dictionary) -> String:
	var result = ""
	
	for section in config.keys():
		result += "[%s]\n" % section
		
		var section_data = config[section]
		if section_data is Dictionary:
			for key in section_data.keys():
				var value = section_data[key]
				
				# 处理需要引号的值
				if value is String and (" " in value or value.is_empty()):
					result += "%s = \"%s\"\n" % [key, value]
				else:
					result += "%s = %s\n" % [key, str(value)]
		
		result += "\n"
	
	return result

# ============ 配置管理高级方法 ============

## 合并配置与默认值（用于兼容性）
## 将用户配置与默认配置合并，用户设置优先
func merge_with_defaults(user_config: Dictionary, default_config: Dictionary) -> Dictionary:
	var merged = default_config.duplicate(true)
	
	for section in user_config.keys():
		if not merged.has(section):
			merged[section] = {}
		
		var user_section = user_config[section]
		if user_section is Dictionary:
			for key in user_section.keys():
				merged[section][key] = user_section[key]
	
	return merged

## 清空缓存
func clear_cache() -> void:
	configs.clear()
	GameLogger.instance.info("Config cache cleared", "ConfigManager")

## 获取当前活跃配置
func get_current_config() -> Dictionary:
	return _current_config

## 重新加载配置（优先用户配置）
## 清空缓存后重新加载用户配置和默认配置，然后合并以确保完整性
func reload_config() -> bool:
	# 清除所有缓存以确保读取最新文件
	clear_cache()
	
	# 优先加载用户配置
	var user_config = {}
	if FileAccess.file_exists(USER_CONFIG_PATH):
		user_config = load_config(USER_CONFIG_PATH)
		if not user_config.is_empty():
			GameLogger.instance.info("User configuration reloaded from %s" % USER_CONFIG_PATH, "ConfigManager")
		else:
			GameLogger.instance.warning("User configuration file is empty, using default", "ConfigManager")
	else:
		GameLogger.instance.warning("User configuration file not found at %s, using default" % USER_CONFIG_PATH, "ConfigManager")
	
	# 加载默认配置来补充缺失部分
	var default_config = load_config(DEFAULT_CONFIG_PATH)
	if default_config.is_empty():
		push_error("Failed to load default configuration")
		return false
	
	# 合并配置：用户配置优先
	_current_config = merge_with_defaults(user_config, default_config)
	
	# 发送批量变更通知
	if EventBus.instance != null:
		EventBus.instance.config_changed.emit("*", "all", null)  # 通配符表示全量变更
	
	GameLogger.instance.info("Configuration reload complete with user priority", "ConfigManager")
	return true

## 检查并迁移配置版本
## 当用户配置版本过旧时，从默认配置中恢复缺失部分
func check_and_migrate(config: Variant = null, file_path: String = "") -> Dictionary:
	if config == null:
		config = _current_config
	
	var version = get_value("Game", "config_version", "0.0.0", config)
	
	if version == CONFIG_VERSION:
		GameLogger.instance.debug("Configuration version is current", "ConfigManager")
		return config
	
	# 版本不匹配，进行迁移
	GameLogger.instance.info("Migrating config from version %s to %s" % [version, CONFIG_VERSION], "ConfigManager")
	
	# 加载默认配置以获取新增部分
	var default_config = load_config(DEFAULT_CONFIG_PATH)
	if default_config.is_empty():
		push_error("Failed to load default config for migration")
		return config
	
	# 合并配置（保留用户设置，添加新的默认值）
	var migrated = merge_with_defaults(config, default_config)
	
	# 更新版本号
	set_value("Game", "config_version", CONFIG_VERSION, migrated)
	
	# 保存迁移后的配置到用户配置文件
	var save_path = USER_CONFIG_PATH if file_path.is_empty() else file_path
	if save_config(save_path, migrated):
		GameLogger.instance.info("Configuration migrated and saved to %s" % save_path, "ConfigManager")
	else:
		GameLogger.instance.warning("Failed to save migrated configuration", "ConfigManager")
	
	# 更新当前活跃配置
	_current_config = migrated
	
	return migrated

# ============ JSON 文件操作方法 ============

## 加载JSON文件
func load_json_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		GameLogger.instance.warning("Failed to open JSON file: %s" % file_path, "ConfigManager")
		return {}
	
	var content = file.get_as_text()
	var json = JSON.parse_string(content)
	
	if json == null:
		GameLogger.instance.warning("Failed to parse JSON file: %s" % file_path, "ConfigManager")
		return {}
	
	return json if json is Dictionary else {}

## 保存JSON文件（合并模式：保留原有字段，补充新字段）
## 参数merge_existing决定是否合并现有文件内容
func save_json_file(file_path: String, data: Dictionary, merge_existing: bool = true) -> bool:
	var final_data = data
	
	# 如果启用合并模式且文件存在，先读取现有内容
	if merge_existing and FileAccess.file_exists(file_path):
		var existing = load_json_file(file_path)
		if not existing.is_empty():
			# 深度合并：保留所有原有字段，覆盖或添加新字段
			for key in data.keys():
				existing[key] = data[key]
			final_data = existing
	
	# 序列化为JSON字符串
	var json_str = JSON.stringify(final_data)
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to save JSON file: %s (Error: %d)" % [file_path, FileAccess.get_open_error()])
		return false
	
	file.store_string(json_str)
	file.close()
	
	GameLogger.instance.info("JSON file saved to: %s" % file_path, "ConfigManager")
	return true
