## 歌曲视图
## 显示选中专辑下的所有歌曲列表
extends BaseScrollList

class_name SongView

## 当前显示的歌曲列表
var current_songs: Array[SongData] = []

## 当前选中的专辑ID
var current_album_id: String = ""

## 管理器引用
var data_manager: DataManager
var event_bus: EventBus

func _ready() -> void:
	super._ready()
	
	# 获取管理器引用
	data_manager = DataManager.instance
	event_bus = EventBus.instance
	
	if not data_manager or not event_bus:
		push_error("SongView: Missing manager instances")
		return
	
	# 连接事件
	event_bus.album_selected.connect(_on_album_selected)

## 处理专辑选择事件
func _on_album_selected(album_id: String, album_data: AlbumData) -> void:
	current_album_id = album_id
	_load_songs(album_id)

## 加载指定专辑的歌曲
func _load_songs(album_id: String) -> void:
	if not data_manager:
		return
	
	current_songs = data_manager.get_songs_by_album(album_id)
	_refresh_display()

## 刷新显示
func _refresh_display() -> void:
	# 清空现有项
	_clear_list()
	
	# 添加新项
	for song in current_songs:
		var item = create_and_add_item(song.id, "song")
		if item:
			_initialize_song_item(item, song)

## 清空列表
func _clear_list() -> void:
	if container == null:
		return
	
	for item in container.get_children():
		item.queue_free()
	
	list_items.clear()

## 初始化歌曲项
func _initialize_song_item(item: ListItemBase, song: SongData) -> void:
	# 如果item有setup方法，调用它
	if item.has_method("setup_with_song"):
		item.setup_with_song(song)

## 列表项选中回调
func _on_item_selected(item_id: String) -> void:
	if event_bus:
		# 查找对应的歌曲
		for song in current_songs:
			if song.id == item_id:
				event_bus.emit_song_selected(item_id, song)
				break

## 列表项悬停回调
func _on_item_hovered(item_id: String) -> void:
	pass

## 列表项取消悬停回调
func _on_item_unhovered() -> void:
	pass
