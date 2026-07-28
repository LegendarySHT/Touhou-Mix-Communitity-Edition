extends BaseScrollList

class_name TrackView

@onready var master_note_displayer: NoteDisplayer = $MC/VBox/TotalView/MC/VBoxC/flowArea
@onready var current_time: Label = $MC/VBox/TotalView/MC/VBoxC/playArea/currentTime
@onready var progress_bar: HSlider = $MC/VBox/TotalView/MC/VBoxC/playArea/progressBar
@onready var total_time: Label = $MC/VBox/TotalView/MC/VBoxC/playArea/totalTime

# 导入人声按钮
@onready var vocal_import_btn: TextureButton = $MC/VBox/VolumeView/HBoxC/VBoxC2/VocalImportBtn
# 切换人声启用状态按钮
@onready var vocal_enable_btn: Button = $MC/VBox/VolumeView/HBoxC/VBoxC2/VocalEnableBtn

# FileDialog 用于导入人声文件（动态创建）
var file_dialog: FileDialog = null

@onready var latency_edit: LineEdit = $MC/VBox/VolumeView/HBoxC/VBoxC2/HBoxC/Latency
@onready var midi_vol_btn: TextureButton = $MC/VBox/VolumeView/HBoxC/GridC/midiVolIcon
@onready var midi_vol_slider: HSlider = $MC/VBox/VolumeView/HBoxC/GridC/midiVolSlider
@onready var vocal_vol_btn: TextureButton = $MC/VBox/VolumeView/HBoxC/GridC/vocalVolIcon
@onready var vocal_vol_slider: HSlider = $MC/VBox/VolumeView/HBoxC/GridC/vocalVolSlider

@onready var midi_vol_label: Label = $MC/VBox/VolumeView/HBoxC/GridC/midiVolLabel
@onready var vocal_vol_label: Label = $MC/VBox/VolumeView/HBoxC/GridC/vocalVolLabel

# MIDI播放相关

@onready var midi_playback_manager: MidiPlaybackManager = MidiPlaybackManager.instance
@onready var ui_stat_mgr: UIStateManager = UiStatMGR

var current_midi_data: MidiData = null
var is_progress_dragging: bool = false

var current_tick: int = 0
var last_position_ms: float = 0.0  # 用于检测循环播放重置

# 给midi轨道访问的默认值，临时占位用。
var instrument_options: Array = [] # 全局乐器列表（会被 _extract_instruments_from_midi() 填充）
var regular_instruments: Array = []  # 常规乐器 (Bank 0)
var drum_instruments: Array = []     # 鼓组乐器 (Bank 128)
# 人声音频路径存在时相关组件会显示
# vocal_file_path 现由 _vocal_controller 管理

# 子系统控制器
var _vocal_controller: VocalTrackController = null
var _config_persistence: MidiConfigPersistence = null


# 用于存储所有音符的列表
var All_Notes: Array[NoteDisplayer.NoteEvent] = []

# Additive Solo 状态
var solo_pairs: Dictionary = {}  # {"track:channel": true}
var solo_mute_snapshot: Dictionary = {}  # {"track:channel": bool}

func _ready() -> void:
	work_state = UIStateManager.UIState.TRACK_VIEW

	# 检查管理器引用
	if midi_playback_manager == null:
		push_error("MidiPlaybackManager not initialized in Main! MIDI features will not work.")
		return

	# 初始化UI
	# 确保音量滑块的范围正确（0-100）
	# 动态创建FileDialog
	if file_dialog == null:
		file_dialog = FileDialog.new()
		file_dialog.name = "VocalFileDialog"
		add_child(file_dialog)
		file_dialog.filters = PackedStringArray(["Audio Files (*.mp3,*.wav,*.ogg,*.flac) ; *.mp3,*.wav,*.ogg,*.flac", "All Files ; *"])
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.use_native_dialog = true
	
	if midi_vol_slider:
		midi_vol_slider.min_value = 0
		midi_vol_slider.max_value = 200  # 上限200% (+6dB), 允许用户在MeltySynth合成音量偏小时主动提升
		midi_vol_slider.step = 1
	if vocal_vol_slider:
		vocal_vol_slider.min_value = 0
		vocal_vol_slider.max_value = 200  # 与midi音量上限保持一致
		vocal_vol_slider.step = 1

	midi_vol_slider.value = db_to_linear(midi_playback_manager.midi_player_config["volume_db"]) * 100
	_set_display_midi_volume(midi_vol_slider.value)
	
	# 连接信号（检查防止重复连接）
	if not EvtBus.is_connected("enter_track_view_with", Callable(self, "_load_midi")):
		EvtBus.enter_track_view_with.connect(_load_midi)
	
	if not ui_stat_mgr.is_connected("state_changed", Callable(self, "_on_ui_state_changed")):
		ui_stat_mgr.state_changed.connect(_on_ui_state_changed)

	# 监听SoundFont变更信号（用于实时更新乐器列表）
	if midi_playback_manager.midi_player and not midi_playback_manager.midi_player.is_connected("soundfont_changed", Callable(self, "_on_soundfont_changed")):
		midi_playback_manager.midi_player.soundfont_changed.connect(_on_soundfont_changed)

	# 音量（检查防止重复连接）
	if not midi_vol_btn.is_connected("toggled", Callable(self, "_on_volume_btn_toggled")):
		midi_vol_btn.toggled.connect(_on_volume_btn_toggled.bind(midi_vol_btn))
	
	if not vocal_vol_btn.is_connected("toggled", Callable(self, "_on_volume_btn_toggled")):
		vocal_vol_btn.toggled.connect(_on_volume_btn_toggled.bind(vocal_vol_btn))
	
	if not midi_vol_slider.is_connected("value_changed", Callable(self, "_on_midi_volume_changed")):
		midi_vol_slider.value_changed.connect(_on_midi_volume_changed)
	
	if not vocal_vol_slider.is_connected("value_changed", Callable(self, "_on_vocal_volume_changed")):
		vocal_vol_slider.value_changed.connect(_on_vocal_volume_changed)

	# Progress bar（检查防止重复连接）
	if not progress_bar.is_connected("drag_started", Callable(self, "_on_progress_bar_drag_started")):
		progress_bar.drag_started.connect(_on_progress_bar_drag_started)
	
	if not progress_bar.is_connected("drag_ended", Callable(self, "_on_progress_bar_drag_ended")):
		progress_bar.drag_ended.connect(_on_progress_bar_drag_ended)
	
	if not progress_bar.is_connected("value_changed", Callable(self, "_on_progress_bar_value_changed")):
		progress_bar.value_changed.connect(_on_progress_bar_value_changed)

	# 初始化子系统控制器
	if _vocal_controller == null:
		_vocal_controller = VocalTrackController.new()
		_vocal_controller.name = "VocalTrackController"
		add_child(_vocal_controller)
		_vocal_controller.setup(self, file_dialog, vocal_import_btn, vocal_enable_btn,
			vocal_vol_btn, vocal_vol_slider, vocal_vol_label)

	if _config_persistence == null:
		_config_persistence = MidiConfigPersistence.new()
		_config_persistence.name = "MidiConfigPersistence"
		add_child(_config_persistence)
		_config_persistence.setup(self)

	# 连接人声导入和启用信号（检查防止重复连接）
	if not vocal_import_btn.is_connected("pressed", Callable(_vocal_controller, "on_vocal_import_btn_pressed")):
		vocal_import_btn.pressed.connect(_vocal_controller.on_vocal_import_btn_pressed)

	if not vocal_enable_btn.is_connected("toggled", Callable(_vocal_controller, "on_vocal_enable_btn_toggled")):
		vocal_enable_btn.toggled.connect(_vocal_controller.on_vocal_enable_btn_toggled)

	# 连接FileDialog信号（使用file_selected而不是files_selected，因为是单文件模式）
	if file_dialog:
		if not file_dialog.is_connected("file_selected", Callable(_vocal_controller, "on_vocal_file_selected")):
			file_dialog.file_selected.connect(_vocal_controller.on_vocal_file_selected)

	# 连接Latency输入框信号（检查防止重复连接）
	if latency_edit:
		if not latency_edit.is_connected("text_changed", Callable(self, "_on_latency_changed")):
			latency_edit.text_changed.connect(_on_latency_changed)

	super._ready()

# 加载并播放midi
func _load_midi(midi: MidiData) -> void:
	current_midi_data = midi
	# 清空独奏状态
	solo_pairs.clear()
	solo_mute_snapshot.clear()
	
	# 清空现有的轨道
	clear_items()

	# 重置列表高度
	await get_tree().process_frame
	container.custom_minimum_size.y = 0
	container.size.y = 0
	
# 【关键】在加载MIDI之前先检测人声文件，确保vocal_file_path已设置
	_vocal_controller.detect_vocal_file(current_midi_data)
	# 加载MIDI到播放管理器
	if not midi_playback_manager.load_midi(midi):
		push_error("Failed to load MIDI: " + midi.name)
	await get_tree().process_frame

	# 更新进度条最大范围
	if midi.duration_ms > 0:
		_set_display_total_time(midi.duration_ms)
	# TrackView 加载时设置循环播放
	midi_playback_manager.set_loop(true)

	# 新增：从加载的 MIDI 和 SoundFont 提取可用乐器选项
	_extract_instruments_from_midi()

	# 恢复用户配置的数据部分（音量值、进度条、独奏状态）
	_config_persistence.restore_midi_data_config()

	# 加载音符
	var all_notes = midi_playback_manager.current_notes
	if all_notes.is_empty():
		push_warning("No notes found in MIDI")
		return
	
	# 在一次遍历中过滤并转换为显示格式（notes已按时间顺序）
	All_Notes.clear()
	for note in all_notes:
		if note is MidiParser.Note and note.event != null:
			var evt = note.event
			var display_note = NoteDisplayer.NoteEvent.new(
				evt.pitch,
				evt.velocity,
				int(evt.start_time),
				int(evt.duration),
				evt.track_index,
				evt.channel
			)
			All_Notes.append(display_note)

	# 初始化总览的音符显示器
	_init_master_note_displayer()
	master_note_displayer.is_master = true
	await get_tree().process_frame

	# 创建轨道UI
	await _create_track_views()

	# 初始化新MIDI的轨道音量为50%（如果没有保存过配置）
	_initialize_track_volumes_for_new_midi()

	# 恢复用户配置的UI部分（按钮状态、文本标签等）
	_config_persistence.restore_midi_ui_config()

	# 检测并初始化人声文件
	_vocal_controller.init_vocal_btn_display()

	# 初始化Latency输入框
	_init_latency_edit()

	# 启动播放（UI 已完全加载，避免 _prepare_to_play 阻塞 UI 渲染）
	midi_playback_manager.play()

	# 启用 TrackView 进度更新和音符显示器
	set_process(true)
	_set_note_displayers_process(true)

	# 等容器尺寸更新，再增加上下边距 （这个不是一定会触发，请勿在后面加总是需要执行的代码）
	await container.resized
	container.custom_minimum_size.y = container.size.y + 300

# 创建轨道视图
func _create_track_views() -> void:
	if not current_midi_data:
		return

	# 获取轨道信息
	var track_infos = midi_playback_manager.get_track_infos()
	
	if track_infos.is_empty():
		push_warning("No track info available")
		return
	
	# 第1步：聚合每个track中包含的所有unique channels
	var track_channel_groups: Dictionary = {}  # {track_idx: [ch0, ch1, ...]}
	for note in All_Notes:
		if not track_channel_groups.has(note.track_index):
			track_channel_groups[note.track_index] = []
		if note.channel not in track_channel_groups[note.track_index]:
			track_channel_groups[note.track_index].append(note.channel)
	
	# 第2步：按channel升序、track升序排序，构建(track, channel)列表
	var track_channel_pairs: Array = []  # [{track: int, channel: int, notes: Array}, ...]
	
	for track_idx in track_channel_groups.keys():
		var channels = track_channel_groups[track_idx]
		channels.sort()  # channel升序
		
		for ch in channels:
			# 过滤该(track, channel)的所有notes
			var pair_notes: Array[NoteDisplayer.NoteEvent] = All_Notes.filter(
				func(note):
					return note.track_index == track_idx and note.channel == ch
			)
			
			track_channel_pairs.append({
				"track": track_idx,
				"channel": ch,
				"notes": pair_notes
			})
	
	# 按(channel asc, track asc)排序
	track_channel_pairs.sort_custom(func(a, b):
		if a["channel"] != b["channel"]:
			return a["channel"] < b["channel"]
		return a["track"] < b["track"]
	)
	
	# 第3步：为每个(track, channel)对创建MidiTrack UI项
	var track_name_map = {}  # 缓存track名称
	for track_info in track_infos:
		track_name_map[track_info.index] = track_info.name
	
	for pair in track_channel_pairs:
		var track_idx = pair["track"]
		var channel = pair["channel"]
		var pair_notes = pair["notes"]
		
		if pair_notes.is_empty():
			continue
		
		# 获取track名称
		var track_name = track_name_map.get(track_idx, "Track %d" % track_idx)
		
		# 创建MidiTrack UI项
		var track_scene = create_and_add_item(track_name, "MidiTrack") as MidiTrack
		track_scene.setup_track(self, track_idx, track_name, instrument_options, channel, current_midi_data)

		# 新增：设置该 (track, channel) 的正确乐器
		_set_track_instrument_from_midi_data(track_scene, track_idx, channel)

		# 初始化该(track, channel)对的音符显示
		_init_track_note_displayer(track_scene, track_idx, channel, pair_notes)
		await get_tree().process_frame

	


# ============= 信号回调函数 ===============

# 进度条拖拽开始
func _on_progress_bar_drag_started() -> void:
	# 拖拽开始时停止自动更新进度条
	is_progress_dragging = true
	print("Progress bar drag started")

# 进度条拖拽结束 - 执行跳转
func _on_progress_bar_drag_ended(_value_changed: bool) -> void:
	is_progress_dragging = false
	
	if midi_playback_manager == null:
		return
	
	var target_ms = progress_bar.value
	print("Progress bar seek to: %.1f ms" % target_ms)
	
	# 执行跳转
	midi_playback_manager.seek(target_ms)
	
	# 【关键】更新 last_position_ms 和 current_tick，防止下一帧循环检测误判
	last_position_ms = target_ms
	current_tick = int(midi_playback_manager.position)
	
	# Reset individual track displayers first
	for track in list_items:
		if track.note_display:
			track.note_display.reset_playhead_position(target_ms)

	# Then reset master displayer
	if master_note_displayer:
		master_note_displayer.reset_playhead_position(target_ms)

	# Sum passed count from enabled tracks
	if master_note_displayer and current_midi_data:
		var total_passed = 0
		for track in list_items:
			if track is MidiTrack:
				var en = current_midi_data.is_track_channel_selected(track.track_index, track.track_channel)
				if en and track.note_display:
					total_passed += int(track.note_display.note_count_passed.text)
		master_note_displayer.note_count_passed.text = str(total_passed)

# 进度条值改变 - 预览时间
func _on_progress_bar_value_changed(value: float) -> void:
	# 只在拖拽时预览时间
	if is_progress_dragging:
		current_time.text = _format_time(value)


# 音量按钮回调
func _on_volume_btn_toggled(toggle_on: bool, btn: TextureButton) -> void:
	if btn == midi_vol_btn:
		midi_vol_slider.editable = not toggle_on
	elif btn == vocal_vol_btn:
		vocal_vol_slider.editable = not toggle_on

	var mute_clr := ThemeManager.DANGER_COLOR
	btn.modulate = Color(mute_clr.r, mute_clr.g, mute_clr.b, 0.6) if toggle_on else Color(1, 1, 1, 1)

# MIDI音量改变回调
func _on_midi_volume_changed(value: float) -> void:
	if midi_playback_manager == null:
		return
	
	# 转换为dB (-80 ~ 0)
	var volume_db = linear_to_db(value / 100.0)
	midi_playback_manager.set_volume_db(volume_db)
	
	# 更新标签
	_set_display_midi_volume(value)

func _on_vocal_volume_changed(value: float) -> void:
	if midi_playback_manager == null:
		return

	# 转换为dB (-80 ~ 0)
	var volume_db = linear_to_db(value / 100.0)
	midi_playback_manager.set_vocal_volume_db(volume_db)

	# 更新MidiData中的音量值，用于持久化
	if current_midi_data != null:
		current_midi_data.vocal_volume = int(value)

	# 更新标签
	_vocal_controller.set_display_vocal_volume(value)

func _on_expand_master_area_btn_toggled(is_expanded: bool) -> void:
	var node: Panel = $MC/VBox/TotalView
	var expd_y:int = int(get_viewport().get_visible_rect().size.y) - 50
	
	var tween: Tween = create_tween()
	tween.pause()
	tween.set_parallel(true)
	
	var finl_size = Vector2(node.custom_minimum_size.x, expd_y if is_expanded else 350)
	tween.tween_property(node, "custom_minimum_size", finl_size, 0.25)
	
	container.custom_minimum_size.y += expd_y if is_expanded else -expd_y
	await get_tree().process_frame
	
	tween.tween_property(self, "scroll_vertical", 0, 0.2)
	tween.tween_property(master_note_displayer, "lane_count", 88 if is_expanded else 24, 0.2)
	
	tween.play()
	await tween.finished
	master_note_displayer.refresh_notes_lane(master_note_displayer.lane_count)

# ============= 音轨信号回调 =======================

# 轨道启用状态切换
func _on_track_enable_toggled(is_checked: bool, track_index: int, channel: int) -> void:
	if current_midi_data == null:
		return

	# 更新指定(track, channel)启用状态
	current_midi_data.set_track_channel_enabled(track_index, channel, is_checked)

	# 仅更新已有音符的可见性，不重建（性能优化）
	master_note_displayer.sync_from_midi_data(current_midi_data)

	# Recalculate passed count from enabled tracks
	var total_passed = 0
	for track in list_items:
		if track is MidiTrack:
			var en = current_midi_data.is_track_channel_selected(track.track_index, track.track_channel)
			if en and track.note_display:
				total_passed += int(track.note_display.note_count_passed.text)
	master_note_displayer.note_count_passed.text = str(total_passed)

# 轨道静音切换
func _on_track_mute_toggled(is_muted: bool, track_index: int, channel: int) -> void:
	print("Track %d Channel %d mute: %s" % [track_index, channel, is_muted])
	if midi_playback_manager == null:
		return

	# 调用MidiPlaybackManager的实时mute接口（会同步MidiData）
	midi_playback_manager.set_track_channel_mute(track_index, channel, is_muted)

# 轨道独奏切换
func _on_track_solo_toggled(is_solo: bool, track_index: int, channel: int) -> void:
	print("Track %d Channel %d solo: %s" % [track_index, channel, is_solo])
	if midi_playback_manager == null:
		return

	var key = _make_pair_key(track_index, channel)

	# 第一次进入独奏时，记录当前mute状态
	if is_solo and solo_pairs.is_empty():
		_capture_solo_snapshot()

	if is_solo:
		solo_pairs[key] = true
	else:
		solo_pairs.erase(key)

	# 更新MIDI播放的mute状态（根据独奏状态调整）
	if solo_pairs.is_empty():
		_restore_solo_snapshot()
	else:
		for track_ui in list_items:
			var tc_key = _make_pair_key(track_ui.track_index, track_ui.track_channel)
			var should_solo = solo_pairs.has(tc_key)
			var is_muted_in_snapshot = solo_mute_snapshot.get(tc_key, false)
			var target_muted = true if not should_solo else is_muted_in_snapshot
			midi_playback_manager.set_track_channel_mute_runtime(track_ui.track_index, track_ui.track_channel, target_muted)

# 轨道音量改变
func _on_track_volume_changed(value: float, track_index: int, channel: int ) -> void:
	if midi_playback_manager == null:
		return
	
	# 获取对应的轨道UI（需要同时匹配 track_index 和 channel）
	var track_ui: MidiTrack = null
	for track in list_items:
		if track.track_index == track_index and track.track_channel == channel:
			track_ui = track
			break
	
	if track_ui == null:
		return
	
	# 转换百分比到线性值 (0-100 → 0.0-1.0)
	var volume_linear = value / 100.0
	
	# 调用MidiPlaybackManager设置轨道音量（立即生效）
	midi_playback_manager.set_track_channel_volume(track_index, channel, volume_linear)
	
	# 同时保存到MidiData以支持持久化
	if current_midi_data != null:
		current_midi_data.set_track_channel_volume(track_index, channel, volume_linear)
	
	print("[TrackView] Track %d Channel %d volume changed: %.1f%%" % [track_index, channel, value])
	
# 乐器选择
func _on_track_instrument_changed(index: int, track_index: int, channel: int) -> void:
	# 获取对应的轨道UI（需要同时匹配 track_index 和 channel）
	var track_item: MidiTrack = null
	for track in list_items:
		if track.track_index == track_index and track.track_channel == channel:
			track_item = track
			break
	
	if track_item == null:
		return
	
	var selected_text = track_item.instruments_option_btn.get_item_text(index)
	
	# 解析 "乐器名 (BX:PY)" 格式
	var instr_data = _parse_instrument_string(selected_text)
	if instr_data.is_empty():
		push_error("无法解析乐器格式: %s" % selected_text)
		return
	
	# 1. 保存到 MidiData
	current_midi_data.set_track_channel_instrument_override(
		track_index,
		channel,
		instr_data["bank"],
		instr_data["program"],
		instr_data["name"]
	)
	
	# 2. 立即应用到后端播放器
	if not midi_playback_manager:
		push_error("[TrackView] midi_playback_manager is null")
		return

	var midi_player_ref = midi_playback_manager.midi_player

	if midi_player_ref == null:
		push_error("[TrackView] midi_player is null - backend probably not initialized")
		return

	if not midi_player_ref.has_method("set_track_channel_instrument"):
		push_error("[TrackView] midi_player doesn't have set_track_channel_instrument method")
		return
	
	print("[TrackView] 【调用】 set_track_channel_instrument(track=%d, channel=%d, bank=%d, program=%d)" %
		[track_index, channel, instr_data["bank"], instr_data["program"]])
	
	midi_player_ref.set_track_channel_instrument(
		track_index,
		channel,
		instr_data["bank"],
		instr_data["program"]
	)
	
	print("[TrackView] Track %d Channel %d: 乐器设置为 %s (Bank %d Program %d)" %
		[track_index, channel, instr_data["name"], instr_data["bank"], instr_data["program"]])

# 解析乐器字符串 "乐器名 (BX:PY)" 返回 {name, bank, program}
func _parse_instrument_string(instrument_str: String) -> Dictionary:
	var regex = RegEx.new()
	regex.compile(r"^(.+?)\s*\(B(\d+):P(\d+)\)$")
	var result = regex.search(instrument_str)
	
	if result:
		return {
			"name": result.get_string(1).strip_edges(),
			"bank": int(result.get_string(2)),
			"program": int(result.get_string(3))
		}
	return {}

# 重置轨道-通道的乐器到 MIDI 原始值
func _on_track_instrument_reset(track_index: int, channel: int) -> void:
	if not current_midi_data:
		return
	
	# 清除用户覆盖
	current_midi_data.clear_track_channel_instrument_override(track_index, channel)
	
	# 从 MIDI 原始数据恢复
	if midi_playback_manager:
		var original_instr = midi_playback_manager.get_original_track_channel_instrument(track_index, channel)
		midi_playback_manager.set_track_channel_instrument(
			track_index,
			channel,
			original_instr["bank"],
			original_instr["program"]
		)
		
		# 更新 UI 下拉框（需要遍历查找匹配 track_index 和 channel 的UI项）
		var track_ui: MidiTrack = null
		for track in list_items:
			if track.track_index == track_index and track.track_channel == channel:
				track_ui = track
				break
		
		if track_ui:
			_set_track_instrument_from_midi_data(track_ui, track_index, channel)
	
	print("[TrackView] Track %d Channel %d: 已重置为原始乐器" % [track_index, channel])

# 更新预览（当轨道或音源改变时）
func _update_preview() -> void:	
	var current_pos = midi_playback_manager.position_ms
	midi_playback_manager.load_midi(current_midi_data)
	midi_playback_manager.seek(current_pos)
	midi_playback_manager.play()

## 更新主音符显示器（从MidiData同步启用的(track, channel)列表）
func _update_master_note_displayer() -> void:
	if master_note_displayer == null or current_midi_data == null:
		return

	if All_Notes.is_empty():
		push_warning("No notes found in MIDI")
		return

	# 传入全部音符（未过滤），由 sync_from_midi_data 控制可见性
	master_note_displayer.init_displayer(self, All_Notes)
	if not current_midi_data.selected_track_configs.is_empty():
		master_note_displayer.sync_from_midi_data(current_midi_data)


func _make_pair_key(track_index: int, channel: int) -> String:
	return "%d:%d" % [track_index, channel]

func _capture_solo_snapshot() -> void:
	solo_mute_snapshot.clear()
	if current_midi_data == null:
		return
	for track_ui in list_items:
		var key = _make_pair_key(track_ui.track_index, track_ui.track_channel)
		solo_mute_snapshot[key] = current_midi_data.get_track_channel_mute(track_ui.track_index, track_ui.track_channel)

func _restore_solo_snapshot() -> void:
	if midi_playback_manager == null or current_midi_data == null:
		solo_mute_snapshot.clear()
		return
	for track_ui in list_items:
		var key = _make_pair_key(track_ui.track_index, track_ui.track_channel)
		if solo_mute_snapshot.has(key):
			var muted = solo_mute_snapshot[key]
			midi_playback_manager.set_track_channel_mute_runtime(track_ui.track_index, track_ui.track_channel, muted)
	solo_mute_snapshot.clear()

func _apply_solo_state() -> void:
	if midi_playback_manager == null:
		return
	if solo_pairs.is_empty():
		_restore_solo_snapshot()
		return

	for track_ui in list_items:
		var key = _make_pair_key(track_ui.track_index, track_ui.track_channel)
		var should_solo = solo_pairs.has(key)
		var is_muted_in_snapshot = solo_mute_snapshot.get(key, false)
		var target_muted = true if not should_solo else is_muted_in_snapshot
		# 使用runtime mute来应用临时的独奏状态（不持久化）
		midi_playback_manager.set_track_channel_mute_runtime(track_ui.track_index, track_ui.track_channel, target_muted)

# =============== MIDI播放器信号回调 ====================

func _set_note_displayers_process(enable: bool) -> void:
	if master_note_displayer:
		master_note_displayer.set_process(enable)
	for item in list_items:
		if item is MidiTrack and item.note_display:
			item.note_display.set_process(enable)

# ============== UI 显示函数 ========================

# 更新MIDI音量标签
func _set_display_midi_volume(value: float) -> void:
	# value 已经是 0-100 的百分比
	midi_vol_slider.set_block_signals(true)
	midi_vol_slider.value = value
	midi_vol_slider.set_block_signals(false)

	midi_vol_label.text = "%d%%" % int(value)

# 格式化时间（毫秒到 HH:MM:SS）
func _format_time(ms: float) -> String:
	var total_seconds: int = int(ms / 1000)
	@warning_ignore("integer_division")
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	@warning_ignore("integer_division")
	var hours: int = minutes / 60
	if hours:
		return "%02d:%02d:%02d" % [hours, minutes, seconds]
	else:
		return "%02d:%02d" % [minutes, seconds]

# 设置总时间
func _set_display_total_time(total_ms: float) -> void:
	progress_bar.set_block_signals(true)
	progress_bar.max_value = total_ms
	progress_bar.set_block_signals(false)
	
	total_time.text = _format_time(total_ms)

func _set_display_current_time(current_ms: float) -> void:
	# 只在不拖拽时更新进度条位置和时间文本
	if not is_progress_dragging:
		progress_bar.set_block_signals(true)
		progress_bar.value = current_ms
		progress_bar.set_block_signals(false)
		
		current_time.text = _format_time(current_ms)

func _process(delta: float) -> void:
	if midi_playback_manager.is_playing:
		var current_position = midi_playback_manager.position_ms
		
		# 检测循环播放重置（位置从大跳到小，说明循环了）
		if current_position < last_position_ms - 100:  # 100ms容差，避免误判seek操作
			print("[TrackView] Loop detected: %.1f -> %.1f ms, resetting noteDisplayers" % [last_position_ms, current_position])
			_reset_player()
		
		# 更新当前时间
		_set_display_current_time(current_position)
		# 更新当前 tick（从 position 获取）
		current_tick = int(midi_playback_manager.position)
		# 记录本帧位置
		last_position_ms = current_position

	super._process(delta)

func _gui_input(event: InputEvent) -> void:
	super._gui_input(event)

# 初始化主音符显示器（显示已开启音轨中的所有音符）
func _init_master_note_displayer() -> void:
	if master_note_displayer == null:
		return
	
	if current_midi_data == null:
		push_warning("No MIDI data loaded")
		return
	
	_reset_player()

	# 获取所有音符	
	if All_Notes.is_empty():
		push_warning("No notes found in selected tracks")
		return
	
	# 初始化selected_track_configs - 如果是新MIDI（从未配置过），则默认将所有(track, channel)对设为启用
	# 这是新MIDI的首次初始化，将完成enable按钮的最终状态设置
	if not current_midi_data._track_config_initialized:
		var recommended := current_midi_data._desc_recommended_tracks
		var use_recommendation := not recommended.is_empty()
		GLogger.info("[TrackView] first init: midi=%s recommended=%s use_rec=%s notes=%d" % [current_midi_data.id, recommended, use_recommendation, All_Notes.size()], "TrackView")

		# 设置 (track, channel) 启用状态：有简介推荐时仅启用推荐轨道，否则启用全部（原逻辑）
		for note in All_Notes:
			var should_enable := true
			if use_recommendation:
				should_enable = note.track_index in recommended
			current_midi_data.set_track_channel_enabled(note.track_index, note.channel, should_enable)

		# 推荐轨道均不存在于 MIDI 时回退到启用全部，避免无音符可见
		if use_recommendation and current_midi_data.selected_track_configs.is_empty():
			for note in All_Notes:
				current_midi_data.set_track_channel_enabled(note.track_index, note.channel, true)
			print("[TrackView] Recommended tracks %s not found in MIDI, fell back to enabling all" % recommended)
		elif use_recommendation:
			print("[TrackView] Enabled recommended tracks from description: %s" % recommended)
		else:
			print("[TrackView] Initialized %d notes from all (track, channel) pairs as ENABLED" % All_Notes.size())

		current_midi_data._track_config_initialized = true

		# 同时更新UI显示（更新enable按钮和文本）
		for track_item in list_items:
			if track_item is MidiTrack:
				var track_idx = track_item.track_index
				var channel = track_item.track_channel

				# 检查该(track, channel)是否有Note
				var has_note = false
				for note in All_Notes:
					if note.track_index == track_idx and note.channel == channel:
						has_note = true
						break

				if has_note and track_item.enable_btn:
					var is_enabled := current_midi_data.is_track_channel_selected(track_idx, channel)
					track_item.enable_btn.set_block_signals(true)
					track_item.enable_btn.button_pressed = is_enabled
					track_item.enable_btn.set_block_signals(false)
					if track_item.enable_btn_text:
						track_item.enable_btn_text.text = "已启用" if is_enabled else "已禁用"
					if track_item.note_display:
						track_item.note_display.note_color = track_item.color_normal if is_enabled else track_item.color_dark
						track_item.note_display.update_color()
	else:
		# 旧MIDI：selected_track_configs已从JSON恢复（可能为空或有配置），只需要记录日志
		print("[TrackView] Existing MIDI: selected_track_configs already initialized with %d tracks" % 
			current_midi_data.selected_track_configs.size())
	
	print("[TrackView] Master note displayer: %d total notes (time-sorted)" % All_Notes.size())
	# 初始化主音符显示器（notes已按时间顺序排列）
	master_note_displayer.init_displayer(self, All_Notes)
	if not current_midi_data.selected_track_configs.is_empty():
		master_note_displayer.sync_from_midi_data(current_midi_data)

func _init_track_note_displayer(track_scene: MidiTrack, track_index: int, channel: int, track_notes: Array[NoteDisplayer.NoteEvent]) -> void:
	if track_scene.note_display == null:
		return
	
	# track_notes 已经由 _create_track_views() 过滤好了，直接使用
	if track_notes.is_empty():
		push_warning("No notes found for track %d channel %d" % [track_index, channel])
		return
	
	print("[TrackView] Track %d Channel %d: %d notes (time-sorted)" % [track_index, channel, track_notes.size()])
	# 初始化该(track, channel)的音符显示器（notes已按时间顺序排列）
	track_scene.note_display.init_displayer(self, track_notes)

# 重置音符显示器索引
func _reset_player() -> void:	
	current_tick = 0
	last_position_ms = 0.0
	_set_display_current_time(0)

	# 重置音符显示器位置
	master_note_displayer.reset_playhead_position(0)
	for track in list_items:
		if track.note_display:
			track.note_display.reset_playhead_position(0)

## 初始化新MIDI的轨道音量为50%
## 只在首次加载MIDI时调用（如果没有保存过音量配置）
func _initialize_track_volumes_for_new_midi() -> void:
	if current_midi_data == null or midi_playback_manager == null:
		return
	
	# 检查是否已有音量配置（旧MIDI或已保存过）
	if not current_midi_data.track_channel_volume_config.is_empty():
		# 已有配置，跳过初始化
		return
	
	# 新MIDI：为所有已创建的轨道初始化音量为50%（0.5线性值）
	var initialized_count = 0
	for track_item in list_items:
		if track_item is MidiTrack:
			var track_idx = track_item.track_index
			var channel = track_item.track_channel
			
			# 设置默认音量为50%（0.5）
			var default_volume = 0.5
			midi_playback_manager.set_track_channel_volume(track_idx, channel, default_volume)
			current_midi_data.set_track_channel_volume(track_idx, channel, default_volume)
			initialized_count += 1
	
	print("[TrackView] Initialized %d tracks with default volume 50%%" % initialized_count)

# 页面状态回调
func _on_ui_state_changed(old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	# 保存当前MIDI配置到JSON文件
	if current_midi_data != null:
		_config_persistence.call_deferred("save_midi_config")

	if old_state == work_state:
		if midi_playback_manager:
			if new_state == ui_stat_mgr.UIState.MIDI_VIEW:
				midi_playback_manager.stop()
			elif new_state == ui_stat_mgr.UIState.SETTINGS_VIEW:
				midi_playback_manager.pause()
			
		_set_note_displayers_process(false)
		# 收起主面板的展开状态
		get_node("MC/VBox/TotalView/MC/VBoxC/flowArea/noteFlowArea/Button").button_pressed = false

	# Reload MIDI when returning from settings (handles backend switch)
	if old_state == ui_stat_mgr.UIState.SETTINGS_VIEW and new_state == work_state:
		if current_midi_data:
			midi_playback_manager.set_loop(true)
			midi_playback_manager.resume()
			_set_note_displayers_process(true)
			print("[TrackView] Reloaded MIDI after returning from settings")

## 初始化Latency输入框（从MidiData读取偏移值）
func _init_latency_edit() -> void:
	if latency_edit == null or current_midi_data == null:
		return

	# 从MidiData读取人声偏移量并显示
	latency_edit.set_block_signals(true)
	latency_edit.text = str(int(current_midi_data.vocal_offset_ms))
	latency_edit.set_block_signals(false)

	# 将偏移值应用到MidiPlaybackManager
	midi_playback_manager.set_vocal_offset_ms(current_midi_data.vocal_offset_ms)

## 处理Latency输入框文本变化
func _on_latency_changed(new_text: String) -> void:
	if current_midi_data == null or midi_playback_manager == null or latency_edit == null:
		return

	# 验证输入（确保是有效的整数）
	var offset_ms: int = 0
	if not new_text.is_empty():
		if new_text.is_valid_int():
			offset_ms = int(new_text)
		else:
			# 如果输入无效，恢复为之前的值
			latency_edit.set_block_signals(true)
			latency_edit.text = str(int(current_midi_data.vocal_offset_ms))
			latency_edit.set_block_signals(false)
			return

	# 更新MidiData中的偏移值
	current_midi_data.vocal_offset_ms = offset_ms

	# 应用到MidiPlaybackManager
	midi_playback_manager.set_vocal_offset_ms(offset_ms)

	# 如果人声正在播放，立即应用偏移
	if midi_playback_manager.is_playing:
		midi_playback_manager.apply_vocal_offset()

	print("[TrackView] Latency offset changed to %d ms" % offset_ms)

## 从当前加载的 MIDI 和 SoundFont 提取可用的乐器选项
func _extract_instruments_from_midi() -> void:
	if midi_playback_manager == null:
		return

	var presets_list = midi_playback_manager.get_presets_list()

	if presets_list.is_empty():
		GLogger.warning("No presets available from SoundFont", "TrackView")
		instrument_options = ["Unknown (B0:P0)"]
		regular_instruments = instrument_options.duplicate()
		drum_instruments = []
		return

	# 清空之前的列表
	instrument_options.clear()
	regular_instruments.clear()
	drum_instruments.clear()
	
	var seen_options = {}  # 用于去重

	for preset in presets_list:
		var bank = preset["bank"]
		var program = preset["program"]
		var preset_name = preset["name"].strip_edges()
		
		if preset_name.is_empty():
			preset_name = "#%d" % program
		
		# 构建显示名称："乐器名 (BX:PY)"
		var display_name = "%s (B%d:P%d)" % [preset_name, bank, program]
		
		# 去重
		if seen_options.has(display_name):
			continue
		seen_options[display_name] = true
		
		# 根据 bank 分类
		if bank == 128:
			# 鼓组乐器
			drum_instruments.append(display_name)
		else:
			# 常规乐器
			regular_instruments.append(display_name)
		
		# 全局列表包含所有
		instrument_options.append(display_name)

	print("[TrackView] 已提取 %d 个常规乐器, %d 个鼓组乐器" %
		[regular_instruments.size(), drum_instruments.size()])

## 根据 MIDI 数据设置轨道的正确乐器
func _set_track_instrument_from_midi_data(track_scene: MidiTrack, track_idx: int, channel: int) -> void:
	if current_midi_data == null or midi_playback_manager == null:
		return
	
	# 首先检查是否有用户覆盖
	var override_instr = current_midi_data.get_track_channel_instrument_override(track_idx, channel)
	var bank: int
	var program: int
	var preset_name: String
	
	if not override_instr.is_empty():
		# 使用用户覆盖的乐器
		bank = override_instr.get("bank", 0)
		program = override_instr.get("program", 0)
		preset_name = override_instr.get("name", midi_playback_manager.get_preset_name(program, bank))
		print("[TrackView] Track %d Channel %d: 使用用户覆盖乐器 %s" % [track_idx, channel, preset_name])
	else:
		# 使用 MIDI 文件中的原始乐器
		var instrument_info = midi_playback_manager.get_track_channel_instrument(track_idx, channel)
		bank = instrument_info.get("bank", 0)
		program = instrument_info.get("program", 0)
		preset_name = midi_playback_manager.get_preset_name(program, bank)

	# 构建显示名称
	var display_name = "%s (B%d:P%d)" % [preset_name, bank, program]
	
	# 在乐器选项中查找匹配项
	if track_scene.instruments_option_btn:
		var selected_index = 0  # 默认选择第一个
		for i in range(track_scene.instruments_option_btn.item_count):
			if track_scene.instruments_option_btn.get_item_text(i) == display_name:
				selected_index = i
				break

		# 设置下拉框选中项（阻止信号以避免不必要的回调）
		track_scene.instruments_option_btn.set_block_signals(true)
		track_scene.instruments_option_btn.select(selected_index)
		track_scene.instruments_option_btn.set_block_signals(false)

		print("[TrackView] 轨道 %d 通道 %d: 设置乐器为 '%s' (program: %d, bank: %d)" %
			[track_idx, channel, preset_name, program, bank])

## 当SoundFont变更时，重新提取乐器列表并更新UI
func _on_soundfont_changed(soundfont_path: String) -> void:
	print("[TrackView] SoundFont changed: %s" % soundfont_path)

	# 重新提取乐器列表
	_extract_instruments_from_midi()

	# 更新所有现有的MidiTrack UI项的乐器选项
	_refresh_all_track_instruments()

## 当乐器列表变更时，快速更新所有MidiTrack的选项
func _refresh_all_track_instruments() -> void:
	print("[TrackView] Refreshing all track instrument options")

	if current_midi_data == null or not has_meta("list_items"):
		return

	for item in list_items:
		if item is MidiTrack and item.instruments_option_btn:
			# 清空并重建选项列表
			item.instruments_option_btn.clear()
			for option_text in instrument_options:
				item.instruments_option_btn.add_item(option_text)

			# 重新设置默认选中项（使用MidiTrack的track_index和track_channel）
			var track_idx = item.track_index
			var channel = item.track_channel
			_set_track_instrument_from_midi_data(item, track_idx, channel)

			print("[TrackView] Updated instrument options for track %d channel %d" % [track_idx, channel])
