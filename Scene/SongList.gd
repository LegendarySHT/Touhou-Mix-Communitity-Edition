extends ScrollContainer
var initial = 0
var index = 0

signal storeButtonSwitch(showBackButton:bool)

# 管理器引用
@onready var data_manager = DataManager.instance
@onready var state_manager = UIStateManager.instance
@onready var event_bus = EventBus.instance

# 指示当前是否有拖拽操作
# var is_dragging := false
# # 当鼠标开始拖拽至松手前，计算列表滚动值的
# var drag_pos1 = 0;
# var drag_pos2 = 0;
# 开始拖拽时的列表滚动值
# var start_scroll_v_pos = 0

var scroll: GeneralScroll

func _ready():
	# 连接事件总线
	if event_bus:
		event_bus.album_selected.connect(_on_album_selected)
	scroll = GeneralScroll.new(self)
	scroll.enable()

func _exit_tree():
	if scroll:
		scroll.disable()

func _process(delta: float):
	scroll.process(delta)
	if state_manager.current_state != state_manager.UIState.SONG_VIEW:
		return
	
	if initial == 0:
		_load_songs()
		
	# 图片移动（保持原有视觉效果）
	for i in range(get_child(0).get_child_count()):
		var cover = get_child(0).get_child(i).get_node("PC/Shader/cover")
		if cover:
			cover.position.y = 250 - ((1.0 * i / max(1, get_child(0).get_child_count() - 1)) * 800)

func _load_songs():
	if not data_manager:
		print("SongList: DataManager not available")
		return
	
	# 使用 DataManager 获取歌曲
	var songs = data_manager.get_songs_by_album(Global.album_id)
	if songs.is_empty():
		print("SongList: No songs found for album ID:", Global.album_id)
		return
	
	# 清空现有节点
	for child in get_child(0).get_children():
		child.queue_free()
	
	var button_group = ButtonGroup.new()
	index = 0
	
	for song_data in songs:
		var song = load("res://Scene/songNode.tscn").instantiate()
		song.set_meta("index", index)
		song.set_meta("sourceSongName", song_data.name)
		song.set_meta("song_id", song_data.id)  # 存储歌曲ID
		
		# 获取该歌曲的MIDI数量
		var midis = data_manager.get_midis_by_song(song_data.id)
		song.set_meta("midiCount", midis.size())
		song.get_node("PC/CountBase/SongCount").text = "%d" % midis.size()
		
		index += 1
		
		var SongName = song.get_node("PC/Shader/SongName")
		SongName.text = song_data.name
		if SongName.text == "":
			SongName.text = "Unknown"
		
		var button = song.get_node("PC/Shader/SongButton")
		button.button_group = button_group
		button.toggled.connect(_on_button_toggled.bind(button, song_data.id))
		get_child(0).add_child(song)
	
	initial = 1
	print("SongList: Loaded", songs.size(), "songs for album:", Global.album_id)

func back():
	state_manager.change_state(state_manager.UIState.ALBUM_VIEW)

func _on_button_toggled(toggled_on: bool, button, song_id: String):
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_parallel(true)
	
	var songNode = button.get_parent().get_parent().get_parent()
	if toggled_on:
		if Global.song_id == song_id:
			print("Select Song:", songNode.get_meta("sourceSongName"))
			# 切换到MIDI视图
			if event_bus:
				
				state_manager.change_state(state_manager.UIState.MIDI_VIEW)
				event_bus.emit_song_selected(song_id, data_manager.get_song_by_id(song_id))
			else:
				state_manager.change_state(state_manager.UIState.MIDI_VIEW)
			
		tween.tween_property(songNode, "scale", Vector2(1.05, 1.05), 0.1)
		Global.song_id = song_id
		Global.song = songNode.get_meta("index")
	else:
		tween.tween_property(songNode, "scale", Vector2(1, 1), 0.25)

func _update_polygon(np: Vector2, i, polygon):
	polygon.polygon[i] = np

# func _on_scrolling():
# 	# 用户正在滚动时标记为拖拽中
# 	is_dragging = true
# 	start_scroll_v_pos = scroll_vertical

func _input(event):
	scroll.input(event)
	#if state_manager.current_state != state_manager.UIState.SONG_VIEW:
		#return
	#
	## 检测鼠标释放或触摸结束
	#if event is InputEventMouseButton:
		#if event.button_index == MOUSE_BUTTON_LEFT:
			## 停止拖拽
			#if not event.pressed:
				#is_dragging = false
			## 开始拖拽
			#else:
				#_on_scrolling()
				#drag_pos1 = event.global_position.y
				#drag_pos2 = drag_pos1
	## 左键拖拽
	#elif event is InputEventMouseMotion:
		#if is_dragging:
			#drag_pos2 = event.global_position.y - drag_pos1
			#if drag_pos2 != 0:
				#scroll_vertical = -drag_pos2 * 1.5 + start_scroll_v_pos

func _on_album_selected(album_id: String, album_data: AlbumData):
	Global.album_id = album_id
	initial = 0  # 重置初始化状态，触发重新加载
