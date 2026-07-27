## 可滚动列表的基类
## 处理通用的滚动、吸附、虚拟化等功能
## 注：项目启用了"鼠标模拟触摸"，Godot ScrollContainer 自带惯性滚动，无需手动处理
extends ScrollContainer

class_name BaseScrollList

enum ScrollControlState {
	IDLE,              # 空闲 —— 无滚动活动
	SCROLLBAR_DRAG,    # 用户拖拽滚动条
	SNAP_ANIMATION,    # 吸附动画播放中
}

## 容器（放置列表项的VBox或HBox）
@export var container_path: NodePath
@onready var container: Container = get_node(container_path) if container_path else null

## 列表项场景或预制体
@export var list_item_class: Variant
@onready var item_instance = load(list_item_class).instantiate()

## 工作状态，当不处于该状态时停止处理操作
var work_state: UIStateManager.UIState = UIStateManager.UIState.NONE

## 正在拖动滚动条（内部状态，对外通过 scroll_control_state 统一查询）
var _is_dragging_bar: bool = false

## 滚动控制状态 —— 统一查询当前是谁在控制滚动位置
## IDLE=空闲, SCROLLBAR_DRAG=拖拽滚动条, SNAP_ANIMATION=吸附动画
var scroll_control_state: ScrollControlState:
	get:
		if _is_dragging_bar:
			return ScrollControlState.SCROLLBAR_DRAG
		if _snap_active:
			return ScrollControlState.SNAP_ANIMATION
		return ScrollControlState.IDLE

## 所有列表项
var list_items: Array[ListItemBase] = []
var selected_item: int = -1 # 选中的项，或者snap的目标项

## snap相关
var need_snap: bool = false # 吸附请求标志
var snap_offset_y: float = 500 # 吸附偏移量
var _snap_active: bool = false # 吸附动画进行中
var _snap_stable_frames: int = 0 # 连续稳定帧计数（防止布局抖动导致提前收敛）
var _snap_integral: float = 0.0 # PI控制积分项

## 滚动速度追踪（像素/秒）—— 替代手动拖拽检测
var _prev_scroll_vertical: int = 0
var _scroll_speed: float = 0.0
const SCROLL_SPEED_COLLAPSE: float = 80.0   # 超过此速度 → 收起展开项
const SCROLL_SPEED_SNAP: float = 30.0       # 低于此速度 → 允许吸附

## 滚动稳定性检测 —— 速度降到阈值以下 + 短暂等待后允许吸附
var _scroll_stable: bool = true
var _scroll_stable_timer: Timer = null

func _ready() -> void:
	if container == null:
		push_error("Container not found at path: %s" % container_path)
		return

	# 创建滚动稳定性计时器（速度降到阈值以下 0.15 秒后允许吸附）
	_scroll_stable_timer = Timer.new()
	_scroll_stable_timer.wait_time = 0.15
	_scroll_stable_timer.one_shot = true
	_scroll_stable_timer.timeout.connect(_on_scroll_stable)
	add_child(_scroll_stable_timer)

	UiStatMGR.state_changed.connect(_on_state_changed)
	_on_state_changed(UIStateManager.UIState.NONE, UiStatMGR.current_state)

	get_v_scroll_bar().gui_input.connect(_on_v_scrollbar_gui_input)
	get_v_scroll_bar().value_changed.connect(_on_v_scrollbar_changed)
	get_v_scroll_bar().custom_minimum_size.x = 18

func _on_scroll_stable():
	_scroll_stable = true

## 外部查询：当前是否正在滚动（用于封面视差等效果）
func is_scrolling() -> bool:
	return not _scroll_stable or _is_dragging_bar or _snap_active

# 滚动条值变化（scrollbar 自身拖拽时）
func _on_v_scrollbar_changed(_value: float):
	if work_state in [UIStateManager.UIState.ALBUM_VIEW] and _is_dragging_bar:
		call_deferred("reset_selection")

func _on_state_changed(_oldState: UIStateManager.UIState, state: UIStateManager.UIState) -> void:
	var enable:bool = state == work_state
	
	# TRACK_VIEW 和 SETTINGS_VIEW 不需要 BaseScrollList 的触摸/滚动逻辑
	if work_state in [UIStateManager.UIState.TRACK_VIEW, UIStateManager.UIState.SETTINGS_VIEW]:
		enable = false
	
	set_process(enable)
	set_process_input(enable)

	# 聚焦列表项
	if enable:
		print("Node: %s , ProcessMode: %s" % [self.name, enable])

func _process(delta: float) -> void:
	if container == null:
		return
	
	# TRACK_VIEW 和 SETTINGS_VIEW 不需要 BaseScrollList 的触摸/滚动逻辑
	if work_state in [UIStateManager.UIState.TRACK_VIEW, UIStateManager.UIState.SETTINGS_VIEW]:
		return

	# 计算滚动速度
	var sv := scroll_vertical
	_scroll_speed = abs(sv - _prev_scroll_vertical) / max(delta, 0.001)
	_prev_scroll_vertical = sv

	# 滚动速度快 → 不稳定，自动收起展开项
	# 吸附期间跳过速度检测（吸附自己驱动 scroll_vertical，不应自中断）
	if not _snap_active and _scroll_speed > SCROLL_SPEED_COLLAPSE:
		_scroll_stable = false
		if _scroll_stable_timer and not _scroll_stable_timer.is_stopped():
			_scroll_stable_timer.stop()
		if work_state in [UIStateManager.UIState.ALBUM_VIEW]:
			call_deferred("reset_selection")
	# 速度降到阈值以下 → 准备吸附
	elif not _snap_active and _scroll_speed < SCROLL_SPEED_SNAP and not _scroll_stable:
		if _scroll_stable_timer and _scroll_stable_timer.is_stopped():
			_scroll_stable_timer.start()

	# 吸附（逐帧 lerp，每帧重新计算目标位置以应对项展开/收起导致的布局变化）
	# 仅当滚动已稳定且未拖拽滚动条时执行
	if list_items and need_snap and not _is_dragging_bar and (_scroll_stable or _snap_active):
		if not _snap_active:
			_snap_active = true
		_process_snap(delta)
	elif _snap_active:
		_snap_active = false
		_snap_stable_frames = 0


func _find_snap_target_from_visible() -> int:
	var view_top = global_position.y
	# 只要列表项的顶部在可视区域内，就认为它是吸附目标
	for it in container.get_children():
		if it.global_position.y > view_top:
			return it.get_index()
	return -1

## 逐帧吸附处理
## 基于全局位置直接修正 —— 无视 scroll_vertical，只维护目标项在屏幕上的位置
func _process_snap(delta: float) -> void:
	# 无选中项时尝试自动寻找可见项
	if selected_item == -1:
		var found := _find_snap_target_from_visible()
		if found != -1:
			select_item(found)
		if selected_item == -1:
			need_snap = false
			_snap_active = false
			return

	var snap_node := container.get_child(selected_item)
	if not snap_node:
		need_snap = false
		_snap_active = false
		return

	# 目标：项顶部距离 ScrollContainer 顶部 = snap_offset_y 像素
	# 只用全局位置算距离，不依赖 scroll_vertical（避免容器尺寸变化干扰）
	var distance: float = snap_node.global_position.y - global_position.y - snap_offset_y

	# PI 控制：P项快速响应，I项累积小偏差消除稳态误差
	_snap_integral = clampf(_snap_integral + distance * delta, -20.0, 20.0)
	var step: float = distance * clampf(delta * 12.0, 0.0, 1.0) + _snap_integral * 0.3

	if abs(distance) < 1.0:
		_snap_stable_frames += 1
		if _snap_stable_frames >= 5:
			need_snap = false
			_snap_active = false
			_snap_integral = 0.0
	else:
		_snap_stable_frames = 0
		var int_step := roundi(step)
		if int_step != 0:
			scroll_vertical += int_step

func _on_v_scrollbar_gui_input(event):
	if event is InputEventScreenTouch:
		_is_dragging_bar = event.pressed

func _gui_input(event: InputEvent) -> void:
	if work_state != UiStatMGR.current_state:
		return
	
	# TRACK_VIEW 和 SETTINGS_VIEW 不需要 BaseScrollList 的输入处理
	if work_state in [UIStateManager.UIState.TRACK_VIEW, UIStateManager.UIState.SETTINGS_VIEW]:
		return

	# 滚轮事件（桌面端鼠标滚轮 —— 接管项选择，滚动本身由 Godot ScrollContainer 处理）
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			var sig = 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
			var ui = UIStateManager.UIState
			if work_state in [ui.ALBUM_VIEW, ui.MIDI_VIEW, ui.SONG_VIEW] and get_global_rect().has_point(get_global_mouse_position()) and selected_item != -1:
				select_item(selected_item + sig)
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

func select_item(index: int) -> int:
	if index == selected_item or not list_items:
		return index

	index = (index + list_items.size()) % list_items.size()
	container.get_child(index).button.button_pressed = true
	selected_item = index

	return index

func get_selected_node() -> Control:
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
	need_snap = false
	_snap_active = false
	_snap_stable_frames = 0
	_snap_integral = 0.0
	_is_dragging_bar = false
	_scroll_stable = true
	_scroll_speed = 0.0
	_prev_scroll_vertical = 0

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
	if ThemeMGR == null:
		return
	var pri_light := ThemeMGR.get_color("primary_light")
	for item in list_items:
		var count_base := item.get_node_or_null("PN/CountBase") as TextureRect
		if count_base:
			count_base.self_modulate = pri_light
