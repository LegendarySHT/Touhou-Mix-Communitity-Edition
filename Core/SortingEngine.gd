## 排序引擎
## 负责多维度MIDI谱面排序
extends Node

class_name SortingEngine

## 排序方向枚举
enum SortDirection {
	ASCENDING,  # 升序
	DESCENDING  # 降序
}

## 数据排序字段枚举
enum SortDataField {
	DEFAULT,            # 默认顺序（按专辑）
	DOWNLOAD_COUNT,    # 按下载数排序
	LOVE_COUNT,        # 按收藏数排序
	UP_COUNT,          # 按好评数排序
	TRIAL_COUNT,       # 按试玩数排序
	UPLOADED_DATE     # 按上传时间排序
}

## 状态排序字段枚举
enum SortStatField {
	ALL, 
	PENDING,
	APPROVED,
	INCLUDED,
	DEAD
}

## 专辑排序方式枚举
enum AlbumSortMethod {
	BY_CREATION_TIME,  # 按创建时间（album.date / release_date，空的 fallback 到下载时间）
	BY_DOWNLOAD_TIME   # 按下载时间（= uploadedDate，空日期排最上）
}

## 从字符串解析专辑排序方式（用于 ConfigManager 读回）
static func parse_album_sort_method(method_str: String) -> AlbumSortMethod:
	match method_str:
		"download_time":
			return AlbumSortMethod.BY_DOWNLOAD_TIME
		_:
			return AlbumSortMethod.BY_CREATION_TIME

## 将专辑排序方式转为字符串（用于 ConfigManager 写入）
static func album_sort_method_to_str(method: AlbumSortMethod) -> String:
	match method:
		AlbumSortMethod.BY_DOWNLOAD_TIME:
			return "download_time"
		_:
			return "creation_time"

## 初始化函数
func _ready() -> void:
	add_to_group("singleton")

## 排序配置
var current_sort_field: SortDataField = SortDataField.DEFAULT
var current_sort_stat_field: SortStatField = SortStatField.ALL
var current_sort_direction: SortDirection = SortDirection.DESCENDING

## 缓存排序结果，避免重复排序
var sort_cache: Dictionary = {}
var cache_key: String = ""

const FILTER_BATCH_SIZE := 100

## 排序任务状态
var _sort_request_id: int = 0
var is_sorting_active: bool = false

## 当前的midi列表
var current_midis: Array[MidiData] = []

## 停止排序任务
func stop_sorting() -> void:
	_sort_request_id += 1
	is_sorting_active = false

## 检查排序请求是否已失效
func _is_sort_cancelled(request_id: int) -> bool:
	return request_id != _sort_request_id or not is_inside_tree()

## 协程步骤之间让出一帧，保持UI响应
func _yield_for_sort_step(request_id: int) -> bool:
	var tree := get_tree()
	if tree == null:
		return true
	await tree.process_frame
	return _is_sort_cancelled(request_id)

## 获取排序后的MIDI列表
func _sort_midis(midis: Array[MidiData], 
					   sort_field: SortDataField = SortDataField.DEFAULT,
					   sort_direction: SortDirection = SortDirection.DESCENDING) -> Array[MidiData]:
	# 更新排序配置
	current_sort_field = sort_field
	current_sort_direction = sort_direction
	
	# 执行排序
	var sorted_result: Array[MidiData] = midis.duplicate()
	
	# 使用显式配置进行排序，避免依赖全局状态
	sorted_result.sort_custom(func(a: MidiData, b: MidiData) -> bool:
		return _compare_midis(a, b, sort_field, sort_direction)
	)
	
	# 缓存结果
	# sort_cache[cache_key] = sorted_result
	
	return sorted_result

## 比较两个MIDI谱面
func _compare_midis(
	midi_a: MidiData,
	midi_b: MidiData,
	sort_field: SortDataField,
	sort_direction: SortDirection
) -> bool:
	var sort_ascending = sort_direction == SortDirection.ASCENDING
	var result: int = 0
	
	match sort_field:
		SortDataField.DOWNLOAD_COUNT:
			result = _compare_int(midi_a.download_count, midi_b.download_count)
		
		SortDataField.LOVE_COUNT:
			result = _compare_int(midi_a.love_count, midi_b.love_count)
		
		SortDataField.UP_COUNT:
			result = _compare_int(midi_a.up_count, midi_b.up_count)
		
		SortDataField.TRIAL_COUNT:
			result = _compare_int(midi_a.trial_count, midi_b.trial_count)
		
		SortDataField.UPLOADED_DATE:
			result = _compare_string(midi_a.uploaded_date, midi_b.uploaded_date)
		
		SortDataField.DEFAULT:
			# 默认排序：按专辑名->歌曲名->谱面名
			result = _compare_string(midi_a.album_data.name if midi_a.album_data else "", 
									  midi_b.album_data.name if midi_b.album_data else "")
			if result == 0:
				result = _compare_string(midi_a.song_data.name if midi_a.song_data else "",
										 midi_b.song_data.name if midi_b.song_data else "")
			if result == 0:
				result = _compare_string(midi_a.name, midi_b.name)
	
	# 根据排序方向返回结果
	return result < 0 if sort_ascending else result > 0

## 比较整数
func _compare_int(a: int, b: int) -> int:
	if a < b:
		return -1
	elif a > b:
		return 1
	else:
		return 0

## 比较字符串
func _compare_string(a: String, b: String) -> int:
	if a < b:
		return -1
	elif a > b:
		return 1
	else:
		return 0

## 将状态枚举映射为数据中的字符串
func _get_status_name(status: SortStatField) -> String:
	match status:
		SortStatField.PENDING:
			return "PENDING"
		SortStatField.APPROVED:
			return "APPROVED"
		SortStatField.INCLUDED:
			return "INCLUDED"
		SortStatField.DEAD:
			return "DEAD"
		_:
			return ""

## 按状态过滤MIDI列表（协程批量处理版本）
func _filter_midis_by_status(
	midis: Array[MidiData],
	status: SortStatField,
	request_id: int,
	batch_size: int = FILTER_BATCH_SIZE
) -> Array[MidiData]:
	if status == SortStatField.ALL:
		return midis
	
	var status_name := _get_status_name(status)
	var result: Array[MidiData] = []
	
	for i in range(0, midis.size(), batch_size):
		if _is_sort_cancelled(request_id):
			return []
		
		var end_index = min(i + batch_size, midis.size())
		for j in range(i, end_index):
			var midi = midis[j]
			if midi.status == status_name:
				result.append(midi)
		
		if end_index < midis.size() and await _yield_for_sort_step(request_id):
			return []
	
	return result

## 给UI获取Midi列表用
func get_midis() -> Array[MidiData]:
	GLogger.info("当前midi数量: %d" % current_midis.size(), "SortEngine")
	return current_midis

## 设置排序模式
func set_sort_mode(status: SortStatField = SortStatField.ALL,
					sort_field: SortDataField = SortDataField.DEFAULT,
					sort_direction: SortDirection = SortDirection.DESCENDING,
					midis = null):
	_sort_request_id += 1
	var request_id := _sort_request_id
	is_sorting_active = true
	_sort_mode_task(request_id, status, sort_field, sort_direction, midis)

## 排序任务收尾
func _finish_sort_task(request_id: int, should_emit_signal: bool) -> void:
	if request_id != _sort_request_id:
		return
	
	is_sorting_active = false
	if should_emit_signal:
		_emit_sort_finished()

## 按状态和排序过滤MIDI列表（协程任务）
## 数据源：ChartDb（状态过滤 + 字段排序在 C# 完成，返回有序规范键，再分批惰性水合）
## 仅当调用方显式传入 midis（自定义列表）时退回内存排序路径保持兼容
func _sort_mode_task(
	request_id: int,
	status: SortStatField = SortStatField.ALL,
	sort_field: SortDataField = SortDataField.DEFAULT,
	sort_direction: SortDirection = SortDirection.DESCENDING,
	midis = null
) -> void:
	current_sort_field = sort_field
	current_sort_direction = sort_direction
	current_sort_stat_field = status

	# 兼容路径：显式传入的 midis 列表走原内存排序
	if midis != null:
		GLogger.info("开始排序任务(内存): 状态=%s, 字段=%s, 方向=%s" % [status, sort_field, sort_direction], "SortEngine")
		var source_midis: Array = midis
		if await _yield_for_sort_step(request_id):
			return
		var temp_list = await _filter_midis_by_status(source_midis, status, request_id)
		if _is_sort_cancelled(request_id):
			return
		temp_list = _sort_midis(temp_list, sort_field, sort_direction)
		if _is_sort_cancelled(request_id):
			return
		current_midis = temp_list
		_finish_sort_task(request_id, true)
		return

	GLogger.info("开始排序任务(DB): 状态=%s, 字段=%s, 方向=%s" % [status, sort_field, sort_direction], "SortEngine")

	# DB 全量排序：状态过滤 + 字段排序在 C# 一次完成，只返回键，主线程分批水合
	var status_str := _get_status_name(status)
	var keys: Array = ChartDB.GetSortedMidiKeys(status_str, int(sort_field), int(sort_direction), "")
	GLogger.info("DB 排序返回 %d 个键" % keys.size(), "SortEngine")

	var temp_list: Array[MidiData] = []
	for i in range(0, keys.size(), FILTER_BATCH_SIZE):
		if _is_sort_cancelled(request_id):
			return
		var end_index = min(i + FILTER_BATCH_SIZE, keys.size())
		for j in range(i, end_index):
			var midi = DataMGR._ensureMidi(String(keys[j]))
			if midi:
				temp_list.append(midi)
		if end_index < keys.size() and await _yield_for_sort_step(request_id):
			return

	if _is_sort_cancelled(request_id):
		return
	current_midis = temp_list
	_finish_sort_task(request_id, true)

## 发射排序完成信号
func _emit_sort_finished() -> void:
	GLogger.info("排序完成", "SortEngine")
	EvtBus.sort_finished.emit()

## 清空缓存
func clear_cache() -> void:
	sort_cache.clear()
	cache_key = ""

## 搜索MIDI（按原名/专辑名/谱面名/歌手/原曲作者/上传者/描述，多关键字 AND 匹配）
## 在传入的（已筛选+已排序）列表内过滤并保持原序 —— 兼容 SortedMidiView 等当前集搜索
## 全库搜索请用 DataMGR.search_all_midis（DB 驱动，DelView 扁平搜索用）
func search_midis(midis: Array[MidiData], query: String) -> Array[MidiData]:
	if query.is_empty():
		return midis

	var keywords = query.to_lower().split(" ", false)
	var result: Array[MidiData] = []

	for midi in midis:
		var midi_name = midi.name.to_lower()
		var song_name = (midi.song_data.name if midi.song_data else "").to_lower()
		var album_name = (midi.album_data.name if midi.album_data else "").to_lower()
		var artist_name = midi.artist_name.to_lower()
		var author_name = midi.author_name.to_lower()
		var uploader_name = midi.uploader_name.to_lower()
		var description = midi.description.to_lower()

		var all_keywords_match = true
		for keyword in keywords:
			if not (midi_name.contains(keyword) or
				song_name.contains(keyword) or
				album_name.contains(keyword) or
				artist_name.contains(keyword) or
				author_name.contains(keyword) or
				uploader_name.contains(keyword) or
				description.contains(keyword)):
				all_keywords_match = false
				break

		if all_keywords_match:
			result.append(midi)

	return result

## ========== 专辑级排序 ==========

## 对专辑列表排序（专辑级，与 MIDI 排序独立）
## Unknown 专辑（id 含 "__unknown"）始终排在最后
func sort_albums(albums: Array[AlbumData], method: AlbumSortMethod, direction: SortDirection) -> Array[AlbumData]:
	if albums.is_empty():
		return albums
	
	var sorted := albums.duplicate()
	var ascending := direction == SortDirection.ASCENDING
	
	# 分离 Unknown 专辑
	var unknown_albums: Array[AlbumData] = []
	var normal_albums: Array[AlbumData] = []
	for a in sorted:
		if a is AlbumData and a.id.begins_with("__unknown"):
			unknown_albums.append(a)
		else:
			normal_albums.append(a)
	
	# 对普通专辑排序
	normal_albums.sort_custom(func(a: AlbumData, b: AlbumData) -> bool:
		return _compare_albums(a, b, method, ascending)
	)
	
	# Unknown 拼接到最后
	normal_albums.append_array(unknown_albums)
	return normal_albums

## 专辑比较函数（预计算字段已在数据加载时准备好）
## 倒序通过交换 a/b 实现，避免空字符串时 not(a<b) 违反严格弱序
func _compare_albums(a: AlbumData, b: AlbumData, method: AlbumSortMethod, ascending: bool) -> bool:
	if not ascending:
		var tmp := a
		a = b
		b = tmp
	
	match method:
		AlbumSortMethod.BY_CREATION_TIME:
			return _compare_dates(a.release_date, b.release_date, a.earliest_uploaded_date, b.earliest_uploaded_date, false)
		AlbumSortMethod.BY_DOWNLOAD_TIME:
			return _compare_dates(a.earliest_uploaded_date, b.earliest_uploaded_date, "", "", true)
	return false

## 日期比较：primary 优先，primary 为空时用 fallback；empty_to_top 控制空值排最上还是最下
func _compare_dates(a_primary: String, b_primary: String, a_fallback: String, b_fallback: String, empty_to_top: bool) -> bool:
	var a_date := a_primary if not a_primary.is_empty() else a_fallback
	var b_date := b_primary if not b_primary.is_empty() else b_fallback
	
	if a_date.is_empty() and b_date.is_empty():
		return false
	if a_date.is_empty():
		return empty_to_top   # 下载时间：空→最上；创建时间：空→最下
	if b_date.is_empty():
		return not empty_to_top
	return a_date < b_date

## 场景退出时的清理
func _exit_tree() -> void:
	# 停止排序任务
	stop_sorting()

	# 清理缓存
	clear_cache()
