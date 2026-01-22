## 专辑视图
## 显示所有专辑列表，支持排序和搜索
extends BaseScrollList

class_name AlbumView

## 当前显示的专辑列表
var current_albums: Array[AlbumData] = []

## 排序引擎引用
@onready var data_manager: DataManager = DataMGR.instance
@onready var event_bus: EventBus = EvtBus.instance

func _ready() -> void:
	if not data_manager or not event_bus:
		push_error("AlbumView: Missing manager instances")
		return
	
	work_state = UIStateManager.UIState.ALBUM_VIEW
	item_height = 173 # 间距29 项高144
	item_spacing = 29
	snap_offset_y = 0

	# 连接事件
	data_manager.data_loaded.connect(_load_albums)

	super._ready()

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

		counter += 1

## 清空列表
func _clear_list() -> void:
	if container == null:
		return
	
	for item in container.get_children():
		item.queue_free()
	
	list_items.clear()


func _process(delta):
	super._process(delta)
	
	if scroll_velocity == 0 and not (is_dragging_bar or is_dragging_list):
		if not need_snap:
			if selected_item == -1:
				need_snap = true
			elif not container.get_child(selected_item).is_selected:
				selected_item = -1
				need_snap = true
				
	else:
		need_snap = false
		if selected_item!= -1 and not is_dragging_list:
			reset_selection()

	# 图片移动
	process_item_cover_move()

func reset_selection():
	if selected_item!= -1:
		var temp = get_child(0).get_child(selected_item)
		temp.button.button_pressed = false

		selected_item= -1

func _on_button_confirmed(index: int):
	var album_id = current_albums[index].id
	event_bus.album_selected.emit(album_id)
	UiStatMGR.change_state(UiStatMGR.UIState.SONG_VIEW)

func _on_button_toggled(toggled_on: bool, index:int):
	if toggled_on:
		need_snap = true
		selected_item = index
