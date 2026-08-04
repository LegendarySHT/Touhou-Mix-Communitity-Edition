## 歌曲视图
## 显示选中专辑下的所有歌曲列表
extends BaseScrollList

class_name SongView

## 当前显示的歌曲列表
var current_songs: Array = []
## 当前已选中的专辑 ID
var current_album_id: String = ""

## 标记 _load_songs 刚被调用（album_selected 触发，先于 state_changed）
## 用于跳过 state_changed lambda 中的冗余 _refresh_from_data 重建
## （_load_songs 已创建列表项，lambda 再重建会导致封面加载被中断重发）
var _load_songs_just_called: bool = false

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
	# 设置直接相邻状态：切到不在此集合的状态时释放所有列表项封面
	# SONG_VIEW 相邻：ALBUM_VIEW（返回）、MIDI_VIEW（点进歌曲）
	set_adjacent_states([
		UIStateManager.UIState.ALBUM_VIEW,
		UIStateManager.UIState.MIDI_VIEW,
	])
	# 连接事件
	event_bus.album_selected.connect(_load_songs)
	event_bus.midi_deleted.connect(func(_id): if not current_album_id.is_empty(): _load_songs(current_album_id))
	# 回到 SongView 时自动刷新，确保删除等操作后数据最新
	# 但 _load_songs 已处理首次进入和 album_selected 触发的场景，
	# 需跳过冗余重建避免封面加载被中断
	state_manager.state_changed.connect(func(_old, new):
		if new == UIStateManager.UIState.SONG_VIEW and not current_album_id.is_empty():
			if _load_songs_just_called:
				_load_songs_just_called = false
				return  # _load_songs 已创建列表项,跳过冗余重建
			call_deferred("_refresh_from_data")
	)

	super._ready()

	# 注册主题色应用器，由 ThemeManager 在主题切换时广播调用
	if ThemeMGR:
		ThemeMGR.register_theme_applier(self)
		apply_theme()

## 应用主题色（由 ThemeManager 广播调用 + _ready 首次自调）
func apply_theme() -> void:
	if item_instance:
		ThemeMGR._style_song_instance(item_instance, ThemeMGR.get_color("primary_light"))

func _exit_tree() -> void:
	if ThemeMGR:
		ThemeMGR.unregister_theme_applier(self)

## 加载指定专辑的歌曲
func _load_songs(album_id: String) -> void:
	if not data_manager:
		return
	_load_songs_just_called = true  # 标记,供 state_changed lambda 跳过冗余重建
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
		if ChartDB.GetAlbum(current_album_id).is_empty():
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
		var item = create_and_add_item(String(song.get("id", "")), "song")
		if item:
			item.setup_with_dict(self, song, counter, bg)
			counter += 1
	# 列表构建完成，触发未加载项的封面加载
	trigger_cover_chain()

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
		if ChartDB.GetAlbum(current_album_id).is_empty():
			_deferred_go_back()

## 同步更新 SS 节点（AnimationManager 在 SongView 过渡时从专辑列表复制的快照）的歌曲计数
func _update_ss_count() -> void:
	var album: Dictionary = ChartDB.GetAlbum(current_album_id)
	if album.is_empty():
		return
	var ss_node = get_node_or_null("/root/Main/skew/SS")
	if not is_instance_valid(ss_node):
		return
	var count_label = ss_node.get_node_or_null("SongCount")
	if is_instance_valid(count_label):
		count_label.text = "%d" % album.get("song_ids", []).size()


func on_item_button_confirmed(index: int):
	if index < 0 or index >= current_songs.size():
		return
	var song: Dictionary = current_songs[index]
	print("Select Song:", song.get("name", ""))
	# 切换到MIDI视图
	state_manager.change_state(state_manager.UIState.MIDI_VIEW)
	event_bus.emit_song_selected(String(song.get("id", "")))
