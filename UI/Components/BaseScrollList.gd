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

var work_state: UIStateManager.UIState = UIStateManager.UIState.NONE

## 当前滚动速度
var scroll_velocity: float = 0.0

## 上一帧的滚动位置
var last_scroll_position: float = 0.0

## 是否正在滚动
var is_dragging_list: bool = false # 区分点击事件
var _is_dragging_list: bool = false
var is_dragging_bar: bool = false
var is_wheel_scrolling: bool = false

var _start_pos: float = 0.0
var _mouse_start_pos: float = 0.0

# 配置参数
var deceleration_rate := 0.99  # 基础减速速率
var drag_sensitivity := 1.5  # 拖拽灵敏度
var max_velocity := 5000.0  # 最大速度
var wheel_velocity := 425.0  # 滚轮速度增量

## 所有列表项
var list_items: Array[ListItemBase] = []

var scroll_timer: Timer

func _ready() -> void:
	if container == null:
		push_error("Container not found at path: %s" % container_path)
		return
	
	# 创建计时器
	scroll_timer = Timer.new()
	scroll_timer.wait_time = 0.3
	scroll_timer.one_shot = true  # 单次触发
	scroll_timer.timeout.connect(_on_scroll_timer_timeout)
	add_child(scroll_timer)

	UIStateManager.instance.state_changed.connect(_on_state_changed)
	_on_state_changed(UIStateManager.UIState.NONE, UIStateManager.instance.current_state)

	get_v_scroll_bar().gui_input.connect(_on_v_scrollbar_gui_input)

func _on_state_changed(_oldState: UIStateManager.UIState, state: UIStateManager.UIState) -> void:
	var enable:bool = state == work_state
	set_process(enable)
	set_process_input(enable)
	if enable:
		print("Node: %s , ProcessMode: %s" % [self.name, enable])

func _process(delta: float) -> void:
	if container == null:
		return

	if not _is_dragging_list:
		# 动态计算最大滚动值
		var max_scroll := 0.0
		if get_v_scroll_bar():
			max_scroll = get_v_scroll_bar().max_value
		if abs(scroll_velocity) > max_velocity:
			scroll_velocity = max_velocity * sign(scroll_velocity)
		if scroll_vertical < max_scroll:
			scroll_velocity *= deceleration_rate
		
		scroll_vertical += int(scroll_velocity * delta)

		# 动不了就停止
		if last_scroll_position == scroll_vertical:
			scroll_velocity = 0.0
		last_scroll_position = scroll_vertical
		
		# 当速度很小时停止
		if abs(scroll_velocity) < 30.0:
			scroll_velocity = 0.0

func _on_v_scrollbar_gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging_bar = event.pressed
			if event.pressed:
				scroll_velocity = 0.0
				
func _on_scroll_timer_timeout():
	is_wheel_scrolling = false

func _input(event: InputEvent) -> void:
	# 鼠标按钮事件

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging_list = event.pressed
			if event.pressed:
				scroll_velocity = 0
				_start_pos = scroll_vertical
				_mouse_start_pos = event.global_position.y
			else:
				is_dragging_list = false
		
		# 鼠标滚轮事件
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			var sig = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0
			if scroll_velocity * sig < 0.0:
				scroll_velocity = 0

			var tIndex = 0
			if work_state in [UIStateManager.UIState.ALBUM_VIEW] and has_method("reset_selection"):
				tIndex = (self.selected_album + int(sig)) % list_items.size()
				call("reset_selection")

			if not is_wheel_scrolling:

				is_wheel_scrolling = true
				scroll_timer.start()
				
				container.get_child(tIndex).button.button_pressed = true
			else:
				scroll_velocity += wheel_velocity * sig
				scroll_timer.stop()
				scroll_timer.start()
	# 鼠标移动事件
	elif event is InputEventMouseMotion:
		if _is_dragging_list and not is_dragging_bar:
			is_dragging_list = true
			var _mouse_delta = event.global_position.y - _mouse_start_pos
			# 异号或者速度大于最大速度就更新速度
			if scroll_velocity * event.velocity.y > 0.0 or abs(event.velocity.y) > abs(scroll_velocity):
				scroll_velocity = - event.velocity.y
			if _mouse_delta != 0:
				scroll_vertical = int(-_mouse_delta * drag_sensitivity + _start_pos)

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
		item.queue_free()
	
	list_items.clear()

## 获取所有列表项
func get_all_items() -> Array[ListItemBase]:
	return list_items

## 获取焦点项（可见范围内的中心项）
func get_focused_item() -> ListItemBase:
	if list_items.is_empty():
		return null
	
	var scroll_pos = get_v_scroll_bar().value
	var view_height = get_v_scroll_bar().page
	var center_pos = scroll_pos + view_height / 2.0
	
	var closest_item: ListItemBase = list_items[0]
	var closest_distance: float = INF
	
	for item in list_items:
		var item_center = item.get_global_rect().get_center().y
		var distance = abs(item_center - center_pos)
		
		if distance < closest_distance:
			closest_distance = distance
			closest_item = item
	
	return closest_item

## 列表项图片位移
func process_item_cover_move() -> void:
	var window_height = get_viewport_rect().size.y
	var idx:int = floori(scroll_vertical / item_height) - 3
	idx = idx if idx >= 0 else 0
	var midx = clampi(0,list_items.size(),idx + 10 + window_height/item_height)
	
	# 调用这个方法需要在item中添加cover_texture对象
	for i in range(idx, midx):
		var tex_r:TextureRect = container.get_child(i).cover_texture
		tex_r.position = Vector2(0 , - tex_r.global_position.y / window_height * tex_r.size.y)
