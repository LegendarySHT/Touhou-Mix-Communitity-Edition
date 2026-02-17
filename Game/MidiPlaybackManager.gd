## MIDI播放管理器
## 负责MIDI文件的加载、播放、轨道选择和音源管理
extends Node

class_name MidiPlaybackManager

## 单例实例
static var instance: MidiPlaybackManager

## MIDI播放器引用
var midi_player: MidiPlaybackInterface

## MeltySynth C# 播放器引用（后端为meltysynth时使用）
var meltysynth_player: MidiPlaybackInterface

## 当前加载的MIDI数据
var current_midi_data: MidiData

## 当前解析的音符列表
var current_notes: Array = []

## MIDI的BPM变化时间线 (用于精确时间计算)
var bpm_timeline: Array = []

## 缓存的轨道-通道乐器映射 (从 MIDI 文件中提取)
## 格式: {track_index: {channel: {bank: int, program: int}}}
var cached_track_channel_instruments: Dictionary = {}

## MIDI播放状态
var is_playing: bool = false

## 后端切换锁（防止短时间内重复切换）
## 当正在处理后端切换时，此标志为true，防止重复的set_backend()调用
var backend_switching: bool = false

## 当前播放位置（MIDI tick单位，NOT毫秒！）
## 注意：MidiPlayer.position使用tick单位。此属性直接来自MidiPlayer.position
## 要获取毫秒值，请使用 get_position_ms()
var position: float = 0.0

## 当前播放位置（毫秒，用于向后兼容 - 不推荐使用）
## ⚠️ 已弃用：使用 position 获取tick，或使用 get_position_ms() 获取毫秒值
var position_ms: float = 0.0

## MIDI时间基准 (ticks per beat)
var midi_timebase: int = 480

## 当前使用的MIDI后端 ("addons" / "meltysynth")
var midi_backend: String = "addons"

## 总时长（毫秒）
var duration_ms: float = 0.0

## 可用的SoundFont列表（缓存）
var available_soundfonts: Array = []

## 默认SoundFont路径
var default_soundfont_path: String = "res://Resources/Soundfont/GeneralUser-GS.sf2"

## 当前使用的SoundFont路径
var current_soundfont_path: String = ""

## 人声偏移量（毫秒）
var vocal_offset_ms: float = 0.0

## 音频不同步阈值（毫秒）
var sync_threshold_ms: float = 200.0

## 上次同步检查时的MIDI位置（毫秒）
var last_sync_check_pos_ms: float = 0.0

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

## 信号：(track, channel) 的静音状态改变
signal channel_mute_state_changed(track_index: int, channel: int, muted: bool)

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	
	add_to_group("singleton")
	
	# 从配置文件加载MIDI后端设置
	_load_backend_from_config()
	
	# 初始化MIDI播放器
	_initialize_backend()
	
	# 扫描可用的SoundFont
	_scan_soundfonts()
	
	# 从配置文件加载音源设置
	_load_soundfont_from_config()
	
	# 监听设置改变信号（用于动态切换MIDI后端和音源）
	if EventBus.instance:
		EventBus.instance.settings_changed.connect(_on_settings_changed)
		# 监听配置变更信号（新增，用于应对直接配置文件修改）
		EventBus.instance.config_changed.connect(_on_config_changed)

## 处理设置改变信号回调（当退出SettingView时触发）
## @param setting_name: 改变的设置名 ("*" 表示所有设置)
## @param value: 设置的新值（此时未使用，因为我们直接从配置文件读取）
func _on_settings_changed(setting_name: String, value: Variant) -> void:
	print("[MidiPlaybackManager] Settings changed event: setting_name='%s', value=%s" % [setting_name, value])
	
	# 如果是泛指信号（所有设置改变）或具体是midi_backend改变
	if setting_name == "*" or setting_name == "midi_backend":
		# 重新读取MIDI后端配置
		var old_backend = midi_backend
		_load_backend_from_config()
		
		# 如果后端改变了，进行动态切换
		if midi_backend != old_backend:
			GameLogger.instance.info("MIDI backend changed from '%s' to '%s'" % [old_backend, midi_backend], "MidiPlaybackManager")
			print("[MidiPlaybackManager] MIDI backend changed from '%s' to '%s' (triggered by settings)" % [old_backend, midi_backend])
			
			# 停止当前播放（如果有）
			if is_playing:
				print("[MidiPlaybackManager] Stopping playback before backend switch")
				stop()
			
			# 清理旧后端（极其重要！）
			print("[MidiPlaybackManager] Cleaning up old backend: %s" % old_backend)
			_cleanup_old_backend(old_backend)
			
			# 重新初始化后端
			print("[MidiPlaybackManager] Reinitializing backend: %s" % midi_backend)
			var init_success = _initialize_backend()
			if not init_success:
				push_error("[MidiPlaybackManager] Backend initialization failed, attempting fallback to addon")
				midi_backend = "addons"
				_initialize_addon_backend()
				print("[MidiPlaybackManager] Fallback to addon backend")
			
			# 如果原来有加载的MIDI，重新加载到新后端（但不自动播放）
			if current_midi_data != null and not current_midi_data.midi_file_path.is_empty():
				print("[MidiPlaybackManager] Reloading MIDI with new backend: %s" % current_midi_data.midi_file_path)
				if load_midi(current_midi_data):
					print("[MidiPlaybackManager] MIDI reloaded successfully")
					# 重要：确保重新加载后不自动播放（防止从SettingView返回时错误播放）
					stop()
					print("[MidiPlaybackManager] Stopped playback after reload to prevent auto-play")
				else:
					push_error("[MidiPlaybackManager] Failed to reload MIDI with new backend")
			else:
				print("[MidiPlaybackManager] No MIDI loaded, skipping reload")
		else:
			print("[MidiPlaybackManager] Backend unchanged (still: %s)" % midi_backend)
	
	# 如果是泛指信号或音源改变
	if setting_name == "*" or setting_name == "soundfont_select":
		# 重新读取音源配置
		print("[MidiPlaybackManager] Reloading soundfont from settings")
		_load_soundfont_from_config()
		print("[MidiPlaybackManager] Soundfont reloaded successfully")

func _process(_delta: float) -> void:
	var backend = _get_active_backend()
	if not is_playing or backend == null:
		return
	
	# 对于addon后端，直接读取position（tick）
	if midi_backend == "addons" and midi_player != null:
		position = midi_player.position
		
		# 更新position_ms，带BPM时间线支持
		if midi_player.smf_data != null and midi_player.smf_data.timebase > 0:
			midi_timebase = midi_player.smf_data.timebase
			position_ms = _calculate_position_with_bpm_timeline(position, midi_timebase)
	
	# 对于meltysynth后端，使用毫秒位置
	elif midi_backend == "meltysynth" and meltysynth_player != null:
		position_ms = meltysynth_player.get_position_ms()
		# 将毫秒转为tick（使用BPM时间线）
		if midi_timebase > 0:
			position = _calculate_tick_from_position_with_bpm_timeline(position_ms, midi_timebase)
	
	# 调用自动同步逻辑
	_sync_vocal_with_midi()

## 初始化MIDI播放器
func _initialize_midi_player() -> void:
	# This method is kept for compatibility but now delegates to _initialize_backend
	_initialize_backend()

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
	midi_timebase = parse_result.get("timebase", 480)  # 保存timebase
	
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
	
	# 从 track_infos 中提取乐器信息（用于不维护此信息的后端，如 MeltySynth）
	_extract_track_channel_instruments(parse_result["track_infos"])
	
	# 如果未选择轨道，则默认选择所有轨道
	if current_midi_data.selected_track_indices.is_empty():
		for i in range(current_midi_data.track_count):
			current_midi_data.selected_track_indices.append(i)
	
	# 加载到活跃后端
	var backend = _get_active_backend()
	if backend != null:
		if backend.has_method("load_midi"):
			backend.load_midi(midi_file_path)
		elif backend.has_method("set_file"):
			backend.set_file(midi_file_path)
		elif "file" in backend:
			backend.file = midi_file_path
	
	# 应用轨道-通道音量配置
	if midi_data.track_channel_volume_config and not midi_data.track_channel_volume_config.is_empty():
		for track_idx in midi_data.track_channel_volume_config.keys():
			for ch in midi_data.track_channel_volume_config[track_idx].keys():
				if backend != null and backend.has_method("set_track_channel_volume"):
					backend.set_track_channel_volume(track_idx, ch, midi_data.track_channel_volume_config[track_idx][ch])
		print("[MidiPlaybackManager] Applied %d track volume configs" % midi_data.track_channel_volume_config.size())
	
	# 清理旧乐器覆盖配置
	if backend != null and "track_channel_instruments" in backend:
		backend.track_channel_instruments.clear()
		print("[MidiPlaybackManager] Cleared old instrument overrides before loading new MIDI")
	
	# 应用轨道-通道乐器覆盖配置
	if midi_data.track_channel_instrument_overrides and not midi_data.track_channel_instrument_overrides.is_empty():
		for track_idx in midi_data.track_channel_instrument_overrides.keys():
			for ch in midi_data.track_channel_instrument_overrides[track_idx].keys():
				var instr = midi_data.track_channel_instrument_overrides[track_idx][ch]
				if backend != null and backend.has_method("set_track_channel_instrument"):
					backend.set_track_channel_instrument(track_idx, ch, instr["bank"], instr["program"])
		print("[MidiPlaybackManager] Applied %d instrument overrides" % midi_data.track_channel_instrument_overrides.size())
	
	# 同步轨道-通道静音状态（清理旧MIDI的残留静音）
	_apply_mute_state_to_backend(backend)
	
	# 发出信号
	midi_loaded.emit(current_midi_data)
	
	return true

## 播放MIDI
func play() -> void:
	var backend = _get_active_backend()
	if backend == null:
		push_error("No MIDI backend initialized")
		return
	
	if current_midi_data == null:
		push_error("No MIDI loaded")
		return
	
	# 设置音源
	if not current_soundfont_path.is_empty() and backend.has_method("set_soundfont"):
		backend.set_soundfont(current_soundfont_path)

	# 重置同步状态
	reset_sync_state()

	backend.play()
	is_playing = true

	# 启动人声播放（如果有人声文件）
	if not current_midi_data.vocal_file_path.is_empty():
		start_vocal_playback()
		print("[MidiPlaybackManager] Started vocal playback: %s (offset: %d ms)" % [current_midi_data.vocal_file_path, vocal_offset_ms])
	else:
		print("[MidiPlaybackManager] No vocal file configured (path: '%s')" % current_midi_data.vocal_file_path)

	midi_started.emit()

## 停止播放
func stop() -> void:
	var backend = _get_active_backend()
	if backend == null:
		return
	
	backend.stop()
	is_playing = false
	position_ms = 0.0

	# 停止人声播放
	stop_vocal_playback()

	midi_stopped.emit()

## 暂停播放
func pause() -> void:
	var backend = _get_active_backend()
	if backend == null:
		return
	
	backend.pause()
	is_playing = false

	# 暂停人声播放
	var audio_manager = AudioManager.instance
	if current_midi_data and audio_manager:
		audio_manager.set_vocal_playing(false)

	midi_paused.emit()

## 继续播放
func resume() -> void:
	var backend = _get_active_backend()
	if backend == null:
		return
	
	backend.resume()
	is_playing = true

	# 恢复人声播放
	var audio_manager = AudioManager.instance
	if current_midi_data and audio_manager and current_midi_data.vocal_file_path:
		audio_manager.set_vocal_playing(true)

	midi_started.emit()

## 设置循环播放
func set_loop(enabled: bool) -> void:
	if midi_backend == "addons" and midi_player != null:
		midi_player.loop = enabled
	elif midi_backend == "meltysynth" and meltysynth_player != null:
		# 直接调用 C# 方法
		meltysynth_player.set_loop(enabled)
	
	# 同时更新配置
	midi_player_config["loop"] = enabled
	print("[MidiPlaybackManager] Loop set to: %s (backend: %s)" % [enabled, midi_backend])

## 获取循环播放状态
func get_loop() -> bool:
	if midi_backend == "addons" and midi_player != null:
		return midi_player.loop
	elif midi_backend == "meltysynth" and meltysynth_player != null:
		return meltysynth_player.get("loop")
	return false

## 跳转到指定位置
## position: 位置（毫秒）
func seek(pos: float) -> void:
	position_ms = pos
	print("[MidiPlaybackManager] Seeking to %.1f ms (backend: %s)" % [pos, midi_backend])
	
	if midi_backend == "addons" and midi_player != null:
		# 使用BPM时间线计算精确的tick位置
		if midi_player.smf_data != null and midi_player.smf_data.timebase > 0:
			var target_tick = _calculate_tick_from_position_with_bpm_timeline(pos, midi_player.smf_data.timebase)
			print("[MidiPlaybackManager] Seeking to tick %.1f (addons backend)" % target_tick)
			midi_player.seek(target_tick)
		elif midi_timebase > 0:
			var target_tick = _calculate_tick_from_position_with_bpm_timeline(pos, midi_timebase)
			print("[MidiPlaybackManager] Seeking to tick %.1f (addons backend, using cached timebase)" % target_tick)
			midi_player.seek(target_tick)
	elif midi_backend == "meltysynth" and meltysynth_player != null:
		# 直接调用 C# 的 seek_ms 方法
		print("[MidiPlaybackManager] Calling MeltySynth seek_ms(%.1f)" % pos)
		meltysynth_player.seek_ms(pos)
	else:
		print("[MidiPlaybackManager] Seek failed: backend not available")

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

## 设置MIDI合成器后端
func set_backend(backend_name: String) -> bool:
	"""
	动态切换MIDI后端，支持 "addons"（当前GDScript播放器）和 "meltysynth"（C#）
	
	Args:
		backend_name: "addons" 或 "meltysynth"
	
	Returns:
		bool: 是否设置成功
	"""
	backend_name = backend_name.to_lower().strip_edges()
	
	# 防止并发的后端切换（竞态条件）
	if backend_switching:
		print("[MidiPlaybackManager] Backend switch already in progress, ignoring redundant set_backend('%s') call" % backend_name)
		return false
	
	# 如果后端相同，无需切换
	if midi_backend == backend_name:
		print("[MidiPlaybackManager] Backend already set to: %s" % backend_name)
		return true
	
	# 标记正在切换
	backend_switching = true
	
	# 记录旧后端
	var old_backend = midi_backend
	
	if backend_name == "addons":
		# 先清理MeltySynth（旧后端）
		if old_backend == "meltysynth":
			print("[MidiPlaybackManager] Cleaning up MeltySynth before switching to Addon")
			_cleanup_old_backend("meltysynth")
		
		# 初始化Addon
		if midi_player == null:
			var init_success = _initialize_addon_backend()
			if not init_success:
				push_error("[MidiPlaybackManager] Failed to initialize addon backend")
				backend_switching = false
				return false
		
		if midi_player == null:
			push_error("[MidiPlaybackManager] Addon backend is still null after initialization attempt")
			backend_switching = false
			return false
		
		midi_backend = "addons"
		print("[MidiPlaybackManager] Switched to addon MIDI backend (GDScript)")
		backend_switching = false
		return true
	
	elif backend_name == "meltysynth":
		if not _is_csharp_available():
			push_warning("[MidiPlaybackManager] C# support not available, falling back to addon backend")
			backend_switching = false
			return set_backend("addons")
		
		# 先清理Addon（旧后端）
		if old_backend == "addons":
			print("[MidiPlaybackManager] Cleaning up Addon before switching to MeltySynth")
			_cleanup_old_backend("addons")
		
		# 初始化MeltySynth
		var init_success = false
		if meltysynth_player == null:
			init_success = _initialize_meltysynth_backend()
		else:
			init_success = true
		
		if not init_success or meltysynth_player == null:
			push_error("[MidiPlaybackManager] Failed to initialize MeltySynth backend, falling back to addon")
			# 确保midi_backend在回退前被重置
			midi_backend = "addons"
			backend_switching = false
			return set_backend("addons")  # Fallback
		
		midi_backend = "meltysynth"
		print("[MidiPlaybackManager] Switched to MeltySynth MIDI backend (C#)")
		backend_switching = false
		return true
	
	else:
		push_error("[MidiPlaybackManager] Unknown backend: %s" % backend_name)
		backend_switching = false
		return false

## 从配置文件加载MIDI后端设置
func _load_backend_from_config() -> void:
	var config_manager = ConfigManager.instance
	
	# 优先从用户配置获取
	var backend = config_manager.get_value("Gameplay", "midi_backend", "addons")
	midi_backend = str(backend).to_lower().strip_edges()

## 初始化指定后端
func _initialize_backend() -> bool:
	match midi_backend:
		"addons":
			return _initialize_addon_backend()
		"meltysynth":
			if _is_csharp_available():
				return _initialize_meltysynth_backend()
			else:
				print("[MidiPlaybackManager] C# support not available, initializing addon backend instead")
				return _initialize_addon_backend()
		_:
			print("[MidiPlaybackManager] Unknown backend '%s', initializing addon backend" % midi_backend)
			return _initialize_addon_backend()

## 初始化插件后端（GDScript MidiPlayer）
## 返回: bool - 初始化是否成功
func _initialize_addon_backend() -> bool:
	if midi_player != null:
		print("[MidiPlaybackManager] Addon backend already initialized, skipping")
		return true  # 已经初始化
	
	print("[MidiPlaybackManager] Attempting to initialize addon MIDI backend")
	
	var midi_player_scene = load("res://addons/midi/MidiPlayer.tscn")
	if midi_player_scene == null:
		push_error("[MidiPlaybackManager] MidiPlayer addon not found!")
		return false
	
	print("[MidiPlaybackManager] MidiPlayer scene loaded successfully")
	
	midi_player = midi_player_scene.instantiate() as MidiPlaybackInterface
	if midi_player == null:
		push_error("[MidiPlaybackManager] Failed to instantiate MidiPlayer as MidiPlaybackInterface")
		return false
	
	print("[MidiPlaybackManager] MidiPlayer instantiated successfully")
	
	midi_player.name = "MidiPlayer"
	add_child(midi_player as Node)
	print("[MidiPlaybackManager] Added MidiPlayer as child node")
	
	# 配置MidiPlayer
	if midi_player.has_meta("script"):
		midi_player.max_polyphony = midi_player_config["max_polyphony"]
		midi_player.loop = midi_player_config["loop"]
		midi_player.volume_db = midi_player_config["volume_db"]
		midi_player.bus = "Master"
		print("[MidiPlaybackManager] Configured MidiPlayer parameters")
	
	# 连接信号
	if midi_player.has_signal("finished"):
		midi_player.finished.connect(_on_midi_finished)
		print("[MidiPlaybackManager] Connected finished signal")
	
	GameLogger.instance.info("Addon MIDI backend initialized successfully", "MidiPlaybackManager")
	print("[MidiPlaybackManager] Addon backend initialization complete")
	
	return true

## 初始化MeltySynth后端（C#）
## 返回: bool - 初始化是否成功
func _initialize_meltysynth_backend() -> bool:
	if meltysynth_player != null:
		print("[MidiPlaybackManager] MeltySynth backend already initialized, skipping")
		return true  # 已经初始化
	
	# 尝试加载预制场景
	var scene_path = "res://CSharp/MeltySynthPlayer.tscn"
	print("[MidiPlaybackManager] Attempting to load MeltySynth scene: %s" % scene_path)
	
	if not ResourceLoader.exists(scene_path):
		push_error("[MidiPlaybackManager] MeltySynth scene path does not exist: %s" % scene_path)
		return false
	
	var scene = load(scene_path) as PackedScene
	if scene == null:
		push_error("[MidiPlaybackManager] Failed to load MeltySynth PackedScene from: %s" % scene_path)
		return false
	
	print("[MidiPlaybackManager] MeltySynth scene loaded successfully")
	
	var wrapper = scene.instantiate() as MidiPlaybackInterface
	if wrapper == null:
		push_error("[MidiPlaybackManager] Failed to instantiate MeltySynth wrapper as MidiPlaybackInterface")
		return false
	
	print("[MidiPlaybackManager] MeltySynth wrapper instantiated successfully")
	
	# 获取 C# 后端子节点
	var csharp_backend = wrapper.get_node_or_null("CSharpBackend")
	if csharp_backend == null:
		push_error("[MidiPlaybackManager] CSharpBackend child node not found in MeltySynth wrapper")
		wrapper.queue_free()
		return false
	
	print("[MidiPlaybackManager] CSharpBackend child node found")
	
	# 尝试设置属性
	if not wrapper.has_meta("script"):
		push_warning("[MidiPlaybackManager] MeltySynth wrapper does not have script meta")
	
	# 设置meltysynth_player属性
	wrapper.set("meltysynth_player", csharp_backend)
	print("[MidiPlaybackManager] Set meltysynth_player property on wrapper")
	
	# 添加为子节点
	add_child(wrapper as Node)
	print("[MidiPlaybackManager] Added wrapper as child node")
	
	# 配置播放器参数
	wrapper.set("max_polyphony", midi_player_config["max_polyphony"])
	wrapper.set("loop", midi_player_config["loop"])
	print("[MidiPlaybackManager] Set playback parameters")
	
	if wrapper.has_method("set_volume_db"):
		wrapper.call("set_volume_db", midi_player_config["volume_db"])
		print("[MidiPlaybackManager] Called set_volume_db")
	
	if wrapper.has_method("set_bus"):
		wrapper.call("set_bus", "Master")
		print("[MidiPlaybackManager] Called set_bus")
	
	# 连接信号
	if wrapper.has_signal("finished"):
		wrapper.finished.connect(_on_midi_finished)
		print("[MidiPlaybackManager] Connected finished signal")
	
	# 保存引用
	meltysynth_player = wrapper
	GameLogger.instance.info("MeltySynth C# backend initialized successfully", "MidiPlaybackManager")
	print("[MidiPlaybackManager] MeltySynth backend initialization complete")
	
	return true

## 检查C#支持
func _is_csharp_available() -> bool:
	return FileAccess.file_exists("res://Touhou Mix Comunitity Edition.csproj")

## 清理旧后端（彻底销毁以避免同时运行多个后端）
## 这是动态切换的关键步骤，防止旧后端继续在后台运行
func _cleanup_old_backend(backend_type: String) -> void:
	match backend_type:
		"addons":
			if midi_player != null:
				print("[MidiPlaybackManager] Cleaning up Addon backend")
				# 1. 停止播放器
				if midi_player.has_method("stop"):
					midi_player.stop()
					print("[MidiPlaybackManager] Addon backend stopped")
				
				# 2. 断开所有信号
				if midi_player.has_signal("finished"):
					if midi_player.finished.is_connected(_on_midi_finished):
						midi_player.finished.disconnect(_on_midi_finished)
						print("[MidiPlaybackManager] Addon finished signal disconnected")
				
				# 3. 从场景树移除（立即删除，同步操作）
				if midi_player.get_parent() != null:
					if midi_player.get_parent() == self:
						remove_child(midi_player)
					midi_player.free()  # 使用free()而不是queue_free()以确保立即销毁
					print("[MidiPlaybackManager] Addon backend freed immediately from scene")
				
				# 4. 清空引用
				midi_player = null
				print("[MidiPlaybackManager] Addon backend reference cleared")
		
		"meltysynth":
			if meltysynth_player != null:
				print("[MidiPlaybackManager] Cleaning up MeltySynth backend")
				# 1. 停止播放器
				if meltysynth_player.has_method("stop"):
					meltysynth_player.stop()
					print("[MidiPlaybackManager] MeltySynth backend stopped")
				
				# 2. 断开所有信号
				if meltysynth_player.has_signal("finished"):
					if meltysynth_player.finished.is_connected(_on_midi_finished):
						meltysynth_player.finished.disconnect(_on_midi_finished)
						print("[MidiPlaybackManager] MeltySynth finished signal disconnected")
				
				# 3. 从场景树移除（立即删除，同步操作）
				if meltysynth_player.get_parent() != null:
					if meltysynth_player.get_parent() == self:
						remove_child(meltysynth_player)
					meltysynth_player.free()  # 使用free()而不是queue_free()以确保立即销毁
					print("[MidiPlaybackManager] MeltySynth backend freed immediately from scene")
				
				# 4. 清空引用
				meltysynth_player = null
				print("[MidiPlaybackManager] MeltySynth backend reference cleared")
		
		_:
			print("[MidiPlaybackManager] Unknown backend type for cleanup: %s" % backend_type)

## 获取活跃的MIDI播放器
func _get_active_backend() -> MidiPlaybackInterface:
	match midi_backend:
		"meltysynth":
			return meltysynth_player if meltysynth_player != null else midi_player
		_:
			return midi_player

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
	var backend = _get_active_backend()
	if backend == null:
		return
	
	# 应用到活跃后端
	if backend.has_method("set_volume_db"):
		backend.call("set_volume_db", volume)
	elif midi_backend == "addons" and midi_player != null:
		midi_player.volume_db = volume
	
	midi_player_config["volume_db"] = volume

## 设置特定(track, channel)对的音量（线性值0.0-1.0）
## 立即生效到正在播放的Note
func set_track_channel_volume(track_index: int, channel: int, volume_linear: float) -> void:
	var backend = _get_active_backend()
	if backend == null:
		return
	
	var clamped_volume = clamp(volume_linear, 0.0, 1.0)
	
	# 通过后端抽象调用
	if backend.has_method("set_track_channel_volume"):
		backend.set_track_channel_volume(track_index, channel, clamped_volume)
		
		# addons 后端特殊处理：立即应用到 channel 总线
		if midi_backend == "addons" and backend == midi_player:
			if midi_player.channel_status.size() > channel:
				var ch_status = midi_player.channel_status[channel]
				midi_player._apply_channel_volume(ch_status)
	
	print("[MidiPlaybackManager] Track %d Channel %d volume set to: %.1f%%" % 
		[track_index, channel, clamped_volume * 100.0])

## 获取特定(track, channel)对的音量
func get_track_channel_volume(track_index: int, channel: int) -> float:
	var backend = _get_active_backend()
	if backend == null:
		return 1.0
	if backend.has_method("get_track_channel_volume"):
		return backend.get_track_channel_volume(track_index, channel)
	return 1.0

## 设置特定轨道的音量（相对于主音量）
## @deprecated 使用 set_track_channel_volume 替代
func set_track_volume_db(track_index: int, volume_db: float) -> void:
	if midi_player == null or current_midi_data == null:
		return
	
	# 注：此方法已升级，现在通过set_track_channel_volume实现
	# 为保持兼容性，这里仅记录日志
	print("[MidiPlaybackManager] Set track %d volume to %.2f dB (deprecated, use set_track_channel_volume)" % [track_index, volume_db])

## 设置人声音量
func set_vocal_volume_db(volume_db: float) -> void:
	var audio_manager = AudioManager.instance
	if audio_manager != null:
		audio_manager.set_vocal_volume_db(volume_db)
		print("[MidiPlaybackManager] Set vocal volume to %.2f dB" % volume_db)
	else:
		push_error("[MidiPlaybackManager] AudioManager not available")

## ========== (Track, Channel) 静音接口 ==========

## 设置 (track, channel) 对的静音状态（立即生效）
## 参数: track_index (0+), channel (0-15), muted (true=静音, false=取消静音)
func set_track_channel_mute(track_index: int, channel: int, muted: bool) -> void:
	if current_midi_data == null:
		push_error("[MidiPlaybackManager] Cannot mute: no MIDI data")
		return
	
	if channel < 0 or channel > 15:
		push_error("[MidiPlaybackManager] Invalid channel: %d (should be 0-15)" % channel)
		return
	
	# 1. 检查状态是否改变（优化：避免重复操作）
	var previous_state = current_midi_data.get_track_channel_mute(track_index, channel)
	if previous_state == muted:
		print("[MidiPlaybackManager] Channel %d already %s, skipping" % [channel, "muted" if muted else "unmuted"])
		return
	
	# 2. 更新 MidiData 中的状态
	current_midi_data.set_track_channel_mute(track_index, channel, muted)
	
	# 3. 如果是 mute，立即停止该 channel 所有正在播放的音符
	if muted:
		if midi_player != null:
			_stop_channel_notes(channel)
			print("[MidiPlaybackManager] Stopped all notes on channel %d" % channel)

	# 3.5 通知后端（如支持）
	var backend = _get_active_backend()
	if backend != null and backend.has_method("set_track_channel_mute"):
		backend.set_track_channel_mute(track_index, channel, muted)
	
	# 4. 发射信号
	channel_mute_state_changed.emit(track_index, channel, muted)

## 仅在运行时设置 (track, channel) 的静音状态（不写入MidiData）
## 用于独奏或临时静音
func set_track_channel_mute_runtime(track_index: int, channel: int, muted: bool) -> void:
	if channel < 0 or channel > 15:
		push_error("[MidiPlaybackManager] Invalid channel: %d (should be 0-15)" % channel)
		return

	if muted:
		if midi_player != null:
			_stop_channel_notes(channel)
			print("[MidiPlaybackManager] Stopped all notes on channel %d (runtime mute)" % channel)

	var backend = _get_active_backend()
	if backend != null and backend.has_method("set_track_channel_mute"):
		backend.set_track_channel_mute(track_index, channel, muted)

	channel_mute_state_changed.emit(track_index, channel, muted)

## 查询 (track, channel) 对的静音状态
func is_track_channel_muted(track_index: int, channel: int) -> bool:
	if current_midi_data == null:
		return false
	return current_midi_data.get_track_channel_mute(track_index, channel)

## 停止指定 channel 的所有正在播放的音符（立即）
## 这是实时生效的关键
func _stop_channel_notes(channel: int) -> void:
	if midi_player == null:
		return
	
	# 遍历所有正在播放的 AudioStreamPlayer
	var stopped_count = 0
	for asp in midi_player.audio_stream_players:
		if asp.channel_number == channel and asp.playing:
			# 触发 release 阶段（而不是直接 stop）
			# 这样会让音符自然地进入 ADSR release 阶段，更平滑
			asp.start_release()
			stopped_count += 1
	
	print("[MidiPlaybackManager] Channel %d: stopped %d notes" % [channel, stopped_count])

## 取消所有 (track, channel) 的静音
func unmute_all_channels() -> void:
	if current_midi_data == null:
		return
	
	current_midi_data.clear_all_mutes()
	print("[MidiPlaybackManager] All channels unmuted")

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

## 获取可用的乐器预设列表
func get_presets_list() -> Array:
	var backend = _get_active_backend()
	if backend == null:
		return []
	if backend.has_method("get_presets_list"):
		return backend.get_presets_list()
	return []

## 获取指定 bank/program 的乐器名称
func get_preset_name(program: int, bank: int = 0) -> String:
	var backend = _get_active_backend()
	if backend == null:
		return "Unknown"
	if backend.has_method("get_preset_name"):
		return backend.get_preset_name(program, bank)
	return "Unknown"

## 获取指定 (track, channel) 的乐器信息
func get_track_channel_instrument(track_index: int, channel: int) -> Dictionary:
	var backend = _get_active_backend()
	if backend == null:
		return _get_instrument_from_cache(track_index, channel)
	
	# 优先使用后端维护的信息（如 Addon 后端）
	if backend.has_method("get_track_channel_instrument"):
		var result = backend.get_track_channel_instrument(track_index, channel)
		# 如果后端返回空字典（如 MeltySynth），使用缓存
		if not result.is_empty():
			return result
	
	# 使用缓存的信息（从 MIDI 文件中提取）
	return _get_instrument_from_cache(track_index, channel)

## 从缓存中获取乐器信息
func _get_instrument_from_cache(track_index: int, channel: int) -> Dictionary:
	if cached_track_channel_instruments.has(track_index):
		if cached_track_channel_instruments[track_index].has(channel):
			return cached_track_channel_instruments[track_index][channel]
	
	# 返回默认值
	return _get_default_instrument(channel)

## 获取默认乐器配置（用于不维护乐器映射的后端）
func _get_default_instrument(channel: int) -> Dictionary:
	# Channel 9 (索引) 是鼓组，使用 Standard Drum Kit
	if channel == 9:
		return {"bank": 128, "program": 0}  # Bank 128 = 鼓组
	else:
		return {"bank": 0, "program": 0}    # Grand Piano

## 同步轨道-通道静音状态到后端（清理旧MIDI残留）
func _apply_mute_state_to_backend(backend: MidiPlaybackInterface) -> void:
	if backend == null or not backend.has_method("set_track_channel_mute"):
		return
	
	# 优先使用缓存的(track, channel)映射，确保覆盖所有实际通道
	for track_idx in cached_track_channel_instruments.keys():
		var channels = cached_track_channel_instruments[track_idx]
		for channel in channels.keys():
			var muted = current_midi_data.get_track_channel_mute(track_idx, channel)
			backend.set_track_channel_mute(track_idx, channel, muted)
	
	print("[MidiPlaybackManager] Applied mute state for %d tracks" % cached_track_channel_instruments.size())

## 从 track_infos 中提取 program_change 事件并缓存乐器信息
func _extract_track_channel_instruments(track_infos: Array) -> void:
	cached_track_channel_instruments.clear()
	
	# 用于跟踪每个通道的当前 bank 值
	var channel_banks: Dictionary = {}  # {track_idx: {channel: bank}}
	
	# 初始化：Channel 9 默认为鼓组 bank
	for track_idx in range(track_infos.size()):
		channel_banks[track_idx] = {}
		for ch in range(16):
			if ch == 9:
				channel_banks[track_idx][ch] = 128  # Drum bank
			else:
				channel_banks[track_idx][ch] = 0
	
	# 遍历每个轨道的事件
	for track_idx in range(track_infos.size()):
		var track_info = track_infos[track_idx]
		if not track_info:
			continue
		
		cached_track_channel_instruments[track_idx] = {}
		
		# 收集该轨道中出现的所有通道
		var channels_in_track: Array = []
		for event_chunk in track_info.events:
			var channel = event_chunk.channel_number
			if channel not in channels_in_track:
				channels_in_track.append(channel)
			
			var event = event_chunk.event
			
			# 处理 Bank Select events (Control Change 0 和 32)
			if event.type == SMF.MIDIEventType.control_change:
				var cc_num = event.number
				var cc_val = event.value
				
				if cc_num == 0:  # Bank Select MSB
					if channel == 9:
						channel_banks[track_idx][channel] = 128  # 鼓组始终 bank 128
					else:
						var current_bank = channel_banks[track_idx].get(channel, 0)
						channel_banks[track_idx][channel] = (current_bank & 0x7F) | (cc_val << 7)
				elif cc_num == 32:  # Bank Select LSB
					if channel == 9:
						channel_banks[track_idx][channel] = 128
					else:
						var current_bank = channel_banks[track_idx].get(channel, 0)
						channel_banks[track_idx][channel] = (current_bank & 0x3F80) | (cc_val & 0x7F)
			
			# 处理 Program Change events
			elif event.type == SMF.MIDIEventType.program_change:
				var program = event.number
				var bank = channel_banks[track_idx].get(channel, 0)
				
				# 存储该 (track, channel) 的乐器
				cached_track_channel_instruments[track_idx][channel] = {
					"bank": bank,
					"program": program
				}
		
		# 对于没有 program_change 的通道，使用默认值
		for channel in channels_in_track:
			if not cached_track_channel_instruments[track_idx].has(channel):
				var bank = channel_banks[track_idx].get(channel, 0)
				cached_track_channel_instruments[track_idx][channel] = {
					"bank": bank,
					"program": 0  # 默认 Grand Piano (或 Standard Drum Kit for channel 9)
				}
	
	print("[MidiPlaybackManager] Extracted instruments for %d tracks from MIDI file" % cached_track_channel_instruments.size())

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
	return _calculate_position_with_bpm_timeline(tick, midi_timebase)

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
	var config_manager = ConfigManager.instance
	
	# 从当前活跃配置获取 soundfont（用户配置 > 默认配置）
	var soundfont_name = config_manager.get_value("Gameplay", "soundfont_file", "GeneralUser-GS.sf2")
	
	if not soundfont_name.is_empty():
		# 去掉 .sf2 扩展名和 [内置] 标签（如果有）
		soundfont_name = soundfont_name.replace(".sf2", "").replace("[内置]", "").strip_edges()
		print("[MidiPlaybackManager] Loading soundfont from config: %s" % soundfont_name)
		if set_soundfont(soundfont_name):
			return
	
	# 使用硬编码的默认值（如果加载失败）
	print("[MidiPlaybackManager] Using hardcoded default soundfont")
	current_soundfont_path = default_soundfont_path
	soundfont_changed.emit(current_soundfont_path)

## ========== 人声同步相关方法 ==========

## 设置人声偏移量（毫秒）
func set_vocal_offset_ms(offset_ms: float) -> void:
	vocal_offset_ms = offset_ms

## 应用人声偏移（重新调整人声播放位置）
func apply_vocal_offset() -> void:
	var audio_manager = AudioManager.instance
	if audio_manager == null:
		return

	# 计算新的人声播放位置：MIDI当前位置 - 偏移量
	var new_position_ms = position_ms - vocal_offset_ms
	# 确保不是负数
	new_position_ms = max(0.0, new_position_ms)
	audio_manager.seek_vocal(new_position_ms)

## 启动人声播放并同步
func start_vocal_playback() -> void:
	if current_midi_data == null or current_midi_data.vocal_file_path.is_empty():
		return

	var audio_manager = AudioManager.instance
	if audio_manager == null:
		return

	# 加载人声音频文件
	var vocal_file_path = current_midi_data.vocal_file_path
	var vocal_stream: AudioStream = null

	# 首先检查文件是否存在（使用FileAccess，支持user://目录）
	if not FileAccess.file_exists(vocal_file_path):
		push_error("Vocal file does not exist: %s" % vocal_file_path)
		return

	# 根据文件扩展名加载对应的AudioStream类型
	var file_ext = vocal_file_path.get_extension().to_lower()

	match file_ext:
		"ogg":
			vocal_stream = AudioStreamOggVorbis.load_from_file(vocal_file_path)
			print("[MidiPlaybackManager] Loading OGG vocal file: %s" % vocal_file_path)
		"mp3":
			vocal_stream = AudioStreamMP3.load_from_file(vocal_file_path)
			print("[MidiPlaybackManager] Loading MP3 vocal file: %s" % vocal_file_path)
		"wav":
			vocal_stream = AudioStreamWAV.load_from_file(vocal_file_path)
			print("[MidiPlaybackManager] Loading WAV vocal file: %s" % vocal_file_path)
		_:
			push_error("Unsupported audio format: %s (file: %s)" % [file_ext, vocal_file_path])
			return

	# 检查加载结果
	if vocal_stream == null:
		push_error("Failed to load vocal file: %s" % vocal_file_path)
		return

	print("[MidiPlaybackManager] Successfully loaded vocal file: %s" % vocal_file_path)

	# 播放人声，使用当前的MIDI位置作为起始位置
	var start_position_ms = position_ms - vocal_offset_ms
	start_position_ms = max(0.0, start_position_ms)

	# 设置人声声音
	audio_manager.set_vocal_volume_db(linear_to_db(current_midi_data.vocal_volume / 100.0))
	audio_manager.play_vocal(vocal_stream, start_position_ms)

## 停止人声播放
func stop_vocal_playback() -> void:
	var audio_manager = AudioManager.instance
	if audio_manager != null:
		audio_manager.stop_vocal()

## 自动同步人声与MIDI（在_process中每帧调用）
func _sync_vocal_with_midi() -> void:
	var audio_manager = AudioManager.instance
	if audio_manager == null or not audio_manager.is_vocal_playing():
		return

	# 检查是否需要同步（时间间隔 > 100ms）
	if abs(position_ms - last_sync_check_pos_ms) < 100.0:
		return

	# 获取MIDI和人声的当前播放进度
	var midi_position = position_ms
	var vocal_position = audio_manager.get_vocal_position()

	# 计算差值：考虑偏移量
	var expected_vocal_position = midi_position - vocal_offset_ms
	var diff = abs(vocal_position - expected_vocal_position)

	# 如果差值超过阈值，进行同步调整
	if diff > sync_threshold_ms:
		var target_position = max(0.0, expected_vocal_position)
		audio_manager.seek_vocal(target_position)
		print("[MidiPlaybackManager] Vocal sync adjusted: diff=%.0f ms, target=%.0f ms" % [diff, target_position])

	# 更新上次同步检查的位置
	last_sync_check_pos_ms = position_ms

## 设置音频同步阈值（毫秒）
func set_sync_threshold(threshold_ms: float) -> void:
	sync_threshold_ms = clamp(threshold_ms, 50.0, 500.0)

## 重置同步检查位置（在开始新播放时调用）
func reset_sync_state() -> void:
	last_sync_check_pos_ms = 0.0

## 配置变更回调（新增）
func _on_config_changed(key: String, section: String, value: Variant) -> void:
	# 只处理 Gameplay 部分的配置变更
	if section != "Gameplay":
		return
	
	# 处理音源文件配置变更
	if key == "soundfont_file":
		var soundfont_name = str(value).replace(".sf2", "").strip_edges()
		if not soundfont_name.is_empty():
			set_soundfont(soundfont_name)
	
	# 处理 MIDI 后端配置变更
	elif key == "midi_backend":
		var backend = str(value).to_lower().strip_edges()
		if backend != midi_backend and not backend_switching:
			set_backend(backend)
