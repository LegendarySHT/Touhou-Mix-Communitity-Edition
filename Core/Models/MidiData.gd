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

## 文件哈希
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
