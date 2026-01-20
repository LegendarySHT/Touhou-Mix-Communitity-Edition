## 歌曲视图
## 显示选中专辑下的所有歌曲列表
extends BaseScrollList

class_name SongView

## 当前显示的歌曲列表
var current_songs: Array[SongData] = []
var selected_song: int = -1

## 管理器引用
@onready var data_manager: DataManager = DataManager.instance
@onready var event_bus: EventBus = EvtBus.instance
@onready var state_manager = UIStateManager.instance

func _ready() -> void:
	super._ready()
	
	# 获取管理器引用
	if not data_manager or not event_bus:
		push_error("SongView: Missing manager instances")
		return
	
	item_height = 169
	item_spacing = 29

	# 连接事件
	event_bus.album_selected.connect(_load_songs)

func _process(delta: float):
	if state_manager.current_state != state_manager.UIState.SONG_VIEW:
		return
	super._process(delta)

func _input(event):
	if state_manager.current_state != state_manager.UIState.SONG_VIEW:
		return
	super._input(event)

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
	
	selected_song = -1
	var counter:int = 0
	var bg = ButtonGroup.new()
	# 添加新项
	for song in current_songs:
		var item = create_and_add_item(song.id, "song")
		if item:
			item.setup_with_song(self, song, counter, bg)
			counter += 1
	
	
	# 设置图片位置
	for i in range(counter):
		var cover = get_child(0).get_child(i).get_node("PC/Shader/cover")
		if cover:
			var y_pos = -(floori(item_height * i ) % int(cover.size.y-item_height))
			cover.position.y = y_pos

## 清空列表
func _clear_list() -> void:
	if container == null:
		return
	
	for item in container.get_children():
		item.queue_free()
	
	list_items.clear()

func _on_button_toggled(toggled_on: bool, songNode, song_id: String):
	if toggled_on:
		if selected_song == songNode.get_meta("index"):
			print("Select Song:", songNode.song_data.name)
			# 切换到MIDI视图
			state_manager.change_state(state_manager.UIState.MIDI_VIEW)
			event_bus.emit_song_selected(song_id)
		selected_song = songNode.get_meta("index")

# ## 列表项选中回调
# func _on_item_selected(item_id: String) -> void:
# 	if event_bus:
# 		# 查找对应的歌曲
# 		for song in current_songs:
# 			if song.id == item_id:
# 				event_bus.emit_song_selected(item_id, song)
# 				break

# ## 列表项悬停回调
# func _on_item_hovered(item_id: String) -> void:
# 	pass

# ## 列表项取消悬停回调
# func _on_item_unhovered() -> void:
# 	pass
