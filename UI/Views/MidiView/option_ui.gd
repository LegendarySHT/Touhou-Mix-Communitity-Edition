extends Polygon2D

## MIDI播放管理器引用
var midi_playback_manager: MidiPlaybackManager

## 当前选中的MIDI数据
var current_midi_data: MidiData

## 音源选择下拉框引用
var soundfont_selector: OptionButton

## 轨道选择容器引用
var track_selector_container: VBoxContainer

## 音量滑块引用
var volume_slider: HSlider

## 预览按钮引用
var preview_button: Button

## 音轨复选框列表
var track_checkboxes: Array = []

## 预览当前状态
var is_previewing: bool = false

func _ready():
	# 获取管理器引用
	midi_playback_manager = MidiPlaybackManager.instance
	
	# 连接选项卡按钮
	for i in get_node("Option").get_children():
		if i is TextureButton:
			i.toggled.connect(_on_button_toggled.bind(i))
	
	# 初始化MIDI配置UI组件（待UI完成后接入）
	_initialize_midi_config_ui()

## 初始化MIDI配置UI组件
## 此方法留待UI View完成后集成相关UI节点
func _initialize_midi_config_ui() -> void:
	# 这些引用在UI实现后应该通过export或get_node获取
	# 当前为框架实现
	
	# 获取音源选择器
	soundfont_selector = _find_node_by_name("SoundfontSelector", OptionButton)
	if soundfont_selector:
		soundfont_selector.item_selected.connect(_on_soundfont_selected)
		_populate_soundfont_selector()
	
	# 获取轨道选择容器
	track_selector_container = _find_node_by_name("TrackSelectorContainer", VBoxContainer)
	
	# 获取音量滑块
	volume_slider = _find_node_by_name("VolumeSlider", HSlider)
	if volume_slider:
		volume_slider.value_changed.connect(_on_volume_changed)
	
	# 获取预览按钮
	preview_button = _find_node_by_name("PreviewButton", Button)
	if preview_button:
		preview_button.pressed.connect(_on_preview_button_pressed)

## 设置当前MIDI数据
func set_midi_data(midi_data: MidiData) -> void:
	current_midi_data = midi_data
	
	# 更新轨道选择UI
	_update_track_selector()
	
	# 更新音源选择
	if midi_data.use_soundfont and soundfont_selector:
		_select_soundfont(midi_data.use_soundfont)

## 更新轨道选择UI
func _update_track_selector() -> void:
	if track_selector_container == null or midi_playback_manager == null:
		return
	
	if current_midi_data == null:
		return
	
	# 清空之前的复选框
	for checkbox in track_checkboxes:
		checkbox.queue_free()
	track_checkboxes.clear()
	
	# 获取轨道信息
	var track_infos = midi_playback_manager.get_track_infos()
	
	if track_infos.is_empty():
		push_warning("No track info available")
		return
	
	# 为每个轨道创建复选框
	for track_info in track_infos:
		var checkbox = CheckBox.new()
		checkbox.text = "%s (ID: %d)" % [track_info.name, track_info.index]
		checkbox.toggled.connect(_on_track_checkbox_toggled.bind(track_info.index))
		
		# 如果该轨道已选中，勾选复选框
		if track_info.index in current_midi_data.selected_track_indices:
			checkbox.button_pressed = true
		
		track_selector_container.add_child(checkbox)
		track_checkboxes.append(checkbox)

## 填充音源选择器
func _populate_soundfont_selector() -> void:
	if soundfont_selector == null or midi_playback_manager == null:
		return
	
	soundfont_selector.clear()
	
	var soundfonts = midi_playback_manager.get_available_soundfonts()
	for soundfont_name in soundfonts:
		soundfont_selector.add_item(soundfont_name)

## 轨道选择复选框回调
func _on_track_checkbox_toggled(is_checked: bool, track_index: int) -> void:
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

## 音源选择回调
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

## 音量改变回调
func _on_volume_changed(value: float) -> void:
	if midi_playback_manager == null:
		return
	
	# 转换为dB (-80 ~ 0)
	var volume_db = linear_to_db(value / 100.0)
	midi_playback_manager.set_volume_db(volume_db)

## 预览按钮回调
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

## 更新预览（当轨道或音源改变时）
func _update_preview() -> void:
	if not is_previewing:
		return
	
	var current_pos = midi_playback_manager.position_ms
	midi_playback_manager.load_midi(current_midi_data)
	midi_playback_manager.seek(current_pos)

## 辅助函数：根据名称和类型查找节点
func _find_node_by_name(name: String, node_type: Variant = null) -> Node:
	var found_node = find_child(name, true, false)
	
	if found_node and node_type and not found_node.is_class(node_type):
		return null
	
	return found_node

## 选择指定的音源
func _select_soundfont(soundfont_name: String) -> void:
	if soundfont_selector == null:
		return
	
	for i in range(soundfont_selector.item_count):
		if soundfont_selector.get_item_text(i) == soundfont_name:
			soundfont_selector.select(i)
			return

## 清理资源
func _exit_tree() -> void:
	# 停止预览
	if is_previewing and midi_playback_manager:
		midi_playback_manager.stop()
	
	# 清空轨道复选框引用
	track_checkboxes.clear()

## 选项卡切换回调（保留原有功能）
func _on_button_toggled(toggle_on, button):
	
	if toggle_on:
		var selector = get_node("Option/Selector")
		var content = get_node("Content")
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_parallel(true)
	
		if button.get_meta("id") == 1:
			tween.tween_property(selector, "position", Vector2(-174, -100), 0.15)
			tween.tween_property(content, "position", Vector2(150, 130), 0.15)
		elif button.get_meta("id") == 2:
			tween.tween_property(selector, "position", Vector2(18, -100), 0.15)
			tween.tween_property(content, "position", Vector2(-450, 130), 0.15)
		elif button.get_meta("id") == 3:
			tween.tween_property(selector, "position", Vector2(202, -100), 0.15)
			tween.tween_property(content, "position", Vector2(-1050, 130), 0.15)
