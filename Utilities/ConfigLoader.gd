## 配置加载器工具
## 用于加载和管理INI配置文件
class_name ConfigLoader
extends Node

## 配置版本号
const CONFIG_VERSION = "1.0.0"

## 配置缓存
var configs: Dictionary[String, Dictionary] = {}

## 加载INI配置文件
func load_config(file_path: String) -> Dictionary:
	# 检查缓存
	if configs.has(file_path):
		return configs[file_path]
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to load config: %s" % file_path)
		return {}
	
	var content = file.get_as_text()
	var result = _parse_ini(content)
	
	# 缓存结果
	configs[file_path] = result
	
	return result

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

## 获取配置值
func get_value(config: Dictionary, section: String, key: String, default: Variant = "") -> Variant:
	if config.has(section) and config[section].has(key):
		return config[section][key]
	return default

## 获取整数值
func get_int(config: Dictionary, section: String, key: String, default: int = 0) -> int:
	var value = get_value(config, section, key, str(default))
	return int(value)

## 获取浮点值
func get_float(config: Dictionary, section: String, key: String, default: float = 0.0) -> float:
	var value = get_value(config, section, key, str(default))
	return float(value)

## 获取布尔值
func get_bool(config: Dictionary, section: String, key: String, default: bool = false) -> bool:
	var value = get_value(config, section, key, str(default)).to_lower()
	return value in ["true", "1", "yes"]

## 清空缓存
func clear_cache() -> void:
	configs.clear()

## 保存配置到INI文件
func save_config(file_path: String, config: Dictionary) -> bool:
	var content = _serialize_ini(config)
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to save config: %s (Error: %d)" % [file_path, FileAccess.get_open_error()])
		return false
	
	file.store_string(content)
	file.close()
	
	# 更新缓存
	configs[file_path] = config
	
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

## 设置单个配置值
func set_value(config: Dictionary, section: String, key: String, value: Variant) -> void:
	if not config.has(section):
		config[section] = {}
	config[section][key] = value

## 合并配置与默认值（用于兼容性）
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

## 检查并迁移配置版本
func check_and_migrate(config: Dictionary, file_path: String) -> Dictionary:
	var version = get_value(config, "Game", "config_version", "0.0.0")
	
	if version == CONFIG_VERSION:
		return config
	
	# 版本不匹配，进行迁移
	print("[ConfigLoader] Migrating config from version %s to %s" % [version, CONFIG_VERSION])
	
	# 加载默认配置
	var default_path = "res://Resources/Config/config.ini"
	var default_config = load_config(default_path) if file_path != default_path else {}
	
	# 合并配置（保留用户设置，添加新的默认值）
	var migrated = merge_with_defaults(config, default_config)
	
	# 更新版本号
	set_value(migrated, "Game", "config_version", CONFIG_VERSION)
	
	# 保存迁移后的配置
	save_config(file_path, migrated)
	
	return migrated
