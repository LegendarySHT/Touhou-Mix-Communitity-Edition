## 日志系统
## 用于统一的日志记录和调试输出
class_name GameLogger
extends Node

## 单例实例
static var instance: GameLogger

## 日志级别
enum LogLevel {
	DEBUG = 0,
	INFO = 1,
	WARNING = 2,
	ERROR = 3
}

## 当前日志级别（低于此级别的日志会被忽略）
var current_level: LogLevel = LogLevel.DEBUG

## 是否输出到文件
var log_to_file: bool = true

## 日志文件路径
var log_file_path: String = "user://logs/game.log"

## 日志前缀映射
var level_names = {
	LogLevel.DEBUG: "[DEBUG]",
	LogLevel.INFO: "[INFO]",
	LogLevel.WARNING: "[WARN]",
	LogLevel.ERROR: "[ERROR]"
}

## 日志颜色映射
var level_colors = {
	LogLevel.DEBUG: "#CCCCCC",
	LogLevel.INFO: "#FFFFFF",
	LogLevel.WARNING: "#FFFF00",
	LogLevel.ERROR: "#FF0000"
}

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
	add_to_group("singleton")
	_ensure_log_directory()

## 确保日志目录存在
func _ensure_log_directory() -> void:
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("user://logs"):
		dir.make_dir("user://logs")

## 调试日志
func debug(message: String, context: String = "") -> void:
	_log(LogLevel.DEBUG, message, context)

## 信息日志
func info(message: String, context: String = "") -> void:
	_log(LogLevel.INFO, message, context)

## 警告日志
func warning(message: String, context: String = "") -> void:
	_log(LogLevel.WARNING, message, context)

## 错误日志
func error(message: String, context: String = "") -> void:
	_log(LogLevel.ERROR, message, context)

## 内部日志实现
func _log(level: LogLevel, message: String, context: String = "") -> void:
	# 检查日志级别
	if level < current_level:
		return
	
	# 构建日志消息
	var timestamp = Time.get_datetime_string_from_system()
	var level_prefix = level_names[level]
	var full_message = "%s %s [%s] %s" % [timestamp, level_prefix, context, message]
	
	# 控制台输出
	print(full_message)
	
	# 文件输出
	if log_to_file:
		_write_to_file(full_message)

## 写入到日志文件
func _write_to_file(message: String) -> void:
	var file = FileAccess.open(log_file_path, FileAccess.READ_WRITE)
	if file == null:
		push_error("Failed to open log file: %s" % log_file_path)
		return
	
	file.seek_end()
	file.store_line(message)

## 设置日志级别
func set_log_level(level: LogLevel) -> void:
	current_level = level

## 清空日志文件
func clear_log_file() -> void:
	var file = FileAccess.open(log_file_path, FileAccess.WRITE)
	file.truncate_64(0)

## 获取日志文件内容
func get_log_contents() -> String:
	var file = FileAccess.open(log_file_path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
