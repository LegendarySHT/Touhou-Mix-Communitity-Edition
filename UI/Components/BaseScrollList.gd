## 可滚动列表的基类
## 处理通用的滚动、吸附、虚拟化等功能
extends ScrollContainer

class_name BaseScrollList

## 容器（放置列表项的VBox或HBox）
@export var container_path: NodePath
@onready var container: Container = get_node(container_path) if container_path else null

## 列表项场景或预制体
@export var list_item_class: Variant
@onready var item_instance = load(list_item_class).instantiate()

## 列表项的高度
@export var item_height: float = 100.0

## 列表项间距
@export var item_spacing: float = 10.0

## 工作状态，当不处于该状态时停止处理操作
var work_state: UIStateManager.UIState = UIStateManager.UIState.NONE

## 惯性滚动驱动器（移动端为 null — 手机 ScrollContainer 自带惯性）
var _inertia_driver: InertiaScrollDriver = null

## —— 代理属性（委托给 _inertia_driver） ——

var scroll_velocity: float:
	get: return _inertia_driver.scroll_velocity if _inertia_driver else 0.0
	set(v):
		if _inertia_driver:
			_inertia_driver.scroll_velocity = v

var is_dragging_list: bool:
	get: return _inertia_driver.is_dragging_list if _inertia_driver else false
	set(v):
		if _inertia_driver:
			_inertia_driver.is_dragging_list = v

@warning_ignore("unused_private_class_variable")
var _is_dragging_list: bool:
	get: return _inertia_driver._is_dragging_list if _inertia_driver else false

@warning_ignore("unused_private_class_variable")
var _mouse_delta: float:
	get: return _inertia_driver._mouse_delta if _inertia_driver else 0.0

var drag_sensitivity: float:
	get: return _inertia_driver.drag_sensitivity if _inertia_driver else 1.5
	set(v):
		if _inertia_driver:
			_inertia_driver.drag_sensitivity = v

var max_velocity: float:
	get: return _inertia_driver.max_velocity if _inertia_driver else 5000.0
	set(v):
		if _inertia_driver:
			_inertia_driver.max_velocity = v

var wheel_velocity: float:
	get: return _inertia_driver.wheel_velocity if _inertia_driver else 425.0
	set(v):
		if _inertia_driver:
			_inertia_driver.wheel_velocity = v

## 上一帧的滚动位置
var last_bar_position: int = 0

## 是否正在滚动
var is_dragging_bar: bool = false # 当鼠标拖动滚动条时为true
var is_wheel_scrolling: bool = false # 当滚轮滚动时为true

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

	# 创建惯性滚动驱动器
	_inertia_driver = InertiaScrollDriver.new()
	_inertia_driver.name = "InertiaScrollDriver"
	add_child(_inertia_driver)

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
	get_v_scroll_bar().custom_minimum_size.x = 18

func _stop_scroll():
	if _inertia_driver:
		_inertia_driver.stop()

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
	if _inertia_driver:
		@warning_ignore("narrowing_conversion")
		_inertia_driver.check_boundary_stop(scroll_vertical, get_v_scroll_bar().max_value)

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

	# 惯性滚动处理 → 委托给驱动器
	if _inertia_driver:
		@warning_ignore("narrowing_conversion")
		var new_pos = _inertia_driver.process_inertia(delta, scroll_vertical, get_v_scroll_bar().max_value)
		if new_pos >= 0:
			scroll_vertical = new_pos
			if snap_tween:
				snap_tween.kill()
				snap_tween = null

	# 吸附
	if list_items and need_snap and not (is_dragging_list or scroll_velocity!=0):
		var snap_index = selected_item if selected_item != -1 else _find_snap_target_from_visible()
		if snap_index == -1:
			return

		snap_index = select_item(snap_index)
		var snap_node = container.get_child(snap_index)
		if not snap_node:
			return

		# 计算吸附位置
		var snap_distant: int = snap_node.position.y + snap_offset_y
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


func _find_snap_target_from_visible() -> int:
	var visible_indices: Array[int] = []
	var view_top = global_position.y
	var view_bottom = global_position.y + size.y

	for i in range(container.get_child_count()):
		var child = container.get_child(i)
		var item_top = child.global_position.y
		var item_bottom = child.global_position.y + child.size.y

		# 至少部分可见
		if item_bottom > view_top and item_top < view_bottom:
			visible_indices.append(i)

	if visible_indices.is_empty():
		return -1

	if visible_indices.size() >= 2:
		return visible_indices[1]
	return visible_indices[0]

func _on_v_scrollbar_gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging_bar = event.pressed
			if _inertia_driver:
				_inertia_driver.handle_scrollbar_press(event.pressed)

func _gui_input(event: InputEvent) -> void:
	if work_state != UIStateManager.instance.current_state:
		return

	# # 鼠标按钮事件
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _inertia_driver:
				_inertia_driver.handle_mouse_button(event, scroll_vertical)

		# 鼠标滚轮事件
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			var sig = 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1

			if _inertia_driver and _inertia_driver.check_wheel_direction(sig):
				scroll_velocity = 0

			var ui = UIStateManager.UIState
			# 部分页面是直接选择项，其余是滚动列表
			if work_state in [ui.ALBUM_VIEW, ui.MIDI_VIEW, ui.SONG_VIEW] and get_global_rect().has_point(get_global_mouse_position()) and selected_item != -1:
				select_item(selected_item + sig)
			else:
				if _inertia_driver:
					_inertia_driver.add_wheel_velocity(wheel_velocity * sig)

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
		if _inertia_driver and not is_dragging_bar:
			var midi_clamp = work_state in [UIStateManager.UIState.MIDI_VIEW]
			@warning_ignore("narrowing_conversion")
			var target = _inertia_driver.handle_mouse_motion(
				event, get_v_scroll_bar().max_value,
				item_height, midi_clamp, selected_item != -1
			)
			if target >= 0:
				scroll_vertical = target

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
	var item: ListItemBase = null

	if list_item_class:
		item = item_instance.duplicate()

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
	if _inertia_driver:
		_inertia_driver.reset()
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

## 刷新已有列表项的非共享属性颜色（如 albumNode 的 CountBase.self_modulate）
## StyleBoxFlat 已在 item_instance 上修改，duplicate() 共享引用，无需逐项刷新
func refresh_item_colors() -> void:
	if ThemeManager.instance == null:
		return
	var pri_light := ThemeManager.instance.get_color("primary_light")
	for item in list_items:
		var count_base := item.get_node_or_null("PN/CountBase") as TextureRect
		if count_base:
			count_base.self_modulate = pri_light
