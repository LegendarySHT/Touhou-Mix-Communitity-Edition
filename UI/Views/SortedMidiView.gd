## 排序MIDI视图
## 显示按特定条件排序或搜索后的MIDI列表
extends BaseScrollList

class_name SortedMidiView

## 当前显示的MIDI列表
var current_midis: Array[MidiData] = []

## 滚动逻辑
var scroll: GeneralScroll

## 当前排序字段
# var current_sort_field: int = SortingEngine.SortDataField.DOWNLOAD_COUNT

## 当前排序方向
# var current_sort_direction: int = SortingEngine.SortDirection.DESCENDING

## 当前状态过滤
# var current_status_filter: SortEngine.SortStatField = SortingEngine.SortStatField.ALL

## 管理器引用
var data_manager: DataManager
var event_bus: EventBus
var sorting_engine: SortingEngine

func _ready() -> void:
	super._ready()
	scroll = GeneralScroll.new(self)
	scroll.enable()
	
	# 获取管理器引用
	data_manager = DataManager.instance
	event_bus = EventBus.instance
	sorting_engine = SortingEngine.instance
	
	if not data_manager or not event_bus or not sorting_engine:
		push_error("SortedMidiView: Missing manager instances")
		return
	
	# 连接事件
	# event_bus.sort_field_changed.connect(_on_sort_field_changed)
	# event_bus.sort_direction_changed.connect(_on_sort_direction_changed)
	# event_bus.status_filter_changed.connect(_on_status_filter_changed)
	event_bus.search_query_changed.connect(_on_search_query_changed)
	event_bus.navigate_to_sort_view.connect(_on_enter_sort_view)

	# 刷新列表事件
	event_bus.sort_finished.connect(_load_sorted_midis)

func _process(delta):
	scroll.process(delta)


func _input(event):
	scroll.input(event)

## 进入排序视图
func _on_enter_sort_view() -> void:
	_load_sorted_midis()

## 加载排序的MIDI列表
func _load_sorted_midis() -> void:
	if not data_manager or not sorting_engine:
		print("Missing manager instances")
		return
	
	# 获取所有MIDI
	var midis: Array = sorting_engine.get_midis()
	# for midi in midis:
	# 	print("midi: %s" % midi.name)
	
	
	_refresh_display()

## 刷新显示
func _refresh_display() -> void:
	# 清空现有项
	_clear_list()
	
	# 添加新项
	for midi in current_midis:
		var item = create_and_add_item(midi.id, "sorted_midi")
		if item:
			_initialize_midi_item(item, midi)

## 清空列表
func _clear_list() -> void:
	if container == null:
		return
	
	for item in container.get_children():
		item.queue_free()
	
	list_items.clear()

## 初始化MIDI项
func _initialize_midi_item(item: ListItemBase, midi: MidiData) -> void:
	# 如果item是SortedMidiListItem，调用setup方法
	if item.has_method("setup_with_midi"):
		var index = current_midis.find(midi)
		item.setup_with_midi(midi, index)

## 排序字段改变
func _on_sort_field_changed(sort_field: int) -> void:
	# current_sort_field = sort_field
	_load_sorted_midis()

## 排序方向改变
func _on_sort_direction_changed(ascending: bool) -> void:
	# current_sort_direction = SortingEngine.SortDirection.ASCENDING if ascending else SortingEngine.SortDirection.DESCENDING
	_load_sorted_midis()

## 状态过滤改变
func _on_status_filter_changed(status: String) -> void:
	# current_status_filter = status
	_load_sorted_midis()

## 搜索查询改变
func _on_search_query_changed(query: String) -> void:
	if not sorting_engine or not data_manager:
		return
	
	# 获取所有MIDI
	var all_midis: Array = []
	for midi in data_manager.midis.values():
		all_midis.append(midi)
	
	if query.is_empty():
		# 如果搜索为空，恢复正常排序视图
		current_midis = sorting_engine.get_sorted_midis(
			all_midis,
			# current_status_filter,
			# current_sort_field,
			# current_sort_direction
		)
	else:
		# 执行搜索
		current_midis = sorting_engine.search_midis(all_midis, query)
	
	_refresh_display()

## 列表项选中回调
func _on_item_selected(item_id: String) -> void:
	if event_bus:
		# 查找对应的MIDI
		for midi in current_midis:
			if midi.id == item_id:
				event_bus.emit_midi_selected(item_id, midi)
				break

## 列表项悬停回调
func _on_item_hovered(item_id: String) -> void:
	pass

## 列表项取消悬停回调
func _on_item_unhovered() -> void:
	pass
