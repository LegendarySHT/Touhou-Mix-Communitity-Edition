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

# MIDI播放相关 下面两个没有（
@onready var soundfont_selector: OptionButton = $MC/VBox/VolumeView/HBoxC/VBoxC2/SoundfontSelector
@onready var preview_button: Button = $MC/VBox/TotalView/MC/VBoxC/playArea/PreviewButton

# 底部填充，增加新项时需要把这个移到底部
@onready var bottom: MarginContainer = $MC/VBox/PaddingBottom

# 给midi轨道访问的默认值
var instrument_options: Array = ["钢琴", "吉他", "贝斯", "鼓", "弦乐"]

# MIDI轨道预制场景
const MIDI_TRACK_SCENE = preload("res://UI/Views/TrackView/midiTrack.tscn")

var midi_tracks: Array[MidiTrack] = []
var current_midi_data: MidiData = null
var midi_playback_manager: MidiPlaybackManager
var is_previewing: bool = false

var vocal_file_path: String = "111"

var current_tick: int = 0

func _ready() -> void:
	work_state = UIStateManager.UIState.TRACK_VIEW
	need_h_expand = true

	# 获取管理器引用（使用单例模式）
	midi_playback_manager = MidiPlaybackManager.instance
	if midi_playback_manager == null:
		push_error("MidiPlaybackManager not initialized in Main! MIDI features will not work.")
		return

	# 如果有人声的话在这里加载

	_init_vocal_btn_display()

	# 初始化UI
	_populate_soundfont_selector()
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

	soundfont_selector.item_selected.connect(_on_soundfont_selected)
	progress_bar.value_changed.connect(_on_progress_bar_changed)

	preview_button.pressed.connect(_on_preview_button_pressed)
	super._ready()

# 加载并播放midi
func _load_midi(midi: MidiData) -> void:
	current_midi_data = midi
	
	# 清空现有的轨道
	_clear_tracks()
	
	# 加载MIDI到播放管理器
	if midi_playback_manager.load_midi(midi):
		# 初始化总览的音符显示器
		_init_master_note_displayer()
		# 创建轨道UI
		_create_track_views()
	else:
		push_error("Failed to load MIDI: " + midi.id)

# 清空所有轨道
func _clear_tracks() -> void:
	for track in midi_tracks:
		track.queue_free()
	midi_tracks.clear()
	
	# 从container中移除所有子节点
	for child in container.get_children():
		if child is MidiTrack:
			child.queue_free()

# 创建轨道视图
func _create_track_views() -> void:
	if not current_midi_data:
		return
	
	# 获取轨道信息
	var track_infos = midi_playback_manager.get_track_infos()
	
	if track_infos.is_empty():
		push_warning("No track info available")
		return
	
	# 为每个轨道创建UI
	for track_info in track_infos:
		var track_scene = MIDI_TRACK_SCENE.instantiate()
		
		track_scene.setup_track(self , track_info.index, track_info.name, instrument_options)

		container.add_child(track_scene)
		container.move_child(bottom, container.get_child_count() - 1)
		
		# 为该轨道初始化音符显示
		_init_track_note_displayer(track_scene, track_info.index)
		
		midi_tracks.append(track_scene)
	
	# 更新音源选择
	if soundfont_selector and current_midi_data.use_soundfont:
		_select_soundfont(current_midi_data.use_soundfont)

# 填充音源选择器
func _populate_soundfont_selector() -> void:
	if soundfont_selector == null or midi_playback_manager == null:
		return
	
	soundfont_selector.clear()
	
	var soundfonts = midi_playback_manager.get_available_soundfonts()
	for soundfont_name in soundfonts:
		soundfont_selector.add_item(soundfont_name)

# 选择指定的音源
func _select_soundfont(soundfont_name: String) -> void:
	if soundfont_selector == null:
		return
	
	for i in range(soundfont_selector.item_count):
		if soundfont_selector.get_item_text(i) == soundfont_name:
			soundfont_selector.select(i)
			return

# ============= 信号回调函数 ===============

# 拖动进度条事件
func _on_progress_bar_changed(progress: float) -> void:
	print("Progress changed to: %f" % progress)

# 音源选择回调
func _on_soundfont_selected(index: int) -> void:
	if soundfont_selector == null or midi_playback_manager == null:
		return
	
	var soundfont_name = soundfont_selector.get_item_text(index)
	var success = midi_playback_manager.set_soundfont(soundfont_name)
	
	if success and current_midi_data:
		current_midi_data.set_soundfont(soundfont_name)
		
		# 如果正在预览，立即更新
		if is_previewing:
			_update_preview()

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
		var load_success = midi_playback_manager.load_midi(current_midi_data)
		if load_success:
			# 重新初始化显示器，确保note数据正确加载
			_init_master_note_displayer()
			for track in midi_tracks:
				_init_track_note_displayer(track, track.track_index)
			
			midi_playback_manager.play()
			is_previewing = true
			if preview_button:
				preview_button.text = "停止预览"
		else:
			push_error("Failed to load MIDI for preview")

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
	midi_playback_manager.set_selected_tracks(selected_tracks)
	
	# 如果正在预览，立即重新加载预览
	if is_previewing:
		_update_preview()

# 轨道静音切换
func _on_track_mute_toggled(is_muted: bool, track_index: int) -> void:
	print("Track %d mute: %s" % [track_index, is_muted])
	if midi_playback_manager == null:
		return
	# 获取当前选中的轨道列表
	var selected_tracks = current_midi_data.selected_track_indices.duplicate() if current_midi_data else []
	
	if is_muted:
		# 静音：移除该轨道
		if track_index in selected_tracks:
			selected_tracks.erase(track_index)
	else:
		# 取消静音：添加该轨道
		if track_index not in selected_tracks:
			selected_tracks.append(track_index)
	
	# 更新选中轨道列表
	if current_midi_data:
		current_midi_data.set_selected_tracks(selected_tracks)
	midi_playback_manager.set_selected_tracks(selected_tracks)
	
	# 如果正在预览，立即更新
	if is_previewing:
		_update_preview()

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
	for track in midi_tracks:
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
	if track_index >= midi_tracks.size():
		return
	
	var instrument_name = midi_tracks[track_index].instruments_option_btn.get_item_text(index)
	
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
	# 设置初始值（假设100%对应0dB）
	midi_vol_slider.set_block_signals(true)
	midi_vol_slider.value = db_to_linear(value) * 100
	midi_vol_slider.set_block_signals(false)

	midi_vol_label.text = "%d%%" % value

func _set_display_vocal_volume(value: float) -> void:
	vocal_vol_slider.set_block_signals(true)
	vocal_vol_slider.value = db_to_linear(value) * 100
	vocal_vol_slider.set_block_signals(false)
	
	vocal_vol_label.text = "%d%%" % value

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
	if master_note_displayer == null or midi_playback_manager == null:
		return
	
	if current_midi_data == null:
		push_warning("No MIDI data loaded")
		return
	
	var selected_tracks = current_midi_data.selected_track_indices
	if selected_tracks.is_empty():
		push_warning("No tracks selected")
		return
	
	# 获取所有音符
	var all_notes = midi_playback_manager.current_notes
	print("[TrackView] Got %d notes from MidiPlaybackManager" % all_notes.size())
	
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
	
	print("[TrackView] Filtered to %d notes from selected tracks" % display_notes.size())
	
	# 初始化显示器（notes已按时间顺序排列）
	master_note_displayer.init_displayer(self, display_notes)

func _init_track_note_displayer(track_scene: MidiTrack, track_index: int) -> void:
	if track_scene.note_display == null or midi_playback_manager == null:
		return
	
	var all_notes = midi_playback_manager.current_notes
	if all_notes.is_empty():
		push_warning("No notes available for track %d" % track_index)
		return
	
	# 在一次遍历中筛选并转换该轨道的音符（notes已按时间顺序）
	var track_notes: Array[NoteDisplayer.NoteEvent] = []
	for note in all_notes:
		if note is MidiParser.Note and note.event != null:
			var evt = note.event
			if evt.track_index == track_index:
				var display_note = NoteDisplayer.NoteEvent.new(
					evt.pitch,
					evt.velocity,
					int(evt.start_time),
					int(evt.duration),
					evt.track_index,
					evt.channel
				)
				track_notes.append(display_note)
	
	if track_notes.is_empty():
		push_warning("No notes found for track %d" % track_index)
		return
	
	print("[TrackView] Track %d: %d notes (time-sorted)" % [track_index, track_notes.size()])
	# 初始化该轨道的音符显示器（notes已按时间顺序排列）
	track_scene.note_display.init_displayer(self, track_notes)



# 清理资源
func _exit_tree() -> void:
	# 停止预览
	if is_previewing and midi_playback_manager:
		midi_playback_manager.stop()
	
	# 清空轨道列表
	midi_tracks.clear()
