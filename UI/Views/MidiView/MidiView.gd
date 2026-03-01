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
@onready var data_manager: DataManager = DataManager.instance
@onready var event_bus: EventBus = EventBus.instance

var showing_info: bool = false

func _ready() -> void:
	if not (track_view_btn and favor_list_btn and play_btn):
		push_error("[MidiViewInit] Failed to find main btn")
		return

	# 连接事件
	event_bus.song_selected.connect(func (song_id: String):
		midi_list.load_midi(data_manager.get_midis_by_song(song_id))
	)
	event_bus.midi_selected.connect(func (_midi_id: String, midi:MidiData):
		midi_list.load_midi([midi])
	)

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

# 点击开始游戏的事件
func _on_click_start_btn() -> void:
	var midi:MidiData = midi_list.get_selection()
	if not midi:
		return
	print("选择歌曲： %s" % midi.name)

	EventBus.instance.start_game_with.emit(midi)
	UIStateManager.instance.change_state(UIStateManager.UIState.PLAY_VIEW)

func _on_click_track_btn():
	var midi:MidiData = midi_list.get_selection()
	if not midi:
		return
	
	EventBus.instance.enter_track_view_with.emit(midi)
	UIStateManager.instance.change_state(UIStateManager.UIState.TRACK_VIEW)

# 跳转到收藏夹
func _on_click_favor_list_btn():
	pass

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
			GameLogger.instance.info("已删除人声音频: %s" % vocal_path, "MidiView")

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
			GameLogger.instance.info("已重置谱面设定: %s" % midi_to_del.name, "MidiView")

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
			DataManager.instance.remove_midi(chart_id)
			# 判断 Song 和 Album 是否被级联删除
			var song_still_exists: bool = not song_id_before.is_empty() and DataManager.instance.songs.has(song_id_before)
			var album_still_exists: bool = not album_id_before.is_empty() and DataManager.instance.albums.has(album_id_before)
			
			if song_still_exists:
				# Song 仍存在，正常返回 SongView
				midi_list.remove_selected_midi()
			elif album_still_exists:
				# Song 被删除但 Album 仍存在，重新加载该 Album 的 SongView（空列表）
				midi_list.current_midis.erase(midi_to_del)
				midi_list._refresh_display()
				EventBus.instance.album_selected.emit(album_id_before)
				UIStateManager.instance.go_back()
			else:
				# Song 和 Album 都被删除，直接跳回 AlbumView
				UIStateManager.instance.go_back_to(UIStateManager.UIState.ALBUM_VIEW)
			EventBus.instance.midi_deleted.emit(deleted_id)
			GameLogger.instance.info("已删除曲包: %s" % midi_to_del.name, "MidiView")
