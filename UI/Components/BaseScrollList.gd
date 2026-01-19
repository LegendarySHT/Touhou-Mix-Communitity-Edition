## 可滚动列表的基类
## 处理通用的滚动、吸附、虚拟化等功能
extends ScrollContainer

class_name BaseScrollList

## 容器（放置列表项的VBox或HBox）
@export var container_path: NodePath
@onready var container: BoxContainer = get_node(container_path) if container_path else null

## 列表项场景或预制体
@export var list_item_class: Variant

## 列表项的高度/宽度
@export var item_size: float = 100.0

## 启用吸附效果
@export var enable_snap: bool = true

## 吸附阈值（滚动速度小于此值时触发吸附）
@export var snap_threshold: float = 100.0

## 列表项间距
@export var item_spacing: float = 10.0

## 当前滚动速度
var scroll_velocity: float = 0.0

## 上一帧的滚动位置
var last_scroll_position: float = 0.0

## 是否正在滚动
var is_scrolling: bool = false

## 吸附目标位置
var snap_target: float = -1.0

## 吸附动画Tween
var snap_tween: Tween

## 所有列表项
var list_items: Array[ListItemBase] = []

## 滚动开始信号
signal list_scroll_started
signal list_scroll_finished
signal item_focused(item_id: String)
signal list_updated

func _ready() -> void:
	if container == null:
		push_error("Container not found at path: %s" % container_path)
		return
	
	list_scroll_started.connect(_on_scroll_started)
	list_scroll_finished.connect(_on_scroll_finished)

func _process(delta: float) -> void:
	if container == null:
		return
	
	var current_scroll = get_v_scroll_bar().value
	scroll_velocity = (current_scroll - last_scroll_position) / delta
	last_scroll_position = current_scroll
	
	# 更新滚动状态
	if abs(scroll_velocity) > 0.1:
		if not is_scrolling:
			is_scrolling = true
			list_scroll_started.emit()
	else:
		if is_scrolling:
			is_scrolling = false
			# 检查是否需要吸附
			if enable_snap and abs(scroll_velocity) < snap_threshold:
				_trigger_snap()
			list_scroll_finished.emit()

## 添加列表项
func add_list_item(item: ListItemBase) -> void:
	if container == null:
		return
	
	container.add_child(item)
	list_items.append(item)
	
	# 连接列表项信号
	#item.selected.connect(_on_item_selected)
	#item.hovered.connect(_on_item_hovered)
	#item.unhovered.connect(_on_item_unhovered)
	
	list_updated.emit()

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
	list_updated.emit()

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

## 滚动到特定列表项
func scroll_to_item(item_id: String) -> void:
	for i in range(list_items.size()):
		if list_items[i].item_id == item_id:
			scroll_to_index(i)
			return

## 滚动到特定索引
func scroll_to_index(index: int) -> void:
	if index < 0 or index >= list_items.size():
		return
	
	var target_y = index * (item_size + item_spacing)
	snap_target = target_y
	_animate_scroll_to(target_y)

## 触发吸附效果
func _trigger_snap() -> void:
	var snap_index = round(last_scroll_position / (item_size + item_spacing))
	var target_y = snap_index * (item_size + item_spacing)
	snap_target = target_y
	_animate_scroll_to(target_y)

## 动画滚动到目标位置
func _animate_scroll_to(target_y: float) -> void:
	if snap_tween:
		snap_tween.kill()
	
	snap_tween = create_tween()
	snap_tween.set_ease(Tween.EASE_OUT)
	snap_tween.set_trans(Tween.TRANS_CUBIC)
	snap_tween.tween_property(get_v_scroll_bar(), "value", target_y, 0.3)

## 列表项选中时的回调
func _on_item_selected(item_id: String) -> void:
	item_focused.emit(item_id)

## 列表项悬停时的回调
func _on_item_hovered(item_id: String) -> void:
	pass

## 列表项取消悬停时的回调
func _on_item_unhovered() -> void:
	pass

## 滚动开始时的回调
func _on_scroll_started() -> void:
	pass

## 滚动结束时的回调
func _on_scroll_finished() -> void:
	pass

## 销毁时清理
func _exit_tree() -> void:
	if snap_tween:
		snap_tween.kill()
