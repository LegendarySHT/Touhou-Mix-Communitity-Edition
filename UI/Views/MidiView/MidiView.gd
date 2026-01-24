## MIDI视图
## 显示选中歌曲下的所有MIDI谱面列表
extends BaseScrollList

class_name MidiView

## 当前显示的MIDI列表
var current_midis: Array[MidiData] = []

var last_selection:int = -1 # 上一次选中的节点

var track_view_btn: TextureButton
var play_btn: TextureButton
var favor_list_btn: TextureButton

## 管理器引用
@onready var data_manager: DataManager = DataManager.instance
@onready var event_bus: EventBus = EventBus.instance
@onready var state_manager = UIStateManager.instance

# 路径
var INDICATOR = "/root/Main/InfoUI/Right/Right/Indicator"

func _init_btn():
	var main_btn_area = get_parent().get_parent().get_node("MainButton")
	track_view_btn = main_btn_area.get_node("Left/TrackViewBtn")
	favor_list_btn = main_btn_area.get_node("Right/FavorListBtn")
	play_btn = main_btn_area.get_node("PlayBtn")

	if not (track_view_btn and favor_list_btn and play_btn):
		print("Failed to find main btn")
		return

	play_btn.pressed.connect(_on_click_start_btn)

func _ready() -> void:	
	# 获取管理器引用
	if not data_manager or not event_bus:
		push_error("MidiView: Missing manager instances")
		return
	_init_btn()

	work_state = UIStateManager.UIState.MIDI_VIEW
	item_height = 150
	item_spacing = 4
	snap_offset_y = 85 #+ int(item_height)

	# 连接事件
	event_bus.song_selected.connect(_load_midis)
	event_bus.midi_selected.connect(_load_midi)

	super._ready()

func _load_midi(_midi_id: String, midi:MidiData) -> void:
	if not data_manager:
		return

	current_midis = [midi]
	_refresh_display()

## 加载指定歌曲的MIDI谱面
func _load_midis(song_id: String) -> void:
	if not data_manager:
		return

	current_midis = data_manager.get_midis_by_song(song_id)
	if current_midis:
		_refresh_display()

## 刷新显示
func _refresh_display() -> void:
	# 清空现有项
	_clear_list()
	
	# 添加新项
	var counter = 0
	var bg = ButtonGroup.new()

	print("[MidiView] Refreshing display with %d midis" % current_midis.size())
	for midi in current_midis:
		var item = create_and_add_item(midi.id, "midi")
		print("[MidiView] Created item: %s, type: %s" % [item, item.get_class() if item else "null"])
		if item:
			# 添加指示器点
			var point = ColorRect.new()
			point.name = "Indicator"
			point.custom_minimum_size = Vector2(20, 20)
			point.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			point.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			point.color = Color.WHITE

			var indicator = get_node(INDICATOR)
			indicator.add_child(point)

			print("[MidiView] Calling setup_with_midi for: %s" % midi.name)
			if item.has_method("setup_with_midi"):
				item.setup_with_midi(self, midi, counter, bg)
			else:
				print("[MidiView] ERROR: Item does not have setup_with_midi method!")
			counter += 1


	print("加载了%d个MIDI谱面" % counter)

func _get_selection() -> MidiData:
	if selected_item == -1:
		print("未选择Midi")
		return null
	
	return current_midis[selected_item]

# 点击开始游戏的事件
func _on_click_start_btn() -> void:
	var midi:MidiData = _get_selection()
	if not midi:
		return
	print("选择歌曲： %d" % midi.name)

	EventBus.instance.start_game_with.emit(midi)
	UIStateManager.instance.change_state(UIStateManager.UIState.PLAY_VIEW)

func _on_click_track_btn():
	var midi:MidiData = _get_selection()
	if not midi:
		return
	
	EventBus.instance.enter_track_view_with.emit(midi)
	UIStateManager.instance.change_state(UIStateManager.UIState.TRACK_VIEW)

func _on_button_toggled(_toggled_on: bool, _index):
	pass

## 清空列表
func _clear_list() -> void:
	if container == null:
		return
	
	for item in container.get_children():
		item.queue_free()
	
	list_items.clear()
	
	# 清空指示器
	var indicator = get_node(INDICATOR)
	if indicator:
		for child in indicator.get_children():
			child.free() # 因为初始化指示器时根据索引位置来设置颜色的，所以得立即清除
	
	selected_item = -1

## 列表项选中回调
func _on_item_selected(item_id: String) -> void:
	if event_bus:
		# 查找对应的MIDI
		for midi in current_midis:
			if midi.id == item_id:
				event_bus.emit_midi_selected(item_id, midi)
				break

func _input(event):
	if event is InputEventKey and event.pressed and get_snap_node().is_selected:
		if event.keycode in [KEY_UP, KEY_W, KEY_DOWN, KEY_S]:
			accept_event()
	super._input(event)

var waiting: bool = false

func _process(_delta):
	super._process(_delta)

	# 吸附	
	if not (is_dragging_list or need_snap) and selected_item != -1 and abs(get_snap_node().global_position.y - item_height + snap_offset_y) > 7:
		need_snap = true
	
	if abs(_mouse_delta) > 50 and is_dragging_list and not waiting:
		waiting = true
		await wait_dragging()
		var direction:int = 1 if _mouse_delta < 0.0 else -1
		scroll_velocity = 0.0
		need_snap = true
		select_item(selected_item + direction)		

func wait_dragging():
	while Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		await get_tree().create_timer(0.2).timeout
	waiting = false
	return true

func _show_midi_list(_index: int = 0) -> void:
	if current_midis.size() == 1:
		return

	if selected_item != -1:
		get_snap_node().button.button_pressed = false
		last_selection = selected_item
		selected_item = -1
	else:
		selected_item = last_selection
		get_snap_node().button.button_pressed = true
		last_selection = -1

func _previous() -> void:
	if current_midis.size() == 1:
		return

	select_item(selected_item - 1)

func _next() -> void:
	if current_midis.size() == 1:
		return

	select_item(selected_item + 1)
