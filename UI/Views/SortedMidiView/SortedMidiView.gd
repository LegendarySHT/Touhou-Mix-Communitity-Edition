## 排序MIDI视图
## 显示按特定条件排序或搜索后的MIDI列表
extends BaseScrollList

class_name SortedMidiView

## 当前显示的MIDI列表
var current_midis: Array[MidiData] = []

## 当前排序字段
# var current_sort_field: int = SortingEngine.SortDataField.DOWNLOAD_COUNT

## 当前排序方向
# var current_sort_direction: int = SortingEngine.SortDirection.DESCENDING

## 当前状态过滤
# var current_status_filter: SortEngine.SortStatField = SortingEngine.SortStatField.ALL

## 管理器引用
@onready var state_manager: UIStateManager = UIStateManager.instance
@onready var data_manager: DataManager = DataManager.instance
@onready var event_bus: EventBus = EventBus.instance
@onready var sorting_engine: SortingEngine = SortingEngine.instance

# ========== 新增的加载控制变量 ==========
## 是否正在加载
var _is_loading: bool = false
## 当前加载任务ID（用于识别和终止旧任务）
var _current_load_task_id: int = 0
## 当前加载的MIDI数据列表
var _midis_to_load: Array[MidiData] = []
## 当前加载的索引
var _current_load_index: int = 0
## 每帧加载的节点数量（可调整以平衡性能）
var _nodes_per_frame: int = 5
## 加载延迟（帧数，用于降低每帧压力）
var _load_frame_delay: int = 0
## 延迟计数器
var _delay_counter: int = 0
# ======================================

var item_bg: ButtonGroup

func _ready() -> void:	
	if not data_manager or not event_bus or not sorting_engine:
		push_error("SortedMidiView: Missing manager instances")
		return
	
	work_state = UIStateManager.UIState.SORTED_VIEW
	item_height = 179 # 间距29 项高150
	item_spacing = 29

	# 连接事件
	event_bus.search_query_changed.connect(_on_search_query_changed)
	event_bus.sort_finished.connect(_load_sorted_midis)

	super._ready()

func _process(delta):
	super._process(delta)
	
	# 处理分帧加载
	_process_loading()

	process_item_cover_move()

func _input(event):
	super._input(event)

## 处理分帧加载逻辑
func _process_loading() -> void:
	if not _is_loading or _midis_to_load.is_empty():
		return

	# 处理加载延迟
	if _delay_counter < _load_frame_delay:
		_delay_counter += 1
		return
	_delay_counter = 0
	
	# 计算本帧要加载的节点数量
	var nodes_to_load_this_frame = min(_nodes_per_frame, _midis_to_load.size() - _current_load_index)
	
	# 加载本帧的节点
	for i in range(nodes_to_load_this_frame):
		var index = _current_load_index + i
		if index >= _midis_to_load.size():
			break
			
		var midi = _midis_to_load[index]
		var node = create_and_add_item(midi.id, "midi")
		node.setup_with_midi(midi, index, item_bg)
	
	# 更新索引
	_current_load_index += nodes_to_load_this_frame
	
	# 检查是否加载完成
	if _current_load_index >= _midis_to_load.size():
		_finish_loading()
		print("Loaded %d midis" % _midis_to_load.size())

## 完成加载任务
func _finish_loading() -> void:
	_is_loading = false
	_midis_to_load.clear()
	_current_load_index = 0
	_delay_counter = 0

## 加载排序的MIDI列表（启动新的加载任务）
func _load_sorted_midis() -> void:
	if not data_manager or not sorting_engine:
		print("Missing manager instances")
		return
	
	if not item_bg:
		item_bg = ButtonGroup.new()

	# 生成新的任务ID（用于标识当前任务）
	var new_task_id = _current_load_task_id + 1
	_current_load_task_id = new_task_id
	
	var midis: Array = sorting_engine.get_midis()
	print("Loading %d midis" % midis.size())
	# 清空现有列表（这会立即移除所有子节点）
	_clear_list()
	
	# 检查是否已经有加载任务在进行
	if _is_loading:
		# 中断当前的加载任务
		_finish_loading()
	
	# 启动新的加载任务
	_is_loading = true
	_midis_to_load = midis
	_current_load_index = 0
	_delay_counter = 0
	
	# 立即加载第一个节点以提供即时反馈
	if not _midis_to_load.is_empty():
		var node = create_and_add_item(_midis_to_load[0].id, "midi")
		node.setup_with_midi(_midis_to_load[0], 0, item_bg)
		_current_load_index = 1
		
		# 如果只有一个节点，直接完成
		if _midis_to_load.size() == 1:
			_finish_loading()

## 清空列表
func _clear_list() -> void:
	if container == null:
		return
	
	# 使用批量移除以提高性能
	var children = container.get_children()
	for i in range(children.size() - 1, -1, -1):
		children[i].queue_free()
	
	list_items.clear()

## 刷新显示（使用分帧加载）
func _refresh_display() -> void:
	# 这里可以调用 _load_sorted_midis() 或者实现类似逻辑
	_load_sorted_midis()

## 初始化MIDI项
func _initialize_midi_item(item: ListItemBase, midi: MidiData) -> void:
	# 如果item是SortedMidiListItem，调用setup方法
	if item.has_method("setup_with_midi"):
		var index = current_midis.find(midi)
		item.setup_with_midi(midi, index)

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
		current_midis = sorting_engine.get_sorted_midis(all_midis)
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

## 设置每帧加载的节点数量（性能调优）
func set_nodes_per_frame(count: int) -> void:
	_nodes_per_frame = max(1, count)

## 设置加载延迟（每多少帧加载一次，0表示每帧都加载）
func set_load_frame_delay(delay: int) -> void:
	_load_frame_delay = max(0, delay)

## 新增：强制停止所有加载任务
func cancel_all_loading() -> void:
	if _is_loading:
		_finish_loading()
		print("All loading tasks cancelled")
