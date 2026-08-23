## 外部游戏（THMIX 原版）数据格式转换器
## 将 THMIX 原始缓存文件转换为 Touhou Mix CE 的 Charts/ 目录格式
##
## 源目录结构（由用户放入 user://files/THMIX_Import/）：
##   Db/midis/    — JSON 元数据文件（无扩展名，MongoDB _id 命名）
##   WebCache/    — MIDI 二进制文件（MD5 hash 命名）+ 封面图
##
## 说明：
##   - 仅处理精确名 THMIX_Import 目录（不区分大小写）；已归档的 THMIX_Import_Converted_*
##     目录不再扫描——重命名本身即完成标记，已导入内容永不再重复处理
##   - 幂等：先一次性列举 Charts 已有 hash，跳过已导入条目（重命名失败 / 重复启动都不会反复处理）
##   - **剪切式导入**：成功导入的文件从源目录 move 走（同盘 rename O(1)，比 copy 快一个数量级，
##     还省一半存储；跨盘/权限受限时回退 copy+删源）。顺序为先写 chart JSON 再移动 MIDI，
##     保证谱面元数据先落盘，中断后残缺可自愈。
##   - 导入进度 UI 仅在 THMIX_Import 待导入时显示；转换完成后源目录重命名（= 完成标记）
##   - 导入在 WorkerThreadPool 后台线程执行（纯文件 I/O，不阻塞主线程），
##     进度经 progress_cb 以 call_deferred 送回主线程；state 只在任务完成后由主线程读取
##     （任务完成提供 happens-before，无跨线程并发读写），由 FileSystemManager 驱动进度条。
##
## 使用方式：
##   var task_info = ExternalGameConverter.check_import_task()
##   var state = {}  # worker 回传进度
##   WorkerThreadPool.add_task(func(): ExternalGameConverter.check_and_convert(state), false, "ImportTHMIX")
class_name ExternalGameConverter

const IMPORT_DIR_NAME := "THMIX_Import"
const CONVERTED_DIR_PREFIX := "THMIX_Import_Converted_"


## 检查导入任务（主线程调用，决定是否启动导入 worker + 是否显示进度 UI）
## 返回 {has_work: bool, ui_pending: int}
##   has_work — 是否存在待处理的 THMIX_Import 源目录（含 Db/midis + WebCache，且有待导入条目）
##   ui_pending — 待导入元数据文件数（>0 才显示进度 UI）
## 仅精确匹配 THMIX_Import（不区分大小写）；已归档的 Converted_* 目录不再扫描——重命名即完成标记
## 无论结果都打印详细诊断日志，便于排查"为什么没触发导入"
static func check_import_task() -> Dictionary:
	var files_dir := PathHelper.get_files_dir()
	if files_dir.is_empty():
		GLogger.warning("无法获取 files 目录，跳过 THMIX 导入检查", "ExternalConverter")
		return {"has_work": false, "ui_pending": 0}

	var source_dirs := _collect_source_dirs(files_dir)
	if source_dirs.is_empty():
		GLogger.info("未检测到 THMIX 导入目录：%s" % files_dir.path_join(IMPORT_DIR_NAME), "ExternalConverter")
		return {"has_work": false, "ui_pending": 0}

	var source_dir: String = source_dirs[0]
	var db_midis_dir := source_dir + "/Db/midis/"
	var webcache_dir := source_dir + "/WebCache/"
	if not DirAccess.dir_exists_absolute(db_midis_dir) or not DirAccess.dir_exists_absolute(webcache_dir):
		GLogger.warning("THMIX 源目录缺少 Db/midis 或 WebCache，跳过检查：%s" % source_dir, "ExternalConverter")
		return {"has_work": false, "ui_pending": 0}

	var ui_pending := _count_metadata_files(db_midis_dir)
	if ui_pending == 0:
		GLogger.info("THMIX_Import 存在但 Db/midis 为空，无待导入条目", "ExternalConverter")
		return {"has_work": false, "ui_pending": 0}
	GLogger.info("THMIX_Import 待导入元数据共 %d 个（目录：%s）" % [ui_pending, source_dir.get_file()], "ExternalConverter")
	return {"has_work": true, "ui_pending": ui_pending}


## 统计目录内文件数（主线程快速调用）
static func _count_metadata_files(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	var count := 0
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir():
			count += 1
		fn = dir.get_next()
	dir.list_dir_end()
	return count


## 后台转换入口（WorkerThreadPool 线程内执行，纯文件 I/O，安全）
## 返回转换的谱面数量，0 表示未转换任何内容
## progress_state 回传（只在任务完成后由主线程读取，任务完成提供 happens-before，无并发读写）：
##   total / current — 进度（条目计数，进度条数据经 progress_cb 以 call_deferred 送主线程）
##   converted: int — 成功转换数
##   warnings / info: Array[String] — 诊断日志（由主线程统一输出到 GLogger）
## progress_cb(cur, total)：进度回调，在 worker 内以 call_deferred 调用（主线程执行，安全更新 UI）
static func check_and_convert(progress_state: Dictionary = {}, progress_cb: Callable = Callable()) -> int:
	var files_dir := PathHelper.get_files_dir()
	if files_dir.is_empty():
		_add_warning(progress_state, "无法获取 files 目录，跳过 THMIX 导入")
		return 0

	# 收集需要处理的源目录：仅在 files/ 下精确匹配 THMIX_Import（不区分大小写）
	var source_dirs := _collect_source_dirs(files_dir)
	if source_dirs.is_empty():
		_add_warning(progress_state, "没有可导入的 THMIX 数据目录（files=%s）" % files_dir)
		return 0

	var charts_dir := PathHelper.get_charts_dir()
	# 一次性列举 Charts 已有谱面 hash → folder_name 映射，用于跳过已导入条目（幂等）
	var existing_hashes := _collect_existing_chart_hashes(charts_dir)

	var total_converted := 0
	for source_dir in source_dirs:
		var source_dir_str: String = source_dir
		total_converted += _convert_source_dir(source_dir_str, files_dir, charts_dir, existing_hashes, progress_state, progress_cb)

	progress_state["converted"] = total_converted
	return total_converted


## 转换单个源目录（Worker 线程内执行）
## existing_hashes: 已存在谱面的 hash(小写) → folder_name 映射，转换成功的条目会加入以去重
## progress_cb: 进度回调（worker 内 call_deferred 送主线程）
static func _convert_source_dir(source_dir: String, files_dir: String, charts_dir: String, existing_hashes: Dictionary, progress_state: Dictionary, progress_cb: Callable = Callable()) -> int:
	var source_name := source_dir.get_file()
	var webcache_dir := source_dir + "/WebCache/"
	var db_midis_dir := source_dir + "/Db/midis/"

	if not DirAccess.dir_exists_absolute(webcache_dir) or not DirAccess.dir_exists_absolute(db_midis_dir):
		_add_warning(progress_state, "%s：缺少 WebCache 或 Db/midis 目录，跳过" % source_name)
		return 0

	# 一次性构建 WebCache 小写文件名 → 路径映射（Android 大小写敏感文件系统上
	# 任何大小写变体的文件名都能命中，比只试 exact/lower/upper 更可靠）
	var webcache_map := _build_webcache_map(webcache_dir)

	# 扫描 Db/midis/ 中的 JSON 元数据文件
	var json_entries: Array[Dictionary] = []
	var parse_fail_count := 0
	var parse_warnings: Array = []
	var dir := DirAccess.open(db_midis_dir)
	if dir == null:
		_add_warning(progress_state, "%s：无法打开 Db/midis 目录" % source_name)
		return 0

	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir():
			var entry := _parse_metadata_file(db_midis_dir.path_join(fn), parse_warnings)
			if not entry.is_empty():
				json_entries.append(entry)
			else:
				parse_fail_count += 1
		fn = dir.get_next()
	dir.list_dir_end()

	if parse_fail_count > 0:
		_add_warning(progress_state, "%s：%d 个元数据文件未解析成功（JSON 格式不符或缺少 hash/file_hash 字段），已跳过" % [source_name, parse_fail_count])
	for w in parse_warnings:
		_add_warning(progress_state, w)

	if json_entries.is_empty():
		_add_warning(progress_state, "%s：Db/midis 中没有可用的元数据条目" % source_name)
		return 0

	progress_state["total"] = int(progress_state.get("total", 0)) + json_entries.size()

	var converted := 0
	var skipped_existing := 0
	var missing_midi: Array = []  # 找不到对应 MIDI 文件的条目（最多记 10 条，便于诊断）
	var cover_cache := {}         # {cover basename: 解析路径}，同专辑多首歌共享封面时避免重复扫描 WebCache

	for entry in json_entries:
		var hash_val: String = entry.get("hash", "")
		var processed: int = int(progress_state.get("current", 0)) + 1
		progress_state["current"] = processed
		# 节流：每 10 条或最后一条才回传进度（避免消息队列风暴）
		if progress_cb.is_valid():
			var total_all: int = int(progress_state.get("total", 0))
			if processed % 10 == 0 or processed >= total_all:
				progress_cb.call_deferred(processed, total_all)
		if hash_val.is_empty():
			continue

		# 已导入过的谱面（幂等核心：重复启动 / Converted 目录重扫都不重拷）
		# 即便 mid + json 都在，也不完全跳过——先补拷缺失的封面与人声（如封面/人声单独曾失败），
		# 只有两者都齐才视为彻底完成；缺任一（或 mid/json 缺任一）都会走下方重转换流程补齐
		var existing_folder: String = existing_hashes.get(hash_val.to_lower(), "")
		if not existing_folder.is_empty():
			var existing_dir := charts_dir.path_join(existing_folder)
			if FileAccess.file_exists(existing_dir.path_join(hash_val + ".mid")) and FileAccess.file_exists(existing_dir.path_join(hash_val + ".json")):
				if _fill_missing_assets(source_dir, webcache_map, existing_dir, hash_val, entry, cover_cache, progress_state, source_name):
					# 补齐了封面/人声 → 重扫进 DB，更新 coverPath 等缓存字段，让运行中的 UI 立即可见
					var imported_list: Array = progress_state.get("imported_folders", [])
					imported_list.append(existing_folder)
					progress_state["imported_folders"] = imported_list
				skipped_existing += 1
				continue

		# 查找 MIDI 文件（经小写映射，任意大小写都能命中）
		var midi_src: String = webcache_map.get(hash_val.to_lower(), "")
		if midi_src.is_empty():
			if missing_midi.size() < 10:
				missing_midi.append("%s（%s）" % [hash_val, entry.get("name", "")])
			continue

		# 创建目标文件夹
		var name: String = entry.get("name", "")
		var folder_name := hash_val
		if not name.is_empty():
			folder_name = hash_val + "_" + _sanitize_filename(name)
		var chart_dir := charts_dir.path_join(folder_name)
		DirAccess.make_dir_recursive_absolute(chart_dir)

		# 先写 JSON（谱面元数据先落盘；即使后续移动失败，chart 也不缺 json，下次可补齐）
		var json_data: Dictionary = entry.get("data", {})
		ChartNormalizer.normalize_chart_json(json_data)
		var json_dst := chart_dir.path_join(hash_val + ".json")
		var jf := FileAccess.open(json_dst, FileAccess.WRITE)
		if jf:
			# 落盘仅保留白名单字段（与进 DB / 扫描提取保持一致，song/album 已由规范化精简）
			jf.store_string(JSON.stringify(_filter_chart_json(json_data), "\t", false))
			jf.close()
		else:
			_add_warning(progress_state, "%s：写入 JSON 失败（磁盘空间/权限？）：%s" % [source_name, json_dst])
			continue

		# 剪切 MIDI（同盘 rename O(1)，比 copy 快；目标已存在则删冗余源；失败回退 copy+删源）
		var midi_dst := chart_dir.path_join(hash_val + ".mid")
		if not _move_file(midi_src, midi_dst):
			_add_warning(progress_state, "%s：移动 MIDI 失败：%s → %s" % [source_name, midi_src, midi_dst])
			continue

		# 复制封面图（封面按专辑名寻址，同专辑多首歌共用 WebCache 里同一份，只能 copy 不能剪切）
		var cover_src: String = _resolve_cover(webcache_map, entry.get("cover_candidates", []), cover_cache)
		if not cover_src.is_empty():
			var cover_filename := cover_src.get_file()
			var cover_err := DirAccess.copy_absolute(cover_src, chart_dir.path_join(cover_filename))
			if cover_err != OK:
				_add_warning(progress_state, "%s：复制封面失败：%s（err=%d）" % [source_name, cover_src, cover_err])

		# 剪切音频文件（在源目录根，按 hash 命名，每首歌独立可剪）
		for ext in [".ogg", ".mp3", ".wav", ".flac"]:
			var audio_src := source_dir.path_join(hash_val + ext)
			if FileAccess.file_exists(audio_src):
				if not _move_file(audio_src, chart_dir.path_join(hash_val + ext)):
					_add_warning(progress_state, "%s：移动音频失败：%s" % [source_name, audio_src])

		converted += 1
		existing_hashes[hash_val.to_lower()] = folder_name  # 同批内去重
		# 收集成功导入的文件夹名，供主线程导入完成后立即同步到 DB 缓存（不必等全量扫描）
		var imported_list: Array = progress_state.get("imported_folders", [])
		imported_list.append(folder_name)
		progress_state["imported_folders"] = imported_list

	if not missing_midi.is_empty():
		_add_warning(progress_state, "%s：%d 个元数据条目在 WebCache 中找不到对应 MIDI 文件：%s" % [
			source_name, missing_midi.size(), "、".join(missing_midi)
		])
	_add_info(progress_state, "%s：跳过 %d 个已导入，转换 %d 个新谱面" % [source_name, skipped_existing, converted])

	# 转换完成后重命名源目录，防止下次启动重复处理（即使重命名失败，跳过逻辑也是幂等的）
	# 后缀用 ticks_msec（进程内单调递增 + 跨进程不同），避免同秒/跨重启重名
	if converted > 0:
		var backup_dir := files_dir.path_join(CONVERTED_DIR_PREFIX + str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_msec()))
		var rename_err := DirAccess.rename_absolute(source_dir, backup_dir)
		if rename_err == OK:
			_add_info(progress_state, "%s：已重命名源目录 → %s" % [source_name, backup_dir.get_file()])
		else:
			_add_warning(progress_state, "%s：重命名源目录失败（err=%d），下次启动靠跳过已导入的逻辑兜底" % [source_name, rename_err])

	return converted


## 查找导入源目录：仅在 files/ 下精确匹配 THMIX_Import（不区分大小写，兼容用户大小写输入）
## 已归档的 THMIX_Import_Converted_* 目录不再扫描——重命名即完成标记，已导入内容永不再处理
## 返回绝对路径数组（0 或 1 个元素），无尾斜杠
static func _collect_source_dirs(files_dir: String) -> Array:
	var result: Array = []
	var dir := DirAccess.open(files_dir)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if dir.current_is_dir() and fn.to_lower() == IMPORT_DIR_NAME.to_lower():
			result.append(files_dir.path_join(fn))
			break
		fn = dir.get_next()
	dir.list_dir_end()
	return result


## 移动文件（剪切式导入核心）
## 优先 rename（同盘 O(1)，比 copy 快一个数量级）；目标已存在 → 内容冗余，删源；
## rename 失败（跨盘/权限）→ 回退 copy + 删源；都失败 → 返回 false，源保持不动可下次重试
static func _move_file(src: String, dst: String) -> bool:
	if FileAccess.file_exists(dst):
		# 目标已存在（残留或此前部分导入），源不再需要
		return DirAccess.remove_absolute(src) == OK
	var err := DirAccess.rename_absolute(src, dst)
	if err == OK:
		return true
	var copy_err := DirAccess.copy_absolute(src, dst)
	if copy_err == OK:
		DirAccess.remove_absolute(src)
		return true
	return false


## 一次性列举 WebCache 目录，构建 小写文件名 → 绝对路径 映射
## 任意大小写变体都能命中（Android 大小写敏感文件系统下最可靠）
static func _build_webcache_map(webcache_dir: String) -> Dictionary:
	var map: Dictionary = {}
	var dir := DirAccess.open(webcache_dir)
	if dir == null:
		return map
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir():
			map[fn.to_lower()] = webcache_dir.path_join(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	return map


## 一次性列举 Charts 目录，构建 hash(大写归一) → folder_name 映射（幂等跳过用）
static func _collect_existing_chart_hashes(charts_dir: String) -> Dictionary:
	var hashes: Dictionary = {}
	var dir := DirAccess.open(charts_dir)
	if dir == null:
		return hashes
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if dir.current_is_dir() and not fn.begins_with("."):
			var idx := fn.find("_")
			var h := fn if idx < 0 else fn.substr(0, idx)
			if not h.is_empty():
				hashes[h.to_lower()] = fn
		fn = dir.get_next()
	dir.list_dir_end()
	return hashes


## 解析 Db/midis/ 中的单个元数据文件
## 解析失败时向 warnings 数组追加原因（含顶层字段名，便于判断格式不符的 JSON）
static func _parse_metadata_file(path: String, warnings: Array = []) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if warnings is Array:
			warnings.append("无法读取元数据文件：%s" % path)
		return {}

	# 处理 UTF-8 BOM
	var raw := file.get_buffer(file.get_length())
	file.close()

	if raw.size() >= 3 and raw[0] == 0xEF and raw[1] == 0xBB and raw[2] == 0xBF:
		raw = raw.slice(3)

	var text := raw.get_string_from_utf8()
	var json = JSON.parse_string(text)
	if json == null or not json is Dictionary:
		if warnings is Array:
			warnings.append("JSON 解析失败（非合法对象）：%s" % path)
		return {}

	var data: Dictionary = json
	# 兼容两种格式：THMIX 用顶层 hash；CE 自身谱面 JSON 用 file_hash（= MIDI 文件的 MD5 = WebCache 文件名）
	var hash_val: String = data.get("hash", "")
	if hash_val.is_empty():
		hash_val = data.get("file_hash", "")
	if hash_val.is_empty():
		if warnings is Array:
			var keys := "、".join(data.keys())
			warnings.append("元数据缺少 hash/file_hash 字段，已跳过：%s（顶层字段：%s）" % [path, keys])
		return {}

	# 收集封面候选（优先显式 coverPath/album.coverPath，再回退 coverUrl）
	# 模糊图 coverBlurUrl 无实用价值，不作为候选
	# 注意：WebCache 中封面文件名常与 URL 不一致（如 -cover.jpg-cut415x150-10.png 等裁剪/尺寸变体），
	# 具体命中交给 _resolve_cover 做前缀模糊匹配
	var cover_candidates: Array = []
	var top_cover = data.get("coverPath")
	if top_cover is String and not (top_cover as String).is_empty():
		cover_candidates.append(top_cover)
	var album = data.get("album", {})
	if album is Dictionary:
		var album_cover = album.get("coverPath")
		if album_cover is String and not (album_cover as String).is_empty():
			cover_candidates.append(album_cover)
	var cover_url = data.get("coverUrl")
	if cover_url is String and not (cover_url as String).is_empty():
		cover_candidates.append(cover_url)

	return {
		"hash": hash_val,
		"name": data.get("name", ""),
		"cover_candidates": cover_candidates,
		"data": data
	}


## 已导入谱面的补齐：封面/人声缺失时从源目录补拷，补齐后仍视为「已跳过」。
## 不重写 json、不重移 midi（两者已存在）；仅补缺失资源，减少重复 I/O。
## 返回是否有实际补齐（调用方据此决定是否把该目录重扫进 DB，更新 coverPath 等缓存字段）
static func _fill_missing_assets(source_dir: String, webcache_map: Dictionary, chart_dir: String,
		hash_val: String, entry: Dictionary, cover_cache: Dictionary,
		progress_state: Dictionary, source_name: String) -> bool:
	var changed := false
	# 封面：按候选解析出实际文件名，目标目录缺该文件才补拷
	var cover_src: String = _resolve_cover(webcache_map, entry.get("cover_candidates", []), cover_cache)
	if not cover_src.is_empty():
		var cover_name := cover_src.get_file()
		if not FileAccess.file_exists(chart_dir.path_join(cover_name)):
			var err := DirAccess.copy_absolute(cover_src, chart_dir.path_join(cover_name))
			if err != OK:
				_add_warning(progress_state, "%s：补齐封面失败：%s（err=%d）" % [source_name, cover_src, err])
			else:
				changed = true
	# 人声：按 hash 命名，源目录根有而目标缺则补拷
	for ext in [".ogg", ".mp3", ".wav", ".flac"]:
		var dst := chart_dir.path_join(hash_val + ext)
		if FileAccess.file_exists(dst):
			continue
		var audio_src := source_dir.path_join(hash_val + ext)
		if not FileAccess.file_exists(audio_src):
			continue
		if _move_file(audio_src, dst):
			changed = true
		else:
			_add_warning(progress_state, "%s：补齐人声失败：%s" % [source_name, audio_src])
	return changed


## 依据封面候选（URL/路径/文件名）从 WebCache 映射中解析实际封面文件路径
## WebCache 封面文件名常与候选不一致（裁剪/尺寸变体，如 {base}-cover.jpg-cut415x150-10.png），
## 先精确匹配，再按去扩展名前缀做一次模糊匹配。cache 记录各候选 basename 的解析结果，
## 同专辑多首歌共享同一份封面时避免重复扫描 WebCache
static func _resolve_cover(webcache_map: Dictionary, candidates: Array, cache: Dictionary) -> String:
	for ident in candidates:
		var s := str(ident).strip_edges()
		if s.is_empty():
			continue
		# 清理可能包裹的反引号（部分导出数据 URL 外层带 `）
		s = s.trim_prefix("`").trim_suffix("`")
		var q := s.find("?")
		if q >= 0:
			s = s.substr(0, q)
		var base := s.get_file()
		if base.is_empty():
			continue
		if cache.has(base):
			var cached: String = cache[base]
			if not cached.is_empty():
				return cached
			continue  # 该候选此前已确认无命中，试下一个
		var found := _resolve_cover_single(webcache_map, base)
		cache[base] = found
		if not found.is_empty():
			return found
	return ""


## 单个候选的精确 + 前缀模糊匹配
## 同前缀可能存在多个尺寸变体（如原始图 / -cut415x150-10.png / -cut390x140-10.png）。
## 优先级：原始图（无 cut 标记，接近 1:1）最优先 → 其次 cut 宽度最大的一份（如 415 而非 390），
## 避免依赖字典遍历顺序（cut 版会压扁高度，原始图观感最好）
static func _resolve_cover_single(webcache_map: Dictionary, base: String) -> String:
	var low := base.to_lower()
	if webcache_map.has(low):
		return webcache_map[low]
	# 前缀模糊：去掉扩展名后的主语，覆盖 -cut{尺寸} / 原始图等变体
	var dot := low.rfind(".")
	var stem := low if dot < 0 else low.substr(0, dot)
	if stem.is_empty():
		return ""
	var best := ""
	var best_score := -1
	for key in webcache_map:
		if not key.begins_with(stem):
			continue
		var width := _extract_cut_width(key)
		# 无 cut 标记 = 原始图，评分为极大值使其恒排最前
		var score := 1_000_000 if width < 0 else width
		if score > best_score:
			best_score = score
			best = webcache_map[key]
	return best


## 从 WebCache 文件名提取 cut 尺寸宽度（如 -cut415x150-10.png → 415）；
## 无 cut 标记（纯前缀匹配，即原始图）返回 -1
static func _extract_cut_width(filename: String) -> int:
	var idx := filename.find("cut")
	if idx < 0:
		return -1
	var num := ""
	var i := idx + 3
	while i < filename.length():
		var c := filename[i]
		if c.is_valid_int():
			num += c
			i += 1
		else:
			break
	if num.is_empty():
		return -1
	return num.to_int()


## 保存谱面 JSON 时只保留白名单字段（与进 DB / 扫描提取保持一致）
## song/album 子对象已由 ChartNormalizer 精简，author 已归一为字符串
static func _filter_chart_json(data: Dictionary) -> Dictionary:
	const WHITELIST := ["_id", "name", "desc", "status", "artistName", "uploaderName", "uploaderId",
		"uploaderAvatarUrl", "artistUrl", "coverPath", "coverUrl", "uploadedDate", "approvedDate",
		"trialCount", "downloadCount", "upCount", "downCount", "hash", "file_hash", "author", "song", "album"]
	var out: Dictionary = {}
	for key in WHITELIST:
		if data.has(key):
			out[key] = data[key]
	return out


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
	# Windows 保留：去除尾部点/空格（Windows 会剥离尾部点导致目录被当作保留管道名）
	while result.ends_with(".") or result.ends_with(" "):
		result = result.substr(0, result.length() - 1)
	# Windows 保留设备名（CON/PRN/AUX/NUL/COM1-9/LPT1-9）加前缀避免冲突（防御性，hash 前缀通常不会触发）
	const RESERVED := ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]
	if RESERVED.has(result.to_upper()):
		result = "_" + result
	if result.is_empty():
		result = "unknown"
	return result


static func _add_warning(state: Dictionary, msg: String) -> void:
	var arr: Array = state.get("warnings", [])
	arr.append(msg)
	state["warnings"] = arr


static func _add_info(state: Dictionary, msg: String) -> void:
	var arr: Array = state.get("info", [])
	arr.append(msg)
	state["info"] = arr
