## MIDI播放管理器
## 负责MIDI文件的加载、播放、轨道选择和音源管理
extends Node

class_name MidiPlaybackManager

## 单例实例
static var instance: MidiPlaybackManager

## MIDI播放器引用
var midi_player: Node

## 当前加载的MIDI数据
var current_midi_data: MidiData

## 当前解析的音符列表
var current_notes: Array = []

## MIDI的BPM变化时间线 (用于精确时间计算)
var bpm_timeline: Array = []

## MIDI播放状态
var is_playing: bool = false

## 当前播放位置（MIDI tick单位，NOT毫秒！）
## 注意：MidiPlayer.position使用tick单位。此属性直接来自MidiPlayer.position
## 要获取毫秒值，请使用 get_position_ms()
var position: float = 0.0

## 当前播放位置（毫秒，用于向后兼容 - 不推荐使用）
## ⚠️ 已弃用：使用 position 获取tick，或使用 get_position_ms() 获取毫秒值
var position_ms: float = 0.0

## 总时长（毫秒）
var duration_ms: float = 0.0

## 可用的SoundFont列表（缓存）
var available_soundfonts: Array = []

## 默认SoundFont路径
var default_soundfont_path: String = "res://Resources/Soundfont/GeneralUser-GS.sf2"

## 当前使用的SoundFont路径
var current_soundfont_path: String = ""

## MIDI播放器配置
var midi_player_config: Dictionary = {
	"max_polyphony": 96,
	"loop": false,
	"volume_db": -20.0
}

## 信号：MIDI加载完成
signal midi_loaded(midi_data: MidiData)

## 信号：MIDI开始播放
signal midi_started

## 信号：MIDI暂停
signal midi_paused

## 信号：MIDI停止
signal midi_stopped

## 信号：MIDI播放完成
signal midi_finished

## 信号：轨道选择改变
signal tracks_changed(selected_indices: Array[int])

## 信号：音源改变
signal soundfont_changed(soundfont_path: String)

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	
	add_to_group("singleton")
	
	# 初始化MIDI播放器
	_initialize_midi_player()
	
	# 扫描可用的SoundFont
	_scan_soundfonts()
	
	# 从配置文件加载音源设置
	_load_soundfont_from_config()

func _process(_delta: float) -> void:
	if is_playing and midi_player != null:
		# 直接从MidiPlayer读取position（tick单位）
		position = midi_player.position
		
		# 同时更新position_ms用于向后兼容
		if midi_player.smf_data != null and midi_player.smf_data.timebase > 0:
			position_ms = _calculate_position_with_bpm_timeline(position, midi_player.smf_data.timebase)

## 初始化MIDI播放器
func _initialize_midi_player() -> void:
	# 检查MidiPlayer插件是否存在
	var midi_player_scene = load("res://addons/midi/MidiPlayer.tscn")
	if midi_player_scene == null:
		push_error("MidiPlayer addon not found!")
		return
	
	midi_player = midi_player_scene.instantiate()
	midi_player.name = "MidiPlayer"
	add_child(midi_player)
	
	# 配置MidiPlayer
	if midi_player.has_meta("script"):
		midi_player.max_polyphony = midi_player_config["max_polyphony"]
		midi_player.loop = midi_player_config["loop"]
		midi_player.volume_db = midi_player_config["volume_db"]
		midi_player.bus = "Master"
	
	# 连接信号
	if midi_player.has_signal("finished"):
		midi_player.finished.connect(_on_midi_finished)

## 加载MIDI文件
## 返回: success (bool)
func load_midi(midi_data: MidiData) -> bool:
	if midi_data == null:
		push_error("MidiData is null")
		return false
	
	# 保存当前MIDI数据
	current_midi_data = midi_data
	
	# 使用FileSystemManager定位MIDI文件路径
	var midi_file_path = _locate_midi_file(midi_data)
	if midi_file_path.is_empty():
		push_error("Cannot locate MIDI file for: %s" % midi_data.id)
		return false
	
	# 存储路径
	current_midi_data.midi_file_path = midi_file_path
	
	# 解析MIDI文件
	var parse_result = MidiParser.load_and_parse_midi(midi_file_path)
	if not parse_result["success"]:
		push_error("Failed to parse MIDI file: %s" % midi_file_path)
		return false
	
	# 保存解析结果
	current_notes = parse_result["notes"]
	bpm_timeline = parse_result.get("bpm_timeline", [])  # 获取BPM时间线
	
	# 对notes按start_time排序（确保时间递增）
	current_notes.sort_custom(func(a, b) -> bool:
		var a_time = a.event.start_time if a is MidiParser.Note and a.event else 0
		var b_time = b.event.start_time if b is MidiParser.Note and b.event else 0
		return a_time < b_time
	)
	
	current_midi_data.parsed_notes = current_notes
	current_midi_data.track_count = parse_result["track_infos"].size()
	current_midi_data.bpm = parse_result["bpm"]
	current_midi_data.duration_ms = parse_result["duration"]
	duration_ms = parse_result["duration"]
	
	# 如果未选择轨道，则默认选择所有轨道
	if current_midi_data.selected_track_indices.is_empty():
		for i in range(current_midi_data.track_count):
			current_midi_data.selected_track_indices.append(i)
	
	# 加载到MidiPlayer
	if midi_player != null:
		midi_player.file = midi_file_path
	
	# 发出信号
	midi_loaded.emit(current_midi_data)
	
	return true

## 播放MIDI
func play() -> void:
	if midi_player == null:
		push_error("MidiPlayer not initialized")
		return
	
	if current_midi_data == null:
		push_error("No MIDI loaded")
		return
	
	# 设置音源
	if not current_soundfont_path.is_empty():
		midi_player.soundfont = current_soundfont_path
	
	midi_player.play()
	is_playing = true
	midi_started.emit()

## 停止播放
func stop() -> void:
	if midi_player == null:
		return
	
	midi_player.stop()
	is_playing = false
	position_ms = 0.0
	midi_stopped.emit()

## 暂停播放
func pause() -> void:
	if midi_player == null:
		return
	
	midi_player.playing = false
	is_playing = false
	midi_paused.emit()

## 继续播放
func resume() -> void:
	if midi_player == null:
		return
	
	midi_player.playing = true
	is_playing = true
	midi_started.emit()

## 跳转到指定位置
## position: 位置（毫秒）
func seek(pos: float) -> void:
	if midi_player == null:
		return
	
	position_ms = pos
	# 使用BPM时间线来计算精确的tick位置
	if midi_player.smf_data != null and midi_player.smf_data.timebase > 0:
		var target_tick = _calculate_tick_from_position_with_bpm_timeline(pos, midi_player.smf_data.timebase)
		midi_player.seek(target_tick)

## 辅助函数：根据BPM时间线计算当前的实际播放时间（毫秒）
func _calculate_position_with_bpm_timeline(current_tick: float, timebase: int) -> float:
	if bpm_timeline.is_empty():
		# 如果没有BPM时间线，使用默认计算方式
		var seconds_per_tick: float = 60.0 / (120.0 * timebase)  # 默认120 BPM
		return current_tick * seconds_per_tick * 1000.0
	
	var cumulative_time_ms: float = 0.0
	
	# 遍历BPM时间线找到当前tick所在的段
	for i in range(bpm_timeline.size()):
		var entry = bpm_timeline[i]
		var entry_tick = entry["tick"]
		
		# 确定下一个BPM变化的tick
		var next_tempo_tick: float
		if i + 1 < bpm_timeline.size():
			next_tempo_tick = bpm_timeline[i + 1]["tick"]
		else:
			next_tempo_tick = current_tick + 1000000  # 大数字，表示无限远
		
		if current_tick < next_tempo_tick:
			# 当前tick在这个BPM段内
			var bpm = entry["bpm"]
			var tick_delta = current_tick - entry_tick
			var ms_per_tick = (60000.0 / bpm) / timebase
			var segment_time_ms = tick_delta * ms_per_tick
			
			return cumulative_time_ms + segment_time_ms
		else:
			# 继续下一个BPM段
			if i + 1 < bpm_timeline.size():
				var next_entry = bpm_timeline[i + 1]
				var bpm = entry["bpm"]
				var tick_delta = next_entry["tick"] - entry_tick
				var ms_per_tick = (60000.0 / bpm) / timebase
				var segment_time_ms = tick_delta * ms_per_tick
				cumulative_time_ms += segment_time_ms
	
	return cumulative_time_ms

## 辅助函数：根据BPM时间线计算从时间位置（毫秒）到tick的转换
func _calculate_tick_from_position_with_bpm_timeline(target_time_ms: float, timebase: int) -> float:
	if bpm_timeline.is_empty():
		# 如果没有BPM时间线，使用默认计算方式
		var seconds_per_tick: float = 60.0 / (120.0 * timebase)  # 默认120 BPM
		return target_time_ms / 1000.0 / seconds_per_tick
	
	# 遍历BPM时间线找到目标时间所在的段
	for i in range(bpm_timeline.size()):
		var entry = bpm_timeline[i]
		var entry_tick = entry["tick"]
		var entry_time_ms = entry["time_ms"]
		
		# 确定下一个BPM变化
		var next_entry = null
		if i + 1 < bpm_timeline.size():
			next_entry = bpm_timeline[i + 1]
		
		if next_entry == null or target_time_ms <= next_entry["time_ms"]:
			# 目标时间在这个BPM段内
			var bpm = entry["bpm"]
			var time_in_segment = target_time_ms - entry_time_ms
			var ms_per_tick = (60000.0 / bpm) / timebase
			var tick_offset = time_in_segment / ms_per_tick
			
			return entry_tick + tick_offset
	
	# 不应该到达这里，返回最后的tick
	return bpm_timeline[-1]["tick"]

## 设置选中的轨道和通道（支持新格式）
## 接受 Array[Dictionary] 格式: [{"track": int, "channel": int}, ...]
## 或兼容旧 Array[int] 格式（仅按track选中所有channel）
func set_selected_tracks(tracks_data) -> void:
	if current_midi_data == null:
		return
	
	# 兼容旧格式 Array[int]
	if tracks_data is Array:
		if tracks_data.is_empty():
			current_midi_data.selected_track_configs.clear()
			return
		
		# 检查是否为新格式 Array[Dictionary]
		if tracks_data[0] is Dictionary:
			# 新格式：[{"track": int, "channel": int}, ...]
			current_midi_data.selected_track_configs.clear()
			for item in tracks_data:
				var track_idx = item.get("track", -1)
				var channel = item.get("channel", -1)
				if track_idx >= 0 and channel >= 0:
					current_midi_data.set_track_channel_enabled(track_idx, channel, true)
		else:
			# 旧格式：Array[int] - 为了兼容，将其转换为配置格式
			# 注：旧格式仅保留track信息，channel信息会丢失
			# 仅用于向后兼容，不推荐使用
			var track_indices = tracks_data as Array[int]
			current_midi_data.selected_track_indices = track_indices
	
	tracks_changed.emit(tracks_data)

## 设置音源文件
func set_soundfont(soundfont_name: String) -> bool:
	"""
	设置MIDI播放使用的音源文件
	
	优先级：
	1. user://files/Soundfont/{soundfont_name}.sf2
	2. res://Resources/Soundfont/{soundfont_name}.sf2
	3. 回退到内置默认 GeneralUser-GS.sf2
	
	Args:
		soundfont_name: 音源文件名（不含.sf2扩展名和[内置]标签）
	
	Returns:
		bool: 是否设置成功
	"""
	# 验证和定位soundfont文件
	var soundfont_path = _locate_soundfont(soundfont_name)
	
	if soundfont_path.is_empty():
		# 文件不存在，尝试回退到默认
		print("[MidiPlaybackManager] Soundfont '%s' not found, falling back to default" % soundfont_name)
		soundfont_path = _locate_soundfont("GeneralUser-GS")
		
		if soundfont_path.is_empty():
			# 默认文件也不存在，作为最后的回退
			soundfont_path = default_soundfont_path
			push_warning("[MidiPlaybackManager] Default soundfont also not found, using fallback: %s" % soundfont_path)
	
	current_soundfont_path = soundfont_path
	if current_midi_data != null:
		# 提取文件名用于存储（不带路径和扩展名）
		var file_name = soundfont_path.get_file().get_basename()
		current_midi_data.set_soundfont(file_name)
	
	# 如果正在播放，立即切换音源
	if is_playing and midi_player != null:
		midi_player.soundfont = soundfont_path
	
	soundfont_changed.emit(soundfont_path)
	print("[MidiPlaybackManager] Soundfont set to: %s" % soundfont_path)
	return true

## 辅助函数：定位soundfont文件（user优先）
func _locate_soundfont(soundfont_name: String) -> String:
	"""
	定位soundfont文件，user://优先于res://
	
	Args:
		soundfont_name: 文件名不含.sf2扩展名
	
	Returns:
		String: 完整文件路径，若不存在返回空字符串
	"""
	# 第一步：检查user://files/Soundfont/
	var user_path = "user://files/Soundfont/".path_join(soundfont_name + ".sf2")
	if FileAccess.file_exists(user_path):
		return user_path
	
	# 第二步：检查res://Resources/Soundfont/
	var res_path = "res://Resources/Soundfont/".path_join(soundfont_name + ".sf2")
	if ResourceLoader.exists(res_path):
		return res_path
	
	return ""

## 设置音量
func set_volume_db(volume: float) -> void:
	if midi_player == null:
		return
	
	midi_player.volume_db = volume
	midi_player_config["volume_db"] = volume

## 设置特定轨道的音量（相对于主音量）
func set_track_volume_db(track_index: int, volume_db: float) -> void:
	if midi_player == null or current_midi_data == null:
		return
	
	# 注：此方法为框架实现
	# MidiPlayer插件可能不直接支持轨道级音量控制
	# 实际实现可能需要在MidiPlayer或自定义播放器中扩展
	# 当前版本记录日志供调试
	print("[MidiPlaybackManager] Set track %d volume to %.2f dB" % [track_index, volume_db])

## 设置人声音量（占位符 - 待后续实现AudioManager集成）
func set_vocal_volume_db(volume_db: float) -> void:
	# 注：此方法为占位符
	# 人声播放应该由AudioManager处理，而不是MidiPlaybackManager
	# 这里记录日志供调试
	print("[MidiPlaybackManager] Set vocal volume to %.2f dB (not implemented)" % volume_db)

## 获取已选中轨道对应的Note
func get_selected_track_notes() -> Array:
	if current_midi_data == null or current_notes.is_empty():
		return []
	
	return MidiParser.extract_notes_by_track(current_notes, current_midi_data.selected_track_indices)

## 扫描可用的SoundFont文件
func _scan_soundfonts() -> void:
	available_soundfonts.clear()
	
	var soundfont_dir = "res://Resources/Soundfont"
	var dir = DirAccess.open(soundfont_dir)
	
	if dir == null:
		push_warning("Soundfont directory not found: %s" % soundfont_dir)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".sf2"):
			available_soundfonts.append(file_name)
		file_name = dir.get_next()

## 获取可用的SoundFont列表
func get_available_soundfonts() -> Array:
	return available_soundfonts.duplicate()

## 辅助函数：定位MIDI文件路径
func _locate_midi_file(midi_data: MidiData) -> String:
	# 使用FileSystemManager的文件索引来定位MIDI文件
	var filesystem_manager = FileSystemManager.instance
	if filesystem_manager == null:
		push_error("FileSystemManager not initialized")
		return ""

	# 从charts索引中查找（优先使用已缓存的路径）
	var charts_index = filesystem_manager.get_charts_index()
	for folder_name in charts_index.keys():
		var metadata: Dictionary = charts_index[folder_name]
		var chart_id: String = metadata.get("id", "")
		if chart_id == midi_data.id or chart_id == midi_data.file_hash:
			# 首选使用索引中缓存的路径
			var chart_path: String = metadata.get("path", "")
			if chart_path.is_empty():
				chart_path = FileSystemManager.CHARTS_DIR.path_join(folder_name)
			# 1) 按 chart_id 命名的mid
			var midi_file_path: String = chart_path.path_join(chart_id + ".mid")
			if FileAccess.file_exists(midi_file_path):
				return midi_file_path
			# 2) 按 midi_data.id 命名的mid（旧格式）
			var alt_id_path: String = chart_path.path_join(midi_data.id + ".mid")
			if FileAccess.file_exists(alt_id_path):
				return alt_id_path
			# 3) 按 midi_data.file_hash 命名的mid（若提供）
			if not midi_data.file_hash.is_empty():
				var hash_path: String = chart_path.path_join(midi_data.file_hash + ".mid")
				if FileAccess.file_exists(hash_path):
					return hash_path
			# 4) 作为后备，尝试 res:// 目录同名路径
			var res_chart_path: String = FileSystemManager.DEFAULT_CHARTS_SRC.path_join(folder_name)
			var res_candidates = [
				res_chart_path.path_join(chart_id + ".mid"),
				res_chart_path.path_join(midi_data.id + ".mid"),
				res_chart_path.path_join(midi_data.file_hash + ".mid") if not midi_data.file_hash.is_empty() else ""
			]
			for candidate in res_candidates:
				if candidate != "" and FileAccess.file_exists(candidate):
					return candidate

	return ""

## 回调：MIDI播放完成
func _on_midi_finished() -> void:
	is_playing = false
	midi_finished.emit()

## 获取当前MIDI的轨道信息列表
func get_track_infos() -> Array:
	if current_midi_data == null or current_notes.is_empty():
		return []
	
	# 重新解析以获取完整轨道信息
	var parse_result = MidiParser.load_and_parse_midi(current_midi_data.midi_file_path)
	if parse_result["success"]:
		return parse_result["track_infos"]
	
	return []

## ========== Note分类接口 ==========
## 将解析的note分为两类：自动播放和手动控制
## 该方法当前仅为占位，待后续将Touhou Mix原有生成逻辑移植过来
## @param	all_notes				所有已解析的note列表
## @param	manual_track_indices	需要手动控制的轨道索引数组
## @return 返回 {auto_play_notes: Array[Note], manual_control_notes: Array[Note]}
func classify_notes(all_notes: Array, manual_track_indices: Array[int] = []) -> Dictionary:
	var result = {
		"auto_play_notes": [],
		"manual_control_notes": []
	}
	
	if all_notes.is_empty():
		return result
	
	# 创建manual轨道集合便于快速查询
	var manual_tracks_set = {}
	for track_idx in manual_track_indices:
		manual_tracks_set[track_idx] = true
	
	# ========== 预留分类逻辑 ==========
	# 此处将在后续实现具体的分类算法
	# 目前暂时将所有note划为自动播放，待游戏逻辑完成后填充
	#
	# 当前暂时实现方案：
	for note in all_notes:
		if note is MidiParser.Note:
			# 检查note的轨道是否在手动控制列表中
			if note.event.track_index in manual_tracks_set:
				# 转换为ManualControlNote
				var manual_note = MidiParser.ManualControlNote.new(note.event, note.note_index)
				manual_note.midi_player = midi_player
				result["manual_control_notes"].append(manual_note)
			else:
				# 保持为AutoPlayNote
				result["auto_play_notes"].append(note)
		else:
			# 非Note类型，默认为自动播放
			result["auto_play_notes"].append(note)
	
	print("[MidiPlaybackManager] Classified notes: %d auto-play, %d manual-control" % 
		[result["auto_play_notes"].size(), result["manual_control_notes"].size()])
	
	return result

## 设置MidiPlayer的手动控制note标记
## 游戏完成分类后，应调用此方法通知MidiPlayer哪些note需要手动控制
## @param	manual_control_notes	ManualControlNote数组
func set_manual_control_notes(manual_control_notes: Array) -> void:
	if midi_player == null:
		push_warning("[MidiPlaybackManager] MidiPlayer not initialized")
		return
	
	# 构建手动控制note的字典 {channel: {pitch: true}}
	var manually_controlled: Dictionary = {}
	
	for note in manual_control_notes:
		if note is MidiParser.ManualControlNote:
			var channel = note.event.channel
			var pitch = note.event.pitch
			
			if not manually_controlled.has(channel):
				manually_controlled[channel] = {}
			
			manually_controlled[channel][pitch] = true
	
	# 传递给MidiPlayer
	midi_player.set_manually_controlled_notes(manually_controlled)

## ========== 位置单位转换工具 ==========
## 将tick位置转换为毫秒（使用BPM时间线）
func tick_to_ms(tick: float) -> float:
	return _calculate_position_with_bpm_timeline(tick, midi_player.smf_data.timebase)

## 获取当前播放位置（毫秒）
## 这是对position_ms的替代方法，更明确地表示返回值的单位
func get_position_ms() -> float:
	return position_ms

## 获取当前播放位置（tick）
## 这是对position的替代方法，更明确地表示返回值的单位
func get_position_tick() -> float:
	return position

## 从配置文件加载音源设置
## 优先级：user://files/settings.ini > res://Resources/Config/config.ini > 默认值
func _load_soundfont_from_config() -> void:
	var config_loader = ConfigLoader.new()
	
	# 1. 尝试加载用户配置（优先）
	var user_config_path = "user://files/settings.ini"
	if FileAccess.file_exists(user_config_path):
		var user_config = config_loader.load_config(user_config_path)
		if not user_config.is_empty():
			var soundfont_name = config_loader.get_value(user_config, "Gameplay", "soundfont_file", "")
			if not soundfont_name.is_empty():
				# 去掉 .sf2 扩展名和 [内置] 标签（如果有）
				soundfont_name = soundfont_name.replace(".sf2", "").replace("[内置]", "").strip_edges()
				print("[MidiPlaybackManager] Loading soundfont from user config: %s" % soundfont_name)
				if set_soundfont(soundfont_name):
					return
	
	# 2. 尝试加载默认配置
	var default_config_path = "res://Resources/Config/config.ini"
	var default_config = config_loader.load_config(default_config_path)
	if not default_config.is_empty():
		var soundfont_name = config_loader.get_value(default_config, "Gameplay", "soundfont_file", "GeneralUser-GS.sf2")
		# 去掉 .sf2 扩展名
		soundfont_name = soundfont_name.replace(".sf2", "").strip_edges()
		print("[MidiPlaybackManager] Loading soundfont from default config: %s" % soundfont_name)
		if set_soundfont(soundfont_name):
			return
	
	# 3. 使用硬编码的默认值
	print("[MidiPlaybackManager] Using hardcoded default soundfont")
	current_soundfont_path = default_soundfont_path
	soundfont_changed.emit(current_soundfont_path)
