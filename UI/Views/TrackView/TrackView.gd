extends BaseScrollList

class_name TrackView

@onready var master_note_displayer: NoteDisplayer = $MC/VBox/TotalView/MC/VBoxC/flowArea
@onready var current_time: Label = $MC/VBox/TotalView/MC/VBoxC/playArea/currentTime
@onready var progress_bar: HSlider = $MC/VBox/TotalView/MC/VBoxC/playArea/progressBar
@onready var total_time: Label = $MC/VBox/TotalView/MC/VBoxC/playArea/totalTime

# 导入人声按钮，存在人声时变为切换启用状态？
@onready var vocal_btn: TextureButton = $MC/VBox/VolumeView/HBoxC/VBoxC2/VocalBtn
@onready var latency_edit: LineEdit = $MC/VBox/VolumeView/HBoxC/VBoxC2/HBoxContainer/Latency
@onready var midi_vol_btn: TextureButton = $MC/VBox/VolumeView/HBoxC/GridC/midiVolIcon
@onready var midi_vol_slider: HSlider = $MC/VBox/VolumeView/HBoxC/GridC/midiVolSlider
@onready var vocal_vol_btn: TextureButton = $MC/VBox/VolumeView/HBoxC/GridC/vocalVolIcon
@onready var vocal_vol_slider: HSlider = $MC/VBox/VolumeView/HBoxC/GridC/vocalVolSlider

@onready var midi_vol_label: Label = $MC/VBox/VolumeView/HBoxC/GridC/midiVolLabel
@onready var vocal_vol_label: Label = $MC/VBox/VolumeView/HBoxC/GridC/vocalVolLabel

# MIDI播放相关 下面两个没有（SoundFont选择功能已迁移至SettingView）
@onready var preview_button: Button = $MC/VBox/TotalView/MC/VBoxC/playArea/PreviewButton

@onready var midi_playback_manager: MidiPlaybackManager = MidiPlaybackManager.instance
@onready var ui_stat_mgr: UIStateManager = UIStateManager.instance

var current_midi_data: MidiData = null
var is_previewing: bool = false
var is_progress_dragging: bool = false

var current_tick: int = 0

# 给midi轨道访问的默认值
var instrument_options: Array = ["钢琴", "吉他", "贝斯", "鼓", "弦乐"]
var vocal_file_path: String = "111"


# 用于存储所有音符的列表
var All_Notes: Array[NoteDisplayer.NoteEvent] = []

func _ready() -> void:
	work_state = UIStateManager.UIState.TRACK_VIEW
	need_h_expand = true

	# 检查管理器引用
	if midi_playback_manager == null:
		push_error("MidiPlaybackManager not initialized in Main! MIDI features will not work.")
		return

	# 初始化UI

	midi_vol_slider.value = db_to_linear(midi_playback_manager.midi_player_config["volume_db"]) * 100
	_set_display_midi_volume(midi_vol_slider.value)
	
	# 连接信号
	EventBus.instance.enter_track_view_with.connect(_load_midi)

	midi_playback_manager.midi_loaded.connect(_on_midi_loaded)
	midi_playback_manager.midi_started.connect(_on_midi_started)
	midi_playback_manager.midi_stopped.connect(_on_midi_stopped)
	midi_playback_manager.midi_finished.connect(_on_midi_finished)
	
	# 音量
	midi_vol_btn.toggled.connect(_on_volume_btn_toggled.bind(midi_vol_btn))
	vocal_vol_btn.toggled.connect(_on_volume_btn_toggled.bind(vocal_vol_btn))
	midi_vol_slider.value_changed.connect(_on_midi_volume_changed)
	vocal_vol_slider.value_changed.connect(_on_vocal_volume_changed)


	progress_bar.drag_started.connect(_on_progress_bar_drag_started)
	progress_bar.drag_ended.connect(_on_progress_bar_drag_ended)
	progress_bar.value_changed.connect(_on_progress_bar_value_changed)

	preview_button.pressed.connect(_on_preview_button_pressed)
	super._ready()

# 加载并播放midi
func _load_midi(midi: MidiData) -> void:
	current_midi_data = midi
	
	# 清空现有的轨道
	clear_items()

	# 重置列表高度
	await get_tree().process_frame
	container.custom_minimum_size.y = 0
	container.size.y = 0
	
	# 加载MIDI到播放管理器
	if not midi_playback_manager.load_midi(midi):
		push_error("Failed to load MIDI: " + midi.id)

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

	# 创建轨道UI
	_create_track_views()

	# 初始化人声按钮显示
	_init_vocal_btn_display()

# 创建轨道视图
func _create_track_views() -> void:
	if not current_midi_data:
		return

	# 获取轨道信息
	var track_infos = midi_playback_manager.get_track_infos()
	
	if track_infos.is_empty():
		push_warning("No track info available")
		return
	
	# 为每个轨道创建UI（仅当轨道有音符时）
	for track_info in track_infos:
		# 先检查该轨道是否有音符
		var track_notes: Array[NoteDisplayer.NoteEvent] = All_Notes.filter(
			func (note):
				return note.track_index == track_info.index
		)
		
		# 如果轨道没有音符，跳过创建UI
		if track_notes.is_empty():
			push_warning("Track %d (%s) has no notes, skipping UI creation" % [track_info.index, track_info.name])
			continue
		
		# 创建轨道UI
		var track_scene = create_and_add_item(track_info.name, "MidiTrack") as MidiTrack
		
		track_scene.setup_track(self , track_info.index, track_info.name, instrument_options)

		# 为该轨道初始化音符显示（传入已过滤的音符）
		_init_track_note_displayer(track_scene, track_info.index, track_notes)
		
	# 增加上下边距
	container.custom_minimum_size.y = container.size.y + 800

	


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
	
	# 重置noteDisplayer状态
	if master_note_displayer:
		master_note_displayer.reset_playhead_position(target_ms)
	
	# 重置所有轨道的noteDisplayer
	for track in list_items:
		if track.note_display:
			track.note_display.reset_playhead_position(target_ms)

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

	btn.modulate = Color(1, 0.5, 0.5, 1) if toggle_on else Color(1, 1, 1, 1)

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
	# 更新标签
	_set_display_vocal_volume(value)

# 预览按钮回调
func _on_preview_button_pressed() -> void:
	if midi_playback_manager == null or current_midi_data == null:
		return
	
	if is_previewing:
		# 停止预览
		midi_playback_manager.stop()
		is_previewing = false
		if preview_button:
			preview_button.text = "播放预览"
	else:
		# 开始预览
		_reset_player()

		midi_playback_manager.play()
		is_previewing = true
		if preview_button:
			preview_button.text = "停止预览"

# ============= 音轨信号回调 =======================

# 轨道启用状态切换
func _on_track_enable_toggled(is_checked: bool, track_index: int) -> void:
	if current_midi_data == null:
		return
	
	var selected_tracks = current_midi_data.selected_track_indices.duplicate()
	
	if is_checked:
		# 添加轨道
		if track_index not in selected_tracks:
			selected_tracks.append(track_index)
	else:
		# 移除轨道
		if track_index in selected_tracks:
			selected_tracks.erase(track_index)
	
	# 更新MIDI数据
	current_midi_data.set_selected_tracks(selected_tracks)
	
	# 更新主音符显示器以反映选中轨道的变化
	master_note_displayer.toggle_track(is_checked, track_index)

# 轨道静音切换
func _on_track_mute_toggled(is_muted: bool, track_index: int) -> void:
	print("Track %d mute: %s" % [track_index, is_muted])
	if current_midi_data == null:
		return
	
	# 获取当前选中的轨道列表
	var selected_tracks = current_midi_data.selected_track_indices.duplicate()
	
	if is_muted:
		# 静音：移除该轨道
		if track_index in selected_tracks:
			selected_tracks.erase(track_index)
	else:
		# 取消静音：添加该轨道
		if track_index not in selected_tracks:
			selected_tracks.append(track_index)
	
	# 更新选中轨道列表
	current_midi_data.set_selected_tracks(selected_tracks)
	
	# 更新主音符显示器以反映选中轨道的变化
	_update_master_note_displayer()

# 轨道独奏切换
func _on_track_solo_toggled(is_solo: bool, track_index: int) -> void:
	print("Track %d solo: %s" % [track_index, is_solo])
	# TODO: 实现轨道独奏逻辑

# 轨道音量改变
func _on_track_volume_changed(value: float, track_index: int) -> void:
	if midi_playback_manager == null:
		return
	
	# 获取对应的轨道UI
	var track_ui: MidiTrack = null
	for track in list_items:
		if track.track_index == track_index:
			track_ui = track
			break
	
	if track_ui == null:
		return
	
	# 转换为dB (-80 ~ 0)
	var volume_db = linear_to_db(value / 100.0)
	
	# 调用MidiPlaybackManager设置轨道音量
	# 注：这里假设MidiPlaybackManager支持按轨道设置音量
	# 如果不支持，需要扩展MidiPlaybackManager的功能
	midi_playback_manager.set_track_volume_db(track_index, volume_db)
	
# 乐器选择
func _on_track_instrument_changed(index: int, track_index: int) -> void:
	if track_index >= list_items.size():
		return
	
	var instrument_name = list_items[track_index].instruments_option_btn.get_item_text(index)
	
	# 注：乐器切换通过MIDI的Program Change消息实现
	# 当前版本记录选择，具体实现需要通过MidiPlayer的乐器配置
	print("Track %d instrument changed to: %s" % [track_index, instrument_name])
	
	# TODO: 后续可扩展支持通过MidiPlayer的API设置轨道乐器

# 更新预览（当轨道或音源改变时）
func _update_preview() -> void:
	if not is_previewing:
		return
	
	var current_pos = midi_playback_manager.position_ms
	midi_playback_manager.load_midi(current_midi_data)
	midi_playback_manager.seek(current_pos)
	midi_playback_manager.play()

# 更新主音符显示器（当选中轨道改变时）
func _update_master_note_displayer() -> void:
	if master_note_displayer == null or midi_playback_manager == null or current_midi_data == null:
		return
	
	var selected_tracks = current_midi_data.selected_track_indices
	if selected_tracks.is_empty():
		push_warning("No tracks selected")
		# 清空显示器中的所有音符
		master_note_displayer.init_displayer(self, [])
		return
	
	# 获取所有音符
	var all_notes = midi_playback_manager.current_notes
	if all_notes.is_empty():
		push_warning("No notes found in MIDI")
		return
	
	# 在一次遍历中过滤并转换为显示格式（notes已按时间顺序）
	var display_notes: Array[NoteDisplayer.NoteEvent] = []
	for note in all_notes:
		if note is MidiParser.Note and note.event != null:
			var evt = note.event
			if evt.track_index in selected_tracks:
				var display_note = NoteDisplayer.NoteEvent.new(
					evt.pitch,
					evt.velocity,
					int(evt.start_time),
					int(evt.duration),
					evt.track_index,
					evt.channel
				)
				display_notes.append(display_note)
	
	if display_notes.is_empty():
		push_warning("No notes found in selected tracks")
		return
	
	print("[TrackView] Updated master note displayer with %d notes from selected tracks" % display_notes.size())
	
	# 更新显示器的current_note数据
	master_note_displayer.init_displayer(self, display_notes)

# =============== MIDI播放器信号回调 ====================

func _on_midi_loaded(midi_data: MidiData) -> void:
	print("MIDI loaded: " + midi_data.name)
	# 更新进度条最大范围
	if midi_data.duration_ms > 0:
		_set_display_total_time(midi_data.duration_ms)

func _on_midi_started() -> void:
	print("MIDI playback started")
	# 开始更新进度条
	set_process(true)

func _on_midi_stopped() -> void:
	print("MIDI playback stopped")
	set_process(false)
	progress_bar.value = 0
	current_time.text = "00:00"

func _on_midi_finished() -> void:
	print("MIDI playback finished")
	is_previewing = false
	if preview_button:
		preview_button.text = "播放预览"

# ============== UI 显示函数 ========================

func _init_vocal_btn_display() -> void:
	if not vocal_file_path:
		pass
	else:
		pass

# 更新MIDI音量标签
func _set_display_midi_volume(value: float) -> void:
	# value 已经是 0-100 的百分比
	midi_vol_slider.set_block_signals(true)
	midi_vol_slider.value = value
	midi_vol_slider.set_block_signals(false)

	midi_vol_label.text = "%d%%" % int(value)

func _set_display_vocal_volume(value: float) -> void:
	vocal_vol_slider.set_block_signals(true)
	vocal_vol_slider.value = value
	vocal_vol_slider.set_block_signals(false)
	
	vocal_vol_label.text = "%d%%" % int(value)

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
	if is_previewing and midi_playback_manager:
		# 更新当前时间
		_set_display_current_time(midi_playback_manager.position_ms)
		# 更新当前 tick（从 position 获取）
		current_tick = int(midi_playback_manager.position)

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
	
	print("[TrackView] Filtered to %d notes from selected tracks" % All_Notes.size())
	
	# 初始化显示器（notes已按时间顺序排列）
	master_note_displayer.init_displayer(self, All_Notes)

func _init_track_note_displayer(track_scene: MidiTrack, track_index: int, track_notes: Array[NoteDisplayer.NoteEvent]) -> void:
	if track_scene.note_display == null:
		return
	
	# track_notes 已经由 _create_track_views() 过滤好了，直接使用
	if track_notes.is_empty():
		push_warning("No notes found for track %d" % track_index)
		return
	
	print("[TrackView] Track %d: %d notes (time-sorted)" % [track_index, track_notes.size()])
	# 初始化该轨道的音符显示器（notes已按时间顺序排列）
	track_scene.note_display.init_displayer(self, track_notes)

# 重置音符显示器索引
func _reset_player() -> void:	
	current_tick = 0
	_set_display_current_time(0)

	# 重置音符显示器位置
	master_note_displayer.reset_playhead_position(0)
	for track in list_items:
		if track.note_display:
			track.note_display.reset_playhead_position(0)

# 页面状态回调
func _on_state_changed(old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	if old_state == work_state and new_state == ui_stat_mgr.UIState.MIDI_VIEW:
		# 停止预览
		if is_previewing and midi_playback_manager:
			midi_playback_manager.stop()
		
		# 清空轨道列表
		clear_items()	
