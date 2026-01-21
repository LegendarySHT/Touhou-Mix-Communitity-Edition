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

## 日志文件路径（会在 _ready 中初始化）
var log_file_path: String = ""

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
	
	# 初始化日志文件路径（包含日期）
	var date = Time.get_date_string_from_system()
	var logs_dir = "user://files/Logs/"  # 默认路径

	# 如果 FileSystemManager 已初始化则使用其目录，否则回落到默认
	if FileSystemManager and FileSystemManager.instance: #由于初始化顺序问题，这段检查事实上永远不会通过，但是先留着吧:(
		logs_dir = FileSystemManager.instance.get_logs_directory()

	log_file_path = logs_dir.path_join("game_%s.log" % date)
	
	_ensure_log_directory()

## 确保日志目录存在
func _ensure_log_directory() -> void:
	# 获取日志目录路径
	var log_dir = log_file_path.get_base_dir()
	var dir = DirAccess.open("user://")
	
	if dir == null:
		push_error("Failed to open user:// directory")
		return
	
	# 创建日志目录（如果不存在）
	var relative_path = log_dir.replace("user://", "")
	if not dir.dir_exists(relative_path):
		var new_error = dir.make_dir_recursive(relative_path)
		if new_error != OK:
			push_error("Failed to create logs directory: %s" % new_error)
			return
	
	# 确保日志文件存在，或者追加到现有文件
	if not FileAccess.file_exists(log_file_path):
		var file = FileAccess.open(log_file_path, FileAccess.WRITE)
		if file == null:
			push_error("Failed to create log file: %s" % log_file_path)
		else:
			file.store_line("=== Game Logger Started at %s ===" % Time.get_datetime_string_from_system())
			file.close()
	else:
		# 文件已存在，追加一个会话开始标记
		var file = FileAccess.open(log_file_path, FileAccess.READ_WRITE)
		if file:
			file.seek_end()
			file.store_line("\n=== New Session Started at %s ===" % Time.get_datetime_string_from_system())
			file.close()


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
	# 检查日志目录是否存在
	if not FileAccess.file_exists(log_file_path):
		_ensure_log_directory()
	
	# 尝试以追加模式打开（WRITE模式会从头开始覆盖）
	var file = FileAccess.open(log_file_path, FileAccess.READ_WRITE)
	if file == null:
		# 如果失败，尝试创建新文件
		file = FileAccess.open(log_file_path, FileAccess.WRITE)
		if file == null:
			push_error("Failed to open or create log file: %s" % log_file_path)
			return
	
	# 移动到文件末尾以追加
	if file.get_length() > 0:
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
