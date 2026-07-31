## MIDI解析工具类
## 提供MIDI文件的加载、解析和Note事件提取功能
class_name MidiParser

## MIDI Note事件数据结构（内部使用，保留以向后兼容）
class NoteEvent:
	var pitch: int              # MIDI音符号 (0-127)
	var velocity: int           # 速度/力度 (1-127)
	var start_time: float       # 开始时间（MIDI Tick单位，不是毫秒）
	var duration: float         # 持续时间（MIDI Tick单位，不是毫秒）
	var track_index: int        # 所在轨道索引
	var channel: int            # MIDI通道号 (0-15)
	
	func _init(p: int, v: int, start: float, dur: float, track: int, ch: int) -> void:
		pitch = p
		velocity = v
		start_time = start
		duration = dur
		track_index = track
		channel = ch
	
	func _to_string() -> String:
		return "NoteEvent(pitch=%d, vel=%d, start=%.0f, dur=%.0f)" % [pitch, velocity, start_time, duration]

## Note - MIDI 音符对象，持有原始 NoteEvent 数据
## 说明：原 AutoPlayNote / ManualControlNote 子类已移除——外部消费者均直接调用
## midi_player.trigger_note_on/off，不依赖 Note 的 start/stop 方法；
## 原 is_on/is_off/note_index 字段无任何消费者，一并移除以缩小对象头（6万音符省 ~3-4 MB）
class Note:
	## 原始Note事件数据
	var event: NoteEvent

	func _init(note_evt: NoteEvent) -> void:
		event = note_evt

	func _to_string() -> String:
		return "Note(pitch=%d, start=%.0f, dur=%.0f)" % [event.pitch, event.start_time, event.duration]

## MIDI轨道信息
## 说明：原 note_count 字段无外部消费者（TrackView 用的是 UI 文本 note_count_passed），
## 已移除；events 在 MidiPlaybackManager 提取乐器后会被 clear，释放 SMF 原始事件内存
class TrackInfo:
	var index: int              # 轨道索引
	var name: String            # 轨道名称
	var events: Array           # 包含的所有MIDI事件

	func _init(idx: int, n: String = "") -> void:
		index = idx
		name = n if not n.is_empty() else "Track %d" % idx
		events = []

## 加载并解析MIDI文件
## 返回: {success: bool, notes: Array[Note], bpm: float, duration: float, track_infos: Array[TrackInfo], bpm_timeline: Array[Dictionary]}
## 说明:
##   - notes: 包含 Note 对象的数组，用于游戏逻辑
##   - bpm_timeline 格式: [{tick: int, bpm: float, time_ms: float}, ...]
static func load_and_parse_midi(file_path: String) -> Dictionary:
	var result = {
		"success": false,
		"notes": [],                  # Array[Note]
		"bpm": 120.0,
		"duration": 0.0,
		"track_infos": [],
		"timebase": 480,
		"bpm_timeline": []  # BPM变化时间线
	}
	
	# 检查文件是否存在
	if not FileAccess.file_exists(file_path):
		# 后备：尝试将用户数据目录路径替换为 res://Resources
		var fallback_path = file_path
		var files_dir = PathHelper.get_files_dir()
		if file_path.begins_with(files_dir):
			fallback_path = file_path.replace(files_dir, "res://Resources/")

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
	var max_end_tick: int = 0  # 最大的tick值（而不是时间）
	var bpm_timeline: Array[Dictionary] = []  # BPM变化时间线 [{tick, bpm, time_ms}, ...]
	var current_bpm: float = 120.0  # 当前BPM
	
	# 首先添加初始BPM
	bpm_timeline.append({
		"tick": 0,
		"bpm": current_bpm,
		"time_ms": 0.0
	})
	
	for track_idx in range(smf_data.tracks.size()):
		var track = smf_data.tracks[track_idx]
		var track_info = TrackInfo.new(track_idx)
		
		for event_chunk in track.events:
			# 保持为 tick 单位，不转换为毫秒
			var current_tick = event_chunk.time
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
						var new_bpm = 60000000.0 / micros_per_beat  # 微秒/beat转BPM
						result["bpm"] = new_bpm
						current_bpm = new_bpm
						
						# 添加到BPM时间线
						bpm_timeline.append({
							"tick": current_tick,
							"bpm": new_bpm
						})
			
			# 处理音符开始事件
			elif event.type == SMF.MIDIEventType.note_on:
				if event.velocity > 0:
					# 创建唯一键来追踪NoteOn/Off对
					var key = "%d_%d_%d" % [channel, event.note, current_tick]
					note_on_map[key] = {
						"pitch": event.note,
						"velocity": event.velocity,
						"start_tick": current_tick,
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
						var duration = current_tick - note_data["start_tick"]
						var note_event = NoteEvent.new(
							note_data["pitch"],
							note_data["velocity"],
							note_data["start_tick"],
							duration,
							note_data["track_index"],
							note_data["channel"]
						)
						notes.append(note_event)
						note_on_map.erase(found_key)
				if current_tick > max_end_tick:
					max_end_tick = current_tick
			
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
					var duration = current_tick - note_data["start_tick"]
					
					# 创建NoteEvent对象
					var note_event = NoteEvent.new(
						note_data["pitch"],
						note_data["velocity"],
						note_data["start_tick"],
						duration,
						note_data["track_index"],
						note_data["channel"]
					)
					notes.append(note_event)
					note_on_map.erase(found_key)
					
				# 更新最大tick
				if current_tick > max_end_tick:
					max_end_tick = current_tick
		
		track_infos.append(track_info)
	
	# 处理未匹配的NoteOn（没有对应的NoteOff）
	for key in note_on_map.keys():
		var note_data = note_on_map[key]
		# 假设持续时间为100ms
		var note_event = NoteEvent.new(
			note_data["pitch"],
			note_data["velocity"],
			note_data["start_tick"],
			100.0,
			note_data["track_index"],
			note_data["channel"]
		)
		notes.append(note_event)
	
	# 精确计算BPM时间线中的实际时间
	_calculate_bpm_timeline_time(bpm_timeline, smf_data.timebase)
	
	# 使用BPM时间线精确计算总时长
	var actual_duration: float = _calculate_duration_with_bpm_timeline(max_end_tick, bpm_timeline, smf_data.timebase)
	
	# 将NoteEvent转换为Note对象
	var note_objects: Array[Note] = []
	for note_evt in notes:
		note_objects.append(Note.new(note_evt))
	
	result["notes"] = note_objects
	result["duration"] = actual_duration
	result["track_infos"] = track_infos
	result["bpm_timeline"] = bpm_timeline
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

## 精确计算BPM时间线中的实际时间（考虑BPM变化）
static func _calculate_bpm_timeline_time(bpm_timeline: Array, timebase: int) -> void:
	if bpm_timeline.is_empty():
		return
	
	var cumulative_time_ms: float = 0.0
	
	for i in range(1, bpm_timeline.size()):
		var prev_entry = bpm_timeline[i - 1]
		var curr_entry = bpm_timeline[i]
		
		var tick_delta = curr_entry["tick"] - prev_entry["tick"]
		var bpm = prev_entry["bpm"]
		
		# 根据BPM计算这段的实际时间
		# 1 quarter note = 60000 / BPM 毫秒
		# 1 tick = (60000 / BPM) / timebase 毫秒
		var ms_per_tick = (60000.0 / bpm) / timebase
		var segment_time_ms = tick_delta * ms_per_tick
		
		cumulative_time_ms += segment_time_ms
		curr_entry["time_ms"] = cumulative_time_ms
	
	# 更新第一个条目的时间
	if bpm_timeline.size() > 0:
		bpm_timeline[0]["time_ms"] = 0.0

## 辅助函数：根据BPM时间线计算从0到指定tick的精确时长
static func _calculate_duration_with_bpm_timeline(max_tick: int, bpm_timeline: Array, timebase: int) -> float:
	if bpm_timeline.is_empty():
		# 如果没有BPM时间线，使用默认的120 BPM
		var ms_per_tick = (60000.0 / 120.0) / timebase
		return max_tick * ms_per_tick
	
	var cumulative_time_ms: float = 0.0
	
	# 遍历BPM时间线找到max_tick所在的段
	for i in range(bpm_timeline.size()):
		var entry = bpm_timeline[i]
		var entry_tick = entry["tick"]
		
		# 确定下一个BPM变化的tick
		var next_tempo_tick: float
		if i + 1 < bpm_timeline.size():
			next_tempo_tick = bpm_timeline[i + 1]["tick"]
		else:
			next_tempo_tick = max_tick + 1000000  # 大数字，表示无限远
		
		if max_tick < next_tempo_tick:
			# max_tick在这个BPM段内
			var bpm = entry["bpm"]
			var tick_delta = max_tick - entry_tick
			var ms_per_tick = (60000.0 / bpm) / timebase
			var segment_time_ms = tick_delta * ms_per_tick
			
			# 加上前面所有BPM段的时间
			if entry["time_ms"] != null:
				return entry["time_ms"] + segment_time_ms
			else:
				return cumulative_time_ms + segment_time_ms
		else:
			# 继续下一个BPM段，累加当前段的时间
			if i + 1 < bpm_timeline.size():
				var next_entry = bpm_timeline[i + 1]
				# next_entry["time_ms"] 已经在 _calculate_bpm_timeline_time 中计算过了
				cumulative_time_ms = next_entry.get("time_ms", 0.0)
	
	# 如果到这里，返回最后计算的累积时间
	return cumulative_time_ms

## 辅助函数：将MIDI时间转换为毫秒
static func _convert_time_to_ms(time: int, timebase: int) -> float:
	# 假设标准节拍=120BPM，则一个quarter note = 500ms
	# time单位为timebase divisions，所以: ms = time * (500 / timebase)
	return time * 500.0 / timebase

## 计算Note的八度和相对音高（用于键盘映射）
static func get_note_octave_and_relative_pitch(midi_note: int) -> Dictionary:
	# C0=0, C1=12, C2=24, ...
	@warning_ignore("integer_division")
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
