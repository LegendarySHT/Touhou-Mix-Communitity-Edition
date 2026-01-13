## 配置加载器工具
## 用于加载和管理INI配置文件
class_name ConfigLoader
extends Node

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
