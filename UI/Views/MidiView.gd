## MIDI视图
## 显示选中歌曲下的所有MIDI谱面列表
extends BaseScrollList

class_name MidiView

## 当前显示的MIDI列表
var current_midis: Array[MidiData] = []

## 当前选中的歌曲ID
var current_song_id: String = ""

## 管理器引用
var data_manager: DataManager
var event_bus: EventBus
var sorting_engine: SortingEngine

func _ready() -> void:
	super._ready()
	
	# 获取管理器引用
	data_manager = DataManager.instance
	event_bus = EventBus.instance
	sorting_engine = SortingEngine.instance
	
	if not data_manager or not event_bus:
		push_error("MidiView: Missing manager instances")
		return
	
	# 连接事件
	event_bus.song_selected.connect(_on_song_selected)
	event_bus.sort_field_changed.connect(_on_sort_changed)
	event_bus.status_filter_changed.connect(_on_filter_changed)

## 处理歌曲选择事件
func _on_song_selected(song_id: String, song_data: SongData) -> void:
	current_song_id = song_id
	_load_midis(song_id)

## 加载指定歌曲的MIDI谱面
func _load_midis(song_id: String) -> void:
	if not data_manager:
		return
	
	current_midis = data_manager.get_midis_by_song(song_id)
	_refresh_display()

## 刷新显示
func _refresh_display() -> void:
	# 清空现有项
	_clear_list()
	
	# 添加新项
	for midi in current_midis:
		var item = create_and_add_item(midi.id, "midi")
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
	# 如果item是MidiListItem，调用setup方法
	if item.has_method("setup_with_midi"):
		var index = current_midis.find(midi)
		item.setup_with_midi(midi, index)

## 排序改变回调
func _on_sort_changed(sort_field: int) -> void:
	if not sorting_engine:
		return
	
	# 获取排序方向（假设默认降序）
	var direction = SortingEngine.SortDirection.DESCENDING
	current_midis = sorting_engine.get_sorted_midis(
		current_midis,
		sort_field,
		direction
	)
	_refresh_display()

## 状态过滤改变回调
func _on_filter_changed(status: String) -> void:
	_load_midis(current_song_id)  # 重新加载并应用过滤

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
