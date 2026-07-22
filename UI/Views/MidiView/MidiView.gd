extends Control

# 主要节点
@onready var midi_list: MidiView = $LeftArea/InfoWindow/HBoxC/MidiList
@onready var option_list: VBoxContainer = $RightArea/OptionPanel/VBoxC
@onready var description: RichTextLabel = $LeftArea/InfoWindow/HBoxC/Description

# 下面的三个主要按钮
@onready var main_btns: HBoxContainer = $LeftArea/MainBtn
@onready var track_view_btn: Button = $LeftArea/MainBtn/TrackViewBtn
@onready var play_btn: Button = $LeftArea/MainBtn/PlayBtn
@onready var favor_list_btn: Button = $LeftArea/MainBtn/FavorListBtn

# RightArea 滑动面板
@onready var right_area: Control = $RightArea
@onready var option_panel: PanelContainer = $RightArea/OptionPanel
@onready var favor_panel: PanelContainer = $RightArea/FavorPanel

# 收藏夹按钮图标
const ICON_FAVOR_LIST := "res://Resources/icon/midiInfoPage/addToList.png"
const ICON_BACK := "res://Resources/icon/back.png"

# 收藏夹面板状态
var _favor_panel_visible: bool = false
var _is_animating: bool = false
# 上一次 midi_list 选中索引，用于检测内部切换
var _last_midi_selection: int = -1

# midi信息框左边的三个按钮
@onready var left_btns: Array[Button] = [$LeftArea/InfoWindow/HBoxC/Left/PreviBtn, $LeftArea/InfoWindow/HBoxC/Left/Fold/Btn, $LeftArea/InfoWindow/HBoxC/Left/NextBtn]

# midi信息框右边的两个按钮
@onready var info_btn: Button = $LeftArea/InfoWindow/HBoxC/Right/InfoBtn
@onready var delete_btn: Button = $LeftArea/InfoWindow/HBoxC/Right/DelBtn

# 显示midi的各种数值的地方，但是更新不在这个脚本进行
@onready var detail_data_area: GridContainer = $LeftArea/DetailData
# 点击info按钮后显示以下按钮组，用于跳转到浏览器
@onready var redirect_btns: FlowContainer = $LeftArea/RedirectButtons

# 管理器
@onready var data_manager: DataManager = DataMGR
@onready var event_bus: EventBus = EvtBus

var showing_info: bool = false

func _ready() -> void:
	if not (track_view_btn and favor_list_btn and play_btn):
		push_error("[MidiViewInit] Failed to find main btn")
		return

	# 连接事件
	event_bus.song_selected.connect(_on_song_selected)
	event_bus.midi_selected.connect(_on_midi_selected)
	# 监听 UI 状态变化，进入 MIDI_VIEW 时若 FavorPanel 可见则刷新
	UiStatMGR.state_changed.connect(_on_state_changed)

	# 连接主要按钮事件
	play_btn.pressed.connect(_on_click_start_btn)
	track_view_btn.pressed.connect(_on_click_track_btn)
	favor_list_btn.pressed.connect(_on_click_favor_list_btn)

	# 按钮的焦点逻辑
	for i in left_btns:
		i.focus_entered.connect(func():
			i.focus_neighbor_right = midi_list.get_focus_node_path()
		)
	play_btn.focus_entered.connect(func():
		play_btn.focus_neighbor_top = midi_list.get_focus_node_path()
	)

	for btn in main_btns.get_children():
		btn.focus_entered.connect((func (b):
			for i in main_btns.get_children():
				i.z_index = 0
			b.z_index += 1).bind(btn)
			)

	# 连接右侧按钮事件
	info_btn.pressed.connect(_on_info_btn_pressed)
	delete_btn.pressed.connect(_on_del_btn_pressed)

# MIDI 选择变化：加载列表，若收藏夹面板可见则同步刷新
func _on_midi_selected(_midi_id: String, midi: MidiData) -> void:
	midi_list.load_midi([midi])
	if _favor_panel_visible and favor_panel:
		favor_panel.show_with_midi(midi)


# 歌曲选择：加载该歌曲的 midi 列表，加载完成后若 FavorPanel 可见则刷新
func _on_song_selected(song_id: String) -> void:
	await midi_list.load_midi(data_manager.get_midis_by_song(song_id))
	if _favor_panel_visible and favor_panel:
		var midi: MidiData = midi_list.get_selection()
		if midi:
			favor_panel.show_with_midi(midi)


# UI 状态变化：进入 MIDI_VIEW 时若 FavorPanel 可见，用当前选中 midi 刷新
func _on_state_changed(_old_state: int, new_state: int) -> void:
	if new_state == UIStateManager.UIState.MIDI_VIEW and _favor_panel_visible and favor_panel:
		var midi: MidiData = midi_list.get_selection()
		if midi:
			favor_panel.show_with_midi(midi)
		_last_midi_selection = midi_list.selected_item


# 轮询检测 midi_list 内部切换（prev/next/list 展开按钮不发出信号）
# FavorPanel 可见时，若选中项变化则同步刷新操作对象
func _process(_delta: float) -> void:
	if not _favor_panel_visible or not favor_panel:
		return
	var cur_sel: int = midi_list.selected_item
	if cur_sel != _last_midi_selection and cur_sel != -1:
		_last_midi_selection = cur_sel
		var midi: MidiData = midi_list.get_selection()
		if midi:
			favor_panel.show_with_midi(midi)

# 点击开始游戏的事件
func _on_click_start_btn() -> void:
	var midi:MidiData = midi_list.get_selection()
	if not midi:
		return
	print("选择歌曲： %s" % midi.name)

	EvtBus.start_game_with.emit(midi)
	UiStatMGR.change_state(UIStateManager.UIState.PLAY_VIEW)

func _on_click_track_btn():
	var midi:MidiData = midi_list.get_selection()
	if not midi:
		return
	
	UiStatMGR.change_state(UIStateManager.UIState.TRACK_VIEW)
	EvtBus.enter_track_view_with.emit.call_deferred(midi)

# 收藏夹按钮：切换 RightArea 中 OptionPanel 和 FavorPanel 的滑动显示
func _on_click_favor_list_btn() -> void:
	if _is_animating:
		return
	if _favor_panel_visible:
		_hide_favor_panel()
	else:
		var midi: MidiData = midi_list.get_selection()
		if not midi:
			return
		favor_panel.show_with_midi(midi)
		_show_favor_panel()


# 显示收藏夹面板：OptionPanel 淡出，FavorPanel 淡入
func _show_favor_panel() -> void:
	_is_animating = true
	_favor_panel_visible = true
	# 同步当前选中索引，作为后续 _process 检测内部切换的基准
	_last_midi_selection = midi_list.selected_item
	favor_list_btn.icon = load(ICON_BACK)
	# 先重置透明度
	option_panel.modulate.a = 1.0
	favor_panel.modulate.a = 0.0
	favor_panel.visible = true
	var tween := create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(option_panel, "modulate:a", 0.0, 0.3)
	tween.tween_property(favor_panel, "modulate:a", 1.0, 0.3)
	await tween.finished
	option_panel.visible = false
	_is_animating = false


# 隐藏收藏夹面板：FavorPanel 淡出，OptionPanel 淡入
func _hide_favor_panel() -> void:
	_is_animating = true
	_favor_panel_visible = false
	favor_list_btn.icon = load(ICON_FAVOR_LIST)
	favor_panel.cancel_create()
	option_panel.visible = true
	option_panel.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(favor_panel, "modulate:a", 0.0, 0.3)
	tween.tween_property(option_panel, "modulate:a", 1.0, 0.3)
	await tween.finished
	favor_panel.visible = false
	_is_animating = false

# 显示简介什么的
func _on_info_btn_pressed():
	if midi_list.selected_item == -1:
		return
	
	showing_info = not showing_info
	# 窗口部分
	description.visible = showing_info
	midi_list.visible = not showing_info

	# 禁用按钮，防止点击
	for btn in left_btns:
		btn.disabled = showing_info
	delete_btn.disabled = showing_info

	midi_list.get_parent().get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL if showing_info else SIZE_FILL

	# 数据区
	detail_data_area.visible = not showing_info
	redirect_btns.visible = showing_info

	midi_list.need_snap = true

func _on_del_btn_pressed():
	var window = PopupWindow.instance
	var midi_to_del: MidiData = midi_list.get_selection()

	if not midi_to_del:
		window.set_message("请先选择歌曲")
		return

	# 填充三档删除选项
	window.option_btn.clear()
	window.option_btn.add_item("删除人声音频", 0)
	window.option_btn.add_item("重置设定", 1)
	window.option_btn.add_item("删除曲包", 2)
	window.show_del_selection()

	await window.window_close
	if not window.confirm:
		return

	var chart_id: String = midi_to_del.file_hash if not midi_to_del.file_hash.is_empty() else midi_to_del.id
	var json_path: String = FileSystemManager.instance.get_chart_json_path(chart_id)

	match window.option_btn.get_selected_id():
		0: # 删除人声音频文件，并清除 JSON 内人声相关设置
			var vocal_path: String = midi_to_del.vocal_file_path
			if vocal_path.is_empty():
				window.set_message("该谱面没有设置人声音频")
				return
			if not FileSystemManager.instance.delete_file(vocal_path):
				window.set_message("删除人声文件失败")
				return
			# 更新内存
			midi_to_del.vocal_file_path = ""
			midi_to_del.vocal_offset_ms = 0
			midi_to_del.vocal_volume = 50
			# 写回 JSON（merge 模式，仅覆盖人声相关字段）
			if not json_path.is_empty():
				var runtime_patch := {
					"vocal_file_path": "",
					"vocal_offset_ms": 0,
					"vocal_volume": 50
				}
				ConfigManager.instance.save_json_file(json_path, {"_runtime": runtime_patch}, true)
			GLogger.info("已删除人声音频: %s" % vocal_path, "MidiView")

		1: # 重置设定：清除音轨/音量/静音/独奏配置，保留人声路径
			# 更新内存
			midi_to_del.selected_track_indices.clear()
			midi_to_del.selected_track_configs.clear()
			midi_to_del.track_channel_mute_state.clear()
			midi_to_del.track_channel_volume_config.clear()
			midi_to_del.track_channel_instrument_overrides.clear()
			midi_to_del.solo_pairs.clear()
			midi_to_del.midi_volume = 50
			# 从 JSON 中整体移除 _runtime 块
			if not json_path.is_empty():
				var json_dict: Dictionary = ConfigManager.instance.load_json_file(json_path)
				json_dict.erase("_runtime")
				ConfigManager.instance.save_json_file(json_path, json_dict, false)
			GLogger.info("已重置谱面设定: %s" % midi_to_del.name, "MidiView")

		2: # 删除曲包：删除整个文件夹，并从内存中移除
			var folder_path: String = FileSystemManager.instance.get_chart_folder_path(chart_id)
			if folder_path.is_empty():
				window.set_message("找不到曲包文件夹路径")
				return
			if not FileSystemManager.instance.delete_directory_recursive(folder_path):
				window.set_message("删除曲包文件夹失败")
				return
			FileSystemManager.instance.remove_from_charts_index(chart_id)
			# 删除前先记录 song_id 和 album_id，用于判断是否被级联删除
			var song_id_before: String = midi_to_del.song_data.id if midi_to_del.song_data else ""
			var album_id_before: String = midi_to_del.album_data.id if midi_to_del.album_data else ""
			var deleted_id: String = midi_to_del.id
			DataMGR.remove_midi(chart_id)
			# 判断 Song 和 Album 是否被级联删除
			var song_still_exists: bool = not song_id_before.is_empty() and DataMGR.songs.has(song_id_before)
			var album_still_exists: bool = not album_id_before.is_empty() and DataMGR.albums.has(album_id_before)
			
			if song_still_exists:
				# Song 仍存在，正常返回 SongView
				midi_list.remove_selected_midi()
			elif album_still_exists:
				# Song 被删除但 Album 仍存在，重新加载该 Album 的 SongView（空列表）
				midi_list.current_midis.erase(midi_to_del)
				midi_list._refresh_display()
				EvtBus.album_selected.emit(album_id_before)
				UiStatMGR.go_back()
			else:
				# Song 和 Album 都被删除，直接跳回 AlbumView
				UiStatMGR.go_back_to(UIStateManager.UIState.ALBUM_VIEW)
			EvtBus.midi_deleted.emit(deleted_id)
			GLogger.info("已删除曲包: %s" % midi_to_del.name, "MidiView")
