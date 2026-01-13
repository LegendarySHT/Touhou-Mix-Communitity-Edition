## 排序引擎
## 负责多维度MIDI谱面排序
extends Node

class_name SortingEngine

## 排序方向枚举
enum SortDirection {
	ASCENDING,  # 升序
	DESCENDING  # 降序
}

## 排序字段枚举
enum SortField {
	DOWNLOAD_COUNT,    # 按下载数排序
	LOVE_COUNT,        # 按收藏数排序
	UP_COUNT,          # 按好评数排序
	TRIAL_COUNT,       # 按试玩数排序
	UPLOADED_DATE,     # 按上传时间排序
	DEFAULT            # 默认顺序（按专辑）
}

## 排序配置
var current_sort_field: SortField = SortField.DEFAULT
var current_sort_direction: SortDirection = SortDirection.DESCENDING

## 缓存排序结果，避免重复排序
var sort_cache: Dictionary = {}
var cache_key: String = ""

## 获取排序后的MIDI列表
func get_sorted_midis(midis: Array[MidiData], 
					   sort_field: SortField = SortField.DEFAULT,
					   sort_direction: SortDirection = SortDirection.DESCENDING) -> Array[MidiData]:
	
	# 更新排序配置
	current_sort_field = sort_field
	current_sort_direction = sort_direction
	
	# 生成缓存key
	cache_key = "%d_%d" % [sort_field, sort_direction]
	
	# 检查缓存
	if sort_cache.has(cache_key):
		return sort_cache[cache_key]
	
	# 执行排序
	var sorted_result = midis.duplicate()
	sorted_result.sort_custom(func(a: MidiData, b: MidiData) -> bool:
		return _compare_midis(a, b)
	)
	
	# 缓存结果
	sort_cache[cache_key] = sorted_result
	
	return sorted_result

## 比较两个MIDI谱面
func _compare_midis(midi_a: MidiData, midi_b: MidiData) -> bool:
	var is_ascending = current_sort_direction == SortDirection.ASCENDING
	var result: int = 0
	
	match current_sort_field:
		SortField.DOWNLOAD_COUNT:
			result = _compare_int(midi_a.download_count, midi_b.download_count)
		
		SortField.LOVE_COUNT:
			result = _compare_int(midi_a.love_count, midi_b.love_count)
		
		SortField.UP_COUNT:
			result = _compare_int(midi_a.up_count, midi_b.up_count)
		
		SortField.TRIAL_COUNT:
			result = _compare_int(midi_a.trial_count, midi_b.trial_count)
		
		SortField.UPLOADED_DATE:
			result = _compare_string(midi_a.uploaded_date, midi_b.uploaded_date)
		
		SortField.DEFAULT:
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

## 按状态过滤MIDI列表
func filter_by_status(midis: Array[MidiData], status: String) -> Array[MidiData]:
	var result: Array[MidiData] = []
	
	for midi in midis:
		if midi.status == status:
			result.append(midi)
	
	return result

## 按状态和排序过滤MIDI列表
func filter_and_sort(midis: Array[MidiData],
					 status: String = "",
					 sort_field: SortField = SortField.DEFAULT,
					 sort_direction: SortDirection = SortDirection.DESCENDING) -> Array[MidiData]:
	
	var filtered = midis
	
	# 先过滤状态
	if not status.is_empty():
		filtered = filter_by_status(midis, status)
	
	# 再排序
	return get_sorted_midis(filtered, sort_field, sort_direction)

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
	
	for midi in midis:
		if (midi.name.to_lower().contains(search_text) or
			midi.artist_name.to_lower().contains(search_text) or
			midi.uploader_name.to_lower().contains(search_text)):
			result.append(midi)
	
	return result
