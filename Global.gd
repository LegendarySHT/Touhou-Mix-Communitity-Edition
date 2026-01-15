extends Node

## =============================================================================
##  THMIX Global 脚本 - 保持兼容性的过渡层
##  注意：这是临时的兼容层，逐步迁移旧代码到新架构后可以移除
## =============================================================================

## 新架构系统引用（从Main节点获取）
var data_manager: DataManager
var event_bus: EventBus
var state_manager: UIStateManager
var animation_manager: AnimationManager
var sorting_engine: SortingEngine


#当前选中的专辑和歌曲的编号
var album=-1;
var song=-1;
#当前选中的专辑和歌曲的名字
var album_id = ""
var song_id = ""

var _thread: Thread
var Sorting=0

#选中的经过筛选的midi
var select_midi=-1

#指示当前是否启用筛选 1表示降序，2表示升序
var Sort=0
var SortStatus=0 #0全要 1保留Pending 2Approved 3Included 4Dead



func _ready():
	# 获取新架构系统引用
	_initialize_new_architecture_refs()
	
	# 连接菜单信号
	get_node("/root/Main/Menu_Bar/HBC/Sub_Menu").menu_closed.connect(_close_sort_menu)
	
## 初始化新架构系统引用
func _initialize_new_architecture_refs() -> void:
	# 等待一帧确保Main节点已初始化
	await get_tree().process_frame
	
	var main_node = get_node("/root/Main")
	if main_node:
		data_manager = DataManager.instance
		event_bus = EventBus.instance
		state_manager = UiStatMGR.instance
		animation_manager = AniMGR.instance
		
		if data_manager:
			print("[Global] Connected to DataManager")
		if event_bus:
			print("[Global] Connected to EventBus")
			# 连接新架构的事件
			event_bus.data_loaded_complete.connect(_on_new_data_loaded)
		if state_manager:
			print("[Global] Connected to UIStateManager")
	else:
		push_warning("[Global] Main node not found, new architecture unavailable")

## 新架构数据加载完成回调
func _on_new_data_loaded() -> void:
	print("[Global] New architecture data loaded")
	# 这里可以桥接到旧系统

## 便利函数：使用新架构获取数据
func get_albums_new() -> Array:
	if data_manager:
		return data_manager.get_all_albums()
	return []

func get_songs_by_album_new(album_id: String) -> Array:
	if data_manager:
		return data_manager.get_songs_by_album(album_id)
	return []

func get_midis_by_song_new(song_id: String) -> Array:
	if data_manager:
		return data_manager.get_midis_by_song(song_id)
	return []

func _close_sort_menu() -> void:
	# Handle menu closed event
	pass

func _exit_tree():
	# 确保退出时释放线程
	if _thread != null && _thread.is_alive():
		_thread.wait_to_finish()

#路径
var ALBUMLIST="/root/Main/Album/AlbumList"
var SONGLIST="/root/Main/Song/SongList"
var _SS="/root/Main/SS/SS"



## 执行状态转换动画
func _execute_state_transition_animation(old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	# 根据状态转换执行相应的动画
	match [old_state, new_state]:
		[UIStateManager.UIState.ALBUM_VIEW, UIStateManager.UIState.SONG_VIEW]:
			_animate_album_to_song()
		[UIStateManager.UIState.SONG_VIEW, UIStateManager.UIState.ALBUM_VIEW]:
			_animate_song_to_album()
		[UIStateManager.UIState.ALBUM_VIEW, UIStateManager.UIState.SORTED_VIEW]:
			_animate_album_to_sorted()
		[UIStateManager.UIState.SORTED_VIEW, UIStateManager.UIState.ALBUM_VIEW]:
			_animate_sorted_to_album()
		[UIStateManager.UIState.SONG_VIEW, UIStateManager.UIState.MIDI_VIEW]:
			_animate_song_to_midi()
		[UIStateManager.UIState.MIDI_VIEW, UIStateManager.UIState.SONG_VIEW]:
			_animate_midi_to_song()
		[UIStateManager.UIState.MIDI_VIEW, UIStateManager.UIState.SORTED_VIEW]:
			_animate_midi_to_sorted()
		_:
			print("未处理的状态转换: %s -> %s" % [
				state_manager.get_state_name(old_state),
				state_manager.get_state_name(new_state)
			])

## 专辑视图 -> 歌曲视图动画
func _animate_album_to_song() -> void:
	print("动画: ALBUM_VIEW -> SONG_VIEW")
	
	var SS=get_node(_SS)
	var album_list=get_node(ALBUMLIST)
	var song_list=get_node(SONGLIST)
	
	# 复制并生成节点
	var polygon=Polygon2D.new()
	var copy=album_list.get_node("VBox").get_child(album).duplicate(true)
	polygon.skew=deg_to_rad(15)
	copy.name="SS"
	polygon.add_child(copy)
	polygon.name="SS"
	copy=polygon
	
	copy.position=album_list.get_node("VBox").get_child(album).global_position
	
	# 设置节点
	var button=copy.get_node("SS/PC/Polygon2D/AlbumButton")
	button.button_group=null
	button.toggle_mode=false
	get_node("/root/Main").add_child(copy)
	SS=get_node(_SS)
	
	# 创建补间动画
	var tween = animation_manager.animate_list_item_horizontal(album_list, album, -1200, "AlbumListHorizontal")
	tween.finished.connect(_finish_album_to_song.bind(SS, album_list, song_list))

## 完成专辑到歌曲的动画
func _finish_album_to_song(SS: Node, album_list: Node, song_list: Node) -> void:
	album_list.visible=false
	
	var finish_tween = animation_manager.animate_position(SS, Vector2(0, -SS.global_position.y), 0.15, "SSPosition")
	song_list.visible=true
	song_list.position=Vector2(285,-679)
	finish_tween.parallel().tween_property(song_list,"position",Vector2(song_list.position.x, 440),0.15)
	animation_manager.animate_fade_in(song_list, 1, "SongListFadeIn")

	var button=SS.get_node("PC/Polygon2D/AlbumButton")
	button.pressed.connect(song_list.back)

## 歌曲视图 -> 专辑视图动画
func _animate_song_to_album() -> void:
	print("动画: SONG_VIEW -> ALBUM_VIEW")
	
	var song_list=get_node(SONGLIST)
	var album_list=get_node(ALBUMLIST)
	var SS=get_node(_SS)

	album_list.get_node("VBox").get_child(album).modulate = Color(1, 1, 1, 0)
	animation_manager.animate_position(SS, Vector2(0, SS.global_position.y), 0.15, "SSPosition")
	album_list.visible=true
	
	# 歌曲列表收起
	animation_manager.animate_fade_out(song_list, 0.25, "SongListFadeOut")
	var tween = animation_manager.animate_position(song_list, Vector2(song_list.position.x, 2*song_list.position.y), 0.25, "SongListPosition")
	animation_manager.animate_list_item_horizontal(album_list, album, 0, "AlbumListHorizontal")
	
	tween.finished.connect(_finish_song_to_album.bind(SS, album_list, song_list))

## 完成歌曲到专辑的动画
func _finish_song_to_album(SS:Node,album_list:Node, song_list: Node) -> void:
	album_list.get_node("VBox").get_child(album).modulate = Color(1, 1, 1, 1)
	SS.get_parent().queue_free()

	song_list.initial=0
	# 释放子项
	song_list.visible=false
	for i in song_list.get_child(0).get_children():
		i.queue_free()

# 右侧组件的进出动画
func _right_comp_InOut(AniIn: bool):
	var vet1 = Vector2(1305, 15)
	var vet2 = Vector2(0, 0)
	var vet3 = Vector2(-44.393, 257.71)
	if not AniIn:
		vet1 = Vector2(1305+53.58,-215-800)
		vet2 = Vector2(0,950)
		vet3 = Vector2(-44.393+650,257.71)
	animation_manager.animate_position(get_node("/root/Main/Menu_Bar"), vet1, 0.25, "MenuBarPosition")
	animation_manager.animate_position(get_node("/root/Main/Player_Info/Charactor"), vet2, 0.15, "CharactorPosition")
	animation_manager.animate_position(get_node("/root/Main/Player_Info"), vet3, 0.5, "PlayerInfoPosition")

## 专辑视图 -> 排序视图动画
func _animate_album_to_sorted() -> void:
	print("动画: ALBUM_VIEW -> SORTED_VIEW")
	
	animation_manager.animate_position(get_node("/root/Main/SortedMidi"), Vector2(-1500, 0), 0.25, "SortedMidiPosition")
	
	# 右侧退场
	_right_comp_InOut(false)
	
	var song_list=get_node(SONGLIST)
	song_list.storeButtonSwitch.emit(true)
	
	# MIDI界面入场
	var Main=get_node("/root/Main")
	if not Main.get_node("InfoUI"):
		var info_window=load("res://Scene/info_ui.tscn").instantiate()
		Main.add_child(info_window)
	else:
		Main.get_node("InfoUI").visible=true
		Main.get_node("InfoUI").modulate=Color(1,1,1,1)
	
	Main.get_node("InfoUI").position=Vector2(130+500*0.2679,-450)
	
	var tween = animation_manager.animate_position(Main.get_node("InfoUI"), Vector2(130,50), 0.5, "InfoUIPosition")
	tween.finished.connect(_finish_album_to_sorted)

## 完成专辑到排序的动画
func _finish_album_to_sorted() -> void:
	print("切换到排序视图完成")
	get_node("/root/Main/SortedMidi").visible=false
	

## 排序视图 -> 专辑视图动画
func _animate_sorted_to_album() -> void:
	print("动画: SORTED_VIEW -> ALBUM_VIEW")
	
	var Main=get_node("/root/Main")
	var tween = animation_manager.animate_fade_out(Main.get_node("InfoUI"), 0.1, "InfoUIFadeOut")
	
	tween.finished.connect(_finish_sorted_to_album_first.bind(Main))

## 完成排序到专辑的第一步动画
func _finish_sorted_to_album_first(Main: Node) -> void:
	Main.get_node("InfoUI").visible=false
	if Main.get_node("InfoUI/OptionWindow/Option/Rank"):
		Main.get_node("InfoUI/OptionWindow/Option/Rank").button_pressed=true
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	var song_list=get_node(SONGLIST)
	tween.tween_property(song_list,"position",Vector2(285,390),0.5)
	
	# 右侧
	tween.tween_property(get_node("/root/Main/Menu_Bar"),"position",Vector2(1305,15),0.25)
	tween.tween_property(get_node("/root/Main/Player_Info/Charactor"),"position",Vector2(0,0),0.15)
	tween.tween_property(get_node("/root/Main/Player_Info"),"position",Vector2(-44.393,257.71),0.5)
	
	song_list.storeButtonSwitch.emit(false)
	
	get_node("/root/Main/SortedMidi").visible=true
	tween.tween_property(get_node("/root/Main/SortedMidi"),"position",Vector2(0,0),1)
	
	tween.finished.connect(_finish_sorted_to_album_final)

## 完成排序到专辑的最终动画
func _finish_sorted_to_album_final() -> void:
	get_node("/root/Main/Menu_Bar/HBC/Sub_Menu").switch_table(1)

## 歌曲视图 -> MIDI视图动画
func _animate_song_to_midi() -> void:
	print("动画: SONG_VIEW -> MIDI_VIEW")
	
	var SS=get_node(_SS)
	var song_list=get_node(SONGLIST)
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	
	# 本页面退场
	tween.tween_property(song_list,"position",Vector2(1080*0.2679,-779),0.5)
	# 左侧离场
	tween.tween_property(SS.get_node("PC"),"modulate",Color(1,1,1,0),0.5)
	# 右侧离场
	tween.tween_property(get_node("/root/Main/Menu_Bar"),"position",Vector2(1305+53.58,-215),0.25)
	tween.tween_property(get_node("/root/Main/Player_Info/Charactor"),"position",Vector2(0,950),0.15)
	tween.tween_property(get_node("/root/Main/Player_Info"),"position",Vector2(-44.393+650,257.71),0.5)
	
	song_list.storeButtonSwitch.emit(true)
	
	# 左侧入场
	var Main=get_node("/root/Main")
	if not Main.get_node("InfoUI"):
		var info_window=load("res://Scene/info_ui.tscn").instantiate()
		Main.add_child(info_window)
	else:
		Main.get_node("InfoUI").visible=true
		Main.get_node("InfoUI").modulate=Color(1,1,1,1)
	
	Main.get_node("InfoUI").position=Vector2(130+500*0.2679,-450)
	tween.tween_property(Main.get_node("InfoUI"),"position",Vector2(130,50),0.5)
	
	tween.finished.connect(_finish_song_to_midi.bind(SS, song_list))

## 完成歌曲到MIDI的动画
func _finish_song_to_midi(SS: Node, song_list: Node) -> void:
	song_list.visible=false
	SS.visible=false

## MIDI视图 -> 歌曲视图动画
func _animate_midi_to_song() -> void:
	print("动画: MIDI_VIEW -> SONG_VIEW")
	
	var Main=get_node("/root/Main")
	var tween = create_tween()
	
	tween.tween_property(Main.get_node("InfoUI"),"modulate",Color(1,1,1,0),0.1)
	
	tween.finished.connect(_finish_midi_to_song_first.bind(Main))

## 完成MIDI到歌曲的第一步动画
func _finish_midi_to_song_first(Main: Node) -> void:
	Main.get_node("InfoUI").visible=false
	if Main.get_node("InfoUI/OptionWindow/Option/Rank"):
		Main.get_node("InfoUI/OptionWindow/Option/Rank").button_pressed=true
	
	var SS=get_node(_SS)
	var song_list=get_node(SONGLIST)

	# 歌曲列表入场	
	animation_manager.animate_position(song_list, Vector2(song_list.position.x, 440), 0.5, "SongListPosition")
	# 信息框入场
	animation_manager.animate_position(SS, Vector2(0, -177.5), 0.2, "SSPosition")
	animation_manager.animate_fade_in(SS.get_node("PC"), 0.25, "SSFadeIn")
	# 右侧组件入场
	_right_comp_InOut(true)

	song_list.storeButtonSwitch.emit(false)
	
	song_list.visible=true
	SS.visible=true
	song = -1
	
## MIDI视图 -> 排序视图动画
func _animate_midi_to_sorted() -> void:
	print("动画: MIDI_VIEW -> SORTED_VIEW")
	
	# 这个转换与 SORTED_VIEW -> ALBUM_VIEW 类似，但目标不同
	_animate_sorted_to_album()
