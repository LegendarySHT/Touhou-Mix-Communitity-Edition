extends BaseScrollList

class_name TrackView

@onready var total_note: NoteDisplayer = $VBox/TotalView/VBoxC/flowArea
@onready var current_time: Label = $VBox/TotalView/VBoxC/playArea/currentTime
@onready var progress_bar: HSlider = $VBox/TotalView/VBoxC/playArea/progressBar
@onready var total_time: Label = $VBox/TotalView/VBoxC/playArea/totalTime

# 导入人声按钮，存在人声时变为切换启用状态？
@onready var vocal_btn: TextureButton = $VBox/VolumeView/HBoxC/VBoxC2/VocalBtn
@onready var latency_edit: LineEdit = $VBox/VolumeView/HBoxC/VBoxC2/HBoxContainer/Latency
@onready var midi_vol_btn: TextureButton = $VBox/VolumeView/HBoxC/GridC/midiVolIcon
@onready var midi_vol_slider: HSlider = $VBox/VolumeView/HBoxC/GridC/midiVolSlider
@onready var midi_vol_label: Label = $VBox/VolumeView/HBoxC/GridC/midiVolLabel
@onready var volcal_vol_btn: TextureButton = $VBox/VolumeView/HBoxC/GridC/vocalVolIcon
@onready var vocal_vol_slider: HSlider = $VBox/VolumeView/HBoxC/GridC/vocalVolSlider
@onready var vocal_vol_label: Label = $VBox/VolumeView/HBoxC/GridC/vocalVolLabel

# MIDI播放相关 下面两个没有（
@onready var soundfont_selector: OptionButton = $VBox/VolumeView/HBoxC/VBoxC2/SoundfontSelector
@onready var preview_button: Button = $VBox/TotalView/VBoxC/playArea/PreviewButton

# 底部填充，增加新项时需要把这个移到底部
@onready var bottom: MarginContainer = $VBox/PaddingBottom

# MIDI轨道预制场景
const MIDI_TRACK_SCENE = preload("res://UI/Views/TrackView/midiTrack.tscn")

var midi_tracks: Array[MidiTrack] = []
var current_midi_data: MidiData = null
var midi_playback_manager: MidiPlaybackManager
var is_previewing: bool = false

func _ready() -> void:
	work_state = UIStateManager.UIState.TRACK_VIEW

	# 获取管理器引用（使用单例模式）
	midi_playback_manager = MidiPlaybackManager.instance
	if midi_playback_manager == null:
		push_error("MidiPlaybackManager not initialized in Main! MIDI features will not work.")
		return
	
	# 初始化MIDI配置UI
	_initialize_midi_config_ui()
	
	# 连接信号
	EventBus.instance.enter_track_view_with.connect(_load_midi)
	midi_playback_manager.midi_loaded.connect(_on_midi_loaded)
	midi_playback_manager.midi_started.connect(_on_midi_started)
	midi_playback_manager.midi_stopped.connect(_on_midi_stopped)
	midi_playback_manager.midi_finished.connect(_on_midi_finished)
	
	super._ready()

# 初始化MIDI配置UI组件
func _initialize_midi_config_ui() -> void:
	# 连接音源选择器
	if soundfont_selector:
		soundfont_selector.item_selected.connect(_on_soundfont_selected)
		_populate_soundfont_selector()
	
	# 连接音量滑块
	if midi_vol_slider:
		# 设置初始值（假设100%对应0dB）
		midi_vol_slider.value = db_to_linear(midi_playback_manager.midi_player_config["volume_db"]) * 100
		midi_vol_slider.value_changed.connect(_on_midi_volume_changed)
		_update_midi_volume_label(midi_vol_slider.value)
	
	# 连接预览按钮
	if preview_button:
		preview_button.pressed.connect(_on_preview_button_pressed)

# 加载并播放midi
func _load_midi(midi: MidiData) -> void:
	current_midi_data = midi
	
	# 清空现有的轨道
	_clear_tracks()
	
	# 加载MIDI到播放管理器
	if midi_playback_manager.load_midi(midi):
		# 创建轨道UI
		_create_track_views()
		# 更新总音符显示
		_update_total_note_display()
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
		
		# 先加入scene tree，让 _ready() 执行并初始化 @onready 变量
		container.add_child(track_scene)
		container.move_child(bottom, container.get_child_count() - 1)
		
		# 设置基本属性
		track_scene.track_index = track_info.index
		track_scene.track_name = track_info.name
		
		# 现在可以安全地配置轨道UI
		_configure_track_view(track_scene, track_info)
		
		midi_tracks.append(track_scene)
	
	# 更新音源选择
	if soundfont_selector and current_midi_data.use_soundfont:
		_select_soundfont(current_midi_data.use_soundfont)

# 配置轨道视图
func _configure_track_view(track_view: MidiTrack, track_info) -> void:
	# 设置轨道名称
	track_view.track_btn.text = "%s (ID: %d)" % [track_info.name, track_info.index]
	
	# 连接启用按钮
	track_view.enable_btn.toggled.connect(_on_track_enable_toggled.bind(track_info.index))
	
	# 设置初始启用状态
	var is_enabled = track_info.index in current_midi_data.selected_track_indices
	track_view.enable_btn.button_pressed = is_enabled
	
	# 连接静音按钮
	track_view.mute_btn.toggled.connect(_on_track_mute_toggled.bind(track_info.index))
	
	# 连接独奏按钮
	track_view.solo_btn.toggled.connect(_on_track_solo_toggled.bind(track_info.index))
	
	# 连接音量滑块
	track_view.volume_slider.value_changed.connect(_on_track_volume_changed.bind(track_info.index))
	
	# 设置初始音量
	track_view.volume_slider.value = 80
	track_view.volume_label.text = "80%"
	
	# 配置乐器选择
	_configure_instrument_selector(track_view.instruments_option_btn, track_info.index)
	
	# 更新音符显示（这里需要根据实际数据来）
	# track_view.note_display.init_display(track_info.note_count)

# 配置乐器选择器
func _configure_instrument_selector(option_btn: OptionButton, track_index: int) -> void:
	# 这里应该从MIDI数据中获取乐器和音色
	# 暂时添加一些示例乐器
	option_btn.clear()
	option_btn.add_item("钢琴")
	option_btn.add_item("吉他")
	option_btn.add_item("贝斯")
	option_btn.add_item("鼓")
	option_btn.add_item("弦乐")
	
	# 连接选择信号
	option_btn.item_selected.connect(_on_instrument_selected.bind(track_index))

# 更新总音符显示
func _update_total_note_display() -> void:
	if not current_midi_data or current_midi_data.parsed_notes.is_empty():
		return
	
	var total_notes = current_midi_data.parsed_notes.size()
	total_note.init_display(total_notes)

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

# --- 信号回调函数 ---

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

# MIDI音量改变回调
func _on_midi_volume_changed(value: float) -> void:
	if midi_playback_manager == null:
		return
	
	# 转换为dB (-80 ~ 0)
	var volume_db = linear_to_db(value / 100.0)
	midi_playback_manager.set_volume_db(volume_db)
	
	# 更新标签
	_update_midi_volume_label(value)

# 更新MIDI音量标签
func _update_midi_volume_label(value: float) -> void:
	if midi_vol_label:
		midi_vol_label.text = "%d%%" % value

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
			midi_playback_manager.play()
			is_previewing = true
			if preview_button:
				preview_button.text = "停止预览"
		else:
			push_error("Failed to load MIDI for preview")

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
	
	# 更新标签
	track_ui.volume_label.text = "%d%%" % value

# 乐器选择
func _on_instrument_selected(index: int, track_index: int) -> void:
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

# --- MIDI播放器信号回调 ---

func _on_midi_loaded(midi_data: MidiData) -> void:
	print("MIDI loaded: " + midi_data.id)
	# 更新进度条最大范围
	if midi_data.duration_ms > 0:
		progress_bar.max_value = midi_data.duration_ms
		total_time.text = _format_time(midi_data.duration_ms)

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

func _process(delta: float) -> void:
	if is_previewing and midi_playback_manager:
		# 更新当前时间
		progress_bar.value = midi_playback_manager.position_ms
		current_time.text = _format_time(midi_playback_manager.position_ms)

# 格式化时间（毫秒到 MM:SS）
func _format_time(ms: float) -> String:
	var total_seconds = int(ms / 1000)
	var minutes = total_seconds / 60
	var seconds = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]

func _gui_input(event: InputEvent) -> void:
	super._gui_input(event)

# 清理资源
func _exit_tree() -> void:
	# 停止预览
	if is_previewing and midi_playback_manager:
		midi_playback_manager.stop()
	
	# 清空轨道列表
	midi_tracks.clear()
