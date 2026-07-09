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
var is_paused: bool = false

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
var _soundfont_preloaded_to_backend: bool = false

## 人声偏移量（毫秒）
var vocal_offset_ms: float = 0.0

## 人声是否已初始化（预卷支持）
var _vocal_initialized: bool = false

## 人声文件预加载缓存（在 load_midi 后异步预载，消除 is_pause=false 时的解码卡顿）
var _preloaded_vocal_stream: AudioStream = null
var _vocal_preload_path: String = ""

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

## Android 平台标志（用于降级音频复杂度）
var _is_android: bool = false

# 实时位置的同帧缓存: 避免同一帧多次调用后端导致 GetLatencyMs() 波动
# 使去重逻辑 (基于 judge_time_ms 差值) 失效
var _realtime_pos_cache: float = 0.0
var _realtime_pos_cache_frame: int = -1

## 信号：MIDI播放完成
signal midi_finished

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	
	add_to_group("singleton")
	
	# 检测 Android 平台，降级音频参数以避免引擎级崩溃
	_is_android = OS.get_name() == "Android"
	if _is_android:
		# Android 上 AudioStreamPlayer 数量过多会导致音频线程 StringName 腐败
		# 从 96（192个播放器节点）降低到 24（48个播放器节点）
		midi_player_config["max_polyphony"] = 24
		print("[MidiPlaybackManager] Android detected: max_polyphony reduced to 24")
	
	# 从配置文件加载MIDI后端设置
	_load_backend_from_config()
	
	# 初始化MIDI播放器
	_initialize_backend()
	
	# 扫描可用的SoundFont
	_scan_soundfonts()
	
	# 从配置文件加载音源设置
	_load_soundfont_from_config()
	
	# 监听设置改变信号（用于动态切换MIDI后端和音源）
	if EvtBus:
		EvtBus.settings_changed.connect(_on_settings_changed)
		# 监听配置变更信号（新增，用于应对直接配置文件修改）
		EvtBus.config_changed.connect(_on_config_changed)

	# 启动后预加载 SoundFont 到后端
	call_deferred("_preload_soundfont_to_backend")

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
			GLogger.info("MIDI backend changed from '%s' to '%s'" % [old_backend, midi_backend], "MidiPlaybackManager")
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
	
	# 【修复D-4】如果是泛指信号或系统时钟设置改变
	if setting_name == "*" or setting_name == "use_system_stopwatch":
		print("[MidiPlaybackManager] Applying system stopwatch setting")
		var use_system_stopwatch = ConfigManager.instance.get_int("Playback", "use_system_stopwatch", 0) == 1
		var backend = _get_active_backend()
		if backend != null and backend.has_method("set_use_system_stopwatch"):
			backend.set_use_system_stopwatch(use_system_stopwatch)
			GLogger.info("System stopwatch mode: %s" % ("ON" if use_system_stopwatch else "OFF"), "MidiPlaybackManager")
			print("[MidiPlaybackManager] System stopwatch mode set to: %s" % ("ON" if use_system_stopwatch else "OFF"))
		else:
			print("[MidiPlaybackManager] Current backend does not support system stopwatch setting")

	# 最大复音数改变（需要重新加载SoundFont才能生效）
	if setting_name == "*" or setting_name == "max_polyphony":
		print("[MidiPlaybackManager] Polyphony setting changed, reloading soundfont")

		# 获取当前是否正在播放
		var was_playing = is_playing
		var current_pos = get_position_ms()

		# 停止播放
		if was_playing:
			stop()

		# 如果是MeltySynth后端，重新设置复音数并重新加载SoundFont
		var backend = _get_active_backend()
		if backend != null and midi_backend == "meltysynth":
			# 设置新的复音数
			if backend.has_method("set_max_polyphony"):
				var max_polyphony = ConfigManager.instance.get_int("Playback", "max_polyphony", 96)
				backend.call("set_max_polyphony", max_polyphony)
				print("[MidiPlaybackManager] Updated max polyphony to: %d" % max_polyphony)

			# 重新加载SoundFont使设置生效
			_load_soundfont_from_config()
			print("[MidiPlaybackManager] Soundfont reloaded with new audio settings")
			
			# 如果之前正在播放，恢复播放位置
			if was_playing and current_midi_data != null:
				seek(current_pos)
				play()
				print("[MidiPlaybackManager] Resumed playback at %.2fms" % current_pos)


func _process(_delta: float) -> void:
	var backend = _get_active_backend()
	if not is_playing or backend == null:
		return
	
	# 对于addon后端，直接读取position（tick）
	if midi_backend == "addons" and midi_player != null:
		# Android线程安全：检查对象有效性（音频线程可能导致对象被释放）
		if not is_instance_valid(midi_player):
			push_warning("[MidiPlaybackManager] midi_player invalidated during playback, stopping")
			is_playing = false
			midi_player = null
			return
		
		position = midi_player.position
		
		# 更新position_ms，带BPM时间线支持
		# 【修复】安全检查：确保smf_data在音频线程操作中仍然有效（仅MidiPlayer插件有此属性）
		if "smf_data" in midi_player:
			var smf = midi_player.smf_data
			if smf != null and smf.timebase > 0:
				midi_timebase = smf.timebase
				position_ms = _calculate_position_with_bpm_timeline(position, midi_timebase)
			else:
				position_ms = position  # 无效的 timebase，直接用 position
	
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
	
	# 解析MIDI文件（带缓存：retry 场景跳过重复解析）
	var track_infos: Array
	if not midi_data.parsed_notes.is_empty() and midi_data.midi_file_path == midi_file_path and not midi_data._runtime_track_infos.is_empty():
		# 缓存命中：跳过昂贵的 MIDI 解析
		current_notes = midi_data.parsed_notes
		bpm_timeline = midi_data.bpm_timeline.duplicate()
		midi_timebase = midi_data.midi_timebase
		track_infos = midi_data._runtime_track_infos
		duration_ms = midi_data.duration_ms
		GLogger.info("MIDI parse cache hit, skipping re-parse", "MidiPlaybackManager")
	else:
		var parse_result = MidiParser.load_and_parse_midi(midi_file_path)
		if not parse_result["success"]:
			push_error("Failed to parse MIDI file: %s" % midi_file_path)
			return false

		# 保存解析结果
		current_notes = parse_result["notes"]
		bpm_timeline = parse_result.get("bpm_timeline", [])  # 获取BPM时间线
		midi_timebase = parse_result.get("timebase", 480)  # 保存timebase
		track_infos = parse_result["track_infos"]

		# 对notes按start_time排序（确保时间递增）
		current_notes.sort_custom(func(a, b) -> bool:
			var a_time = a.event.start_time if a is MidiParser.Note and a.event else 0
			var b_time = b.event.start_time if b is MidiParser.Note and b.event else 0
			return a_time < b_time
		)

		current_midi_data.parsed_notes = current_notes
		current_midi_data.track_count = track_infos.size()
		current_midi_data.bpm = parse_result["bpm"]
		current_midi_data.duration_ms = parse_result["duration"]
		current_midi_data.bpm_timeline = bpm_timeline.duplicate()
		current_midi_data.midi_timebase = midi_timebase
		current_midi_data._runtime_track_infos = track_infos
		duration_ms = parse_result["duration"]

	# 从 track_infos 中提取乐器信息（用于不维护此信息的后端，如 MeltySynth）
	_extract_track_channel_instruments(track_infos)
	
	# 如果未选择轨道，则默认选择所有轨道
	if current_midi_data.selected_track_indices.is_empty():
		for i in range(current_midi_data.track_count):
			current_midi_data.selected_track_indices.append(i)

	# 初始化 selected_track_configs：新MIDI（从未配置过）默认启用所有 (track, channel) 对
	# 这样直接进入 PlayView 也能正确生成音符，无需先经过 TrackView
	if not current_midi_data._track_config_initialized:
		current_midi_data.selected_track_configs.clear()
		for note in current_notes:
			if note is MidiParser.Note and note.event != null:
				current_midi_data.set_track_channel_enabled(note.event.track_index, note.event.channel, true)
		current_midi_data._track_config_initialized = true
		GLogger.info("Initialized selected_track_configs with all (track, channel) pairs for new MIDI", "MidiPlaybackManager")
	
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
	
	# 清理旧乐器覆盖配置（双重保障：后端 set_file/load_midi 已清理，这里再次确认）
	# 注意：后端的 set_file/load_midi 方法已经清理了 track_channel_instruments
	# 这里的检查主要用于防御性编程，确保清理操作成功
	if backend != null and "track_channel_instruments" in backend:
		if backend.track_channel_instruments.size() > 0:
			print("[MidiPlaybackManager] Warning: Backend still has %d instrument overrides after file load, clearing..." % backend.track_channel_instruments.size())
			backend.track_channel_instruments.clear()
	
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
	
	# 应用系统时钟配置（后端实现了 set_use_system_stopwatch 即可）
	if backend != null and backend.has_method("set_use_system_stopwatch"):
		var use_system_stopwatch = ConfigManager.instance.get_int("Playback", "use_system_stopwatch", 0) == 1
		backend.set_use_system_stopwatch(use_system_stopwatch)
		GLogger.info("System stopwatch mode: %s" % ("ON" if use_system_stopwatch else "OFF"), "MidiPlaybackManager")
	
	# 发出信号

	# 预载人声文件（利用 PlayView 后续 0.8s+1s await 的空闲时间，消除 is_pause=false 时的解码卡顿）
	_preload_vocal_async()

	return true

## 异步预载人声文件（call_deferred 避免阻塞当前帧，AudioStream 须在主线程创建）
func _preload_vocal_async() -> void:
	if current_midi_data == null or current_midi_data.vocal_file_path.is_empty():
		return
	if not current_midi_data.vocal_enabled:
		return
	var path = current_midi_data.vocal_file_path
	if path == _vocal_preload_path and _preloaded_vocal_stream != null:
		return  # 已预加载
	_vocal_preload_path = path
	_preloaded_vocal_stream = null
	_do_load_vocal.call_deferred(path)

func _do_load_vocal(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var ext = path.get_extension().to_lower()
	match ext:
		"mp3":
			_preloaded_vocal_stream = AudioStreamMP3.load_from_file(path)
		"ogg":
			_preloaded_vocal_stream = AudioStreamOggVorbis.load_from_file(path)
		"wav":
			_preloaded_vocal_stream = AudioStreamWAV.load_from_file(path)

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
	if not _soundfont_preloaded_to_backend and not current_soundfont_path.is_empty() and backend.has_method("set_soundfont"):
		backend.set_soundfont(current_soundfont_path)
		_soundfont_preloaded_to_backend = true

	# 重置同步状态
	reset_sync_state()

	# 保留当前 seek 目标（可为负数 pre-roll），避免 play() 覆盖外部预设位置
	var start_position_ms = position_ms

	backend.play()
	is_playing = true
	is_paused = false

	# 若存在预设起始位置（含负数 pre-roll），在启动后立即恢复到该位置
	if abs(start_position_ms) > 0.001:
		seek(start_position_ms)
	else:
		# 默认从 0 开始
		position = 0.0
		position_ms = 0.0

	# 启动人声播放（如果有人声文件）
	if not current_midi_data.vocal_file_path.is_empty():
		start_vocal_playback()
		print("[MidiPlaybackManager] Started vocal playback: %s (offset: %d ms)" % [current_midi_data.vocal_file_path, vocal_offset_ms])
	else:
		print("[MidiPlaybackManager] No vocal file configured (path: '%s')" % current_midi_data.vocal_file_path)

## 停止播放
func stop() -> void:
	var backend = _get_active_backend()
	if backend == null:
		return
	
	backend.stop()
	is_playing = false
	is_paused = false
	position = 0.0
	position_ms = 0.0

	# 停止人声播放
	stop_vocal_playback()

## 暂停播放
func pause() -> void:
	var backend = _get_active_backend()
	if backend == null:
		return
	
	backend.pause()
	is_playing = false
	is_paused = true

	# 暂停人声播放
	var audio_manager = AudioManager.instance
	if current_midi_data and audio_manager:
		audio_manager.set_vocal_playing(false)

## 继续播放
func resume() -> void:
	var backend = _get_active_backend()
	if backend == null:
		return
	
	backend.resume()
	is_playing = true
	is_paused = false

	# 恢复或启动人声播放
	if current_midi_data and not current_midi_data.vocal_file_path.is_empty() and current_midi_data.vocal_enabled:
		if not _vocal_initialized:
			start_vocal_playback()
		else:
			var audio_manager = AudioManager.instance
			if audio_manager:
				audio_manager.set_vocal_playing(true)

## 设置循环播放
func set_loop(enabled: bool) -> void:
	var backend = _get_active_backend()
	if backend != null:
		if backend.has_method("set_loop"):
			backend.call("set_loop", enabled)
		elif "loop" in backend:
			backend.loop = enabled
	
	# 同时更新配置
	midi_player_config["loop"] = enabled
	print("[MidiPlaybackManager] Loop set to: %s (backend: %s)" % [enabled, midi_backend])

## 获取循环播放状态
func get_loop() -> bool:
	var backend = _get_active_backend()
	if backend != null:
		if backend.has_method("get_loop"):
			return backend.call("get_loop")
		elif "loop" in backend:
			return backend.loop
	return false

## 跳转到指定位置
## position: 位置（毫秒）
func seek(pos: float) -> void:
	position_ms = pos
	print("[MidiPlaybackManager] Seeking to %.1f ms (backend: %s)" % [pos, midi_backend])
	
	if midi_backend == "addons" and midi_player != null:
		# 使用BPM时间线计算精确的tick位置
		# 【修复】安全检查 smf_data（仅MidiPlayer插件有）
		var timebase_for_seek = midi_timebase
		if "smf_data" in midi_player and midi_player.smf_data != null and midi_player.smf_data.timebase > 0:
			timebase_for_seek = midi_player.smf_data.timebase
		
		if timebase_for_seek > 0:
			var target_tick = _calculate_tick_from_position_with_bpm_timeline(pos, timebase_for_seek)
			print("[MidiPlaybackManager] Seeking to tick %.1f (addons backend)" % target_tick)
			midi_player.seek(target_tick)
			# 立即同步 position，避免其他系统在下一帧前读到过时的 tick 值
			position = target_tick
	elif midi_backend == "meltysynth" and meltysynth_player != null:
		# 直接调用 C# 的 seek_ms 方法
		print("[MidiPlaybackManager] Calling MeltySynth seek_ms(%.1f)" % pos)
		meltysynth_player.seek_ms(pos)
		# 立即同步 position（从毫秒转 tick）
		if midi_timebase > 0:
			position = _calculate_tick_from_position_with_bpm_timeline(pos, midi_timebase)
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

## 预加载 SoundFont 到后端（启动时延迟调用）
func _preload_soundfont_to_backend() -> void:
	if _soundfont_preloaded_to_backend:
		return
	if midi_player == null or current_soundfont_path.is_empty():
		return
	
	print("[MidiPlaybackManager] Pre-loading SoundFont: %s" % current_soundfont_path)
	midi_player.set_soundfont(current_soundfont_path)
	_soundfont_preloaded_to_backend = true
	print("[MidiPlaybackManager] SoundFont pre-loaded successfully")

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
		midi_player.set_soundfont(soundfont_path)
		_soundfont_preloaded_to_backend = true
	else:
		_soundfont_preloaded_to_backend = false

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
		_soundfont_preloaded_to_backend = false
		print("[MidiPlaybackManager] Switched to addon MIDI backend (GDScript)")

		# Pre-load current MIDI into addon backend
		if current_midi_data != null and not current_midi_data.midi_file_path.is_empty():
			var be = _get_active_backend()
			if be.has_method("load_midi"):
				be.load_midi(current_midi_data.midi_file_path)
			elif be.has_method("set_file"):
				be.set_file(current_midi_data.midi_file_path)
			elif "file" in be:
				be.file = current_midi_data.midi_file_path
			print("[MidiPlaybackManager] Pre-loaded current MIDI into addon backend")

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
		
		# 【关键修复】设置 midi_player 指向 meltysynth_player，确保后续调用能正确转发
		midi_player = meltysynth_player
		midi_backend = "meltysynth"
		_soundfont_preloaded_to_backend = false
		print("[MidiPlaybackManager] Switched to MeltySynth MIDI backend (C#)")

		# Pre-load current MIDI into new backend to avoid empty backend on play
		if current_midi_data != null and not current_midi_data.midi_file_path.is_empty():
			meltysynth_player.load_midi(current_midi_data.midi_file_path)
			print("[MidiPlaybackManager] Pre-loaded current MIDI into MeltySynth backend")

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
	# Android 平台强制优先使用 MeltySynth 后端
	# 原因：addons 后端使用大量 AudioStreamPlayer 节点，会触发 Godot 引擎级
	# StringName 引用计数竞态条件（音频线程 crash: "Unreferenced static string to 0"）
	# MeltySynth 使用单个 AudioStreamPlayer + AudioStreamGenerator 软件混音，完全避免此 bug
	if _is_android:
		print("[MidiPlaybackManager] Android: attempting MeltySynth backend to avoid audio thread crash")
		if _is_csharp_available():
			var melty_ok = _initialize_meltysynth_backend()
			if melty_ok:
				midi_backend = "meltysynth"
				print("[MidiPlaybackManager] Android: MeltySynth backend active (safe mode)")
				return true
			else:
				push_warning("[MidiPlaybackManager] Android: MeltySynth initialization failed, falling back to addon backend")
		else:
			push_warning("[MidiPlaybackManager] Android: C# not available - addon backend may cause audio thread crashes")
			push_warning("[MidiPlaybackManager] Android: Consider exporting with .NET support for stable MIDI playback")
		# Android fallback to addon backend with warning
		return _initialize_addon_backend()
	
	# 非 Android 平台：按配置选择后端
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
		# 若当前引用不是 Addon MidiPlayer（例如切换后残留 MeltySynth wrapper），先清理再重建
		if "loop" in midi_player and "smf_data" in midi_player:
			print("[MidiPlaybackManager] Addon backend already initialized, skipping")
			return true  # 已经初始化
		print("[MidiPlaybackManager] Existing midi_player is not addon backend, recreating addon instance")
		if midi_player.get_parent() == self:
			remove_child(midi_player)
		midi_player.queue_free()
		midi_player = null
	
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
	
	GLogger.info("Addon MIDI backend initialized successfully", "MidiPlaybackManager")
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
	
	# 设置meltysynth_player属性
	wrapper.set("meltysynth_player", csharp_backend)
	print("[MidiPlaybackManager] Set meltysynth_player property on wrapper")
	
	# 添加为子节点
	add_child(wrapper as Node)
	print("[MidiPlaybackManager] Added wrapper as child node")
	
	# 配置播放器参数
	wrapper.set("max_polyphony", midi_player_config["max_polyphony"])
	if wrapper.has_method("set_loop"):
		wrapper.call("set_loop", midi_player_config["loop"])
	print("[MidiPlaybackManager] Set playback parameters")
	
	if wrapper.has_method("set_volume_db"):
		wrapper.call("set_volume_db", midi_player_config["volume_db"])
		print("[MidiPlaybackManager] Called set_volume_db")
	
	if wrapper.has_method("set_bus"):
		wrapper.call("set_bus", "Master")
		print("[MidiPlaybackManager] Called set_bus")
	
	# 【修复D-4】初始化系统时钟配置
	if wrapper.has_method("set_use_system_stopwatch"):
		var use_system_stopwatch = ConfigManager.instance.get_int("Playback", "use_system_stopwatch", 0) == 1
		wrapper.call("set_use_system_stopwatch", use_system_stopwatch)
		print("[MidiPlaybackManager] Set system stopwatch mode: %s" % ("ON" if use_system_stopwatch else "OFF"))

	# 设置最大复音数
	wrapper.set("max_polyphony", ConfigManager.instance.get_int("Playback", "max_polyphony", 96))
	print("[MidiPlaybackManager] Set max polyphony: %d" % wrapper.max_polyphony)

	# 连接信号
	if wrapper.has_signal("finished"):
		wrapper.finished.connect(_on_midi_finished)
		print("[MidiPlaybackManager] Connected finished signal")
	
	# 保存引用
	meltysynth_player = wrapper
	# 【关键修复】初始化时也要设置 midi_player 指向 meltysynth_player，确保 TrackView 的调用能正确转发
	midi_player = wrapper
	GLogger.info("MeltySynth C# backend initialized successfully", "MidiPlaybackManager")
	print("[MidiPlaybackManager] MeltySynth backend initialization complete")
	print("[MidiPlaybackManager] Set both meltysynth_player and midi_player to: %s" % wrapper)
	
	return true

## 检查C#支持（兼容导出包）
## 旧方法检查 .csproj 文件，但导出的 APK 不包含此文件
## 新方法：检查 C# 运行时 + MeltySynth 场景是否存在
func _is_csharp_available() -> bool:
	# 1. 检查 Godot C# 运行时是否可用（仅 Mono 构建版本有此类）
	if not ClassDB.class_exists(&"CSharpScript"):
		print("[MidiPlaybackManager] C# runtime not available (non-Mono build)")
		return false
	# 2. 检查 MeltySynth 场景是否存在
	if not ResourceLoader.exists("res://CSharp/MeltySynthPlayer.tscn"):
		print("[MidiPlaybackManager] MeltySynth scene not found")
		return false
	print("[MidiPlaybackManager] C# runtime and MeltySynth scene available")
	return true

## 清理旧后端（彻底销毁以避免同时运行多个后端）
## 这是动态切换的关键步骤，防止旧后端继续在后台运行
func _cleanup_old_backend(backend_type: String) -> void:
	match backend_type:
		"addons":
			if midi_player != null:
				print("[MidiPlaybackManager] Cleaning up Addon backend")
				# 1. 停止播放器并停止所有音符（确保音频线程不再处理数据）
				if midi_player.has_method("stop"):
					midi_player.stop()
					print("[MidiPlaybackManager] Addon backend stopped")
				if midi_player.has_method("_stop_all_notes"):
					midi_player._stop_all_notes()
					print("[MidiPlaybackManager] All addon notes stopped")
				
				# 2. 断开所有信号
				if midi_player.has_signal("finished"):
					if midi_player.finished.is_connected(_on_midi_finished):
						midi_player.finished.disconnect(_on_midi_finished)
						print("[MidiPlaybackManager] Addon finished signal disconnected")
				
				# 3. 清空引用（先清引用，防止下一帧_process访问）
				var old_player = midi_player
				midi_player = null
				
				# 4. 从场景树移除（使用queue_free而非free，给音频线程时间完成当前回调）
				if old_player.get_parent() != null:
					if old_player.get_parent() == self:
						remove_child(old_player)
				old_player.queue_free()
				print("[MidiPlaybackManager] Addon backend queued for deletion")
		
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
				
				# 3. 清空引用（先清引用，防止下一帧_process访问）
				var old_player = meltysynth_player
				meltysynth_player = null
				if midi_player == old_player:
					midi_player = null
				
				# 4. 从场景树移除（使用queue_free，给音频线程时间完成当前回调）
				if old_player.get_parent() != null:
					if old_player.get_parent() == self:
						remove_child(old_player)
				old_player.queue_free()
				print("[MidiPlaybackManager] MeltySynth backend queued for deletion")
		
		_:
			print("[MidiPlaybackManager] Unknown backend type for cleanup: %s" % backend_type)

## 获取活跃的MIDI播放器
func _get_active_backend() -> MidiPlaybackInterface:
	match midi_backend:
		"meltysynth":
			return meltysynth_player if meltysynth_player != null else midi_player
		_:
			return midi_player

## 辅助函数：定位soundfont文件（用户目录优先）
func _locate_soundfont(soundfont_name: String) -> String:
	"""
	定位soundfont文件，用户目录优先于res://
	
	Args:
		soundfont_name: 文件名不含.sf2扩展名
	
	Returns:
		String: 完整文件路径，若不存在返回空字符串
	"""
	# 第一步：检查用户音源目录
	var user_path = PathHelper.get_soundfont_dir().path_join(soundfont_name + ".sf2")
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

## 获取 MIDI 文件中的原始乐器配置（不考虑用户覆盖）
func get_original_track_channel_instrument(track_index: int, channel: int) -> Dictionary:
	return _get_instrument_from_cache(track_index, channel)

## 设置轨道通道的乐器
func set_track_channel_instrument(track_index: int, channel: int, bank: int, program: int) -> void:
	var backend = _get_active_backend()
	if backend != null and backend.has_method("set_track_channel_instrument"):
		backend.set_track_channel_instrument(track_index, channel, bank, program)

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
		var metadata: ChartMetadata = charts_index[folder_name]
		var chart_id: String = metadata.id
		if chart_id == midi_data.id or chart_id == midi_data.file_hash:
			# 首选使用索引中缓存的路径
			var chart_path: String = metadata.path
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
## @param	manual_control_notes	Note或ManualControlNote数组
func set_manual_control_notes(manual_control_notes: Array) -> void:
	if midi_player == null:
		push_warning("[MidiPlaybackManager] MidiPlayer not initialized")
		return
	
	# 构建手动控制note的字典（精确到起始tick）
	# 新格式：{track_index: {channel: {pitch: {start_tick: true}}}}
	# 兼容性：播放器端仍兼容旧格式 {channel: {pitch: true}}
	var manually_controlled: Dictionary = {}
	
	for note in manual_control_notes:
		# 支持普通Note和ManualControlNote两种类型
		if note is MidiParser.Note and note.event:
			var track_index = note.event.track_index
			var channel = note.event.channel
			var pitch = note.event.pitch
			var start_tick = int(round(note.event.start_time))
			
			if not manually_controlled.has(track_index):
				manually_controlled[track_index] = {}
			if not manually_controlled[track_index].has(channel):
				manually_controlled[track_index][channel] = {}
			if not manually_controlled[track_index][channel].has(pitch):
				manually_controlled[track_index][channel][pitch] = {}
			
			var tick_map = manually_controlled[track_index][channel][pitch]
			tick_map[start_tick] = int(tick_map.get(start_tick, 0)) + 1
	
	# 传递给MidiPlayer
	if midi_player.has_method("set_manually_controlled_notes"):
		midi_player.set_manually_controlled_notes(manually_controlled)
		
		# 调试日志：显示已标记的手动控制notes
		var total_entries = 0
		for track_key in manually_controlled.keys():
			for ch in manually_controlled[track_key].keys():
				for pitch in manually_controlled[track_key][ch].keys():
					total_entries += manually_controlled[track_key][ch][pitch].size()
		print("[MidiPlaybackManager] Set manual control: %d notes, %d precise (track,ch,pitch,start_tick) entries" % 
			[manual_control_notes.size(), total_entries])
	else:
		push_warning("[MidiPlaybackManager] MidiPlayer does not support set_manually_controlled_notes")

## 清除所有手动控制note标记（恢复所有notes自动播放）
## 当退出PlayView返回TrackView等场景时调用
func clear_manual_control_notes() -> void:
	if midi_player == null:
		return
	
	# 传递空字典给MidiPlayer，清除所有手动控制标记
	if midi_player.has_method("set_manually_controlled_notes"):
		midi_player.set_manually_controlled_notes({})
		print("[MidiPlaybackManager] Cleared all manual control notes, restored auto-play")

## ========== 位置单位转换工具 ==========
## 将tick位置转换为毫秒（使用BPM时间线）
func tick_to_ms(tick: float) -> float:
	return _calculate_position_with_bpm_timeline(tick, midi_timebase)

## 获取当前播放位置（毫秒）
## 这是对position_ms的替代方法，更明确地表示返回值的单位
func get_position_ms() -> float:
	return position_ms

## 实时获取当前播放位置（毫秒），绕过 _process 缓存
## 用于触摸判定等对时效性敏感的场景，消除帧级输入延迟
## 同帧缓存: 同一帧内多次调用返回相同值, 避免 GetLatencyMs() 动态波动
## 导致去重逻辑失效 (如 Android 触摸+鼠标模拟事件对)
func get_realtime_position_ms() -> float:
	var current_frame = Engine.get_process_frames()
	if current_frame == _realtime_pos_cache_frame:
		return _realtime_pos_cache
	_realtime_pos_cache_frame = current_frame
	var backend = _get_active_backend()
	if backend != null:
		_realtime_pos_cache = backend.get_position_ms()
	else:
		_realtime_pos_cache = position_ms
	return _realtime_pos_cache

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
	if not current_midi_data.vocal_enabled:
		return

	var audio_manager = AudioManager.instance
	if audio_manager == null:
		return

	# 加载人声音频文件
	var vocal_file_path = current_midi_data.vocal_file_path
	var vocal_stream: AudioStream = null

	# 优先使用预加载的 stream（消除 is_pause=false 时的解码卡顿）
	if _preloaded_vocal_stream != null and _vocal_preload_path == vocal_file_path:
		vocal_stream = _preloaded_vocal_stream
		print("[MidiPlaybackManager] Using preloaded vocal file: %s" % vocal_file_path)
	else:
		# 预加载未完成或路径不匹配，回退到同步加载
		# 首先检查文件是否存在（使用FileAccess，支持user://目录）
		if not FileAccess.file_exists(vocal_file_path):
			GLogger.warning("Vocal file does not exist, skipping vocal playback: %s" % vocal_file_path, "MidiPlaybackMGR")
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
	_vocal_initialized = true
	
	# 如果 MIDI 处于预卷阶段（负位置），暂停人声等待 MIDI 追赶
	if position_ms < 0.0:
		audio_manager.set_vocal_playing(false)

## 停止人声播放
func stop_vocal_playback() -> void:
	_vocal_initialized = false
	var audio_manager = AudioManager.instance
	if audio_manager != null:
		audio_manager.stop_vocal()

## 自动同步人声与MIDI（在_process中每帧调用）
func _sync_vocal_with_midi() -> void:
	var audio_manager = AudioManager.instance
	if audio_manager == null:
		return
	
	# 如果人声已初始化但在预卷期间被暂停，等 MIDI 到达正位置后恢复
	if _vocal_initialized and not audio_manager.is_vocal_playing():
		if position_ms >= 0.0:
			audio_manager.set_vocal_playing(true)
			audio_manager.seek_vocal(0.0)
		return
	
	if not audio_manager.is_vocal_playing():
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
	sync_threshold_ms = clamp(threshold_ms, 1.0, 100000.0)

## 重置同步检查位置（在开始新播放时调用）
func reset_sync_state() -> void:
	last_sync_check_pos_ms = 0.0

## 配置变更回调（新增）
func _on_config_changed(key: String, section: String, value: Variant) -> void:
	# 处理 Gameplay 部分的配置变更
	if section == "Gameplay":
		# 处理音源文件配置变更
		if key == "soundfont_file":
			var soundfont_name = str(value).replace(".sf2", "").strip_edges()
			if not soundfont_name.is_empty():
				set_soundfont(soundfont_name)
		
		# 处理 MIDI 后端配置变更
		elif key == "midi_backend":
			var backend = str(value).to_lower().strip_edges()
			
			# 防御性检查：如果传入的是索引数字，转换为实际名称
			if backend == "0" or backend == "addons":
				backend = "addons"
			elif backend == "1" or backend == "meltysynth":
				backend = "meltysynth"
			else:
				push_warning("[MidiPlaybackManager] Invalid backend value: %s, ignoring" % backend)
				return
			
			if backend != midi_backend and not backend_switching:
				set_backend(backend)
			return
	
	# 处理 Playback 部分的配置变更
	if section == "Playback":
		# 最大复音数改变（需要重新加载SoundFont才能生效）
		if key == "max_polyphony":
			print("[MidiPlaybackManager] Polyphony setting changed via config: %s = %s" % [key, value])

			# 获取当前是否正在播放
			var was_playing = is_playing
			var current_pos = get_position_ms()

			# 停止播放
			if was_playing:
				stop()

			# 如果是MeltySynth后端，重新设置复音数并重新加载SoundFont
			var backend = _get_active_backend()
			if backend != null and midi_backend == "meltysynth":
				# 设置新的复音数
				if backend.has_method("set_max_polyphony"):
					var max_polyphony = int(value) if value is int else ConfigManager.instance.get_int("Playback", "max_polyphony", 96)
					backend.call("set_max_polyphony", max_polyphony)
					print("[MidiPlaybackManager] Updated max polyphony to: %d" % max_polyphony)

				# 重新加载SoundFont使设置生效
				_load_soundfont_from_config()
				print("[MidiPlaybackManager] Soundfont reloaded with new audio settings")

				# 如果之前正在播放，恢复播放位置
				if was_playing and current_midi_data != null:
					seek(current_pos)
					play()
					print("[MidiPlaybackManager] Resumed playback at %.2fms" % current_pos)
			return
