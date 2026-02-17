## 可滚动列表的基类
## 处理通用的滚动、吸附、虚拟化等功能
extends ScrollContainer

class_name BaseScrollList

## 容器（放置列表项的VBox或HBox）
@export var container_path: NodePath
@onready var container: Container = get_node(container_path) if container_path else null

## 列表项场景或预制体
@export var list_item_class: Variant

## 列表项的高度
@export var item_height: float = 100.0

## 列表项间距
@export var item_spacing: float = 10.0

## 工作状态，当不处于该状态时停止处理操作
var work_state: UIStateManager.UIState = UIStateManager.UIState.NONE

## 当前滚动速度
var scroll_velocity: float = 0.0:
	set(v):
		var sv = scroll_velocity
		if abs(v) > max_velocity:
			v = max_velocity * sign(v)
		scroll_velocity = v
		if abs(v) > abs(sv) or v == 0:
			if _velocity_decrease_tween:
				_velocity_decrease_tween.kill()
				_velocity_decrease_tween = null

			if v == 0:
				return

			_velocity_decrease_tween = create_tween()
			_velocity_decrease_tween.tween_property(self, "scroll_velocity", 0 , 3)

		
var _velocity_decrease_tween: Tween = null

## 上一帧的滚动位置
var last_bar_position: int = 0

## 是否正在滚动
var is_dragging_list: bool = false # 区分点击事件,当鼠标按下并有位移时为true
var _is_dragging_list: bool = false # 当鼠标按下时为true
var is_dragging_bar: bool = false # 当鼠标拖动滚动条时为true
var is_wheel_scrolling: bool = false # 当滚轮滚动时为true

var _list_start_pos: float = 0.0 # 开始拖拽时的列表起始位置
var _mouse_start_pos: float = 0.0 # 开始拖拽时的鼠标位置
var _mouse_delta: float = 0.0 # 鼠标拖动的距离

## 配置参数
var deceleration_rate := 0.99  # 基础减速速率
var drag_sensitivity := 1.5  # 拖拽灵敏度
var max_velocity := 5000.0  # 最大速度
var wheel_velocity := 425.0  # 滚轮速度增量

## 所有列表项
var list_items: Array[ListItemBase] = []
var selected_item: int = -1 # 选中的项，或者snap的目标项

## snap相关
var need_snap: bool = false # 吸附完成后为false
var snap_offset_y: float = 500 # 吸附偏移量
var snap_tween: Tween

## 计时器
var scroll_state_reset_timer: Timer

func _ready() -> void:
	if container == null:
		push_error("Container not found at path: %s" % container_path)
		return

	# 创建计时器
	scroll_state_reset_timer = Timer.new()
	scroll_state_reset_timer.wait_time = 0.3
	scroll_state_reset_timer.one_shot = true  # 单次触发
	scroll_state_reset_timer.timeout.connect(_stop_scroll)
	add_child(scroll_state_reset_timer)

	UIStateManager.instance.state_changed.connect(_on_state_changed)
	_on_state_changed(UIStateManager.UIState.NONE, UIStateManager.instance.current_state)

	get_v_scroll_bar().gui_input.connect(_on_v_scrollbar_gui_input)
	get_v_scroll_bar().value_changed.connect(_on_v_scrollbar_changed)

func _stop_scroll():
	scroll_velocity = 0.0

# 停止滚动时重置速度
func _on_v_scrollbar_changed(_value: float):
	if scroll_state_reset_timer.is_stopped():
		scroll_state_reset_timer.start()
	else:
		scroll_state_reset_timer.stop()
		scroll_state_reset_timer.start()

	if work_state in [UIStateManager.UIState.ALBUM_VIEW] and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		call_deferred("reset_selection")

	# 到达上下边界就停止
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and scroll_velocity!= 0 and (scroll_vertical < 10 or (get_v_scroll_bar().max_value - scroll_vertical < 10)):
		scroll_velocity = 0

func _on_state_changed(_oldState: UIStateManager.UIState, state: UIStateManager.UIState) -> void:
	var enable:bool = state == work_state
	set_process(enable)
	set_process_input(enable)

	# 聚焦列表项
	if enable and work_state not in [UIStateManager.UIState.TRACK_VIEW, UIStateManager.UIState.SETTINGS_VIEW]:
		print("Node: %s , ProcessMode: %s" % [self.name, enable])

func _process(delta: float) -> void:
	if container == null:
		return

	if not _is_dragging_list and scroll_velocity != 0:
		# 减速
		# if abs(scroll_velocity) > max_velocity:
		# 	scroll_velocity = max_velocity * sign(scroll_velocity)
		# scroll_velocity *= (1-(deceleration_rate)*delta)
		
		scroll_vertical += int(scroll_velocity * delta)
		if snap_tween:
			snap_tween.kill()
			snap_tween = null
	elif _is_dragging_list and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_is_dragging_list = false
		is_dragging_list = false
		print("cancel drag",_is_dragging_list, get_path())

	# 吸附
	if list_items and need_snap and not (is_dragging_list or scroll_velocity!=0):
		var snap_index = selected_item if selected_item != -1 else round((scroll_vertical) / (item_height))
		
		snap_index = select_item(snap_index)
		var snap_node = container.get_child(snap_index)
		if not snap_node:
			return
		
		# 计算吸附位置
		var snap_distant: int = snap_node.position.y + snap_offset_y
		if work_state in [UIStateManager.UIState.ALBUM_VIEW]:
			snap_distant = snap_node.global_position.y + snap_offset_y + scroll_vertical
		need_snap=false
		if abs(snap_distant-scroll_vertical)<10:
			return
		# 补间动画
		snap_tween = AnimationManager.instance._create_tween("snap_target")

		snap_tween.set_ease(Tween.EASE_IN)
		snap_tween.tween_property(self, "scroll_vertical", snap_distant, 0.2)

		snap_tween.finished.connect(func ():
			snap_tween.kill()
			snap_tween = null
		)

func _on_v_scrollbar_gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging_bar = event.pressed
			if event.pressed:
				scroll_velocity = 0.0

func _gui_input(event: InputEvent) -> void:
	if work_state != UIStateManager.instance.current_state:
		return

	# # 鼠标按钮事件
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging_list = event.pressed
			if event.pressed:
				scroll_velocity = 0
				_list_start_pos = scroll_vertical
				_mouse_start_pos = event.global_position.y
			else:
				is_dragging_list = false
		
		# 鼠标滚轮事件
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			var sig = 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1

			if scroll_velocity * sig < 0.0: # 方向相反时重置
				scroll_velocity = 0

			var ui = UIStateManager.UIState
			# 部分页面是直接选择项，其余是滚动列表
			if work_state in [ui.ALBUM_VIEW, ui.MIDI_VIEW, ui.SONG_VIEW] and get_global_rect().has_point(get_global_mouse_position()) and selected_item != -1:
				select_item(selected_item + sig)
			else:
				scroll_velocity += wheel_velocity * sig
			
			accept_event()
	
	elif event is InputEventKey and event.pressed:
		if event.keycode in [KEY_W, KEY_S]:
			var evt = InputEventKey.new()
			if event.keycode == KEY_W:
				evt.keycode = KEY_UP
			elif event.keycode == KEY_S:
				evt.keycode = KEY_DOWN
				
			evt.pressed = true
			evt.echo = false
			
			# 发送到输入系统
			Input.parse_input_event(evt)
			accept_event()

		elif event.keycode in [KEY_TAB]:
			get_node("/root/Main/skew/C/ShortCutMenu/Btns/Search").grab_focus()
			accept_event()
	
	# 鼠标移动事件
	elif event is InputEventMouseMotion:
		if _is_dragging_list and not is_dragging_bar:
			is_dragging_list = true
			_mouse_delta = (event.global_position.y - _mouse_start_pos) * drag_sensitivity
			
			# 限制滚动范围
			if work_state in [UIStateManager.UIState.MIDI_VIEW] and abs(_mouse_delta * drag_sensitivity) > item_height and selected_item != -1:
				_mouse_delta = item_height * sign(_mouse_delta)

			# 异号或者速度大于最大速度就更新速度
			if scroll_velocity * event.velocity.y > 0.0 or abs(event.velocity.y) > abs(scroll_velocity):
				scroll_velocity = - event.velocity.y
			if _mouse_delta != 0:
				scroll_vertical = clamp(int(-_mouse_delta + _list_start_pos), 0, get_v_scroll_bar().max_value)

func select_item(index: int) -> int:
	if index == selected_item or not list_items:
		return index
	
	index = (index + list_items.size()) % list_items.size()
	container.get_child(index).button.button_pressed = true
	selected_item = index

	return index

func get_selected_node() -> Node2D:
	if selected_item == -1:
		return null
	return container.get_child(selected_item)

## 添加列表项
func add_list_item(item: ListItemBase) -> void:
	if container == null:
		return
	
	container.add_child(item)
	list_items.append(item)
	
## 创建并添加列表项
func create_and_add_item(item_id: String, item_type: String = "") -> ListItemBase:
	var item: ListItemBase
	
	if list_item_class is GDScript:
		item = list_item_class.new()
	elif list_item_class:
		item = load(list_item_class).instantiate()
	
	item.initialize(item_id, item_type)
	add_list_item(item)
	
	return item

## 清空列表
func clear_items() -> void:
	if container == null:
		return
	
	for item in list_items:
		if item:
			item.queue_free()
	
	list_items.clear()

	# 重置值
	selected_item = -1
	scroll_velocity = 0.0
	is_dragging_bar = false

## 将头尾连接 用于focus循环
func _connect_head_and_tail() -> void:
	if container == null:
		return
	
	var node_h: Control = container.get_child(0).button
	var node_t: Control = container.get_child(-1).button

	node_h.focus_neighbor_top = node_t.get_path()
	node_h.focus_neighbor_left = node_t.get_path()
	node_t.focus_neighbor_bottom = node_h.get_path()
	node_t.focus_neighbor_right = node_h.get_path()
