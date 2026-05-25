## 惯性滚动驱动器
## 处理鼠标拖拽和惯性减速滚动，作为子节点添加到 BaseScrollList。
## 移动端（Android/iOS）自动禁用——手机 ScrollContainer 自带惯性。
extends Node
class_name InertiaScrollDriver

# ===== 配置属性 =====
@export var drag_sensitivity: float = 1.5
@export var max_velocity: float = 5000.0
@export var wheel_velocity: float = 425.0
@export var velocity_decay_time: float = 3.0

# ===== 公共状态（通过 BaseScrollList 代理属性暴露） =====
var scroll_velocity: float = 0.0:
	set(v):
		if abs(v) > max_velocity:
			v = max_velocity * sign(v)
		var sv = scroll_velocity
		scroll_velocity = v
		if abs(v) > abs(sv) or v == 0:
			if _velocity_decrease_tween:
				_velocity_decrease_tween.kill()
				_velocity_decrease_tween = null

			if v == 0:
				return

			_velocity_decrease_tween = create_tween()
			_velocity_decrease_tween.tween_property(self, "scroll_velocity", 0, velocity_decay_time)

var is_dragging_list: bool = false
var _is_dragging_list: bool = false
var _list_start_pos: float = 0.0
var _mouse_start_pos: float = 0.0
var _mouse_delta: float = 0.0

# ===== 内部状态 =====
var _velocity_decrease_tween: Tween = null
var _mobile_platform: bool = false

func _ready() -> void:
	_mobile_platform = OS.get_name() in ["Android", "iOS"]
	if _mobile_platform:
		set_process(false)
		set_process_input(false)

func _process(_delta: float) -> void:
	if _is_dragging_list and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_is_dragging_list = false
		is_dragging_list = false

# ===== 公开 API（由 BaseScrollList 调用） =====

## 处理惯性滚动。返回新的 scroll_vertical 值，或 -1 表示无变化。
func process_inertia(delta: float, current_scroll: int, max_scroll: int) -> int:
	if not _is_dragging_list and scroll_velocity != 0:
		var displacement = int(scroll_velocity * delta)
		if displacement == 0:
			scroll_velocity = 0
			return -1
		return clampi(current_scroll + displacement, 0, max_scroll)
	return -1

## 处理鼠标按钮事件（从父级 _gui_input 转发）
func handle_mouse_button(event: InputEventMouseButton, current_scroll_vertical: int) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		_is_dragging_list = event.pressed
		if event.pressed:
			scroll_velocity = 0
			_list_start_pos = current_scroll_vertical
			_mouse_start_pos = event.global_position.y
		else:
			is_dragging_list = false

## 处理鼠标移动事件（从父级 _gui_input 转发）。
## 返回新的 scroll_vertical 值，或 -1 表示无需更新。
func handle_mouse_motion(event: InputEventMouseMotion, max_scroll: int,
		item_height: float, midi_view_clamp: bool, has_selected_item: bool) -> int:
	if not _is_dragging_list:
		return -1

	is_dragging_list = true
	var raw_delta = (event.global_position.y - _mouse_start_pos) * drag_sensitivity

	# MIDI 视图的行限制
	if midi_view_clamp and abs(raw_delta * drag_sensitivity) > item_height and has_selected_item:
		_mouse_delta = item_height * sign(raw_delta)
	else:
		_mouse_delta = raw_delta

	# 更新速度（来自引擎的内置指针速度）
	if scroll_velocity * event.velocity.y > 0.0 or abs(event.velocity.y) > abs(scroll_velocity):
		scroll_velocity = -event.velocity.y

	# 应用位置（非移动端——移动端有自己的惯性）
	if _mouse_delta != 0 and not _mobile_platform:
		return clampi(int(-_mouse_delta + _list_start_pos), 0, max_scroll)

	return -1

## 处理滚动条按下（从父级 _on_v_scrollbar_gui_input 转发）
func handle_scrollbar_press(pressed: bool) -> void:
	if pressed:
		scroll_velocity = 0.0

## 检查到达边界时停止速度。返回 true 表示已在边界停止。
func check_boundary_stop(current_scroll: int, max_scroll: int) -> bool:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and scroll_velocity != 0:
		if current_scroll < 10 or (max_scroll - current_scroll < 10):
			scroll_velocity = 0
			return true
	return false

## 检查滚轮方向是否与当前速度相反
func check_wheel_direction(wheel_sign: float) -> bool:
	return scroll_velocity * wheel_sign < 0.0

## 向速度添加滚轮增量
func add_wheel_velocity(amount: float) -> void:
	scroll_velocity += amount

## 停止所有惯性
func stop() -> void:
	scroll_velocity = 0.0

## 重置所有拖拽/滚动状态
func reset() -> void:
	scroll_velocity = 0.0
	_is_dragging_list = false
	is_dragging_list = false
	_mouse_delta = 0.0
	_list_start_pos = 0.0
	_mouse_start_pos = 0.0

## 外部状态检查器
func is_dragging_active() -> bool:
	return _is_dragging_list or is_dragging_list

func is_inertia_active() -> bool:
	return scroll_velocity != 0
