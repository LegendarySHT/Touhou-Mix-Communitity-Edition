# inertial_scroll.gd
# 通用滚动脚本
# 使用方法：在ScrollContainer脚本中:
# func _ready():
#   scroll = GeneralScroll.new(self)
#
# 在处理帧时传递delta时间:
# func _process(delta):
#   scroll.process(delta)
#
# 处理事件时把事件也传过来:
# func _input(event):
#   scroll.input(event)

class_name GeneralScroll

var _scroll_container: ScrollContainer
var _is_dragging := false
var _drag_pos1 := 0.0
var _drag_pos2 := 0.0
var _start_scroll_v_pos := 0.0
var _scroll_velocity := 0.0
var _is_enabled := false
var _previ_scroll_vertical := 0.0

# 配置参数
var deceleration_rate := 0.99  # 基础减速速率
var drag_sensitivity := 1.5  # 拖拽灵敏度
var max_velocity := 6500.0  # 最大速度
var wheel_velocity := 450.0  # 滚轮速度增量

func _init(scroll_container: ScrollContainer) -> void:
	_scroll_container = scroll_container
	enable()

# 启用惯性滚动
func enable() -> void:
	if _is_enabled:
		return
	
	_is_enabled = true
	_scroll_container.process_mode = Node.PROCESS_MODE_ALWAYS
	
	# 连接信号
	if _scroll_container.get_h_scroll_bar():
		_scroll_container.get_h_scroll_bar().gui_input.connect(_on_scrollbar_input.bind("horizontal"))
	if _scroll_container.get_v_scroll_bar():
		_scroll_container.get_v_scroll_bar().gui_input.connect(_on_scrollbar_input.bind("vertical"))
	
	# 设置输入处理
	_scroll_container.set_process(true)
	_scroll_container.set_process_input(true)

# 禁用惯性滚动
func disable() -> void:
	if not _is_enabled:
		return
	
	_is_enabled = false
	_is_dragging = false
	
	# 断开信号连接
	if _scroll_container.get_h_scroll_bar():
		_scroll_container.get_h_scroll_bar().gui_input.disconnect(_on_scrollbar_input)
	if _scroll_container.get_v_scroll_bar():
		_scroll_container.get_v_scroll_bar().gui_input.disconnect(_on_scrollbar_input)


func process(delta: float) -> void:
	if not _is_enabled:
		return
	
	if not _is_dragging:
		# 动态计算最大滚动值
		var max_scroll := 0.0
		if _scroll_container.get_v_scroll_bar():
			max_scroll = _scroll_container.get_v_scroll_bar().max_value
		if _scroll_container.scroll_vertical < max_scroll:
			_scroll_velocity *= deceleration_rate
		
		_scroll_container.scroll_vertical += int(_scroll_velocity * delta)
		
		# 动不了就停止
		if _previ_scroll_vertical == _scroll_container.scroll_vertical:
			_scroll_velocity = 0.0
		_previ_scroll_vertical = _scroll_container.scroll_vertical
		
		# 当速度很小时停止
		if abs(_scroll_velocity) < 30.0:
			_scroll_velocity = 0.0

func input(event: InputEvent) -> void:
	if not _is_enabled:
		return
	
	# 鼠标按钮事件
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_is_dragging = event.pressed
				if event.pressed:  # 鼠标释放
					_scroll_velocity = 0
					_start_scroll_v_pos = _scroll_container.scroll_vertical
					_drag_pos1 = event.global_position.y
					_drag_pos2 = _drag_pos1
		
		# 鼠标滚轮
			MOUSE_BUTTON_WHEEL_UP:
				_scroll_velocity -= wheel_velocity
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_velocity += wheel_velocity
	
	# 鼠标移动事件
	elif event is InputEventMouseMotion and _is_dragging:
		_drag_pos2 = event.global_position.y - _drag_pos1
		if abs(event.velocity.y) > abs(_scroll_velocity) or _scroll_velocity * event.velocity.y > 0.0:
			_scroll_velocity = - event.velocity.y
		if _drag_pos2 != 0:
			_scroll_container.scroll_vertical = int(-_drag_pos2 * drag_sensitivity + _start_scroll_v_pos)


func _on_scrollbar_input(event: InputEvent, orientation: String) -> void:
	if not _is_enabled:
		return
	if event is InputEventMouseButton:
		if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_scroll_velocity = 0.0
