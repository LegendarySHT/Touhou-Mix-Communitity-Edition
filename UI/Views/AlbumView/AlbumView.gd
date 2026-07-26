## 专辑视图
## 显示所有专辑列表，支持排序和搜索
extends BaseScrollList

class_name AlbumView

## 当前显示的专辑列表
var current_albums: Array[AlbumData] = []

## 排序引擎引用
@onready var data_manager: DataManager = DataMGR
@onready var event_bus: EventBus = EvtBus

## 列表刷新控制
var _refresh_id: int = 0
@onready var _loading_node: Control = get_parent().get_node("Loading") if get_parent() else null

func _ready() -> void:
	if not data_manager or not event_bus:
		push_error("AlbumView: Missing manager instances")
		return
	
	work_state = UIStateManager.UIState.ALBUM_VIEW
	snap_offset_y = 100

	# 连接事件
	data_manager.data_loaded.connect(_load_albums)
	event_bus.midi_deleted.connect(func(_id): _load_albums())
	event_bus.config_changed.connect(_on_config_changed)
	modulate.a = 0.0

	super._ready()

## 加载专辑数据（异步，避免阻塞主线程）
func _load_albums() -> void:
	if not data_manager:
		return
	
	_refresh_id += 1
	var my_id := _refresh_id
	
	current_albums = data_manager.get_sorted_albums()
	
	# 启动 Loading 动画
	if _loading_node:
		_loading_node.start_rotation()
	
	# 异步刷新列表项（内部在首个 item 出现时自动停止 Loading）
	await _refresh_display_async(my_id)

## 配置变更时重新排序（deferred，避免阻塞 save 流程）
func _on_config_changed(key: String, section: String, _value: Variant) -> void:
	if section == "Browse":
		call_deferred("_load_albums")


## 异步刷新显示（逐帧创建列表项，避免卡顿）
func _refresh_display_async(refresh_id: int) -> void:
	clear_items()
	await get_tree().process_frame
	
	var counter := 0
	var bg := ButtonGroup.new()
	for album in current_albums:
		if refresh_id != _refresh_id:
			return  # 被新的刷新请求中断
		
		var item = create_and_add_item(album.id, "album")
		item.setup_with_album(self, album, counter, bg)
		counter += 1
		
		# 第一批出来后立即隐藏 Loading
		if counter == 1 and _loading_node:
			_loading_node.stop_rotation()
			create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
		
		# 每 3 个专辑释放一帧，保持 UI 响应
		if counter % 3 == 0:
			await get_tree().process_frame
	
	if refresh_id != _refresh_id:
		return
	
	if counter:
		_connect_head_and_tail()

func _process(delta):
	super._process(delta)

	if selected_item == -1 and not is_scrolling():
		need_snap = true

func _gui_input(event: InputEvent) -> void:
	super._gui_input(event)

func reset_selection():
	if selected_item == -1:
		return
	get_selected_node().button.button_pressed = false

	selected_item= -1

func on_item_button_confirmed(index: int):
	var album_id = current_albums[index].id
	if container.get_child(index).expand_tween:
		await container.get_child(index).expand_tween.finished
	event_bus.album_selected.emit(album_id)
	UiStatMGR.change_state(UiStatMGR.UIState.SONG_VIEW)
