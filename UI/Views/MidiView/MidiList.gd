## MIDI视图
## 显示选中歌曲下的所有MIDI谱面列表
extends BaseScrollList

class_name MidiView

## 当前显示的MIDI列表
var current_midis: Array[MidiData] = []

var last_selection:int = -1 # 上一次选中的节点
var _collapsed: bool = false # 列表是否处于收起状态
var _prev_scroll: int = 0  # 上帧滚动位置，变化说明有人在动列表

@onready var indicator = $/root/Main/skew/C/MidiView/LeftArea/InfoWindow/HBoxC/Right/Center/Indicator
@onready var  previ_btn = $/root/Main/skew/C/MidiView/LeftArea/InfoWindow/HBoxC/Left/PreviBtn
@onready var info_btn = $/root/Main/skew/C/MidiView/LeftArea/InfoWindow/HBoxC/Right/InfoBtn

# MidiView
@onready var midi_view = $/root/Main/skew/C/MidiView

func _ready() -> void:
	work_state = UIStateManager.UIState.MIDI_VIEW
	snap_offset_y = 0

	super._ready()

# 加载midi
func load_midi(midis:Array[MidiData]) -> void:
	current_midis = midis
	_refresh_display()
	_setup_focus_neighbor()
	
	await get_tree().process_frame
	_collapsed = false
	_prev_scroll = scroll_vertical  # 重置滚动追踪
	select_item(0)
	for item in list_items:
		item.set_expanded(true)
	need_snap = true

func _setup_focus_neighbor():
	if container == null:
		return

	var left_node_path = previ_btn.get_path()
	var right_node_path = info_btn.get_path()
	
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
	if indicator:
		for child in indicator.get_children():
			child.free() # 因为初始化指示器时根据索引位置来设置颜色的，所以得立即清除

	selected_item = -1

## 展开状态下被滚动了 → 立即收起
func _process(delta):
	super._process(delta)
	if not _collapsed and not _snap_active and scroll_vertical != _prev_scroll:
		_show_midi_list()
	_prev_scroll = scroll_vertical

func _show_midi_list(_index: int = -1) -> void:
	if current_midis.size() == 1:
		return
	if not _collapsed:
		# 展开 → 收起全部
		_collapsed = true
		if selected_item != -1:
			last_selection = selected_item
			get_selected_node().button.button_pressed = false
		selected_item = -1
		for item in list_items:
			item.set_expanded(false)
		need_snap = false
	else:
		# 收起 → 展开全部
		_collapsed = false
		_prev_scroll = scroll_vertical  # 重置滚动追踪
		var target := _index if _index >= 0 else last_selection
		if target >= 0 and target < list_items.size():
			selected_item = target
			last_selection = target
			get_selected_node().button.button_pressed = true
		for item in list_items:
			item.set_expanded(true)
		need_snap = true
		# 指示器移到选中项
		if indicator and selected_item != -1:
			create_tween().tween_property(indicator, "position", Vector2(30, 100 - selected_item * 24), 0.35)

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
	var removed_index = selected_item
	current_midis.erase(get_selection())
	_refresh_display()
	_setup_focus_neighbor()

	if not list_items.size():
		UiStatMGR.go_back()
		return

	# 重建后默认选中并展开剩余项（与 load_midi 行为一致）
	await get_tree().process_frame
	_collapsed = false
	_prev_scroll = scroll_vertical
	var target = mini(removed_index, list_items.size() - 1)
	select_item(target)
	for item in list_items:
		item.set_expanded(true)
	if indicator:
		indicator.position = Vector2(30, 100 - selected_item * 24)
	need_snap = true
