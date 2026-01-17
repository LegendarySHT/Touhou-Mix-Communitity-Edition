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

## 初始化标志（防止重复初始化）
var _architecture_initialized: bool = false

#当前选中的专辑和歌曲的编号
var album: int= -1
var song: int = -1

#选中的经过筛选的midi
var select_midi: int = -1

#当前选中的专辑和歌曲的名字
var album_id: String = ""
var song_id: String = ""




func _ready():
	# 获取新架构系统引用
	_initialize_new_architecture_refs()
	
	# 连接菜单信号
	get_node("/root/Main/Menu_Bar/HBC/Sub_Menu").menu_closed.connect(_close_sort_menu)
	
## 初始化新架构系统引用
func _initialize_new_architecture_refs() -> void:
	# 防止重复初始化
	if _architecture_initialized:
		return
	_architecture_initialized = true
	
	# 等待一帧确保Main节点已初始化
	await get_tree().process_frame
	
	var main_node = get_node("/root/Main")
	if main_node:
		data_manager = DataManager.instance
		event_bus = EventBus.instance
		state_manager = UIStateManager.instance
		animation_manager = AnimationManager.instance
		
		if data_manager:
			print("[Global] Connected to DataManager")
		if event_bus:
			print("[Global] Connected to EventBus")
			# 连接新架构的事件（先断开已有连接再重新连接）
			if event_bus.data_loaded_complete.is_connected(_on_new_data_loaded):
				event_bus.data_loaded_complete.disconnect(_on_new_data_loaded)
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
	pass
