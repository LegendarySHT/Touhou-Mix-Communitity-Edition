## MIDI视图
## 显示选中歌曲下的所有MIDI谱面列表
extends BaseScrollList

class_name MidiView

## 当前显示的MIDI列表
var current_midis: Array[MidiData] = []

var last_selection:int = -1 # 上一次选中的节点

# 路径
const INDICATOR = "/root/Main/skew/C/InfoUI/LeftArea/InfoWindow/HBoxC/Right/Center/Indicator"
const PREVI_BTN = "/root/Main/skew/C/InfoUI/LeftArea/InfoWindow/HBoxC/Left/PreviBtn"
const INFO_BTN = "/root/Main/skew/C/InfoUI/LeftArea/InfoWindow/HBoxC/Right/InfoBtn"

func _ready() -> void:
	work_state = UIStateManager.UIState.MIDI_VIEW
	item_height = 150
	item_spacing = 4
	snap_offset_y = 0

	super._ready()

# 加载midi
func load_midi(midis:Array[MidiData]) -> void:
	current_midis = midis
	_refresh_display()
	_setup_focus_neighbor()

func _setup_focus_neighbor():
	if container == null:
		return

	var left_node_path = get_node(PREVI_BTN).get_path()
	var right_node_path = get_node(INFO_BTN).get_path()
	
	var ln = container.get_child(-1).button
	var cn
	for i in container.get_children():
		cn = i.button
		ln.focus_neighbor_bottom = cn.get_path()

		cn.focus_neighbor_left = left_node_path
		cn.focus_neighbor_right = right_node_path
		cn.focus_neighbor_top = ln.get_path()
		ln = cn

# 返回当前的选择
func get_selection() -> MidiData:
	if selected_item == -1:
		print("未选择Midi")
		return null
	
	return current_midis[selected_item]

func get_focus_node_path() -> NodePath:
	var node = get_selected_node()
	if node:
		return node.button.get_path()
	return ""
 
## 清空列表
func _clear_list() -> void:
	clear_items()
	
	# 清空指示器
	var indicator = get_node(INDICATOR)
	if indicator:
		for child in indicator.get_children():
			child.free() # 因为初始化指示器时根据索引位置来设置颜色的，所以得立即清除
	
	selected_item = -1

func _gui_input(event):
	super._gui_input(event)

var waiting: bool = false

func _process(_delta):
	super._process(_delta)

	# 吸附	
	if not (is_dragging_list or snap_tween or selected_item == -1) and abs(scroll_vertical - get_selected_node().position.y + snap_offset_y) > 7:
		need_snap = true
	
	if abs(_mouse_delta) > 50 and is_dragging_list and not waiting and selected_item != -1:
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
		get_selected_node().button.button_pressed = false
		last_selection = selected_item
		selected_item = -1
	else:
		selected_item = last_selection
		get_selected_node().button.button_pressed = true
		last_selection = -1

func _previous() -> void:
	if current_midis.size() != 1:
		select_item(selected_item - 1)

func _next() -> void:
	if current_midis.size() != 1:
		select_item(selected_item + 1)

## 刷新显示
func _refresh_display() -> void:
	# 清空现有项
	_clear_list()
	
	# 添加新项
	var counter = 0
	var bg = ButtonGroup.new()
	var indicator = get_node(INDICATOR)

	for midi in current_midis:
		var item = create_and_add_item(midi.id, "midi")
		if item:
			# 添加指示器点
			var point = ColorRect.new()
			point.name = "Indicator"
			point.custom_minimum_size = Vector2(20, 20)
			point.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			point.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			point.color = Color.WHITE

			indicator.add_child(point)

			item.setup_with_midi(self, midi, counter, bg)
			counter += 1

func remove_selected_midi():
	current_midis.erase(get_selection())
	_refresh_display()

	if not list_items.size():
		UIStateManager.instance.go_back()
