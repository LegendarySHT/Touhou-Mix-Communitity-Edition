## 外部游戏（THMIX 原版）数据格式转换器
## 将 THMIX 原始缓存文件转换为 Touhou Mix CE 的 Charts/ 目录格式
##
## 源目录结构（由用户放入 user://files/THMIX_Import/）：
##   Db/midis/    — JSON 元数据文件（无扩展名，MongoDB _id 命名）
##   WebCache/    — MIDI 二进制文件（MD5 hash 命名）+ 封面图
##
## 使用方式：
##   var count = ExternalGameConverter.check_and_convert()
class_name ExternalGameConverter

const IMPORT_DIR_NAME := "THMIX_Import"


## 检查并转换外部游戏数据
## 返回转换的谱面数量，0 表示无需转换
static func check_and_convert() -> int:
	var files_dir := _get_files_dir()
	if files_dir.is_empty():
		return 0

	var import_dir := files_dir.path_join(IMPORT_DIR_NAME) + "/"
	if not DirAccess.dir_exists_absolute(import_dir):
		return 0

	var webcache_dir := import_dir.path_join("WebCache") + "/"
	var db_midis_dir := import_dir.path_join("Db").path_join("midis") + "/"

	if not DirAccess.dir_exists_absolute(webcache_dir):
		return 0
	if not DirAccess.dir_exists_absolute(db_midis_dir):
		return 0

	# 扫描 Db/midis/ 中的 JSON 元数据文件
	var json_entries: Array[Dictionary] = []
	var dir := DirAccess.open(db_midis_dir)
	if dir == null:
		return 0

	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir():
			var entry := _parse_metadata_file(db_midis_dir.path_join(fn))
			if not entry.is_empty():
				json_entries.append(entry)
		fn = dir.get_next()
	dir.list_dir_end()

	if json_entries.is_empty():
		return 0

	var charts_dir := _get_charts_dir()
	var converted := 0

	for entry in json_entries:
		var hash_val: String = entry.get("hash", "")
		if hash_val.is_empty():
			continue

		# 查找 MIDI 文件
		var midi_src := webcache_dir.path_join(hash_val)
		if not FileAccess.file_exists(midi_src):
			continue

		# 创建目标文件夹
		var name: String = entry.get("name", "")
		var folder_name := hash_val
		if not name.is_empty():
			folder_name = hash_val + "_" + _sanitize_filename(name)
		var chart_dir := charts_dir.path_join(folder_name)
		DirAccess.make_dir_recursive_absolute(chart_dir)

		# 复制 MIDI 文件
		var midi_dst := chart_dir.path_join(hash_val + ".mid")
		var copy_err := DirAccess.copy_absolute(midi_src, midi_dst)
		if copy_err != OK:
			print("[ExternalGameConverter] Failed to copy MIDI: %s" % midi_src)
			continue

		# 规范化并写入 JSON
		var json_data: Dictionary = entry.get("data", {})
		ChartNormalizer.normalize_chart_json(json_data)
		var json_dst := chart_dir.path_join(hash_val + ".json")
		var jf := FileAccess.open(json_dst, FileAccess.WRITE)
		if jf:
			jf.store_string(JSON.stringify(json_data, "\t", false))
			jf.close()

		# 复制封面图
		var cover_path: String = entry.get("cover_path", "")
		if not cover_path.is_empty():
			var cover_filename := cover_path.get_file()
			var cover_src := webcache_dir.path_join(cover_filename)
			if FileAccess.file_exists(cover_src):
				DirAccess.copy_absolute(cover_src, chart_dir.path_join(cover_filename))

		# 复制音频文件
		for ext in [".ogg", ".mp3"]:
			var audio_src := import_dir.path_join(hash_val + ext)
			if FileAccess.file_exists(audio_src):
				DirAccess.copy_absolute(audio_src, chart_dir.path_join(hash_val + ext))

		converted += 1

	# 转换完成后重命名源目录，防止下次启动重复处理
	if converted > 0:
		var backup_dir := files_dir.path_join("THMIX_Import_Converted_" + str(Time.get_unix_time_from_system()))
		DirAccess.rename_absolute(import_dir, backup_dir)

	return converted


## 解析 Db/midis/ 中的单个元数据文件
static func _parse_metadata_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	# 处理 UTF-8 BOM
	var raw := file.get_buffer(file.get_length())
	file.close()

	if raw.size() >= 3 and raw[0] == 0xEF and raw[1] == 0xBB and raw[2] == 0xBF:
		raw = raw.slice(3)

	var text := raw.get_string_from_utf8()
	var json = JSON.parse_string(text)
	if json == null or not json is Dictionary:
		return {}

	var data: Dictionary = json
	var hash_val: String = data.get("hash", "")
	if hash_val.is_empty():
		return {}

	# 提取封面路径（优先顶层 coverPath，回退 album.coverPath）
	var cover_path: String = ""
	var top_cover = data.get("coverPath")
	if top_cover is String and not (top_cover as String).is_empty():
		cover_path = top_cover
	else:
		var album = data.get("album", {})
		if album is Dictionary:
			var album_cover = album.get("coverPath")
			if album_cover is String and not (album_cover as String).is_empty():
				cover_path = album_cover as String

	return {
		"hash": hash_val,
		"name": data.get("name", ""),
		"cover_path": cover_path,
		"data": data
	}


static func _sanitize_filename(nm: String) -> String:
	const INVALID := '<>:"/\\|?*'
	var result := ""
	for c in nm:
		var cu := c.unicode_at(0)
		if cu < 32 or c in INVALID:
			result += "_"
		else:
			result += c
	result = result.strip_edges()
	# 合并连续空格
	while result.find("  ") >= 0:
		result = result.replace("  ", " ")
	return result


static func _get_files_dir() -> String:
	if PathHelper.is_android():
		return "/storage/emulated/0/Android/data/%s/files/" % PathHelper.PACKAGE_NAME
	else:
		return "user://files"


static func _get_charts_dir() -> String:
	return _get_files_dir().path_join("Charts") + "/"
