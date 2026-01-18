## 专辑视图
## 显示所有专辑列表，支持排序和搜索
extends BaseScrollList

class_name AlbumView

## 当前显示的专辑列表
var current_albums: Array[AlbumData] = []
var selected_album: int = -1

## 排序引擎引用
@onready var sorting_engine: SortingEngine = SortEngine.instance
@onready var data_manager: DataManager = DataMGR.instance
@onready var event_bus: EventBus = EvtBus.instance

# 基本滚动逻辑
@onready var scroll:GeneralScroll = GeneralScroll.new(self)

# 吸附相关
@export var item_height: float = 173
var need_snap = false # 指示是否需要吸附
var snap_velocity = 800 # 开始吸附的速度临界值
var snap_index = -1 # 当需要吸附且该值为1时，就近吸附，否则吸附到指定位置
var snap_distant = 0 # 用于指示距离吸附完成位置的距离

# 路径
var ALBUMBUTTON = "PC/Polygon2D/AlbumButton"

func _ready() -> void:
	super._ready()
	
	if not data_manager or not event_bus or not sorting_engine:
		push_error("AlbumView: Missing manager instances")
		return
	
	# 连接事件
	data_manager.data_loaded.connect(_load_albums)

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
	var counter = 0
	var bg = ButtonGroup.new()
	for album in current_albums:
		var item = create_and_add_item(album.id, "album")
		item.setup_with_album(self, album, counter, bg)

		get_child(0).add_child(item)
		counter += 1

## 清空列表
func _clear_list() -> void:
	if container == null:
		return
	
	for item in container.get_children():
		item.queue_free()
	
	list_items.clear()


func _process(delta):
	if UiStatMGR.current_state != UiStatMGR.UIState.ALBUM_VIEW:
		return
	scroll.process(delta)
	
	var albumNode = get_child(0).get_child(Global.album)
	
	if abs(scroll._scroll_velocity) < 800 and not scroll._is_dragging:
		if need_snap:
			# 获取一个吸附对象
			if snap_index == -1:
				scroll._scroll_velocity = 0
				if Global.album == -1:
					snap_index = round((scroll_vertical + item_height) / (item_height))
				else:
					snap_index = Global.album

			var temp = get_node("/root/Main/Album/AlbumList/VBox").get_child(snap_index)
			if temp.is_expanded == false:
				#print("emited")
				temp.get_node(ALBUMBUTTON).button_pressed = true

			snap_distant = get_child(0).get_child(snap_index).global_position.y - item_height
			if abs(snap_distant) < 2 or (snap_index == 0):
				_stop_snap()
		# 低速时吸附
		elif abs(scroll._scroll_velocity) < snap_velocity and (abs(get_child(0).get_child(Global.album).global_position.y - 200) > 20 or Global.album == -1):
			need_snap = true
		
		
		# 吸附时的移动
		if need_snap:
			scroll_vertical += floor((snap_distant) / 6)
		# 选中的曲子在屏幕外时缩小
	
	else:
		_stop_snap()
		if Global.album != -1 and albumNode.is_expanded and (albumNode.global_position.y < 100 or albumNode.global_position.y > 1080):
			reset_selection()

func _input(event):
	if UiStatMGR.current_state != UIStateManager.UIState.ALBUM_VIEW or 0:# Global.Sort:
		return
	scroll.input(event)

func _stop_snap():
	need_snap = false;
	snap_index = -1;
	
func reset_selection():
	if Global.album != -1:
		var temp = get_child(0).get_child(Global.album)
		temp.get_node(ALBUMBUTTON).button_pressed = false

		Global.album = -1

func _on_button_toggled(toggled_on: bool, button):
	if toggled_on:
		if  Global.album != -1 and Global.album == button.get_meta("index"):
			# 设置专辑ID
			var album_id = button.get_meta("album_id")
			# Global.album_id = album_id
			
			# 通过事件总线触发专辑选择
			event_bus.album_selected.emit(album_id)
			UiStatMGR.change_state(UiStatMGR.UIState.SONG_VIEW)
		
		need_snap = true
		snap_index = button.get_meta("index")
		
		Global.album = button.get_meta("index")


## 搜索改变回调
# func _on_search_changed(query: String) -> void:
# 	if query.is_empty():
# 		_load_albums()
# 	else:
# 		# 实现搜索逻辑
# 		var search_results = sorting_engine.search_midis(
# 			data_manager.get_all_midis() if data_manager else [],
# 			query
# 		)
# 		# TODO: 根据MIDI结果过滤专辑
# 		pass

# ## 列表项选中回调
# func _on_item_selected(item_id: String) -> void:
# 	if event_bus:
# 		# 查找对应的专辑
# 		for album in current_albums:
# 			if album.id == item_id:
# 				event_bus.emit_album_selected(item_id, album)
# 				break

# ## 列表项悬停回调
# func _on_item_hovered(item_id: String) -> void:
# 	pass

# ## 列表项取消悬停回调
# func _on_item_unhovered() -> void:
# 	pass

# ## 获取所有MIDI方法（供搜索使用）
# func _get_all_midis() -> Array:
# 	if not data_manager:
# 		return []
	
# 	var all_midis: Array = []
# 	for midi in data_manager.midis.values():
# 		all_midis.append(midi)
# 	return all_midis
