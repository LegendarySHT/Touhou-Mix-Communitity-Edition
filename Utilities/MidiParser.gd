## MIDI解析工具类
## 提供MIDI文件的加载、解析和Note事件提取功能
class_name MidiParser

## MIDI Note事件数据结构
class NoteEvent:
	var pitch: int              # MIDI音符号 (0-127)
	var velocity: int           # 速度/力度 (1-127)
	var start_time_ms: float    # 开始时间（毫秒）
	var duration_ms: float      # 持续时间（毫秒）
	var track_index: int        # 所在轨道索引
	var channel: int            # MIDI通道号 (0-15)
	
	func _init(p: int, v: int, start: float, dur: float, track: int, ch: int) -> void:
		pitch = p
		velocity = v
		start_time_ms = start
		duration_ms = dur
		track_index = track
		channel = ch
	
	func _to_string() -> String:
		return "NoteEvent(pitch=%d, vel=%d, start=%.0f, dur=%.0f)" % [pitch, velocity, start_time_ms, duration_ms]

## MIDI轨道信息
class TrackInfo:
	var index: int              # 轨道索引
	var name: String            # 轨道名称
	var note_count: int         # 音符数量
	var events: Array           # 包含的所有MIDI事件
	
	func _init(idx: int, n: String = "") -> void:
		index = idx
		name = n if not n.is_empty() else "Track %d" % idx
		note_count = 0
		events = []

## 加载并解析MIDI文件
## 返回: {success: bool, notes: Array[NoteEvent], bpm: float, duration: float, track_infos: Array[TrackInfo]}
static func load_and_parse_midi(file_path: String) -> Dictionary:
	var result = {
		"success": false,
		"notes": [],
		"bpm": 120.0,
		"duration": 0.0,
		"track_infos": [],
		"timebase": 480
	}
	
	# 检查文件是否存在（user:// 使用 FileAccess）
	if not FileAccess.file_exists(file_path):
		# 后备：尝试将 user://files 替换为 res://Resources
		var fallback_path = file_path
		if file_path.begins_with("user://files"):
			fallback_path = file_path.replace("user://files", "res://Resources")

		if not FileAccess.file_exists(fallback_path):
			push_error("MIDI file not found: %s" % file_path)
			return result
		else:
			file_path = fallback_path
	
	# 使用SMF解析MIDI文件
	var smf = SMF.new()
	var smf_result = smf.read_file(file_path)
	
	if smf_result.error != OK or smf_result.data == null:
		push_error("Failed to parse MIDI file: %s (error: %s)" % [file_path, smf_result.error])
		return result
	
	var smf_data: SMF.SMFData = smf_result.data
	
	# 设置基本信息
	result["timebase"] = smf_data.timebase
	result["bpm"] = 120.0  # 默认BPM，会从MIDI事件中更新
	
	# 解析所有轨道
	var notes: Array[NoteEvent] = []
	var note_on_map: Dictionary = {}  # 用于匹配NoteOn和NoteOff事件
	var track_infos: Array[TrackInfo] = []
	var max_end_time: float = 0.0
	
	for track_idx in range(smf_data.tracks.size()):
		var track = smf_data.tracks[track_idx]
		var track_info = TrackInfo.new(track_idx)
		
		for event_chunk in track.events:
			var time_ms = _convert_time_to_ms(event_chunk.time, smf_data.timebase)
			var event = event_chunk.event
			var channel = event_chunk.channel_number
			
			# 记录轨道事件
			track_info.events.append(event_chunk)
			
			# 处理节拍事件（提取BPM）
			if event.type == SMF.MIDIEventType.system_event:
				var args = (event as SMF.MIDIEventSystemEvent).args
				if args.has("type") and args["type"] == SMF.MIDISystemEventType.set_tempo:
					var micros_per_beat: float = float(args.get("bpm", 0))
					if micros_per_beat > 0.0:
						result["bpm"] = 60000000.0 / micros_per_beat  # 微秒/beat转BPM
			
			# 处理音符开始事件
			elif event.type == SMF.MIDIEventType.note_on:
				if event.velocity > 0:
					# 创建唯一键来追踪NoteOn/Off对
					var key = "%d_%d_%d" % [channel, event.note, time_ms]
					note_on_map[key] = {
						"pitch": event.note,
						"velocity": event.velocity,
						"start_time": time_ms,
						"track_index": track_idx,
						"channel": channel
					}
				else:
					# velocity 为0的 note_on 等同 note_off
					var note_value = event.note
					var found_key = ""
					for stored_key in note_on_map.keys():
						if stored_key.begins_with("%d_%d" % [channel, note_value]):
							found_key = stored_key
							break
					if not found_key.is_empty():
						var note_data = note_on_map[found_key]
						var duration = time_ms - note_data["start_time"]
						var note_event = NoteEvent.new(
							note_data["pitch"],
							note_data["velocity"],
							note_data["start_time"],
							duration,
							note_data["track_index"],
							note_data["channel"]
						)
						notes.append(note_event)
						track_info.note_count += 1
						if time_ms > max_end_time:
							max_end_time = time_ms
						note_on_map.erase(found_key)
			
			# 处理音符结束事件
			elif event.type == SMF.MIDIEventType.note_off:
				var note_value = event.note
				var found_key = ""
				# 搜索最接近的NoteOn
				for stored_key in note_on_map.keys():
					if stored_key.begins_with("%d_%d" % [channel, note_value]):
						found_key = stored_key
						break
				
				if found_key != "":
					var note_data = note_on_map[found_key]
					var duration = time_ms - note_data["start_time"]
					
					# 创建NoteEvent对象
					var note_event = NoteEvent.new(
						note_data["pitch"],
						note_data["velocity"],
						note_data["start_time"],
						duration,
						note_data["track_index"],
						note_data["channel"]
					)
					notes.append(note_event)
					track_info.note_count += 1
					
					# 更新最大时间
					if time_ms > max_end_time:
						max_end_time = time_ms
					
					# 移除已处理的NoteOn
					note_on_map.erase(found_key)
		
		track_infos.append(track_info)
	
	# 处理未匹配的NoteOn（没有对应的NoteOff）
	for key in note_on_map.keys():
		var note_data = note_on_map[key]
		# 假设持续时间为100ms
		var note_event = NoteEvent.new(
			note_data["pitch"],
			note_data["velocity"],
			note_data["start_time"],
			100.0,
			note_data["track_index"],
			note_data["channel"]
		)
		notes.append(note_event)
		var track_idx = note_data["track_index"]
		if track_idx < track_infos.size():
			track_infos[track_idx].note_count += 1
	
	result["notes"] = notes
	result["duration"] = max_end_time
	result["track_infos"] = track_infos
	result["success"] = true
	
	return result

## 从已解析的音符列表中提取特定轨道的Note
static func extract_notes_by_track(all_notes: Array, track_indices: Array[int]) -> Array:
	var filtered_notes: Array = []
	var track_set = {}
	
	# 创建轨道集合便于快速查询
	for track_idx in track_indices:
		track_set[track_idx] = true
	
	# 过滤Note
	for note in all_notes:
		if note is MidiParser.NoteEvent and note.track_index in track_set:
			filtered_notes.append(note)
	
	return filtered_notes

## 根据通道号过滤Note（用于分离鼓声等特殊通道）
static func extract_notes_by_channel(all_notes: Array, channels: Array[int]) -> Array:
	var filtered_notes: Array = []
	var channel_set = {}
	
	for ch in channels:
		channel_set[ch] = true
	
	for note in all_notes:
		if note is MidiParser.NoteEvent and note.channel in channel_set:
			filtered_notes.append(note)
	
	return filtered_notes

## 获取特定轨道的信息
static func get_track_info(track_infos: Array, track_index: int) -> MidiParser.TrackInfo:
	if track_index >= 0 and track_index < track_infos.size():
		return track_infos[track_index] as MidiParser.TrackInfo
	return null

## 按时间排序Note
static func sort_notes_by_time(notes: Array) -> Array:
	var sorted_notes = notes.duplicate()
	sorted_notes.sort_custom(func(a, b):
		return a.start_time_ms < b.start_time_ms
	)
	return sorted_notes

## 辅助函数：将MIDI时间转换为毫秒
static func _convert_time_to_ms(time: int, timebase: int) -> float:
	# 假设标准节拍=120BPM，则一个quarter note = 500ms
	# time单位为timebase divisions，所以: ms = time * (500 / timebase)
	return time * 500.0 / timebase

## 计算Note的八度和相对音高（用于键盘映射）
static func get_note_octave_and_relative_pitch(midi_note: int) -> Dictionary:
	# C0=0, C1=12, C2=24, ...
	var octave = (midi_note / 12) - 1
	var relative_pitch = midi_note % 12  # 0=C, 1=C#, ..., 11=B
	
	return {
		"octave": octave,
		"relative_pitch": relative_pitch,
		"note_name": ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][relative_pitch]
	}

## 生成MIDI Note的可读名称
static func get_note_name(midi_note: int) -> String:
	var octave_info = get_note_octave_and_relative_pitch(midi_note)
	return "%s%d" % [octave_info["note_name"], octave_info["octave"]]
