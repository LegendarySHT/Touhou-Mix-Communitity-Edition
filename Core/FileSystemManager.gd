## 文件系统管理器
## 负责管理 user:// 目录下的游戏资源（谱面、皮肤、音源、日志等）
## 支持自动初始化默认内容和玩家自定义内容的热加载
extends Node

class_name FileSystemManager

## 单例实例
static var instance: FileSystemManager

## ========== 目录常量定义 ==========
const BASE_DIR = "user://"
const CHARTS_DIR = "user://Charts/"
const SKINS_DIR = "user://Skins/"
const SOUNDFONT_DIR = "user://Soundfont/"
const BACKGROUND_DIR = "user://BackgroundImage/"
const LOGS_DIR = "user://Logs/"
const SETTINGS_DIR = "user://Settings/"

## 默认资源源目录
const DEFAULT_CHARTS_SRC = "res://Resources/midis_info/"
const DEFAULT_SKINS_SRC = "res://Resources/Skins/"
const DEFAULT_SOUNDFONT_SRC = "res://Resources/Soundfont/"
const DEFAULT_BACKGROUND_SRC = "res://Resources/BackgroundImage/"

## ========== 资源索引 ==========
## 谱面索引 {chart_id: ChartMetadata}
var charts_index: Dictionary = {}

## 皮肤索引 {skin_name: SkinMetadata}
var skins_index: Dictionary = {}

## 音源索引 {soundfont_name: String(path)}
var soundfonts_index: Dictionary = {}

## 背景图索引 {background_name: String(path)}
var backgrounds_index: Dictionary = {}

## ========== 状态标志 ==========
var is_initialized: bool = false
var is_scanning: bool = false

## ========== 信号 ==========
signal initialization_complete
signal resources_ready
signal chart_added(chart_id: String, metadata: Dictionary)
signal skin_installed(skin_name: String)
signal resource_scan_completed(resource_type: String, count: int)
signal resource_error(error_message: String)

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
	
	add_to_group("singleton")
	
	GameLogger.instance.info("FileSystemManager initialized", "FileSystemMGR")

## 初始化目录结构
## 检查并创建所有必需的目录，如果目录不存在则创建并填充默认资源
func initialize_directory_structure() -> void:
	if is_initialized:
		GameLogger.instance.warning("FileSystemManager already initialized", "FileSystemMGR")
		return
	
	GameLogger.instance.info("Initializing directory structure...", "FileSystemMGR")
	
	# 创建所有必需目录
	var directories = [
		CHARTS_DIR,
		SKINS_DIR,
		SOUNDFONT_DIR,
		BACKGROUND_DIR,
		LOGS_DIR,
		SETTINGS_DIR
	]
	
	for dir_path in directories:
		_ensure_directory_exists(dir_path)
	
	# 检查并复制默认资源（异步）
	_check_and_copy_default_resources()
	
	is_initialized = true
	initialization_complete.emit()
	
	GameLogger.instance.info("Directory structure initialized", "FileSystemMGR")

## 确保目录存在，不存在则创建
func _ensure_directory_exists(dir_path: String) -> bool:
	var dir = DirAccess.open(BASE_DIR)
	if dir == null:
		GameLogger.instance.error("Failed to open base directory: %s" % BASE_DIR, "FileSystemMGR")
		resource_error.emit("Failed to open base directory")
		return false
	
	# 提取相对路径
	var relative_path = dir_path.replace(BASE_DIR, "")
	
	if not dir.dir_exists(relative_path):
		var error = dir.make_dir_recursive(relative_path)
		if error == OK:
			GameLogger.instance.info("Created directory: %s" % dir_path, "FileSystemMGR")
			return true
		else:
			GameLogger.instance.error("Failed to create directory: %s (Error: %d)" % [dir_path, error], "FileSystemMGR")
			resource_error.emit("Failed to create directory: %s" % dir_path)
			return false
	
	return true

## 检查并复制默认资源
func _check_and_copy_default_resources() -> void:
	# 使用线程异步处理，避免阻塞启动
	var thread = Thread.new()
	thread.start(_copy_default_resources_thread)

## 线程函数：复制默认资源
func _copy_default_resources_thread() -> void:
	# 检查是否需要复制谱面
	if _is_directory_empty(CHARTS_DIR):
		GameLogger.instance.info("Charts directory is empty, copying default charts...", "FileSystemMGR")
		_copy_directory_contents(DEFAULT_CHARTS_SRC, CHARTS_DIR, "json")
	
	# 检查是否需要复制皮肤
	if _is_directory_empty(SKINS_DIR):
		GameLogger.instance.info("Skins directory is empty, copying default skins...", "FileSystemMGR")
		_copy_directory_recursive(DEFAULT_SKINS_SRC, SKINS_DIR)
	
	# 检查是否需要复制音源
	if _is_directory_empty(SOUNDFONT_DIR):
		GameLogger.instance.info("Soundfont directory is empty, copying default soundfonts...", "FileSystemMGR")
		_copy_directory_contents(DEFAULT_SOUNDFONT_SRC, SOUNDFONT_DIR, "sf2")
	
	# 检查是否需要复制背景图
	if _is_directory_empty(BACKGROUND_DIR):
		GameLogger.instance.info("Background directory is empty, copying default backgrounds...", "FileSystemMGR")
		_copy_directory_contents(DEFAULT_BACKGROUND_SRC, BACKGROUND_DIR, "jpg,png")
	
	# 完成后扫描资源
	call_deferred("_scan_all_resources")

## 检查目录是否为空
func _is_directory_empty(dir_path: String) -> bool:
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return true
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not file_name.begins_with("."):
			dir.list_dir_end()
			return false
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return true

## 复制目录内容（仅顶层文件，按扩展名过滤）
func _copy_directory_contents(src_dir: String, dest_dir: String, extensions: String) -> void:
	var dir = DirAccess.open(src_dir)
	if dir == null:
		GameLogger.instance.warning("Source directory not found: %s" % src_dir, "FileSystemMGR")
		return
	
	var ext_list = extensions.split(",")
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var copied_count = 0
	
	while file_name != "":
		if not dir.current_is_dir() and not file_name.begins_with("."):
			var file_ext = file_name.get_extension().to_lower()
			if ext_list.has(file_ext):
				var src_path = src_dir.path_join(file_name)
				var dest_path = dest_dir.path_join(file_name)
				if _copy_file(src_path, dest_path):
					copied_count += 1
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	GameLogger.instance.info("Copied %d files from %s to %s" % [copied_count, src_dir, dest_dir], "FileSystemMGR")

## 递归复制整个目录（包括子目录）
func _copy_directory_recursive(src_dir: String, dest_dir: String) -> void:
	var dir = DirAccess.open(src_dir)
	if dir == null:
		GameLogger.instance.warning("Source directory not found: %s" % src_dir, "FileSystemMGR")
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var copied_count = 0
	
	while file_name != "":
		if not file_name.begins_with("."):
			var src_path = src_dir.path_join(file_name)
			var dest_path = dest_dir.path_join(file_name)
			
			if dir.current_is_dir():
				# 递归复制子目录
				_ensure_directory_exists(dest_path)
				_copy_directory_recursive(src_path, dest_path)
			else:
				# 复制文件
				if _copy_file(src_path, dest_path):
					copied_count += 1
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	GameLogger.instance.info("Recursively copied %d files from %s" % [copied_count, src_dir], "FileSystemMGR")

## 复制单个文件
func _copy_file(src_path: String, dest_path: String) -> bool:
	var src_file = FileAccess.open(src_path, FileAccess.READ)
	if src_file == null:
		GameLogger.instance.warning("Failed to open source file: %s" % src_path, "FileSystemMGR")
		return false
	
	var content = src_file.get_buffer(src_file.get_length())
	src_file.close()
	
	var dest_file = FileAccess.open(dest_path, FileAccess.WRITE)
	if dest_file == null:
		GameLogger.instance.error("Failed to create destination file: %s" % dest_path, "FileSystemMGR")
		return false
	
	dest_file.store_buffer(content)
	dest_file.close()
	
	return true

## 扫描所有资源
func _scan_all_resources() -> void:
	if is_scanning:
		return
	
	is_scanning = true
	GameLogger.instance.info("Scanning all resources...", "FileSystemMGR")
	
	scan_charts()
	scan_skins()
	scan_soundfonts()
	scan_backgrounds()
	
	is_scanning = false
	resources_ready.emit()
	GameLogger.instance.info("All resources scanned and ready", "FileSystemMGR")

## 扫描谱面目录
func scan_charts() -> void:
	charts_index.clear()
	
	var dir = DirAccess.open(CHARTS_DIR)
	if dir == null:
		GameLogger.instance.warning("Failed to open charts directory", "FileSystemMGR")
		return
	
	dir.list_dir_begin()
	var folder_name = dir.get_next()
	var count = 0
	
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var chart_path = CHARTS_DIR.path_join(folder_name)
			var metadata = _load_chart_metadata(chart_path, folder_name)
			
			if metadata != null:
				charts_index[folder_name] = metadata
				count += 1
		
		folder_name = dir.get_next()
	
	dir.list_dir_end()
	
	# 同时扫描旧的 JSON 文件（向后兼容）
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var chart_id = file_name.get_basename()
			var json_path = CHARTS_DIR.path_join(file_name)
			var metadata = _load_chart_from_json(json_path, chart_id)
			
			if metadata != null:
				charts_index[chart_id] = metadata
				count += 1
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	resource_scan_completed.emit("charts", count)
	GameLogger.instance.info("Scanned %d charts" % count, "FileSystemMGR")

## 加载谱面元数据（从谱面文件夹）
func _load_chart_metadata(chart_path: String, chart_id: String) -> Dictionary:
	var json_path = chart_path.path_join(chart_id + ".json")
	
	# 检查必需文件是否存在
	if not FileAccess.file_exists(json_path):
		return {}
	
	# 读取 JSON 元数据
	var metadata = _load_chart_from_json(json_path, chart_id)
	if metadata.is_empty():
		return {}
	
	# 验证谱面完整性
	var required_files = [
		chart_path.path_join(chart_id + ".mid"),
		chart_path.path_join(chart_id + ".ogg"),
	]
	
	for file_path in required_files:
		if not FileAccess.file_exists(file_path):
			GameLogger.instance.warning("Chart %s missing required file: %s" % [chart_id, file_path], "FileSystemMGR")
			metadata["is_complete"] = false
			return metadata
	
	metadata["is_complete"] = true
	metadata["path"] = chart_path
	return metadata

## 从 JSON 文件加载谱面数据
func _load_chart_from_json(json_path: String, chart_id: String) -> Dictionary:
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		GameLogger.instance.warning("Failed to open chart JSON: %s" % json_path, "FileSystemMGR")
		return {}
	
	var content = file.get_as_text()
	var json = JSON.parse_string(content)
	file.close()
	
	if json == null:
		GameLogger.instance.warning("Failed to parse chart JSON: %s" % json_path, "FileSystemMGR")
		return {}
	
	return {
		"id": chart_id,
		"json_path": json_path,
		"data": json,
		"is_complete": false
	}

## 扫描皮肤目录
func scan_skins() -> void:
	skins_index.clear()
	
	var dir = DirAccess.open(SKINS_DIR)
	if dir == null:
		GameLogger.instance.warning("Failed to open skins directory", "FileSystemMGR")
		return
	
	dir.list_dir_begin()
	var folder_name = dir.get_next()
	var count = 0
	
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var skin_path = SKINS_DIR.path_join(folder_name)
			var metadata = _load_skin_metadata(skin_path, folder_name)
			
			if metadata != null and not metadata.is_empty():
				skins_index[folder_name] = metadata
				count += 1
		
		folder_name = dir.get_next()
	
	dir.list_dir_end()
	resource_scan_completed.emit("skins", count)
	GameLogger.instance.info("Scanned %d skins" % count, "FileSystemMGR")

## 加载皮肤元数据
func _load_skin_metadata(skin_path: String, skin_name: String) -> Dictionary:
	# 检查必需的皮肤文件
	var required_files = [
		"instant.png",
		"short.png",
		"long-f.png",
		"long-t.png",
		"long-b.png"
	]
	
	var metadata = {
		"name": skin_name,
		"path": skin_path,
		"is_complete": true,
		"missing_files": []
	}
	
	for file_name in required_files:
		var file_path = skin_path.path_join(file_name)
		if not FileAccess.file_exists(file_path):
			metadata["is_complete"] = false
			metadata["missing_files"].append(file_name)
	
	if not metadata["is_complete"]:
		GameLogger.instance.warning("Skin %s is incomplete, missing: %s" % [skin_name, metadata["missing_files"]], "FileSystemMGR")
	
	return metadata

## 扫描音源目录
func scan_soundfonts() -> void:
	soundfonts_index.clear()
	
	var dir = DirAccess.open(SOUNDFONT_DIR)
	if dir == null:
		GameLogger.instance.warning("Failed to open soundfont directory", "FileSystemMGR")
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var count = 0
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".sf2"):
			var soundfont_path = SOUNDFONT_DIR.path_join(file_name)
			var soundfont_name = file_name.get_basename()
			soundfonts_index[soundfont_name] = soundfont_path
			count += 1
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	resource_scan_completed.emit("soundfonts", count)
	GameLogger.instance.info("Scanned %d soundfonts" % count, "FileSystemMGR")

## 扫描背景图目录
func scan_backgrounds() -> void:
	backgrounds_index.clear()
	
	var dir = DirAccess.open(BACKGROUND_DIR)
	if dir == null:
		GameLogger.instance.warning("Failed to open background directory", "FileSystemMGR")
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var count = 0
	
	while file_name != "":
		if not dir.current_is_dir():
			var ext = file_name.get_extension().to_lower()
			if ext in ["jpg", "jpeg", "png", "webp"]:
				var bg_path = BACKGROUND_DIR.path_join(file_name)
				backgrounds_index[file_name.get_basename()] = bg_path
				count += 1
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	resource_scan_completed.emit("backgrounds", count)
	GameLogger.instance.info("Scanned %d backgrounds" % count, "FileSystemMGR")

## ========== 公共查询接口 ==========

## 获取谱面索引
func get_charts_index() -> Dictionary:
	return charts_index

## 获取皮肤索引
func get_skins_index() -> Dictionary:
	return skins_index

## 获取音源索引
func get_soundfonts_index() -> Dictionary:
	return soundfonts_index

## 获取背景图索引
func get_backgrounds_index() -> Dictionary:
	return backgrounds_index

## 获取谱面目录路径
func get_charts_directory() -> String:
	return CHARTS_DIR

## 获取日志目录路径
func get_logs_directory() -> String:
	return LOGS_DIR

## 获取设置目录路径
func get_settings_directory() -> String:
	return SETTINGS_DIR

## 重新扫描资源（热重载）
func rescan_resources() -> void:
	GameLogger.instance.info("Rescanning resources...", "FileSystemMGR")
	_scan_all_resources()

## 验证谱面完整性
func validate_chart(chart_id: String) -> bool:
	if not charts_index.has(chart_id):
		return false
	
	var metadata = charts_index[chart_id]
	return metadata.get("is_complete", false)

## 获取谱面路径
func get_chart_path(chart_id: String) -> String:
	if not charts_index.has(chart_id):
		return ""
	
	var metadata = charts_index[chart_id]
	return metadata.get("path", "")

## 获取皮肤路径
func get_skin_path(skin_name: String) -> String:
	if not skins_index.has(skin_name):
		return ""
	
	var metadata = skins_index[skin_name]
	return metadata.get("path", "")
