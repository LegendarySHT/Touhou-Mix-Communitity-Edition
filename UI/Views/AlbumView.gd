## 专辑视图
## 显示所有专辑列表，支持排序和搜索
extends BaseScrollList

class_name AlbumView

## 当前显示的专辑列表
var current_albums: Array[AlbumData] = []

## 排序引擎引用
var sorting_engine: SortingEngine
var data_manager: DataManager
var event_bus: EventBus

func _ready() -> void:
	super._ready()
	
	# 获取管理器引用
	data_manager = DataManager.instance
	event_bus = EventBus.instance
	sorting_engine = SortingEngine.instance
	
	if not data_manager or not event_bus or not sorting_engine:
		push_error("AlbumView: Missing manager instances")
		return
	
	# 连接事件
	event_bus.data_loaded_complete.connect(_on_data_loaded)
	event_bus.sort_field_changed.connect(_on_sort_changed)
	event_bus.search_query_changed.connect(_on_search_changed)
	
	# 初始化
	_load_albums()

## 加载专辑数据
func _load_albums() -> void:
	if not data_manager:
		return
	
	current_albums = data_manager.get_all_albums()
	_refresh_display()

## 刷新显示
func _refresh_display() -> void:
	# 清空现有项
	_clear_list()
	
	# 添加新项
	for album in current_albums:
		var item = create_and_add_item(album.id, "album")
		if item:
			_initialize_album_item(item, album)

## 清空列表
func _clear_list() -> void:
	if container == null:
		return
	
	for item in container.get_children():
		item.queue_free()
	
	list_items.clear()

## 初始化专辑项
func _initialize_album_item(item: ListItemBase, album: AlbumData) -> void:
	# 如果item是AlbumListItem，调用setup方法
	if item.has_method("setup_with_album"):
		item.setup_with_album(album)

## 数据加载完成回调
func _on_data_loaded() -> void:
	_load_albums()

## 排序改变回调
func _on_sort_changed(sort_field: int) -> void:
	_load_albums()

## 搜索改变回调
func _on_search_changed(query: String) -> void:
	if query.is_empty():
		_load_albums()
	else:
		# 实现搜索逻辑
		var search_results = sorting_engine.search_midis(
			data_manager.get_all_midis() if data_manager else [],
			query
		)
		# TODO: 根据MIDI结果过滤专辑
		pass

## 列表项选中回调
func _on_item_selected(item_id: String) -> void:
	if event_bus:
		# 查找对应的专辑
		for album in current_albums:
			if album.id == item_id:
				event_bus.emit_album_selected(item_id, album)
				break

## 列表项悬停回调
func _on_item_hovered(item_id: String) -> void:
	pass

## 列表项取消悬停回调
func _on_item_unhovered() -> void:
	pass

## 获取所有MIDI方法（供搜索使用）
func _get_all_midis() -> Array:
	if not data_manager:
		return []
	
	var all_midis: Array = []
	for midi in data_manager.midis.values():
		all_midis.append(midi)
	return all_midis
