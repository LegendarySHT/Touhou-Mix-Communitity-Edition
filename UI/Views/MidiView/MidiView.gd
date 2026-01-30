extends Control

# 主要节点
@onready var midi_list: MidiView = $LeftArea/InfoWindow/HBoxC/MidiList
@onready var option_list: VBoxContainer = $RightArea/OptionPanel/VBoxC

# 下面的三个主要按钮
@onready var track_view_btn: Button = $LeftArea/MainBtn/TrackViewBtn
@onready var play_btn: Button = $LeftArea/MainBtn/PlayBtn
@onready var favor_list_btn: Button = $LeftArea/MainBtn/FavorListBtn

# midi信息框左边的三个按钮
@onready var left_btns: Array[Button] = [$LeftArea/InfoWindow/HBoxC/Left/PreviBtn, $LeftArea/InfoWindow/HBoxC/Left/Fold/Btn, $LeftArea/InfoWindow/HBoxC/Left/NextBtn]

# midi信息框右边的两个按钮
@onready var info_btn: Button = $LeftArea/InfoWindow/HBoxC/Right/InfoBtn
@onready var delete_btn: Button = $LeftArea/InfoWindow/HBoxC/Right/DelBtn

# 管理器
@onready var data_manager: DataManager = DataManager.instance
@onready var event_bus: EventBus = EventBus.instance

func _ready() -> void:
	if not (track_view_btn and favor_list_btn and play_btn):
		push_error("[MidiViewInit] Failed to find main btn")
		return

	# 窗口事件
	get_window().size_changed.connect(_on_window_size_changed)
	_on_window_size_changed()

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

	# 连接右侧按钮事件
	info_btn.pressed.connect(_on_info_btn_pressed)
	delete_btn.pressed.connect(_on_del_btn_pressed)

func _on_window_size_changed() -> void:
	set_deferred("size", get_viewport().get_visible_rect().size)

# 点击开始游戏的事件
func _on_click_start_btn() -> void:
	var midi:MidiData = midi_list.get_selection()
	if not midi:
		return
	print("选择歌曲： %d" % midi.name)

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
	print("click info btn")

func _on_del_btn_pressed():
	print("click del btn")
