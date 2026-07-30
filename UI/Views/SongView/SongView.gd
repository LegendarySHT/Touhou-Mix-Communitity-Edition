## 歌曲视图
## 显示选中专辑下的所有歌曲列表
extends BaseScrollList

class_name SongView

## 当前显示的歌曲列表
var current_songs: Array[SongData] = []
## 当前已选中的专辑 ID
var current_album_id: String = ""

## 管理器引用
@onready var data_manager: DataManager = DataMGR
@onready var event_bus: EventBus = EvtBus
@onready var state_manager = UiStatMGR

func _ready() -> void:
	# 获取管理器引用
	if not data_manager or not event_bus:
		push_error("SongView: Missing manager instances")
		return
	
	work_state = UIStateManager.UIState.SONG_VIEW
	# 连接事件
	event_bus.album_selected.connect(_load_songs)
	event_bus.midi_deleted.connect(func(_id): if not current_album_id.is_empty(): _load_songs(current_album_id))
	# 回到 SongView 时自动刷新，确保删除等操作后数据最新
	state_manager.state_changed.connect(func(_old, new):
		if new == UIStateManager.UIState.SONG_VIEW and not current_album_id.is_empty():
			call_deferred("_refresh_from_data")
	)

	super._ready()

## 加载指定专辑的歌曲
func _load_songs(album_id: String) -> void:
	if not data_manager:
		return
	current_album_id = album_id
	current_songs = data_manager.get_songs_by_album(album_id)
	_refresh_display()

	_connect_head_and_tail()
	_update_ss_count()

	# 加长
	container.custom_minimum_size.y = (140 + 29) * (current_songs.size() + 1)

	# 安全网：若歌曲列表为空且 Album 也被删除（级联），延迟退回 AlbumView
	# 若 Song 被删除但 Album 仍存在，则显示该 Album 的空列表（不退回）
	if current_songs.is_empty() and state_manager.current_state == UIStateManager.UIState.SONG_VIEW:
		var album_data = data_manager.get_album_by_id(current_album_id)
		if album_data == null:
			# Album 也被删除，安全退回
			call_deferred("_deferred_go_back")

## 刷新显示
func _refresh_display() -> void:
	# 清空现有项
	clear_items()
	
	var is_active := UiStatMGR.current_state == UIStateManager.UIState.SONG_VIEW
	var no_items := get_node_or_null("/root/Main/skew/C/NoItems")
	
	if current_songs.is_empty():
		if no_items and is_active:
			no_items.visible = true
		return
	
	# 列表非空，隐藏空提示
	if no_items:
		no_items.visible = false
	
	var counter:int = 0
	var bg = ButtonGroup.new()
	# 添加新项
	for song in current_songs:
		var item = create_and_add_item(song.id, "song")
		if item:
			item.setup_with_song(self, song, counter, bg)
			counter += 1

func _gui_input(event: InputEvent) -> void:
	super._gui_input(event)

func _deferred_go_back() -> void:
	if current_songs.is_empty() and state_manager.current_state == UIStateManager.UIState.SONG_VIEW:
		state_manager.go_back()

## 从 DataManager 重新拉取并刷新列表（call_deferred 调用，确保在状态转换完成后执行）
func _refresh_from_data() -> void:
	if current_album_id.is_empty():
		return
	current_songs = data_manager.get_songs_by_album(current_album_id)
	_refresh_display()
	_connect_head_and_tail()
	_update_ss_count()
	container.custom_minimum_size.y = (140 + 29) * (current_songs.size() + 1)
	if current_songs.is_empty():
		var album_data = data_manager.get_album_by_id(current_album_id)
		if album_data == null:
			_deferred_go_back()

## 同步更新 SS 节点（AnimationManager 在 SongView 过渡时从专辑列表复制的快照）的歌曲计数
func _update_ss_count() -> void:
	var album_data = data_manager.get_album_by_id(current_album_id)
	if not album_data:
		return
	var ss_node = get_node_or_null("/root/Main/skew/SS")
	if not is_instance_valid(ss_node):
		return
	var count_label = ss_node.get_node_or_null("SongCount")
	if is_instance_valid(count_label):
		count_label.text = "%d" % album_data.song_ids.size()


func on_item_button_confirmed(index: int):
	var song_data:SongData = current_songs[index]
	print("Select Song:", song_data.name)
	# 切换到MIDI视图
	state_manager.change_state(state_manager.UIState.MIDI_VIEW)
	event_bus.emit_song_selected(song_data.id)
