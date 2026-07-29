## 文件系统管理器
## 负责管理游戏资源目录（谱面、皮肤、音源、日志等）
## 支持自动初始化默认内容和玩家自定义内容的热加载
## Android 平台使用外部可见路径，其他平台使用 user://
extends Node

class_name FileSystemManager

## 单例实例
static var instance: FileSystemManager

## ========== 目录路径定义（通过 PathHelper 动态获取） ==========
## 使用 getter 确保运行时才求值，避免类加载期间 OS.has_feature() 未就绪的问题
static var BASE_DIR: String:
	get: return PathHelper.get_base_dir()
static var CHARTS_DIR: String:
	get: return PathHelper.get_charts_dir()
static var SKINS_DIR: String:
	get: return PathHelper.get_skins_dir()
static var SOUNDFONT_DIR: String:
	get: return PathHelper.get_soundfont_dir()
static var BACKGROUND_DIR: String:
	get: return PathHelper.get_background_dir()
static var LOGS_DIR: String:
	get: return PathHelper.get_logs_dir()
static var SETTINGS_DIR: String:
	get: return PathHelper.get_settings_dir()

## 默认资源源目录
const DEFAULT_CHARTS_SRC = "res://Resources/Charts/"
const DEFAULT_SOUNDFONT_SRC = "res://Resources/Soundfont/"
const DEFAULT_BACKGROUND_SRC = "res://Resources/BackgroundImage/"

## 图片文件扩展名列表（Godot 导出时会被转换为 .ctex，无法通过 FileAccess 直接读取）
const IMAGE_EXTENSIONS = ["jpg", "jpeg", "png", "webp"]

## .import 文件后缀（Godot 导出后，res:// 中的图片以 xxx.jpg.import 形式存在）
const IMPORT_SUFFIX = ".import"

## ========== 资源索引 ==========
## 谱面索引 {chart_id: ChartMetadata}
var charts_index: Dictionary = {}

## 音源索引 {soundfont_name: {path, size_mb, is_builtin}}
var soundfonts_index: Dictionary = {}

## 背景图索引 {background_name: String(path)}
var backgrounds_index: Dictionary = {}

## 封面纹理缓存 {cover_path: Texture2D}
## 避免同一封面文件被反复从磁盘加载（尤其是 user:// 路径每次都会创建新 ImageTexture）
var _cover_texture_cache: Dictionary = {}

## ========== 反向索引 ==========
## {chart_id: folder_name}
var _chart_id_to_folder: Dictionary = {}
## {file_hash: folder_name}
var _hash_to_folder: Dictionary = {}
## ========== 音频文件索引 ==========
## [{file_name, path, format, chart_id, song_name}]
var audio_files_index: Array[Dictionary] = []

## ========== 状态标志 ==========
var is_initialized: bool = false
var is_scanning: bool = false
var resources_scanned: bool = false  ## 标记资源扫描是否已完成

## ========== 信号 ==========
signal resources_ready

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
	
	add_to_group("singleton")
	
	# 输出平台信息以便调试
	var platform = OS.get_name()
	var user_data_dir = OS.get_user_data_dir()
	GLogger.info("Platform: %s" % platform, "FileSystemMGR")
	GLogger.info("User data directory: %s" % user_data_dir, "FileSystemMGR")
	GLogger.info("Base directory: %s" % BASE_DIR, "FileSystemMGR")
	GLogger.info("Charts directory: %s" % CHARTS_DIR, "FileSystemMGR")
	if PathHelper.is_android():
		GLogger.info("Android external storage enabled", "FileSystemMGR")
		GLogger.info(PathHelper.get_debug_info(), "FileSystemMGR")
	GLogger.info("FileSystemManager initialized", "FileSystemMGR")

## 检查关键 res:// 资源是否在导出包中存在（Android 调试用）
func check_critical_resources() -> void:
	GLogger.info("=== Checking critical resources in PCK ===", "FileSystemMGR")
	
	var critical_resources = {
		"Config": "res://Resources/Config/config.ini",
		"Charts Directory": DEFAULT_CHARTS_SRC,
		"Soundfont Directory": DEFAULT_SOUNDFONT_SRC,
		"Background Directory": DEFAULT_BACKGROUND_SRC,
		"Skins Directory": SkinManager.DEFAULT_SKINS_SRC
	}
	
	for resource_name in critical_resources.keys():
		var resource_path = critical_resources[resource_name]
		var exists = false
		
		# 检查文件或目录是否存在
		if resource_path.ends_with("/"):
			exists = DirAccess.dir_exists_absolute(resource_path)
		else:
			exists = FileAccess.file_exists(resource_path)
		
		var status = "✓ FOUND" if exists else "✗ MISSING"
		GLogger.info("%s: %s [%s]" % [resource_name, status, resource_path], "FileSystemMGR")
		
		if not exists:
			GLogger.error("Critical resource missing: %s - Check export settings!" % resource_name, "FileSystemMGR")
	
	GLogger.info("=== Resource check complete ===", "FileSystemMGR")

## 初始化目录结构（修改为异步等待资源复制完成）
func initialize_directory_structure() -> void:
	if is_initialized:
		GLogger.warning("FileSystemManager already initialized", "FileSystemMGR")
		return
	
	GLogger.info("Initializing directory structure...", "FileSystemMGR")
	
	# Android 平台：首先检查关键资源是否被正确导出
	check_critical_resources()
	
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
	
	# 异步复制默认资源（改为协程，不再开线程）
	await _check_and_copy_default_resources_async()

## 确保目录存在，不存在则创建
## 使用 make_dir_recursive_absolute 以兼容 Android 绝对路径
func _ensure_directory_exists(dir_path: String) -> bool:
	if DirAccess.dir_exists_absolute(dir_path):
		return true
	
	var error = DirAccess.make_dir_recursive_absolute(dir_path)
	if error == OK:
		GLogger.info("Created directory: %s" % dir_path, "FileSystemMGR")
		return true
	else:
		GLogger.error("Failed to create directory: %s (Error: %d)" % [dir_path, error], "FileSystemMGR")
		return false

## 异步检查并复制默认资源
func _check_and_copy_default_resources_async() -> void:
	# 复制谱面（若目录为空）
	if _is_directory_empty(CHARTS_DIR):
		GLogger.info("Charts directory is empty, copying default charts...", "FileSystemMGR")
		await _copy_default_charts_async()   # 改为异步版本
	
	# 复制皮肤（若目录为空）
	if _is_directory_empty(SKINS_DIR):
		GLogger.info("Skins directory is empty, copying default skins...", "FileSystemMGR")
		await _copy_directory_recursive_async(SkinManager.DEFAULT_SKINS_SRC, SKINS_DIR)
	
	# 音源目录：仅创建目录，不复制默认资源
	_ensure_directory_exists(SOUNDFONT_DIR)
	GLogger.info("Soundfont directory ready (no default resources copied)", "FileSystemMGR")
	
	# 复制背景图（若目录为空）
	if _is_directory_empty(BACKGROUND_DIR):
		GLogger.info("Background directory is empty, copying default backgrounds...", "FileSystemMGR")
		await _copy_directory_contents_async(DEFAULT_BACKGROUND_SRC, BACKGROUND_DIR, "jpg,jpeg,png,webp")
	
	# 所有复制完成后扫描资源
	# Convert external game data (THMIX) if present
	ExternalGameConverter.check_and_convert()
	
	call_deferred("_scan_all_resources")

## 异步复制所有默认谱面（在每个文件夹复制后让步）
func _copy_default_charts_async() -> void:
	var source_base = DEFAULT_CHARTS_SRC
	var dest_base = CHARTS_DIR
	
	if not DirAccess.dir_exists_absolute(source_base):
		GLogger.warning("Charts source directory not found in PCK", "FileSystemMGR")
		return
	
	GLogger.info("Starting to copy default charts from PCK...", "FileSystemMGR")
	
	var source_dir = DirAccess.open(source_base)
	if not source_dir:
		GLogger.error("Failed to open source charts directory", "FileSystemMGR")
		return
	
	source_dir.list_dir_begin()
	var chart_folder = source_dir.get_next()
	var copied_count = 0
	
	while chart_folder != "":
		if source_dir.current_is_dir() and not chart_folder.begins_with("."):
			var source_chart_path = source_base + chart_folder
			var dest_chart_path = dest_base + chart_folder
			
			if not DirAccess.dir_exists_absolute(dest_chart_path):
				DirAccess.make_dir_absolute(dest_chart_path)
			
			# 复制该文件夹内的所有文件（内部已改为可让步的版本）
			if await _copy_chart_files_from_pck_async(source_chart_path, dest_chart_path):
				copied_count += 1
			
			# 每处理完一个 chart 文件夹，让出一帧，保持界面响应
			await get_tree().process_frame
		
		chart_folder = source_dir.get_next()
	
	source_dir.list_dir_end()
	GLogger.info("Copied %d chart folders from PCK" % copied_count, "FileSystemMGR")

## 异步复制单个 chart 文件夹的所有文件（内部处理图片时使用资源加载器）
func _copy_chart_files_from_pck_async(source_path: String, dest_path: String) -> bool:
	var source_dir = DirAccess.open(source_path)
	if not source_dir:
		GLogger.warning("Failed to open chart folder: %s" % source_path, "FileSystemMGR")
		return false
	
	var success = false
	source_dir.list_dir_begin()
	var file_name = source_dir.get_next()
	
	while file_name != "":
		if not source_dir.current_is_dir():
			if _is_image_import_file(file_name):
				var original_name = _strip_import_suffix(file_name)
				var source_resource = source_path + "/" + original_name
				var dest_file = dest_path + "/" + original_name
				if _copy_image_via_resource_loader(source_resource, dest_file):
					success = true
			else:
				var source_file = source_path + "/" + file_name
				var dest_file = dest_path + "/" + file_name
				if _copy_file_from_pck(source_file, dest_file):
					success = true
			
			# 每复制一个文件后让出（可选，可减少卡顿感）
			await get_tree().process_frame
		
		file_name = source_dir.get_next()
	
	source_dir.list_dir_end()
	return success


## 检查文件是否为图片文件（基于扩展名）
static func _is_image_file(file_path: String) -> bool:
	var ext = file_path.get_extension().to_lower()
	return ext in IMAGE_EXTENSIONS

## 检查文件是否为图片的 .import 文件（Godot 导出后的形式）
## 例如: cover.jpg.import, instant.png.import
static func _is_image_import_file(file_name: String) -> bool:
	if not file_name.ends_with(IMPORT_SUFFIX):
		return false
	# 去掉 .import 后缀后检查原始扩展名
	var original_name = file_name.substr(0, file_name.length() - IMPORT_SUFFIX.length())
	return _is_image_file(original_name)

## 从 .import 文件名获取原始图片文件名
## cover.jpg.import → cover.jpg
static func _strip_import_suffix(file_name: String) -> String:
	if file_name.ends_with(IMPORT_SUFFIX):
		return file_name.substr(0, file_name.length() - IMPORT_SUFFIX.length())
	return file_name

## 通过 Godot 资源加载器复制图片文件（Android/导出兼容）
## Godot 导出时图片被导入系统转换为 .ctex（压缩纹理），原始 JPG/PNG 不在 PCK/APK 中
## 因此需要通过 ResourceLoader 加载纹理资源，再从 Image 对象重新保存为原始格式
func _copy_image_via_resource_loader(src_path: String, dest_path: String) -> bool:
	if not ResourceLoader.exists(src_path):
		GLogger.warning(
			"Image resource not found in PCK: %s" % src_path, "FileSystemMGR"
		)
		return false
	
	var texture = ResourceLoader.load(src_path, "Texture2D")
	if texture == null or not (texture is Texture2D):
		GLogger.warning(
			"Failed to load image as Texture2D: %s" % src_path, "FileSystemMGR"
		)
		return false
	
	var image: Image = (texture as Texture2D).get_image()
	if image == null:
		GLogger.warning(
			"Failed to get Image from texture: %s" % src_path, "FileSystemMGR"
		)
		return false
	
	# 根据目标文件扩展名选择保存格式
	var ext = dest_path.get_extension().to_lower()
	var error: Error
	
	match ext:
		"jpg", "jpeg":
			error = image.save_jpg(dest_path, 0.95)
		"png":
			error = image.save_png(dest_path)
		"webp":
			error = image.save_webp(dest_path)
		_:
			# 未知格式默认保存为 PNG（无损）
			error = image.save_png(dest_path)
	
	if error != OK:
		GLogger.error(
			"Failed to save image: %s (Error: %d)" % [dest_path, error], "FileSystemMGR"
		)
		return false
	
	#GLogger.info(
		#"Copied image via resource loader: %s" % dest_path.get_file(), "FileSystemMGR"
	#)
	return true

## 从 PCK 复制单个文件（关键方法）
## 注意：.import 图片文件应在目录遍历层处理，此方法作为防御性回退
func _copy_file_from_pck(source_path: String, dest_path: String) -> bool:
	# 跳过非图片的 .import 文件（无用的元数据）
	if source_path.ends_with(IMPORT_SUFFIX):
		if _is_image_import_file(source_path.get_file()):
			# .import 图片文件：转换为原始资源路径后通过 ResourceLoader 复制
			var original_source = _strip_import_suffix(source_path)
			var original_dest = _strip_import_suffix(dest_path)
			return _copy_image_via_resource_loader(original_source, original_dest)
		# 其他 .import 文件直接跳过
		return false
	
	# Android/导出兼容：res:// 下的图片文件需要通过资源加载器复制
	# 因为 Godot 导出时图片被转换为 .ctex，FileAccess 无法直接读取原始数据
	if source_path.begins_with("res://") and _is_image_file(source_path):
		return _copy_image_via_resource_loader(source_path, dest_path)
	
	# 非图片文件：使用 FileAccess 直接复制
	if not FileAccess.file_exists(source_path):
		GLogger.warning("Source file not found in PCK: %s" % source_path, "FileSystemMGR")
		return false
	
	var source_file = FileAccess.open(source_path, FileAccess.READ)
	if not source_file:
		var error = FileAccess.get_open_error()
		GLogger.warning(
			"Failed to read from PCK [%s], error code: %d" % [source_path, error],
			"FileSystemMGR"
		)
		return false
	
	var dest_file = FileAccess.open(dest_path, FileAccess.WRITE)
	if not dest_file:
		var error = FileAccess.get_open_error()
		GLogger.error(
			"Failed to write to user:// [%s], error code: %d" % [dest_path, error],
			"FileSystemMGR"
		)
		source_file.close()
		return false
	
	# 复制数据
	var file_size = source_file.get_length()
	if file_size > 0:
		var buffer = source_file.get_buffer(file_size)
		dest_file.store_buffer(buffer)
	
	source_file.close()
	dest_file.close()
	return true

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

## 异步复制目录内容（仅顶层文件）
func _copy_directory_contents_async(src_dir: String, dest_dir: String, extensions: String) -> void:
	if src_dir.begins_with("res://"):
		if not DirAccess.dir_exists_absolute(src_dir):
			GLogger.warning("Source directory not found in PCK: %s" % src_dir, "FileSystemMGR")
			return
	
	var dir = DirAccess.open(src_dir)
	if dir == null:
		GLogger.warning("Failed to open source directory: %s" % src_dir, "FileSystemMGR")
		return
	
	var ext_list = extensions.split(",")
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var copied_count = 0
	
	while file_name != "":
		if not dir.current_is_dir() and not file_name.begins_with("."):
			if _is_image_import_file(file_name):
				var original_name = _strip_import_suffix(file_name)
				var original_ext = original_name.get_extension().to_lower()
				if ext_list.has(original_ext):
					var src_resource = src_dir.path_join(original_name)
					var dest_path = dest_dir.path_join(original_name)
					if _copy_image_via_resource_loader(src_resource, dest_path):
						copied_count += 1
			else:
				var file_ext = file_name.get_extension().to_lower()
				if ext_list.has(file_ext):
					var src_path = src_dir.path_join(file_name)
					var dest_path = dest_dir.path_join(file_name)
					if _copy_file_from_pck(src_path, dest_path):
						copied_count += 1
			
			# 每复制一个文件后让步
			await get_tree().process_frame
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	GLogger.info("Copied %d files from %s to %s" % [copied_count, src_dir, dest_dir], "FileSystemMGR")

## 异步递归复制整个目录（在文件循环中让步）
func _copy_directory_recursive_async(src_dir: String, dest_dir: String) -> void:
	if src_dir.begins_with("res://"):
		if not DirAccess.dir_exists_absolute(src_dir):
			GLogger.warning("Source directory not found in PCK: %s" % src_dir, "FileSystemMGR")
			return
	
	var dir = DirAccess.open(src_dir)
	if dir == null:
		GLogger.warning("Failed to open source directory: %s" % src_dir, "FileSystemMGR")
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var copied_count = 0
	
	while file_name != "":
		if not file_name.begins_with("."):
			if dir.current_is_dir():
				var src_path = src_dir.path_join(file_name)
				var dest_path = dest_dir.path_join(file_name)
				_ensure_directory_exists(dest_path)
				await _copy_directory_recursive_async(src_path, dest_path)
			elif _is_image_import_file(file_name):
				var original_name = _strip_import_suffix(file_name)
				var src_resource = src_dir.path_join(original_name)
				var dest_path = dest_dir.path_join(original_name)
				if _copy_image_via_resource_loader(src_resource, dest_path):
					copied_count += 1
			else:
				var src_path = src_dir.path_join(file_name)
				var dest_path = dest_dir.path_join(file_name)
				if _copy_file_from_pck(src_path, dest_path):
					copied_count += 1
			
			# 每处理一个文件后让步
			await get_tree().process_frame
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	GLogger.info("Recursively copied %d files from %s" % [copied_count, src_dir], "FileSystemMGR")


## 扫描所有资源
func _scan_all_resources() -> void:
	if is_scanning:
		return
	
	is_scanning = true
	GLogger.info("Scanning all resources...", "FileSystemMGR")

	await scan_charts()
	await SkinMGR.scan_skins()
	await get_tree().process_frame
	scan_soundfonts()
	await get_tree().process_frame
	await scan_backgrounds()
	await get_tree().process_frame

	is_scanning = false
	resources_scanned = true
	resources_ready.emit()

	is_initialized = true

	GLogger.info("Directory structure initialized", "FileSystemMGR")

## 扫描谱面目录
## 仅扫描新的谱面文件夹格式（每个文件夹一个谱面）
func scan_charts() -> void:
	# await get_tree().process_frame
	charts_index.clear()
	_chart_id_to_folder.clear()
	_hash_to_folder.clear()
	audio_files_index.clear()
	
	var dir = DirAccess.open(CHARTS_DIR)
	if dir == null:
		GLogger.warning("Failed to open charts directory", "FileSystemMGR")
		return
	
	dir.list_dir_begin()
	var folder_name = dir.get_next()
	var count = 0
	
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var chart_path = CHARTS_DIR.path_join(folder_name)
			var metadata = _load_chart_metadata(chart_path, folder_name)

			if metadata != null and not metadata.is_empty():
				charts_index[folder_name] = ChartMetadata.from_dict(metadata)
				count += 1

				# 构建反向索引
				var chart_meta = charts_index[folder_name]
				var meta_id: String = chart_meta.id
				if not meta_id.is_empty():
					_chart_id_to_folder[meta_id] = folder_name
				var json_data = chart_meta.data
				if json_data is Dictionary:
					var fh: String = json_data.get("file_hash", "")
					if not fh.is_empty():
						_hash_to_folder[fh] = folder_name
					var ah: String = json_data.get("hash", "")
					if not ah.is_empty() and ah != fh:
						_hash_to_folder[ah] = folder_name
		
		folder_name = dir.get_next()
		if count % 5 == 0:
			await get_tree().process_frame
	
	dir.list_dir_end()

	GLogger.info("Scanned %d charts" % count, "FileSystemMGR")

## 加载谱面元数据（从谱面文件夹）
## 文件夹命名格式：{hash}_{song_name}_{difficulty}/
## 文件命名格式：{hash}.json, {hash}.mid, {hash}-cover.jpg
func _load_chart_metadata(chart_path: String, folder_name: String) -> Dictionary:
	# 从文件夹名称提取 chart_id（哈希值）
	var chart_id = folder_name.split("_")[0]
	var json_path = chart_path.path_join(chart_id + ".json")
	
	# 检查必需文件是否存在
	if not FileAccess.file_exists(json_path):
		GLogger.warning("Chart folder %s missing JSON file: %s" % [folder_name, json_path], "FileSystemMGR")
		return {}
	
	# 读取 JSON 元数据
	var metadata = _load_chart_from_json(json_path, chart_id)
	if metadata.is_empty():
		return {}
	
	# 验证谱面完整性（检查 .mid 文件）
	var mid_path = chart_path.path_join(chart_id + ".mid")
	if not FileAccess.file_exists(mid_path):
		GLogger.warning("Chart %s missing MIDI file: %s" % [chart_id, mid_path], "FileSystemMGR")
		metadata["is_complete"] = false
		return metadata
	
	# 音频文件不是必需的，但会查找
	var audio_extensions = ["ogg", "mp3", "wav", "flac"]
	var has_audio = false
	var _song_name = folder_name
	var _hash_idx = _song_name.find("_")
	if _hash_idx >= 0:
		_song_name = _song_name.substr(_hash_idx + 1)
	for ext in audio_extensions:
		var audio_path = chart_path.path_join(chart_id + "." + ext)
		if FileAccess.file_exists(audio_path):
			audio_files_index.append({
				"file_name": chart_id + "." + ext,
				"path": audio_path,
				"format": ext,
				"chart_id": chart_id,
				"song_name": _song_name,
			})
			if not has_audio:
				metadata["audio_path"] = audio_path
				has_audio = true
			# 不 break，收集所有音频文件到 audio_files_index
	# 查找封面图（可选）- 搜索所有可能的封面文件
	var dir = DirAccess.open(chart_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var lower_name = file_name.to_lower()
				# 检查是否是封面文件（包含 cover 或 thumbnail，且是图片格式）
				if (lower_name.contains("cover") or lower_name.contains("thumbnail")) and \
				   (lower_name.ends_with(".jpg") or lower_name.ends_with(".jpeg") or \
					lower_name.ends_with(".png") or lower_name.ends_with(".webp")):
					metadata["cover_path"] = chart_path.path_join(file_name)
					break
			file_name = dir.get_next()
		dir.list_dir_end()
	
	metadata["is_complete"] = has_audio  # 仅当有音频文件时才算完整
	metadata["path"] = chart_path
	metadata["folder_name"] = folder_name
	return metadata

## 从 JSON 文件加载谱面数据
func _load_chart_from_json(json_path: String, chart_id: String) -> Dictionary:
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		GLogger.warning("Failed to open chart JSON: %s" % json_path, "FileSystemMGR")
		return {}
	
	var content = file.get_as_text()
	var json = JSON.parse_string(content)
	file.close()
	
	if json == null:
		GLogger.warning("Failed to parse chart JSON: %s" % json_path, "FileSystemMGR")
		return {}
	
	# Normalize JSON format (merge song/album/author + source* into 3 fields)
	if ChartNormalizer.normalize_chart_json(json):
		var wf = FileAccess.open(json_path, FileAccess.WRITE)
		if wf:
			wf.store_string(JSON.stringify(json, "\t", false))
			wf.close()
	
	return {
		"id": chart_id,
		"json_path": json_path,
		"data": json,
		"is_complete": false
	}

## 扫描音源目录
func scan_soundfonts() -> void:
	soundfonts_index.clear()
	
	# 辅助函数：扫描单个目录
	var _scan_dir = func(dir_path: String, is_builtin: bool):
		var dir = DirAccess.open(dir_path)
		if dir == null:
			return
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".sf2"):
				var sf_path = dir_path.path_join(file_name)
				var sf_name = file_name.get_basename()
				
				# 如果用户目录有同名文件，内置版本不覆盖
				if is_builtin and soundfonts_index.has(sf_name):
					file_name = dir.get_next()
					continue
				
				var size_mb = 0.0
				var f = FileAccess.open(sf_path, FileAccess.READ)
				if f:
					size_mb = snapped(f.get_length() / 1048576.0, 0.1)
					f.close()
				
				soundfonts_index[sf_name] = {
					"path": sf_path,
					"size_mb": size_mb,
					"is_builtin": is_builtin,
				}
			file_name = dir.get_next()
		dir.list_dir_end()
	
	# 先扫描用户目录，再扫描内置目录
	_scan_dir.call(SOUNDFONT_DIR, false)
	_scan_dir.call("res://Resources/Soundfont/", true)
	
	GLogger.info("Scanned %d soundfonts" % soundfonts_index.size(), "FileSystemMGR")

## 扫描背景图目录
func scan_backgrounds() -> void:
	backgrounds_index.clear()
	
	var dir = DirAccess.open(BACKGROUND_DIR)
	if dir == null:
		GLogger.warning("Failed to open background directory", "FileSystemMGR")
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
		if count % 20 == 0:
			await get_tree().process_frame
	
	dir.list_dir_end()
	GLogger.info("Scanned %d backgrounds" % count, "FileSystemMGR")

## ========== 公共查询接口 ==========

## 获取谱面索引
func get_charts_index() -> Dictionary:
	return charts_index

## 获取音源索引
## 获取音源索引（完整信息）
func get_soundfonts_index() -> Dictionary:
	return soundfonts_index

## 获取指定音源的文件路径
func get_soundfont_path(name: String) -> String:
	var entry = soundfonts_index.get(name, {})
	return entry.get("path", "") if entry is Dictionary else ""

## 获取背景图索引
func get_backgrounds_index() -> Dictionary:
	return backgrounds_index

## 获取音频文件索引
## 返回: Array[Dictionary] 含 file_name/path/format/chart_id/song_name
func get_audio_files_index() -> Array[Dictionary]:
	return audio_files_index

## 获取谱面目录路径
func get_charts_directory() -> String:
	return CHARTS_DIR

## 获取日志目录路径
func get_logs_directory() -> String:
	return LOGS_DIR

## 获取设置目录路径
func get_settings_directory() -> String:
	return SETTINGS_DIR

## 通过 chart_id/hash 查找 charts_index 条目（O(1)反向索引，未命中时回退到线性扫描）
func _lookup_chart(chart_id: String) -> Dictionary:
	if not _chart_id_to_folder.is_empty():
		if _chart_id_to_folder.has(chart_id):
			var fn: String = _chart_id_to_folder[chart_id]
			if charts_index.has(fn):
				return {"folder_name": fn, "metadata": charts_index[fn]}
		if _hash_to_folder.has(chart_id):
			var fn: String = _hash_to_folder[chart_id]
			if charts_index.has(fn):
				return {"folder_name": fn, "metadata": charts_index[fn]}
	# 回退到线性扫描
	for folder_name in charts_index.keys():
		var meta: ChartMetadata = charts_index[folder_name]
		if meta.id == chart_id:
			return {"folder_name": folder_name, "metadata": meta}
		var jd = meta.data
		if jd is Dictionary:
			if jd.get("hash", "") == chart_id or jd.get("file_hash", "") == chart_id:
				return {"folder_name": folder_name, "metadata": meta}
	return {}

## 从 chart_id 反向查询对应的曲包文件夹路径
## 参数: chart_id - MidiData 中的 id 字段或 file_hash 字段
## 返回: user://files/Charts/[folder_name]/ 或空字符串（未找到）
func get_chart_folder_path(chart_id: String) -> String:
	# 事先检查 charts_index 是否已初始化
	if charts_index.is_empty():
		GLogger.warning("charts_index is empty, cannot locate chart folder", "FileSystemMGR")
		return ""
	
	var result = _lookup_chart(chart_id)
	if not result.is_empty():
		var path: String = result["metadata"].path
		if not path.is_empty():
			return path
	GLogger.warning("Chart folder path not found for ID: %s" % chart_id, "FileSystemMGR")
	return ""

## 验证文件是否为有效的音频文件
## 参数: file_path - 文件路径
## 返回: bool - 是否是有效的音频文件
func is_valid_audio_file(file_path: String) -> bool:
	# 检查文件是否存在
	if not FileAccess.file_exists(file_path):
		return false
	
	# 检查文件是否不是空文件
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		GLogger.warning("Cannot access audio file: %s" % file_path, "FileSystemMGR")
		return false
	
	var file_size = file.get_length()
	file.close()
	
	# 检查文件大小（小于1KB的文件不是有效的音频）
	if file_size < 1024:
		return false
	
	# 检查文件扩展名
	var valid_extensions = ["ogg", "mp3", "wav", "flac"]
	var file_ext = file_path.get_extension().to_lower()
	return valid_extensions.has(file_ext)

## 重新扫描资源（热重载）
func rescan_resources() -> void:
	GLogger.info("Rescanning resources...", "FileSystemMGR")
	_scan_all_resources()

## 重置内置资源：强制重新复制默认谱面、皮肤、背景图到 user:// 目录
## 与 _check_and_copy_default_resources_async 不同，此方法不检查目录是否为空，强制覆盖
func reload_default_resources() -> void:
	GLogger.info("Reloading built-in resources...", "FileSystemMGR")

	# 复制默认谱面（强制，不检查空目录）
	GLogger.info("Copying default charts...", "FileSystemMGR")
	await _copy_default_charts_async()

	# 复制默认皮肤（强制）
	GLogger.info("Copying default skins...", "FileSystemMGR")
	await _copy_directory_recursive_async(SkinManager.DEFAULT_SKINS_SRC, SKINS_DIR)

	# 复制默认背景图（强制）
	GLogger.info("Copying default backgrounds...", "FileSystemMGR")
	await _copy_directory_contents_async(DEFAULT_BACKGROUND_SRC, BACKGROUND_DIR, "jpg,jpeg,png,webp")

	# 重新扫描所有资源
	_scan_all_resources()

	GLogger.info("Built-in resources reloaded", "FileSystemMGR")

## 验证谱面完整性
func validate_chart(chart_id: String) -> bool:
	if not charts_index.has(chart_id):
		return false
	
	var metadata: ChartMetadata = charts_index[chart_id]
	return metadata.is_complete

## 获取谱面路径
func get_chart_path(chart_id: String) -> String:
	if not charts_index.has(chart_id):
		return ""
	
	var metadata: ChartMetadata = charts_index[chart_id]
	return metadata.path

func get_cover_by_midiData(midi: MidiData) -> Texture2D:
	const DEFAULT_COVER_PATH := "res://Resources/song_cover/1.jpg"
	if not midi:
		return _load_cover_with_cache(DEFAULT_COVER_PATH)
	
	# 优先用 file_hash 反向索引查找
	var result = _lookup_chart(midi.file_hash)
	if result.is_empty():
		result = _lookup_chart(midi.id)
	if not result.is_empty():
		var path: String = result["metadata"].cover_path
		if path.is_empty():
			return _load_cover_with_cache(DEFAULT_COVER_PATH)
		return _load_cover_with_cache(path)
	return _load_cover_with_cache(DEFAULT_COVER_PATH)

## 带缓存的封面纹理加载
## 同 path 多次调用只从磁盘加载一次，后续直接返回缓存引用
func _load_cover_with_cache(path: String) -> Texture2D:
	const DEFAULT_COVER_PATH := "res://Resources/song_cover/1.jpg"
	# 命中缓存：直接返回（res:// 有 ResourceLoader 内建缓存，user:// 靠本字典）
	if _cover_texture_cache.has(path):
		var cached = _cover_texture_cache[path]
		if is_instance_valid(cached):
			return cached
		_cover_texture_cache.erase(path)  # 已失效的弱引用清理

	var texture: Texture2D = null
	# 区分 res:// 和 user:// 路径
	if path.begins_with("res://"):
		texture = load(path)
	else:
		if not FileAccess.file_exists(path):
			GLogger.warning("Cover file not found: %s" % path, "FileSystemMGR")
			return _load_cover_with_cache(DEFAULT_COVER_PATH)
		var image := Image.load_from_file(path)
		if image:
			texture = ImageTexture.create_from_image(image)
		else:
			GLogger.warning("Failed to load cover image: %s" % path, "FileSystemMGR")
			return _load_cover_with_cache(DEFAULT_COVER_PATH)

	if texture:
		_cover_texture_cache[path] = texture
	return texture

## 清除封面纹理缓存（封面文件更新后调用）
func clear_cover_cache() -> void:
	_cover_texture_cache.clear()

## 获取指定chart ID对应的JSON文件完整路径
## 参数: chart_id - MidiData中的id字段或file_hash字段
## 返回: user://files/Charts/[folder_name]/[chart_id].json
func get_chart_json_path(chart_id: String) -> String:
	var result = _lookup_chart(chart_id)
	if not result.is_empty():
		var meta: ChartMetadata = result["metadata"]
		# 优先使用已缓存的json_path
		var cached_json_path = meta.json_path
		if not cached_json_path.is_empty():
			return cached_json_path
		var chart_path = meta.path
		if not chart_path.is_empty():
			return chart_path.path_join(meta.id + ".json")
	GLogger.warning("Chart JSON path not found for ID: %s (charts_index has %d entries)" % [chart_id, charts_index.size()], "FileSystemMGR")
	return ""

## 删除单个文件
## 参数: absolute_path - 文件绝对路径（user:// 路径或系统路径均可）
## 返回: 是否成功删除
func delete_file(absolute_path: String) -> bool:
	if absolute_path.is_empty():
		GLogger.warning("delete_file: path is empty", "FileSystemMGR")
		return false
	if not FileAccess.file_exists(absolute_path):
		GLogger.warning("delete_file: file not found: %s" % absolute_path, "FileSystemMGR")
		return false
	var err = DirAccess.remove_absolute(absolute_path)
	if err != OK:
		GLogger.error("delete_file: failed to delete %s (err %d)" % [absolute_path, err], "FileSystemMGR")
		return false
	GLogger.info("Deleted file: %s" % absolute_path, "FileSystemMGR")
	return true

## 递归删除整个目录及其所有内容
## 参数: absolute_path - 目录绝对路径
## 返回: 是否成功删除
func delete_directory_recursive(absolute_path: String) -> bool:
	if absolute_path.is_empty():
		GLogger.warning("delete_directory_recursive: path is empty", "FileSystemMGR")
		return false

	# Android 上优先用 rm -rf，避免 DirAccess 逐个文件删除卡住
	if OS.get_name() == "Android":
		var exit_code := OS.execute("rm", ["-rf", absolute_path])
		if exit_code == 0 and not DirAccess.dir_exists_absolute(absolute_path):
			GLogger.info("Deleted directory (rm): %s" % absolute_path, "FileSystemMGR")
			return true
		GLogger.warning("delete_directory_recursive: rm -rf failed (exit %d), falling back to manual delete: %s" % [exit_code, absolute_path], "FileSystemMGR")

	# 手动递归删除（非 Android 或 rm 失败时）
	var dir = DirAccess.open(absolute_path)
	if dir == null:
		# rm -rf 可能已经成功删除了
		if not DirAccess.dir_exists_absolute(absolute_path):
			GLogger.info("Directory already gone: %s" % absolute_path, "FileSystemMGR")
			return true
		GLogger.warning("delete_directory_recursive: cannot open dir: %s" % absolute_path, "FileSystemMGR")
		return false

	var failed_count := 0
	dir.list_dir_begin()
	var entry_name = dir.get_next()
	while entry_name != "":
		if entry_name != "." and entry_name != "..":
			var full_path = absolute_path.path_join(entry_name)
			if dir.current_is_dir():
				delete_directory_recursive(full_path)
			else:
				var err_f := DirAccess.remove_absolute(full_path)
				if err_f != OK:
					GLogger.warning("delete_directory_recursive: failed to remove file (err %d): %s" % [err_f, full_path], "FileSystemMGR")
					failed_count += 1
		entry_name = dir.get_next()
	dir.list_dir_end()

	var err = DirAccess.remove_absolute(absolute_path)
	if err != OK:
		if failed_count > 0:
			GLogger.warning("delete_directory_recursive: could not delete dir %s (%d files remain, err %d)" % [absolute_path, failed_count, err], "FileSystemMGR")
		else:
			GLogger.error("delete_directory_recursive: failed to remove dir %s (err %d)" % [absolute_path, err], "FileSystemMGR")
		return false
	GLogger.info("Deleted directory: %s" % absolute_path, "FileSystemMGR")
	return true

## 从 charts_index 中移除指定 chart_id 对应的条目
## 参数: chart_id - MidiData 中的 file_hash 或 id
func remove_from_charts_index(chart_id: String) -> void:
	var result = _lookup_chart(chart_id)
	if not result.is_empty():
		var folder_name: String = result["folder_name"]
		var meta: ChartMetadata = result["metadata"]
		# 同步清理反向索引
		_chart_id_to_folder.erase(meta.id)
		var jd = meta.data
		if jd is Dictionary:
			_hash_to_folder.erase(jd.get("hash", ""))
			_hash_to_folder.erase(jd.get("file_hash", ""))
		charts_index.erase(folder_name)
		GLogger.info("Removed chart from index: %s (folder: %s)" % [chart_id, folder_name], "FileSystemMGR")
		return
	GLogger.warning("remove_from_charts_index: chart_id not found: %s" % chart_id, "FileSystemMGR")
## 在目录中查找匹配通配符模式（如 "*.mp3"）的所有文件名
## 返回文件名列表（非完整路径）
func find_files_in_dir(dir_path: String, pattern: String) -> PackedStringArray:
	var result: PackedStringArray = []
	if dir_path.is_empty():
		return result
	var d := DirAccess.open(dir_path)
	if d == null:
		GLogger.warning("find_files_in_dir: cannot open dir: %s" % dir_path, "FileSystemMGR")
		return result
	var ext := pattern.replace("*.", ".")
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn.ends_with(ext) and not d.current_is_dir():
			result.append(fn)
		fn = d.get_next()
	d.list_dir_end()
	return result

# ============================================================
# 统一删除函数（文件 + 索引同步清理）
# ============================================================

## 删除谱面及其全部关联资源，并同步清理所有相关索引
## 返回: 是否成功
func delete_chart(chart_id: String) -> bool:
	var result = _lookup_chart(chart_id)
	if result.is_empty():
		GLogger.warning("delete_chart: chart not found: %s" % chart_id, "FileSystemMGR")
		return false

	var folder_name: String = result["folder_name"]
	var meta: ChartMetadata = result["metadata"]
	var folder_path := CHARTS_DIR.path_join(folder_name)

	# 先从 audio_files_index 中移除关联的音频条目
	for i in range(audio_files_index.size() - 1, -1, -1):
		if audio_files_index[i].get("chart_id", "") == chart_id:
			audio_files_index.remove_at(i)

	# 删除目录
	if not delete_directory_recursive(folder_path):
		return false

	# 从 charts_index 移除
	_chart_id_to_folder.erase(meta.id)
	var jd = meta.data
	if jd is Dictionary:
		_hash_to_folder.erase(jd.get("hash", ""))
		_hash_to_folder.erase(jd.get("file_hash", ""))
	charts_index.erase(folder_name)
	GLogger.info("Deleted chart: %s (folder: %s)" % [chart_id, folder_name], "FileSystemMGR")
	return true

## 删除音频文件，并从 audio_files_index 移除
func delete_audio(file_path: String) -> bool:
	if not delete_file(file_path):
		return false
	for i in range(audio_files_index.size() - 1, -1, -1):
		if audio_files_index[i].get("path", "") == file_path:
			audio_files_index.remove_at(i)
	return true

## 删除 SF2 音源文件，并从 soundfonts_index 移除
func delete_soundfont(file_path: String) -> bool:
	if not delete_file(file_path):
		return false
	for sf_name in soundfonts_index.keys():
		if soundfonts_index[sf_name].get("path", "") == file_path:
			soundfonts_index.erase(sf_name)
			break
	return true

## 删除背景图片文件，并从 backgrounds_index 移除
func delete_background(file_path: String) -> bool:
	if not delete_file(file_path):
		return false
	for bg_name in backgrounds_index.keys():
		if backgrounds_index[bg_name] == file_path:
			backgrounds_index.erase(bg_name)
			break
	return true
