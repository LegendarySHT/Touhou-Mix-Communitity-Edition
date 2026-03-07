extends Control

# 音符显示区
@onready var flow_area: Panel = $FlowArea

@onready var background: TextureRect = $Background
@onready var menu_btn: TextureButton = $Layer/BackBtn
@onready var progress_bar: ProgressBar = $Layer/TopProgressBar

# 中间
@onready var combo: Label = $Layer/Combo/count
@onready var score: Label = $Layer/Score/count
@onready var score_add: Label = $Layer/Score/add
# 显示perfect的那个部分
@onready var center: VBoxContainer = $Layer/Center
@onready var center_text: Label = $Layer/Center/type
@onready var early_text: Label = $Layer/Center/up
@onready var late_text: Label = $Layer/Center/down

# 底部
@onready var pp_text: Label = $Layer/LeftBottom
@onready var accuracy_text: Label = $Layer/RightBottom

# 菜单及歌曲信息的背景遮罩
@onready var center_bg:ColorRect = $Layer/CenterBackGround
# 菜单
@onready var menu: Control = $Layer/CenterBackGround/Menu
@onready var retry_btn: Button = $Layer/CenterBackGround/Menu/retry
@onready var continue_btn: Button = $Layer/CenterBackGround/Menu/continue
@onready var quit_btn: Button = $Layer/CenterBackGround/Menu/quit
# 歌曲信息
@onready var song_info: Control = $Layer/CenterBackGround/SongInfo
@onready var cover: TextureRect = $Layer/CenterBackGround/SongInfo/PanelContainer/TextureRect
# 原曲
@onready var album: Label = $Layer/CenterBackGround/SongInfo/GridContainer/album
@onready var song: Label = $Layer/CenterBackGround/SongInfo/GridContainer/song
@onready var artist: Label = $Layer/CenterBackGround/SongInfo/GridContainer/artist
# midi
@onready var midi_name: Label = $Layer/CenterBackGround/SongInfo/GridContainer/midiName
@onready var midi_author: Label = $Layer/CenterBackGround/SongInfo/GridContainer/midiAuthor
@onready var midi_duration: Label = $Layer/CenterBackGround/SongInfo/GridContainer/midiDuration
# 难度
@onready var difficulty: Label = $Layer/CenterBackGround/SongInfo/GridContainer/difficulty

# 轨道光效及键位显示
@onready var lane_area: Control = $Lane

@onready var env: WorldEnvironment = $FlowArea/SVP/WorldEnvironment
@onready var current_env: Environment = env.environment

# auto标识
@onready var auto_label: Label = $AutoLabel
@onready var debug_info_label: Label = $Layer/DebugInfo

var current_midi: MidiData = null
## play_result 仅作为传递给 ScoreView 的展示数据容器
var play_result: ScoreView.ScoreData = null

@onready var ani: AnimationManager = AnimationManager.instance
@onready var playback_mgr: MidiPlaybackManager = MidiPlaybackManager.instance
@onready var key_sequence_mgr: KeySequenceManager = KeySequenceManager.instance
@onready var score_calc: ScoreCalculator = ScoreCalculator.instance

var midi_start_time: float = 0.0

## 演奏模式标志：true = 演奏模式（响应键盘触发音符），false = 听奏模式（MIDI只在背景播放）
var play_mode: bool = true

## 生成的游戏键序列（演奏模式使用）
var game_sequences: Array[KeySequenceManager.GameSequence] = []

## MIDI播放中标志
var is_midi_playing: bool = false

########## 配置参数 #############
# 有一部分配置参数在flow_area里面
var lane_count: int = 12
var lane_padding: int = 200 # 左右填充安全区
var keyboard_mode: bool = false
var key_map: Array[Key] = []

var judge_line_offset_y: int = 250

# 光柱特效不透明度
var beam_alpha: float = 0.5
# 交错轨道颜色（启用时会覆盖音符颜色及轨道光效颜色）
var intersect_lane_color: bool = true
var intersect_color_set: Array = [Color.RED, Color.BLUE] # 这个颜色数量不能超过轨道数的一半

var show_debug_info: bool = false
var debug_info_refresh_interval: float = 0.5
var debug_info_elapsed: float = 0.0

#################################

func _ready() -> void:
	# 从配置加载键盘和轨道相关的参数
	_load_lane_parameters()
	_load_debug_display_setting()
	
	# 窗口大小变化
	get_window().size_changed.connect(_init_lane_display)

	EventBus.instance.start_game_with.connect(_prepare_game)
	UIStateManager.instance.state_changed.connect(_on_state_changed)
	_on_state_changed(UIStateManager.instance.UIState.NONE, UIStateManager.instance.current_state)

	progress_bar.value_changed.connect(_on_top_progress_bar_value_changed)

	flow_area.note_judged.connect(_on_note_judged)
	flow_area.long_holding.connect(_on_long_holding)
	flow_area.parent_node = self

	menu_btn.pressed.connect(show_or_hide_menu)
	continue_btn.pressed.connect(show_or_hide_menu)
	retry_btn.pressed.connect(func ():
		_prepare_game()
	)
	quit_btn.pressed.connect(_on_quit_pressed)
	
	# 初始化MIDI播放管理器
	if playback_mgr == null:
		push_error("MidiPlaybackManager not initialized!")
		return
	
	# 连接MIDI播放信号
	playback_mgr.midi_started.connect(_on_midi_started)
	
	# 从配置加载演奏模式设置
	_load_play_mode_setting()
	
	# 连接配置变更信号
	if not EventBus.instance.config_changed.is_connected(_on_lane_config_changed):
		EventBus.instance.config_changed.connect(_on_lane_config_changed)
	if not EventBus.instance.config_changed.is_connected(_on_config_changed):
		EventBus.instance.config_changed.connect(_on_config_changed)
	_set_debug_overlay_visible(show_debug_info)
	
	env.environment = null

var current_time: float = 0
var max_time: float = 20

func _process(delta: float) -> void:
	if score_wait_to_add > 0:
		var amount = int(sqrt(score_wait_to_add))
		score.text = str(int(score.text) + amount)
		score_wait_to_add -= amount

	if show_debug_info and debug_info_label and debug_info_label.visible:
		debug_info_elapsed += delta
		if debug_info_elapsed >= debug_info_refresh_interval:
			debug_info_elapsed = 0.0
			_update_debug_overlay()

	if not is_pause:
		# 如果正在播放MIDI，使用MIDI播放管理器的时间
		current_time = playback_mgr.get_position_ms()
		progress_bar.value = current_time
	
func get_lane_count() -> int:
	return lane_count if not keyboard_mode else key_map.size()

func get_lane_color(lane_idx: int):
	if lane_idx == -1:
		return
	if intersect_lane_color:
		@warning_ignore("integer_division")
		var lc = int(get_lane_count() / 2)
		return intersect_color_set[lane_idx % lc % intersect_color_set.size()]

func _on_state_changed(_oldState: UIStateManager.UIState, state: UIStateManager.UIState) -> void:
	var enable:bool = state == UIStateManager.UIState.PLAY_VIEW
	set_process(enable)
	set_process_input(enable)
	get_node("Layer").visible = enable
	env.environment = current_env if enable else null
	
	# 离开播放视图时停止MIDI播放
	if _oldState == UIStateManager.UIState.PLAY_VIEW and state != UIStateManager.UIState.PLAY_VIEW:
		if playback_mgr:
			playback_mgr.stop()
			# 清除手动控制notes标记，恢复TrackView等场景的自动播放
			playback_mgr.clear_manual_control_notes()
	
	if enable:
		print("Node: %s , ProcessMode: %s" % [self.name, enable])

## 新增：配置变更回调
func _on_config_changed(key: String, section: String, value: Variant) -> void:
	if section == "General" and key == "display_debug_info":
		show_debug_info = int(value) == 1
		_set_debug_overlay_visible(show_debug_info)
		return

	if section == "Playback" and key == "performing_mode":
		var new_mode = (value as int) == 1
		
		# 只在值实际改变时处理
		if new_mode == play_mode:
			return
		
		play_mode = new_mode
		
		if play_mode:
			# 演奏模式开启：重新应用手动控制notes标记
			if playback_mgr and game_sequences.size() > 0:
				var classification = key_sequence_mgr.get_last_notes_classification()
				var manual_control_notes = classification["manual_control_notes"]
				playback_mgr.set_manual_control_notes(manual_control_notes)
				GameLogger.instance.info("Performing mode ON: reapplied manual control notes (%d)" % manual_control_notes.size(), "PlayView")
		else:
			# 演奏模式关闭：清除手动控制notes标记，恢复全自动播放
			if playback_mgr:
				playback_mgr.clear_manual_control_notes()
				GameLogger.instance.info("Performing mode OFF: cleared manual control notes", "PlayView")

func _load_debug_display_setting() -> void:
	show_debug_info = ConfigManager.instance.get_int("General", "display_debug_info", 0) == 1

func _set_debug_overlay_visible(visible: bool) -> void:
	if debug_info_label == null:
		return

	debug_info_label.visible = visible
	debug_info_elapsed = debug_info_refresh_interval
	if visible:
		_update_debug_overlay()

func _update_debug_overlay() -> void:
	if debug_info_label == null:
		return

	var fps = Engine.get_frames_per_second()
	var frame_ms = (1000.0 / max(1.0, float(fps)))
	var draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects_in_frame = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var memory_static_mb = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)
	var memory_static_max_mb = float(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / (1024.0 * 1024.0)

	debug_info_label.text = "FPS: %d (%.2f ms)\n渲染: DrawCalls %d | Objects %d\n内存: %.1f MB / 峰值 %.1f MB" % [
		fps,
		frame_ms,
		draw_calls,
		objects_in_frame,
		memory_static_mb,
		memory_static_max_mb
	]

var is_pause: bool = false:
	set(v):
		is_pause = v
		if playback_mgr:
			if is_pause:
				playback_mgr.pause()
			else:
				playback_mgr.resume()

func show_or_hide_menu():
	song_info.visible = false
	is_pause = not is_pause
	
	if is_pause:
		ani.animate_fade_in(menu, 0.2, "_show_menu")
		ani.animate_fade_in(center_bg, 0.2, "_show_bg")
	else:
		ani.animate_fade_out(menu, 0.2, "_show_menu")
		ani.animate_fade_out(center_bg, 0.2, "_show_bg")

func _prepare_game(midi:MidiData = current_midi) -> void:
	current_midi = midi
	play_result = ScoreView.ScoreData.new()

	# 重置 ScoreCalculator
	if score_calc:
		score_calc.reset()

	_init_display()
	flow_area.init_flow_area()
	
	await get_tree().create_timer(0.8).timeout

	# 加载MIDI并转换为FlowArea音符
	_load_and_convert_midi_notes(midi)
	
	# 新增：从配置读取演奏模式
	var performing_mode = ConfigManager.instance.get_int("Playback", "performing_mode", 1)
	play_mode = (performing_mode == 1)
	GameLogger.instance.info("Performing mode: %s" % ("ON" if play_mode else "OFF"), "PlayView")
	
	# 新增：连接配置变更信号
	if not EventBus.instance.config_changed.is_connected(_on_config_changed):
		EventBus.instance.config_changed.connect(_on_config_changed)
	
	# 计算初始seek位置：-1000ms（固定：给予UI准备时间）- 音符下落时间（配置项）
	var note_fall_time = ConfigManager.instance.get_float("Generator", "note_fall_time", 1.5)
	var seek_position = -(1000 + note_fall_time * 1000)
	playback_mgr.seek(seek_position)
	is_pause = true
	
	# 读取并设置音频同步阈值
	var setting_view = get_node_or_null("/root/Main/skew/C/SettingView")
	if setting_view and setting_view.has_method("get_setting_value"):
		var sync_threshold = setting_view.get_setting_value("audio_sync_threshold")
		if sync_threshold != null:
			playback_mgr.set_sync_threshold(float(sync_threshold))
			print("[PlayView] Audio sync threshold set to %.0f ms" % float(sync_threshold))
	
	# 生成游戏键序列（无论演奏模式开启或关闭都生成，只是演奏模式决定是否响应键盘输入）
	_generate_game_sequences(midi)
	print("[PlayView] After _generate_game_sequences, game_sequences.size() = %d" % game_sequences.size())
	
	# 将生成的游戏序列转换为FlowArea所需的音符格式
	var flow_notes = _convert_game_sequences_to_flow_notes(game_sequences)
	print("[PlayView] After _convert_game_sequences_to_flow_notes, flow_notes.size() = %d" % flow_notes.size())
	flow_area.notes_list = flow_notes
	# 告知 ScoreCalculator 总音符数(LONG的持续 tick 不计入)
	if score_calc:
		score_calc.total_notes = flow_notes.size()
	play_result.total_notes = flow_notes.size()
	print("[PlayView] FlowArea initialized with %d game sequences" % flow_notes.size())
	# 设置进度条最大值
	progress_bar.max_value = current_midi.duration_ms

	# 等待3秒显示准备界面
	await get_tree().create_timer(1).timeout
	await AnimationManager.instance.animate_fade_out(center_bg, 1).finished
	
	# 开始播放MIDI
	is_pause = false

## 加载MIDI（不再处理FlowArea初始化，该部分由KeySequenceManager处理）
func _load_and_convert_midi_notes(midi_data: MidiData) -> void:
	if playback_mgr == null:
		push_error("MidiPlaybackManager not available!")
		return

	# 加载MIDI
	if not playback_mgr.load_midi(midi_data):
		push_error("Failed to load MIDI for gameplay")
		return
	
	# 应用TrackView中保存的MIDI配置（音量、静音、独奏等）
	_apply_midi_runtime_config(midi_data)
	
	print("[PlayView] MIDI loaded and runtime config applied")

## 将KeySequenceManager生成的游戏序列转换为FlowArea所需的格式
func _convert_game_sequences_to_flow_notes(sequences: Array) -> Array[FlowArea.Note]:
	print("[PlayView] _convert_game_sequences_to_flow_notes called with %d sequences" % sequences.size())
	var flow_notes: Array[FlowArea.Note] = []
	var lc = get_lane_count()
	print("[PlayView] Lane count: %d" % lc)

	for seq in sequences:
		# 确定车道 - 使用GameSequence的pitch字段
		var lane = seq.pitch % lc
		
		# 将block_type转换为FlowArea.NoteType（值相同）
		var note_type = seq.block_type  # 0=Block, 1=Slide, 2=Long
		
		# 创建FlowArea的Note对象
		var flow_note = FlowArea.Note.new(
			note_type,
			seq.start_time_ms,   # 开始时间（毫秒）
			seq.duration_ms,     # 持续时间（毫秒）
			lane                 # 车道
		)
		
		# 新增：建立双向映射
		seq.flow_note_ref = flow_note
		flow_note.game_sequence_ref = seq
		
		flow_notes.append(flow_note)
	
	print("[PlayView] Converted %d sequences to flow notes" % flow_notes.size())
	# FlowArea期望按时间排序（虽然KeySequenceManager应该已排序）
	flow_notes.sort_custom(func(a, b): return a.start_time < b.start_time)
	
	return flow_notes

## 生成游戏序列
func _generate_game_sequences(midi_data: MidiData) -> void:
	if key_sequence_mgr == null:
		GameLogger.instance.warning("KeySequenceManager not available", "PlayView")
		return
	
	if midi_data.parsed_notes.is_empty():
		GameLogger.instance.warning("No parsed notes available for key generation", "PlayView")
		return
	
	# 设置MIDI时间参数
	if playback_mgr != null:
		key_sequence_mgr.set_midi_time_parameters(playback_mgr.midi_timebase, playback_mgr.bpm_timeline)
		key_sequence_mgr.set_screen_size(lane_area.size.x)
	
	# 获取启用的音轨列表
	var enabled_track_indices = _get_enabled_track_indices(midi_data)
	
	# 筛选只有启用音轨的音符
	var enabled_notes = _filter_notes_by_enabled_tracks(midi_data.parsed_notes, enabled_track_indices)
	
	if enabled_notes.is_empty():
		GameLogger.instance.warning("No notes in enabled tracks", "PlayView")
		return
	
	# 调用键序列管理器生成游戏键
	var success = key_sequence_mgr.generate_keys(enabled_notes)
	if not success:
		GameLogger.instance.warning("Failed to generate game keys", "PlayView")
		return
	
	# 新增：获取KeySequenceManager统计的真实分类结果
	var classification = key_sequence_mgr.get_last_notes_classification()
	var manual_control_notes = classification["manual_control_notes"]
	var auto_play_notes = classification["auto_play_notes"]
	
	# 新增：将真实分类提交给MidiPlaybackManager
	# 仅在演奏模式开启时下发手动控制；关闭时必须清空以恢复自动播放
	if playback_mgr:
		if play_mode:
			playback_mgr.set_manual_control_notes(manual_control_notes)
			GameLogger.instance.info(
				"[Performing ON] Submitted notes classification: %d manual, %d auto" %
				[manual_control_notes.size(), auto_play_notes.size()],
				"PlayView"
			)
		else:
			playback_mgr.clear_manual_control_notes()
			GameLogger.instance.info(
				"[Performing OFF] Cleared manual control notes: all notes will auto-play (manual=%d, auto=%d)" %
				[manual_control_notes.size(), auto_play_notes.size()],
				"PlayView"
			)
	
	# 缓存生成的游戏序列
	var raw_sequences = key_sequence_mgr.get_game_sequences()
	print("[PlayView] get_game_sequences returned %d items" % raw_sequences.size())
	game_sequences = raw_sequences
	print("[PlayView] game_sequences assigned, size = %d" % game_sequences.size())
	
	GameLogger.instance.info("Generated %d game sequences for play mode (enabled tracks: %s)" % [game_sequences.size(), enabled_track_indices], "PlayView")

## 获取启用的音轨列表（从MidiData.selected_track_configs读取）
func _get_enabled_track_indices(midi_data: MidiData) -> Array[int]:
	var enabled: Array[int] = []
	
	# 调试：打印 selected_track_configs 内容
	GameLogger.instance.info("selected_track_configs: %s" % str(midi_data.selected_track_configs), "PlayView")
	
	# selected_track_configs 是 Dictionary，格式: {track_idx: [channel1, channel2, ...]}
	# 轨道存在且有通道列表说明该轨道启用
	for track_index in midi_data.selected_track_configs.keys():
		var channels = midi_data.selected_track_configs[track_index]
		# 只有当通道列表不为空时，才认为该轨道启用
		if channels is Array and not channels.is_empty():
			enabled.append(int(track_index))
			GameLogger.instance.info("Track %d enabled with channels: %s" % [track_index, str(channels)], "PlayView")
	
	# 如果没有启用的音轨
	if enabled.is_empty():
		if midi_data._track_config_initialized and midi_data.selected_track_configs.is_empty():
			push_error("[PlayView] All tracks are disabled! Cannot play game without enabled tracks.")
		else:
			push_error("[PlayView] No enabled tracks found and no default configuration applied!")
	
	GameLogger.instance.info("Final enabled tracks: %s" % str(enabled), "PlayView")
	return enabled

## 筛选只有启用音轨的音符
func _filter_notes_by_enabled_tracks(all_notes: Array, enabled_track_indices: Array[int]) -> Array:
	var filtered: Array = []
	var enabled_set = {}
	
	# 构建快速查找的Set
	for track_idx in enabled_track_indices:
		enabled_set[track_idx] = true
	
	GameLogger.instance.info("Filtering %d notes, enabled tracks: %s" % [all_notes.size(), str(enabled_track_indices)], "PlayView")
	
	# 筛选音符
	var track_stats = {}  # 统计每个轨道的音符数
	for note in all_notes:
		if note is MidiParser.Note and note.event != null:
			var evt = note.event
			var track_idx = evt.track_index
			
			# 统计
			if not track_stats.has(track_idx):
				track_stats[track_idx] = 0
			track_stats[track_idx] += 1
			
			# 筛选
			if enabled_set.has(track_idx):
				filtered.append(note)
	
	GameLogger.instance.info("Track note stats: %s" % str(track_stats), "PlayView")
	GameLogger.instance.info("Filtered result: %d notes out of %d" % [filtered.size(), all_notes.size()], "PlayView")
	
	return filtered

## 处理键盘输入触发音符播放
func _process_input(event: InputEvent) -> void:
	if not play_mode or not is_midi_playing or game_sequences.is_empty():
		return
	
	# 检查键盘按键事件（演奏模式下才响应键盘输入）
	if event is InputEventKey and event.pressed:
		var current_time_ms = playback_mgr.get_position_ms()
		
		# 检查是否有键盘映射
		if keyboard_mode:
			# 根据键盘按键找对应的lane
			var key_index = key_map.find(event.keycode)
			if key_index >= 0:
				_trigger_key_press(key_index, current_time_ms)
				get_tree().root.set_input_as_handled()

## 输入事件回调 - Godot标准方法
func _input(event: InputEvent) -> void:
	_process_input(event)

## 触发指定键的音符播放
func _trigger_key_press(key_index: int, current_time_ms: float) -> void:
	if key_index < 0 or key_index >= get_lane_count():
		return
	
	# 计算该key对应的lane
	var lc = get_lane_count()
	var target_lane = key_index % lc
	
	# 查找当前时间接近的游戏序列（判定窗口内）
	var judge_window_ms = 150.0  # 判定窗口（毫秒）
	var triggered_sequences: Array[KeySequenceManager.GameSequence] = []
	
	for seq in game_sequences:
		var time_diff = abs(seq.start_time_ms - current_time_ms)
		# 只触发在时间窗口内且pitch对应的lane匹配的序列
		if time_diff <= judge_window_ms:
			var seq_lane = seq.pitch % lc
			if seq_lane == target_lane:
				triggered_sequences.append(seq)
	
	# 如果找到匹配的序列，触发所有pitch的音符
	if not triggered_sequences.is_empty():
		for seq in triggered_sequences:
			# 播放该序列的所有pitch
			for pitch in seq.pitch_list:
				_play_note(pitch, seq.velocity)
		
		GameLogger.instance.info("Triggered %d notes at key %d (time: %.0f ms)" % [triggered_sequences.size(), key_index, current_time_ms], "PlayView")

## 通过MIDI播放单个音符
func _play_note(pitch: int, velocity: int = 100) -> void:
	if playback_mgr == null or not playback_mgr.midi_player:
		return
	
	# 使用MIDI播放器的note_on方法（如果可用）
	# 这里假设midi_player有note_on和note_off方法
	var midi_player = playback_mgr.midi_player
	if midi_player and midi_player.has_method("note_on"):
		# 发送Note On事件
		midi_player.note_on(0, pitch, velocity)  # channel 0, 持续50ms
		
		# 延迟后发送Note Off事件
		await get_tree().create_timer(0.05).timeout
		if midi_player and midi_player.has_method("note_off"):
			midi_player.note_off(0, pitch)

## 从ConfigManager加载键盘和轨道相关的参数
func _load_lane_parameters() -> void:
	var config_mgr = ConfigManager.instance
	
	# 加载轨道数量（默认12）
	lane_count = config_mgr.get_int("Lane", "lane_count", 12)
	
	# 加载键盘模式（0=关闭，1=开启，默认0）
	keyboard_mode = config_mgr.get_int("Lane", "keyboard_mode", 0) == 1
	
	# 加载键盘键位字符串（默认 "A,S,D,F,J,K,L,;"）
	var keyboard_keys_str = config_mgr.get_string("Lane", "keyboard_mode_keys", "A,S,D,F,J,K,L,;")
	key_map = ConfigParser.parse_keyboard_keys(keyboard_keys_str)
	
	GameLogger.instance.info(
		"PlayView lane parameters loaded: lane_count=%d, keyboard_mode=%s, key_map_size=%d" % 
		[lane_count, str(keyboard_mode), key_map.size()],
		"PlayView"
	)

## 处理Lane段配置变更
func _on_lane_config_changed(key: String, section: String, value: Variant) -> void:
	if section != "Lane":
		return
	
	var should_reinit = false
	
	match key:
		"lane_count":
			var new_lane_count = int(value)
			if new_lane_count != lane_count:
				lane_count = new_lane_count
				# 仅在非键盘模式时需要重初始化轨道显示
				if not keyboard_mode:
					should_reinit = true
				GameLogger.instance.info("PlayView lane_count updated: %d" % lane_count, "PlayView")
		
		"keyboard_mode":
			var new_mode = int(value) == 1
			if new_mode != keyboard_mode:
				keyboard_mode = new_mode
				should_reinit = true
				GameLogger.instance.info("PlayView keyboard_mode updated: %s" % str(keyboard_mode), "PlayView")
		
		"keyboard_mode_keys":
			var new_keys = ConfigParser.parse_keyboard_keys(str(value))
			if new_keys.size() != key_map.size() or _are_keys_different(new_keys, key_map):
				key_map = new_keys
				# 仅在键盘模式时需要重初始化
				if keyboard_mode:
					should_reinit = true
				GameLogger.instance.info("PlayView keyboard_mode_keys updated: %d keys" % key_map.size(), "PlayView")
	
	if should_reinit:
		# 仅在游戏未开始或者允许的情况下重新初始化轨道
		if not is_midi_playing:
			_reinit_lane_display()

## 比较两个KeyCode数组是否不同
func _are_keys_different(keys1: Array[Key], keys2: Array[Key]) -> bool:
	if keys1.size() != keys2.size():
		return true
	for i in range(keys1.size()):
		if keys1[i] != keys2[i]:
			return true
	return false

## 重新初始化轨道显示
## 清空旧轨道并根据当前配置重新初始化
func _reinit_lane_display() -> void:
	if flow_area == null or lane_area == null:
		return
	
	# 重新初始化流动区域
	flow_area.init_flow_area()
	
	# 重新初始化轨道光效（lane_area 已经是 LaneEffect 实例）
	lane_area.init_beam(get_lane_count(), self)
	lane_area.set_beam_alpha(beam_alpha)
	
	# 如果启用了键盘模式，显示键位提示
	if keyboard_mode and key_map.size() > 0:
		lane_area.init_key_display(key_map)
	
	GameLogger.instance.info("PlayView lane display reinitialized", "PlayView")

## 从配置加载演奏模式设置
func _load_play_mode_setting() -> void:
	# 可以从配置文件读取演奏模式设置
	# 临时使用默认值 true（演奏模式开启）
	play_mode = true
	GameLogger.instance.info("PlayView play mode: %s" % ("ON" if play_mode else "OFF"), "PlayView")

## 应用TrackView中保存的MIDI运行时配置（音量、静音、独奏等）
func _apply_midi_runtime_config(midi_data: MidiData) -> void:
	if playback_mgr == null:
		return
	
	# 应用全局音量
	playback_mgr.set_volume_db(linear_to_db(float(midi_data.midi_volume) / 100.0))
	
	# 应用轨道-通道的静音状态
	# track_channel_mute_state: {track_idx: {channel: bool}}
	if not midi_data.track_channel_mute_state.is_empty():
		for track_idx in midi_data.track_channel_mute_state.keys():
			var channels = midi_data.track_channel_mute_state[track_idx]
			if channels is Dictionary:
				for channel in channels.keys():
					var is_muted = channels[channel]
					playback_mgr.set_track_channel_mute(track_idx, channel, is_muted)
	
	# 应用独奏状态（Additive Solo）
	# solo_pairs: {"track:channel": true}
	if not midi_data.solo_pairs.is_empty():
		for solo_key in midi_data.solo_pairs.keys():
			# solo_key 格式: "track:channel"
			var parts = solo_key.split(":")
			if parts.size() == 2:
				var track = int(parts[0])
				var channel = int(parts[1])
				# 独奏意味着这个轨道要启用，其他非独奏的轨道要静音
				playback_mgr.set_channel_mute(track, channel, false)
	
	# 应用音轨-通道的音量调整
	# track_channel_volume_config: {track_idx: {channel: volume_value}}
	if not midi_data.track_channel_volume_config.is_empty():
		for track_idx in midi_data.track_channel_volume_config.keys():
			var channels = midi_data.track_channel_volume_config[track_idx]
			if channels is Dictionary:
				for channel in channels.keys():
					var volume = channels[channel]
					# 设置通道音量
					if playback_mgr.has_method("set_channel_volume"):
						playback_mgr.set_channel_volume(track_idx, channel, float(volume) / 100.0)
	
	# 应用乐器覆盖（如果有）
	if not midi_data.track_channel_instrument_overrides.is_empty():
		for track_index in midi_data.track_channel_instrument_overrides.keys():
			var channels = midi_data.track_channel_instrument_overrides[track_index]
			for channel in channels.keys():
				var instrument = channels[channel]
				var bank = instrument.get("bank", 0)
				var program = instrument.get("program", 0)
				# 设置乐器
				if playback_mgr.has_method("set_track_channel_program"):
					playback_mgr.set_track_channel_program(track_index, channel, bank, program)
	
	GameLogger.instance.info("MIDI runtime config applied: volume=%d, mute_states=%d, solo_pairs=%d" % 
		[midi_data.midi_volume, midi_data.track_channel_mute_state.size(), midi_data.solo_pairs.size()], "PlayView")

## MIDI播放开始回调
func _on_midi_started() -> void:
	print("[PlayView] MIDI playback started")
	is_midi_playing = true

## 游戏结束回调
func _on_game_finished() -> void:
	print("[PlayView] Game finished!")
	
	# 从 ScoreCalculator 拿最终快照，填充结算数据
	var snap = score_calc.get_snapshot()
	play_result.score = snap["total_score"]
	play_result.max_combo = snap["max_combo"]
	play_result.accuracy = snap["accuracy"]
	play_result.performance_point = snap["pp"]
	play_result.count["Perfect"] = snap["judge_counts"][ScoreCalculator.Judgment.PERFECT]
	play_result.count["Great"] = snap["judge_counts"][ScoreCalculator.Judgment.GREAT]
	play_result.count["Good"] = snap["judge_counts"][ScoreCalculator.Judgment.GOOD]
	play_result.count["Bad"] = snap["judge_counts"][ScoreCalculator.Judgment.BAD]
	play_result.count["Miss"] = snap["judge_counts"][ScoreCalculator.Judgment.MISS]
	play_result.early_count = snap["early_count"]
	play_result.late_count = snap["late_count"]
	is_pause = true

	# 结束后的等待
	await get_tree().create_timer(2).timeout

	# 进入结算界面
	get_node("/root/Main/ScoreView").set_display(play_result)
	UIStateManager.instance.change_state(UIStateManager.UIState.SCORE_VIEW, false)
	await get_tree().create_timer(0.8).timeout
	is_pause = true
	_init_display()

## 退出游戏
func _on_quit_pressed() -> void:
	# 停止MIDI播放
	if playback_mgr:
		playback_mgr.stop()
		# 清除手动控制notes标记，恢复TrackView等场景的自动播放
		playback_mgr.clear_manual_control_notes()
	_init_display()
	flow_area.clear_flow_area()
	game_sequences.clear()  # 清空游戏序列
	
	# 返回主菜单或上一级界面
	UIStateManager.instance.go_back()

# 初始化分数等内容的显示
func _init_display():
	score.text = "0"
	combo.text = "0"
	score_wait_to_add = 0
	score_add.text = "+0"

	pp_text.text = "0.00pp"
	accuracy_text.text = "100.00%"

	# 设置歌曲信息
	var cover_texture = FileSystemManager.instance.get_cover_by_midiData(current_midi)
	if cover_texture:
		cover.texture = cover_texture

	ani.animate_fade_in(center_bg, 0.2, "_show_bg")

	album.text = current_midi.artist_name
	song.text = current_midi.song_data.name
	# artist.text = current_midi.song_data.artist_name # 没找着歌手在哪
	var s := int(current_midi.duration_ms / 1000.0)
	midi_duration.text = "%02d:%02d" % [s / 60, s % 60]
	midi_name.text = current_midi.name
	midi_author.text = current_midi.artist_name
	
	menu.visible = false
	song_info.visible = true

	center.modulate.a = 0
	center_bg.visible = true
	is_pause = true
	
	# 恢复flow_area显示
	flow_area.visible = true

	# 重置进度条
	_current_rect = null
	_last_rect = null

	progress_bar.value = 0
	for i in progress_bar.get_children():
		i.queue_free()
	
	_init_lane_display()

	auto_label.visible = flow_area.auto_mode

func _init_lane_display():
	lane_area.init_beam(get_lane_count(), self)
	lane_area.set_beam_alpha(beam_alpha)
	if keyboard_mode:
		lane_area.init_key_display(key_map)

const color_map = {
	"Perfect": Color.PURPLE,
	"Great": Color.ORANGE,
	"Good": Color.DARK_OLIVE_GREEN,
	"Bad": Color.ROYAL_BLUE,
	"Miss": Color.RED
}

func _on_note_judged(result: String, offset: String, block_type: int, timing_sec: float, signed_offset_sec: float):
	# ---- 委托 ScoreCalculator 计算 ----
	var judgment = ScoreCalculator.Judgment.MISS
	match result:
		"Perfect": judgment = ScoreCalculator.Judgment.PERFECT
		"Great":   judgment = ScoreCalculator.Judgment.GREAT
		"Good":    judgment = ScoreCalculator.Judgment.GOOD
		"Bad":     judgment = ScoreCalculator.Judgment.BAD
		"Miss":    judgment = ScoreCalculator.Judgment.MISS

	var snap = score_calc.record_judgment(judgment, block_type, timing_sec, signed_offset_sec)

	# ---- 以下纯 UI 刷新，数据全部来自快照 ----
	center_text.text = result
	var cl = color_map[result]
	center_text.add_theme_color_override("font_color", cl)

	# combo显示
	combo.text = str(snap["combo"])

	# 增加分数
	var score_add_amount = int(snap["last_score_add"])
	_set_score_add_amount(score_add_amount)

	# 设置进度条颜色
	_set_progress_bar_color(cl)

	# pp和准度
	pp_text.text = snap["pp_text"]
	accuracy_text.text = snap["accuracy_text"]

	# 显示偏移
	early_text.self_modulate.a = 0
	late_text.self_modulate.a = 0
	if result != "Miss" and offset != "":
		if offset[0] == "+":
			early_text.text = offset
			early_text.self_modulate.a = 1
		else:
			late_text.text = offset
			late_text.self_modulate.a = 1

	# 动画
	center.rotation_degrees = (randf()-0.5) * 5
	var tween: Tween = ani._create_tween("center pluse")
	tween.set_parallel(true)
	center.scale = Vector2.ONE * 1.1
	tween.tween_property(center, "scale", Vector2.ONE, 0.1)
	tween.tween_property(center, "rotation_degrees", 0, 0.1)

	var t = ani._create_tween("center fade out")
	center.modulate.a = 1
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(center, "modulate:a", 0.0, 2)

## LONG 持续 tick 加分（已委托 ScoreCalculator）
func _on_long_holding(long_instance_id: int):
	var snap = score_calc.record_long_sustain(ScoreCalculator.Judgment.PERFECT, long_instance_id)

	var cl = color_map["Perfect"]
	center_text.add_theme_color_override("font_color", cl)
	center_text.text = "Perfect"
	combo.text = str(snap["combo"])

	_set_progress_bar_color(cl)
	_set_score_add_amount(int(snap["last_score_add"]))

	pp_text.text = snap["pp_text"]
	accuracy_text.text = snap["accuracy_text"]

var score_wait_to_add = 0
func _set_score_add_amount(amount: int):
	if amount == 0:
		return
	score_wait_to_add += amount
	score_add.text = "+%d" % amount

	score_add.modulate.a = 1
	var tween = ani._create_tween("score_add_out")
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(score_add, "modulate:a", 0.0, 2)
	ani.animate_pulse(score_add, 1, 1.1, 0.1, "score_pluse")

# 进度条颜色填充回调
var _current_rect: ColorRect = null
var _last_rect: ColorRect = null
func _on_top_progress_bar_value_changed(value: float):
	if is_pause:
		return

	var anchor_l = 0.0 if not _last_rect else _last_rect.anchor_right
	if not _current_rect:
		_current_rect = ColorRect.new()

		_current_rect.anchor_left = anchor_l if anchor_l < 0.002 else anchor_l - 0.001
		_current_rect.color = color_map["Miss"] if not _last_rect else _last_rect.color
		_current_rect.size.y = progress_bar.size.y

		_last_rect = _current_rect
		progress_bar.add_child(_current_rect)
	
	_current_rect.anchor_right = value / progress_bar.max_value

	# 游戏结束
	if value >= progress_bar.max_value:
		_on_game_finished()

func _set_progress_bar_color(cl: Color):
	if not _current_rect or (_current_rect.size.x > 15 and cl != _current_rect.color):
		_current_rect = null
		_on_top_progress_bar_value_changed(progress_bar.value)
		return

	_current_rect.color = cl
