## INI 解析工具
## 提供统一的 INI 格式文本解析
class_name IniParser
extends RefCounted

## 解析 INI 格式文本为 {section: {key: value}} Dictionary
## 合并自 ConfigManager._parse_ini 和 SkinManager._parse_skin_ini
static func parse(content: String) -> Dictionary:
	var result: Dictionary = {}
	var current_section: String = ""
	for line in content.split("\n"):
		line = line.strip_edges()
		# 支持 # 与 ; 两种行注释（; 为 INI 标准注释符）
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			current_section = line.substr(1, line.length() - 2)
			result[current_section] = {}
			continue
		if "=" in line:
			var parts = line.split("=", true, 1)
			var key = parts[0].strip_edges()
			var value = parts[1].strip_edges()
			if value.begins_with("\"") and value.ends_with("\""):
				value = _unescape_value(value.substr(1, value.length() - 2))
			if not current_section.is_empty():
				result[current_section][key] = value
	return result

## 反转 ConfigManager._serialize_ini 的转义（\" \\ \n \r \t）
static func _unescape_value(value: String) -> String:
	var out := ""
	var i := 0
	while i < value.length():
		var c := value[i]
		if c == "\\" and i + 1 < value.length():
			var n := value[i + 1]
			match n:
				"n":
					out += "\n"
				"r":
					out += "\r"
				"t":
					out += "\t"
				_:
					out += n
			i += 2
		else:
			out += c
			i += 1
	return out
