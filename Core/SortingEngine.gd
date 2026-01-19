## 排序引擎
## 负责多维度MIDI谱面排序
extends Node

class_name SortingEngine

## 单例实例
static var instance: SortingEngine

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

## 初始化函数
func _ready() -> void:
	if instance == null:
		instance = self
		add_to_group("singleton")
	else:
		queue_free()

## 排序配置
var current_sort_field: SortDataField = SortDataField.DEFAULT
var current_sort_stat_field: SortStatField = SortStatField.ALL
var current_sort_direction: SortDirection = SortDirection.DESCENDING

## 缓存排序结果，避免重复排序
var sort_cache: Dictionary = {}
var cache_key: String = ""

## 排序线程
var sort_thread: Thread = null
var should_stop_sorting: bool = false
var is_sorting_active: bool = false

## 当前的midi列表
var current_midis: Array[MidiData] = []

## 安全的开始排序线程
func _start_sort_thread(status: SortStatField, sort_field: SortDataField, sort_direction: SortDirection) -> void:
	# 如果已有线程在运行，请求停止并等待
	if sort_thread and sort_thread.is_alive():
		print("已有线程在运行，请求停止并等待")
		stop_sorting()
		sort_thread.wait_to_finish()
	
	# 重置停止标志
	should_stop_sorting = false
	is_sorting_active = true
	
	# 创建新线程
	if sort_thread:
		sort_thread.wait_to_finish()
	sort_thread = Thread.new()
	sort_thread.start(_sort_mode_thread.bind(status, sort_field, sort_direction))

## 停止排序线程
func stop_sorting() -> void:
	if is_sorting_active:
		should_stop_sorting = true

## 检查是否应该停止
func _should_stop() -> bool:
	return should_stop_sorting

## 获取排序后的MIDI列表
func _sort_midis(midis: Array[MidiData], 
					   sort_field: SortDataField = SortDataField.DEFAULT,
					   sort_direction: SortDirection = SortDirection.DESCENDING) -> Array[MidiData]:
	# 更新排序配置
	current_sort_field = sort_field
	current_sort_direction = sort_direction
	
	# 生成缓存key
	# cache_key = "%d_%d_%d" % [midis.size(), sort_field, sort_direction]
	# print("生成缓存key:", cache_key)

	# # 检查缓存
	# if sort_cache.has(cache_key):
	# 	print("使用缓存结果")
	# 	return sort_cache[cache_key]
	
	# 执行排序
	var sorted_result = midis
	
	# 使用自定义排序函数，并在每次比较前检查停止标志
	sorted_result.sort_custom(func(a: MidiData, b: MidiData) -> bool:
		return _compare_midis(a, b)
	)
	
	# 检查是否应该停止
	if should_stop_sorting:
		return []
	
	# 缓存结果
	# sort_cache[cache_key] = sorted_result
	
	return sorted_result

## 比较两个MIDI谱面
func _compare_midis(midi_a: MidiData, midi_b: MidiData) -> bool:
	var is_ascending = current_sort_direction == SortDirection.DESCENDING
	var result: int = 0
	
	match current_sort_field:
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
	if is_ascending:
		return result > 0
	else:
		return result < 0

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

## 按状态过滤MIDI列表（可中断版本）
func _filter_midis(midis: Array[MidiData], status: String) -> Array[MidiData]:
	var result: Array[MidiData] = []
	# midis = midis.duplicate()
	for i in range(midis.size()):
		# 定期检查停止标志（每处理10个元素检查一次）
		if i % 10 == 0 and should_stop_sorting:
			return []  # 返回空数组表示被中断
		
		var midi = midis[i]
		if midi.status == status:
			result.append(midi)
	
	return result

## 按状态过滤MIDI列表（批量处理版本，更高效）
func _filter_midis_batch(midis: Array[MidiData], status: String, batch_size: int = 50) -> Array[MidiData]:
	var result: Array[MidiData] = []
	
	for i in range(0, midis.size(), batch_size):
		# 检查停止标志
		if should_stop_sorting:
			return []
		
		var end_index = min(i + batch_size, midis.size())
		for j in range(i, end_index):
			var midi = midis[j]
			if midi.status == status:
				result.append(midi)
	
	return result

## 给UI获取Midi列表用
func get_midis() -> Array[MidiData]:
	print("当前midi数量:", current_midis.size())
	return current_midis

## 设置排序模式
func set_sort_mode(status: SortStatField = SortStatField.ALL,
					sort_field: SortDataField = SortDataField.DEFAULT,
					sort_direction: SortDirection = SortDirection.DESCENDING):
	_start_sort_thread(status, sort_field, sort_direction)

## 按状态和排序过滤MIDI列表（线程函数）
func _sort_mode_thread(status: SortStatField = SortStatField.ALL,
					 sort_field: SortDataField = SortDataField.DEFAULT,
					 sort_direction: SortDirection = SortDirection.DESCENDING):
	print("开始排序线程: 状态=%s, 字段=%s, 方向=%s" % [status, sort_field, sort_direction])

	var midis = DataMGR.midis.values().duplicate()
	current_sort_field = sort_field
	current_sort_direction = sort_direction
	var temp_list = _sort_midis(midis, sort_field, sort_direction)
	
	# 检查是否应该停止
	if should_stop_sorting:
		_cleanup_thread()
		return
	current_midis = temp_list
	
	current_sort_stat_field = status
	print("过滤前midi数量", current_midis.size())
	match status:
		SortStatField.PENDING:
			temp_list = _filter_midis_batch(current_midis, "PENDING", 100)
			print("过滤PENDING完成", current_midis.size())
		SortStatField.APPROVED:
			temp_list = _filter_midis_batch(current_midis, "APPROVED", 100)
			print("过滤APPROVED完成", current_midis.size())
		SortStatField.INCLUDED:
			temp_list = _filter_midis_batch(current_midis, "INCLUDED", 100)
			print("过滤INCLUDED完成", current_midis.size())
		SortStatField.DEAD:
			temp_list = _filter_midis_batch(current_midis, "DEAD", 100)
			print("过滤DEAD完成", current_midis.size())
	
	# 检查是否应该停止
	if should_stop_sorting:
		_cleanup_thread()
		return
	
	current_midis = temp_list
	call_deferred("_emit_sort_finished")
	
	# 清理线程状态
	_cleanup_thread()

## 清理线程状态
func _cleanup_thread() -> void:
	is_sorting_active = false

## 发射排序完成信号
func _emit_sort_finished() -> void:
	print("排序完成")
	EvtBus.sort_finished.emit()

## 清空缓存
func clear_cache() -> void:
	sort_cache.clear()
	cache_key = ""

## 搜索MIDI（按名称或作者）
func search_midis(midis: Array[MidiData], query: String) -> Array[MidiData]:
	if query.is_empty():
		return midis
	
	var search_text = query.to_lower()
	var result: Array[MidiData] = []
	
	# 添加中断检查
	for midi in midis:
		if _should_stop():
			break
		
		if (midi.name.to_lower().contains(search_text) or
			midi.artist_name.to_lower().contains(search_text) or
			midi.uploader_name.to_lower().contains(search_text)):
			result.append(midi)
	
	return result

## 场景退出时的清理
func _exit_tree() -> void:
	# 停止排序线程
	stop_sorting()
	
	# 等待线程结束
	if sort_thread and sort_thread.is_active():
		sort_thread.wait_to_finish()
	
	# 清理缓存
	clear_cache()

## 强制终止并重新开始（用于紧急情况）
func force_restart_sorting(status: SortStatField = SortStatField.ALL,
							sort_field: SortDataField = SortDataField.DEFAULT,
							sort_direction: SortDirection = SortDirection.DESCENDING):
	# 强制停止
	should_stop_sorting = true
	
	# 等待一小段时间让线程有机会退出
	if sort_thread and sort_thread.is_active():
		# 等待最多100ms
		var wait_time = 0
		while sort_thread.is_active() and wait_time < 100:
			OS.delay_msec(10)
			wait_time += 10
	
	# 如果线程还在运行，强制等待（这是最后的手段）
	if sort_thread and sort_thread.is_active():
		sort_thread.wait_to_finish()
	
	# 重置状态
	is_sorting_active = false
	should_stop_sorting = false
	
	# 重新开始排序
	set_sort_mode(status, sort_field, sort_direction)
