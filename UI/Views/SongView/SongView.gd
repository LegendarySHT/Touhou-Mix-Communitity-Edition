## 歌曲视图
## 显示选中专辑下的所有歌曲列表
extends BaseScrollList

class_name SongView

## 当前显示的歌曲列表
var current_songs: Array[SongData] = []
## 当前已选中的专辑 ID
var current_album_id: String = ""

## 管理器引用
@onready var data_manager: DataManager = DataManager.instance
@onready var event_bus: EventBus = EvtBus.instance
@onready var state_manager = UIStateManager.instance

func _ready() -> void:
	# 获取管理器引用
	if not data_manager or not event_bus:
		push_error("SongView: Missing manager instances")
		return
	
	work_state = UIStateManager.UIState.SONG_VIEW
	item_height = 140
	item_spacing = 29

	# 连接事件
	event_bus.album_selected.connect(_load_songs)
	event_bus.midi_deleted.connect(func(_id): if not current_album_id.is_empty(): _load_songs(current_album_id))

	super._ready()

## 加载指定专辑的歌曲
func _load_songs(album_id: String) -> void:
	if not data_manager:
		return
	current_album_id = album_id
	current_songs = data_manager.get_songs_by_album(album_id)
	_refresh_display()

	_connect_head_and_tail()

	# 加长
	container.custom_minimum_size.y = (item_height + item_spacing) * (current_songs.size() + 1)

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


func on_item_button_confirmed(index: int):
	var song_data:SongData = current_songs[index]
	print("Select Song:", song_data.name)
	# 切换到MIDI视图
	state_manager.change_state(state_manager.UIState.MIDI_VIEW)
	event_bus.emit_song_selected(song_data.id)
