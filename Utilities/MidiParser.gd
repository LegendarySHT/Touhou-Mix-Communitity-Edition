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

## MIDI轨道信息
## 说明：原 note_count 字段无外部消费者（TrackView 用的是 UI 文本 note_count_passed），已移除
## 原 events 字段（SMF 原始事件）已随 C# MidiParserNative 接管解析而移除——乐器信息由 C# 一次性提取到 track_instruments
class TrackInfo:
	var index: int              # 轨道索引
	var name: String            # 轨道名称

	func _init(idx: int, n: String = "") -> void:
		index = idx
		name = n if not n.is_empty() else "Track %d" % idx

## 加载并解析MIDI文件（薄包装：调用 C# MidiParserNative 完成 SMF 解析）
## 返回: {success: bool, notes: Array, soa: Dictionary, bpm: float, duration: float, track_infos: Array[TrackInfo], bpm_timeline: Array[Dictionary], max_end_tick: int, track_instruments: Dictionary}
## 说明:
##   - notes: 空数组（NoteEvent 重建由调用方在主线程通过 build_notes_from_soa 完成）
##   - soa: 紧凑 SOA 数组 {pitches, velocities, start_ticks, durations, track_indices, channels}（PackedInt32Array）
##   - bpm_timeline 格式: [{tick: int, bpm: float, time_ms: float}, ...]
##   - max_end_tick: 所有音符 end_tick 的最大值，用于 NoteDisplayer ct 异常保护
##   - track_instruments: C# 一次性提取的 (track, channel) → {bank, program} 映射
##   - track_infos: TrackInfo 数组（仅 index/name，乐器信息已由 C# 提取到 track_instruments）
## 线程安全: 本函数可在 worker 线程调用（C# 纯 .NET + PackedArray marshalling 安全）；
##          NoteEvent 是 RefCounted，在 worker 线程批量创建会触发 StringName 引用计数损坏（Android ARM 弱内存模型），
##          因此本函数不创建 NoteEvent，由调用方在主线程调用 build_notes_from_soa 重建
static func load_and_parse_midi(file_path: String) -> Dictionary:
	var result = {
		"success": false,
		"notes": [],
		"soa": {},
		"bpm": 120.0,
		"duration": 0.0,
		"track_infos": [],
		"timebase": 480,
		"bpm_timeline": [],
		"max_end_tick": 0,
		"track_instruments": {},
	}

	# 检查文件是否存在
	if not FileAccess.file_exists(file_path):
		var fallback_path = file_path
		var files_dir = PathHelper.get_files_dir()
		if file_path.begins_with(files_dir):
			fallback_path = file_path.replace(files_dir, "res://Resources/")
		if not FileAccess.file_exists(fallback_path):
			push_error("MIDI file not found: %s" % file_path)
			return result
		else:
			file_path = fallback_path

	# 读取文件为 PackedByteArray
	var fa := FileAccess.open(file_path, FileAccess.READ)
	if fa == null:
		push_error("Cannot open MIDI file: %s" % file_path)
		return result
	var bytes := fa.get_buffer(fa.get_length())
	fa.close()

	# 调用 C# 原生解析器（纯 .NET，线程安全）
	var parser := MidiParserNative.new()
	var native: Dictionary = parser.Parse(bytes)

	if not native.get("success", false):
		push_error("C# MidiParserNative failed: %s" % native.get("error_msg", "unknown"))
		return result

	# 保留 SOA 数组（NoteEvent 重建由调用方在主线程完成，避免 worker 线程批量创建 RefCounted）
	# 详见 build_notes_from_soa
	var count: int = (native["pitches"] as PackedInt32Array).size()

	# 重建 bpm_timeline 为 Array[Dictionary]（保持下游 entry["tick"]/["bpm"]/["time_ms"] 访问兼容）
	var tl_ticks: PackedInt32Array = native["bpm_timeline_ticks"]
	var tl_bpms: PackedFloat32Array = native["bpm_timeline_bpms"]
	var tl_times_ms: PackedFloat32Array = native["bpm_timeline_times_ms"]
	var tl_count := tl_ticks.size()
	var bpm_timeline: Array = []
	for i in range(tl_count):
		bpm_timeline.append({
			"tick": tl_ticks[i],
			"bpm": float(tl_bpms[i]),
			"time_ms": float(tl_times_ms[i]),
		})

	# 重建 track_infos（仅 index/name——乐器信息已由 C# 提取到 track_instruments）
	var track_count: int = native["track_count"]
	var track_infos: Array[TrackInfo] = []
	track_infos.resize(track_count)
	for i in range(track_count):
		track_infos[i] = TrackInfo.new(i)

	result["notes"] = []  # NoteEvent 由调用方在主线程通过 build_notes_from_soa 重建
	result["soa"] = {
		"pitches": native["pitches"],
		"velocities": native["velocities"],
		"start_ticks": native["start_ticks"],
		"durations": native["durations"],
		"track_indices": native["track_indices"],
		"channels": native["channels"],
	}
	result["bpm"] = float(native["bpm"])
	result["duration"] = float(native["duration_ms"])
	result["track_infos"] = track_infos
	result["timebase"] = int(native["timebase"])
	result["bpm_timeline"] = bpm_timeline
	result["max_end_tick"] = int(native["max_end_tick"])
	result["track_instruments"] = native["track_instruments"]
	result["success"] = true

	var parse_ms: float = float(native.get("parse_time_ms", 0.0))
	GLogger.info("MIDI parsed (C#): %d notes, %.0fms, parse=%.1fms" % [count, result["duration"], parse_ms], "MidiParser")

	return result

## 从 SOA 数组重建 NoteEvent 对象（必须在主线程调用）
## SOA 来自 load_and_parse_midi 返回值的 "soa" 字段
## C# 侧已按 start_tick 升序排序，重建后的 notes 数组即为最终顺序
## 重建完成后调用方可 erase "soa" 字段以释放 PackedInt32Array 内存
static func build_notes_from_soa(soa: Dictionary) -> Array[NoteEvent]:
	var pitches: PackedInt32Array = soa["pitches"]
	var velocities: PackedInt32Array = soa["velocities"]
	var start_ticks: PackedInt32Array = soa["start_ticks"]
	var durations: PackedInt32Array = soa["durations"]
	var track_indices: PackedInt32Array = soa["track_indices"]
	var channels: PackedInt32Array = soa["channels"]
	var count := pitches.size()
	var notes: Array[NoteEvent] = []
	notes.resize(count)
	for i in range(count):
		notes[i] = NoteEvent.new(
			pitches[i], velocities[i],
			float(start_ticks[i]), float(durations[i]),
			track_indices[i], channels[i]
		)
	return notes

## 按 (track, channel) 分组构建 { "track:channel": Array[NoteEvent] }
## notes 必须已按 start_time 升序排序（build_notes_from_soa 保证）
## 每 bucket 内天然有序，调用方无需再 sort
## 用于 TrackView._build_buckets，消除重复循环
static func build_track_channel_notes(notes: Array) -> Dictionary:
	var grouping: Dictionary = {}
	for note in notes:
		if note is NoteEvent:
			var key := "%d:%d" % [note.track_index, note.channel]
			if not grouping.has(key):
				grouping[key] = []
			grouping[key].append(note)
	return grouping

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
## 注意：NoteEvent.start_time 单位为 tick（非毫秒）
## 修复字段名 BUG：旧版误用 start_time_ms（NoteEvent 无此字段，会返回 null 导致排序失效）
static func sort_notes_by_time(notes: Array) -> Array:
	var sorted_notes = notes.duplicate()
	sorted_notes.sort_custom(func(a, b):
		return a.start_time < b.start_time
	)
	return sorted_notes

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
