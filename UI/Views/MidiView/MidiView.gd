extends HBoxContainer

# 主要节点
@onready var midi_list: MidiView = $LeftArea/InfoWindow/HBoxC/MidiList
@onready var option_list: VBoxContainer = $OptionPanel/VBoxC
@onready var description: RichTextLabel = $LeftArea/InfoWindow/HBoxC/Description

# 下面的三个主要按钮
@onready var main_btns: HBoxContainer = $LeftArea/MainBtn
@onready var track_view_btn: Button = $LeftArea/MainBtn/TrackViewBtn
@onready var play_btn: Button = $LeftArea/MainBtn/PlayBtn
@onready var favor_list_btn: Button = $LeftArea/MainBtn/FavorListBtn

# RightArea 滑动面板
@onready var option_panel: PanelContainer = $OptionPanel
@onready var favor_panel: PanelContainer = $OptionPanel/VBoxC/TabView/FavorPanel
@onready var tab_container: TabContainer = $OptionPanel/VBoxC/TabView
@onready var tab_btn: HBoxContainer = $OptionPanel/VBoxC/TabBtn

# 收藏夹按钮图标
const ICON_FAVOR_LIST := "res://Resources/icon/midiInfoPage/addToList.png"
const ICON_BACK := "res://Resources/icon/midiInfoPage/back.png"

# 收藏夹面板状态
var _favor_panel_visible: bool = false
var _prev_tab_idx: int = 0
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
func _on_state_changed(old_state: int, new_state: int) -> void:
	if new_state == UIStateManager.UIState.MIDI_VIEW and _favor_panel_visible and favor_panel:
		var midi: MidiData = midi_list.get_selection()
		if midi:
			favor_panel.show_with_midi(midi)
		_last_midi_selection = midi_list.selected_item
	# 退出 MIDI_VIEW 回歌曲列表时释放列表项
	if old_state == UIStateManager.UIState.MIDI_VIEW and new_state != UIStateManager.UIState.MIDI_VIEW:
		if new_state != UIStateManager.UIState.TRACK_VIEW and new_state != UIStateManager.UIState.PLAY_VIEW:
			_cleanup()

## 释放视图内部资源（midi 列表项），保留节点壳和信号连接
## 重新进入时由 song_selected 信号重新加载
func _cleanup() -> void:
	if midi_list:
		midi_list.clear_items()


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

	# 先 change_state 触发 PlayView 懒加载（_ready 连接 start_game_with 信号），
	# 再用 call_deferred emit，确保信号不丢失（与 _on_click_track_btn 模式一致）
	UiStatMGR.change_state(UIStateManager.UIState.PLAY_VIEW)
	EvtBus.start_game_with.emit.call_deferred(midi)

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


# 显示收藏夹面板：两阶段动画，避免布局跳变
func _show_favor_panel() -> void:
	_is_animating = true
	_favor_panel_visible = true
	_last_midi_selection = midi_list.selected_item
	favor_list_btn.icon = load(ICON_BACK)
	_prev_tab_idx = tab_container.current_tab
	var current_page := tab_container.get_tab_control(_prev_tab_idx) if _prev_tab_idx >= 0 else null
	# FavorPanel 提前就位（布局占位，视觉偏移到下方）
	favor_panel.visible = true
	favor_panel.modulate.a = 0.0
	favor_panel.offset_transform_position.y = 800
	# 第一阶段：TabBtn 淡出 + 高度收缩，布局空间平滑释放
	var tween1 := create_tween().set_parallel(true)
	tween1.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween1.tween_property(tab_btn, "modulate:a", 0.0, 0.2)
	tween1.tween_property(tab_btn, "custom_minimum_size:y", 0, 0.2)
	if current_page:
		tween1.tween_property(current_page, "modulate:a", 0.0, 0.2)
	await tween1.finished
	tab_btn.visible = false
	# 第二阶段：FavorPanel 从下方滑入 + 淡入
	var tween2 := create_tween().set_parallel(true)
	tween2.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween2.tween_property(favor_panel, "modulate:a", 1.0, 0.3)
	tween2.tween_property(favor_panel, "offset_transform_position:y", 0, 0.4)
	await tween2.finished
	tab_container.current_tab = 3
	_is_animating = false


# 隐藏收藏夹面板：两阶段反向动画
func _hide_favor_panel(exiting_page: bool = false) -> void:
	_is_animating = true
	_favor_panel_visible = false
	favor_list_btn.icon = load(ICON_FAVOR_LIST)
	favor_panel.cancel_create()
	var target_page := tab_container.get_tab_control(_prev_tab_idx) if _prev_tab_idx >= 0 else null
	if not target_page:
		push_error("[MidiView] Invalid target page index: %d" % _prev_tab_idx)
	if not exiting_page:
		# 第一阶段：FavorPanel 滑出到下方 + 淡出
		var tween1 := create_tween().set_parallel(true)
		tween1.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tween1.tween_property(favor_panel, "modulate:a", 0.0, 0.2)
		tween1.tween_property(favor_panel, "offset_transform_position:y", 800, 0.3)
		await tween1.finished
	else:
		favor_panel.modulate.a = 0.0
		favor_panel.offset_transform_position.y = 800
	tab_container.current_tab = _prev_tab_idx
	# 第二阶段：TabBtn 高度恢复 + 淡入 + 目标标签页淡入
	tab_btn.visible = true
	tab_btn.modulate.a = 1.0 if exiting_page else 0.0
	tab_btn.custom_minimum_size.y = 120 if exiting_page else 0
	
	target_page.visible = true
	target_page.modulate.a = 1.0 if exiting_page else 0.0
	if not exiting_page:
		var tween2 := create_tween().set_parallel(true)
		tween2.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tween2.tween_property(tab_btn, "modulate:a", 1.0, 0.25)
		tween2.tween_property(tab_btn, "custom_minimum_size:y", 120, 0.25)
		tween2.tween_property(target_page, "modulate:a", 1.0, 0.25)
		await tween2.finished
	_is_animating = false

	if exiting_page:
		get_node("OptionPanel/VBoxC/TabBtn/Rank").button_pressed=true

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
		window.show_message("请先选择歌曲")
		return

	# 填充三档删除选项
	if not await window.show_message("请选择要删除的内容", true, ["删除曲包", "删除设定", "删除人声音频"]):
		return

	var chart_id: String = midi_to_del.file_hash if not midi_to_del.file_hash.is_empty() else midi_to_del.id
	var json_path: String = FileSystemManager.instance.get_chart_json_path(chart_id)

	match window.get_selected():
		"删除人声音频": # 删除人声音频文件，并清除 JSON 内人声相关设置
			var vocal_path: String = midi_to_del.vocal_file_path
			if vocal_path.is_empty():
				window.show_message("该谱面没有设置人声音频")
				return
			if not FileSystemManager.instance.delete_file(vocal_path):
				window.show_message("删除人声文件失败")
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

		"删除设定": # 重置设定：清除音轨/音量/静音/独奏配置，保留人声路径
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

		"删除曲包": # 删除曲包：删除整个文件夹，并从内存中移除
			if not FileSystemManager.instance.delete_chart(chart_id):
				window.show_message("删除曲包文件夹失败")
				return
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
				# 确保 SS 节点被清理（直接跳转时可能跳过 SongView 的退出流程）
				var ss_node = get_node_or_null("/root/Main/skew/SS")
				if is_instance_valid(ss_node):
					ss_node.queue_free()
				UiStatMGR.go_back_to(UIStateManager.UIState.ALBUM_VIEW)
			EvtBus.midi_deleted.emit(deleted_id)
			GLogger.info("已删除曲包: %s" % midi_to_del.name, "MidiView")

# 退出界面时恢复页面状态
func restore_panel_state() -> void:
	if _favor_panel_visible:
		_hide_favor_panel(true)
	get_node("OptionPanel/VBoxC/TabBtn/Rank").button_pressed=true
