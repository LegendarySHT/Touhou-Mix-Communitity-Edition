## MIDI 谱面数据模型
## 代表一个单独的MIDI谱面记录
class_name MidiData
extends Resource

## 唯一标识符
var id: String

## 谱面名称
var name: String

## 谱面描述
var description: String

## 谱面状态 (PENDING, APPROVED, INCLUDED, DEAD)
var status: String

## 作曲者名字
var artist_name: String

## 上传者名字
var uploader_name: String

## 上传时间戳
var uploaded_date: String

## 所属歌曲信息
var song_data: SongData

## 所属专辑信息
var album_data: AlbumData

## 统计数据 - 试玩数
var trial_count: int = 0

## 统计数据 - 下载数
var download_count: int = 0

## 统计数据 - 收藏数
var love_count: int = 0

## 统计数据 - 好评数
var up_count: int = 0

## 统计数据 - 差评数
var down_count: int = 0

## 统计数据 - 平均准确率
var avg_accuracy: float = 0.0

## 统计数据 - 通关人数
var pass_count: int = 0

## 统计数据 - 失败人数
var fail_count: int = 0

## 评级分布
var rank_distribution: Dictionary = {
	"S": 0,
	"A": 0,
	"B": 0,
	"C": 0,
	"D": 0,
	"F": 0
}

## MIDI文件哈希（MD5）
var file_hash: String = ""

## ========== MIDI播放相关字段 ==========

## MIDI文件完整路径
var midi_file_path: String = ""

## MIDI轨道总数
var track_count: int = 1

## 已选中的轨道索引列表（支持多轨选择）
var selected_track_indices: Array[int] = []

## 已选中的轨道和通道配置 (格式: {track_idx: [ch0, ch1, ...], ...})
var selected_track_configs: Dictionary = {}

## (track, channel) 对的 mute 状态映射 (格式: {track_idx: {channel: bool}})
var track_channel_mute_state: Dictionary = {}

## 已选中的音源文件名（默认为空表示使用系统默认）
var use_soundfont: String = ""

## 已解析的MIDI音符列表（未分类）
var parsed_notes: Array = []

## MIDI每分钟节拍数（BPM）
var bpm: float = 120.0

## MIDI总时长（毫秒）
var duration_ms: float = 0.0

## ========== 用户配置字段（运行时可修改，需持久化）==========

## MIDI播放音量（0-100）
var midi_volume: int = 50

## 人声音量（0-100）
var vocal_volume: int = 50

## 人声文件路径（完整路径或相对路径）
var vocal_file_path: String = ""

## 人声音频偏移量（毫秒）
var vocal_offset_ms: int = 0

## 轨道-通道音量配置 {track_idx: {ch_idx: float(0.0-1.0)}}
var track_channel_volume_config: Dictionary = {}

## 独奏状态 (track:channel -> true)
var solo_pairs: Dictionary = {}

## 轨道-通道的乐器映射 {track_idx: {channel: {bank: int, program: int}}}
## 在 MIDI 解析时填充，用于在 UI 中显示正确的乐器
var track_channel_instruments: Dictionary = {}

## 从JSON数据构造MIDI数据
func from_json(json_data: Dictionary) -> void:
	id = json_data.get("_id", "")
	name = json_data.get("name", "")
	description = json_data.get("desc", "")
	status = json_data.get("status", "PENDING")
	artist_name = json_data.get("artistName", "")
	uploader_name = json_data.get("uploaderName", "")
	uploaded_date = json_data.get("uploadedDate", "")
	
	# 处理两种格式的字段名
	trial_count = json_data.get("trialCount", 0)
	download_count = json_data.get("downloadCount", 0)
	love_count = json_data.get("loveCount", 0)
	up_count = json_data.get("upCount", 0)
	down_count = json_data.get("downCount", 0)
	
	# 平均准确率可能有不同字段名
	avg_accuracy = json_data.get("avgAccuracy", 0.0)
	if avg_accuracy == 0.0:
		avg_accuracy = json_data.get("avgAccuracy", 0.0)
	
	pass_count = json_data.get("passCount", 0)
	fail_count = json_data.get("failCount", 0)
	file_hash = json_data.get("hash", "")
	
	# 处理评级分布
	rank_distribution["S"] = json_data.get("sCount", 0)
	rank_distribution["A"] = json_data.get("aCount", 0)
	rank_distribution["B"] = json_data.get("bCount", 0)
	rank_distribution["C"] = json_data.get("cCount", 0)
	rank_distribution["D"] = json_data.get("dCount", 0)
	rank_distribution["F"] = json_data.get("fCount", 0)
	
	# 读取用户运行时配置（从 _runtime 对象）
	var runtime_config = json_data.get("_runtime", {})
	if runtime_config is Dictionary:
		midi_volume = runtime_config.get("midi_volume", 50)
		vocal_volume = runtime_config.get("vocal_volume", 50)
		
		# 恢复轨道选择配置
		var saved_track_indices = runtime_config.get("selected_track_indices", [])
		if saved_track_indices is Array and not saved_track_indices.is_empty():
			selected_track_indices.clear()
			for idx in saved_track_indices:
				selected_track_indices.append(int(idx))
		
		# 恢复轨道静音状态（处理JSON中的字符串键）
		var saved_mute_state = runtime_config.get("track_channel_mute_state", {})
		if saved_mute_state is Dictionary:
			track_channel_mute_state.clear()
			for track_key in saved_mute_state.keys():
				var track_idx = int(track_key)  # JSON中的整数键被转换为字符串
				var channels = saved_mute_state[track_key]
				if channels is Dictionary:
					track_channel_mute_state[track_idx] = {}
					for ch_key in channels.keys():
						var channel = int(ch_key)
						track_channel_mute_state[track_idx][channel] = channels[ch_key]
		
		# 恢复轨道音量配置（处理JSON中的字符串键）
		var saved_track_volumes = runtime_config.get("track_channel_volume_config", {})
		if saved_track_volumes is Dictionary:
			track_channel_volume_config.clear()
			for track_key in saved_track_volumes.keys():
				var track_idx = int(track_key)  # JSON中的整数键被转换为字符串
				var channels = saved_track_volumes[track_key]
				if channels is Dictionary:
					track_channel_volume_config[track_idx] = {}
					for ch_key in channels.keys():
						var channel = int(ch_key)
						track_channel_volume_config[track_idx][channel] = float(channels[ch_key])
		
		var saved_soundfont = runtime_config.get("use_soundfont", "")
		if saved_soundfont is String:
			use_soundfont = saved_soundfont
		
		# 恢复独奏状态
		var saved_solo_pairs = runtime_config.get("solo_pairs", {})
		if saved_solo_pairs is Dictionary:
			solo_pairs = saved_solo_pairs.duplicate()
		
		# 恢复音轨启用状态（处理JSON中的字符串键）
		var saved_track_configs = runtime_config.get("selected_track_configs", {})
		if saved_track_configs is Dictionary:
			selected_track_configs.clear()
			for track_key in saved_track_configs.keys():
				var track_idx = int(track_key)  # JSON中的整数键被转换为字符串
				var channels = saved_track_configs[track_key]
				if channels is Array:
					# 将数组中的元素转换为整数（通道编号）
					selected_track_configs[track_idx] = []
					for ch in channels:
						selected_track_configs[track_idx].append(int(ch))
		
		# 恢复人声文件路径
		var saved_vocal_path = runtime_config.get("vocal_file_path", "")
		if saved_vocal_path is String:
			vocal_file_path = saved_vocal_path

		# 恢复人声偏移量
		var saved_vocal_offset = runtime_config.get("vocal_offset_ms", 0)
		if saved_vocal_offset is int:
			vocal_offset_ms = saved_vocal_offset
		elif saved_vocal_offset is float:
			vocal_offset_ms = int(saved_vocal_offset)

## 转换为字典格式（用于导出或缓存）
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"status": status,
		"artist_name": artist_name,
		"uploader_name": uploader_name,
		"uploaded_date": uploaded_date,
		"trial_count": trial_count,
		"download_count": download_count,
		"love_count": love_count,
		"up_count": up_count,
		"down_count": down_count,
		"avg_accuracy": avg_accuracy,
		"pass_count": pass_count,
		"fail_count": fail_count,
		"rank_distribution": rank_distribution,
		"file_hash": file_hash,
		"midi_file_path": midi_file_path,
		"track_count": track_count,
		"selected_track_indices": selected_track_indices,
		"use_soundfont": use_soundfont,
		"bpm": bpm,
		"duration_ms": duration_ms
	}

## 设置选中的轨道
func set_selected_tracks(track_indices: Array[int]) -> void:
	selected_track_indices = track_indices

## 检查指定的(track, channel)是否被选中
func is_track_channel_selected(track_idx: int, channel: int) -> bool:
	if not selected_track_configs.has(track_idx):
		return false
	return channel in selected_track_configs[track_idx]

## 设置指定(track, channel)的启用状态
func set_track_channel_enabled(track_idx: int, channel: int, enabled: bool) -> void:
	if enabled:
		if not selected_track_configs.has(track_idx):
			selected_track_configs[track_idx] = []
		if channel not in selected_track_configs[track_idx]:
			selected_track_configs[track_idx].append(channel)
	else:
		if selected_track_configs.has(track_idx):
			selected_track_configs[track_idx].erase(channel)
			# 如果该轨道已无通道被选中，删除该轨道的条目
			if selected_track_configs[track_idx].is_empty():
				selected_track_configs.erase(track_idx)

## 设置音源
func set_soundfont(soundfont_name: String) -> void:
	use_soundfont = soundfont_name

## 清空已解析的音符列表
func clear_parsed_notes() -> void:
	parsed_notes.clear()

## ========== (Track, Channel) 静音接口 ==========

## 设置 (track, channel) 对的 mute 状态
func set_track_channel_mute(track_index: int, channel: int, muted: bool) -> void:
	if not track_channel_mute_state.has(track_index):
		track_channel_mute_state[track_index] = {}
	track_channel_mute_state[track_index][channel] = muted
	print("[MidiData] Track %d Channel %d: %s" % [track_index, channel, "muted" if muted else "unmuted"])

## 查询 (track, channel) 对是否被静音
func get_track_channel_mute(track_index: int, channel: int) -> bool:
	if track_channel_mute_state.has(track_index):
		if track_channel_mute_state[track_index].has(channel):
			return track_channel_mute_state[track_index][channel]
	return false

## 清除所有 mute 状态
func clear_all_mutes() -> void:
	track_channel_mute_state.clear()

## 设置特定(track, channel)对的音量
func set_track_channel_volume(track_index: int, channel: int, volume: float) -> void:
	if not track_channel_volume_config.has(track_index):
		track_channel_volume_config[track_index] = {}
	track_channel_volume_config[track_index][channel] = clamp(volume, 0.0, 1.0)

## 获取特定(track, channel)对的音量
func get_track_channel_volume(track_index: int, channel: int) -> float:
	if track_channel_volume_config.has(track_index):
		return track_channel_volume_config[track_index].get(channel, 1.0)
	return 1.0

## 导出用户运行时配置为字典
func export_runtime_config() -> Dictionary:
	return {
		"midi_volume": midi_volume,
		"vocal_volume": vocal_volume,
		"vocal_file_path": vocal_file_path,
		"vocal_offset_ms": vocal_offset_ms,
		"selected_track_indices": selected_track_indices.duplicate(),
		"selected_track_configs": selected_track_configs.duplicate(),
		"track_channel_mute_state": track_channel_mute_state.duplicate(),
		"track_channel_volume_config": track_channel_volume_config.duplicate(),
		"solo_pairs": solo_pairs.duplicate(),
		"use_soundfont": use_soundfont,
		"saved_at": Time.get_ticks_msec()
	}

## 获取轨道-通道的乐器 (bank, program)
func get_track_channel_instrument(track_index: int, channel: int) -> Dictionary:
	if track_channel_instruments.has(track_index):
		if track_channel_instruments[track_index].has(channel):
			return track_channel_instruments[track_index][channel]
	return {"bank": 0, "program": 0}

## 设置轨道-通道的乐器
func set_track_channel_instrument(track_index: int, channel: int, bank: int, program: int) -> void:
	if not track_channel_instruments.has(track_index):
		track_channel_instruments[track_index] = {}
	track_channel_instruments[track_index][channel] = {"bank": bank, "program": program}
