extends Control

# Root 节点脚本
# 重构后的主节点，负责初始化核心系统

## 核心系统引用
var data_manager: DataManager
var event_bus: EventBus
var state_manager: UIStateManager
var animation_manager: AnimationManager
var sorting_engine: SortingEngine
var gameplay_manager: GameplayManager
var audio_manager: AudioManager
var midi_playback_manager: MidiPlaybackManager
var key_sequence_manager: KeySequenceManager
var config_loader: ConfigLoader
var logger: GameLogger
var filesystem_manager: FileSystemManager

# UI组件路径
@export var midi_view_path: String
@export var store_view_path: String
@export var track_view_path: String
@export var play_view_path: String
@export var setting_view_path: String

func _ready():	
	# 初始化架构的核心系统
	_initialize_core_systems()
	# get_viewport().gui_focus_changed.connect(func(node):
	# 	print("[Main] Focus changed to: %s" % node.name)
	# )

## 初始化核心系统
func _initialize_core_systems() -> void:
	print("=== Initializing Core Systems ===")


	# 1. 初始化日志系统（单例，已自动管理）
	logger = GameLogger.instance
	if logger:
		logger.info("Logger initialized", "Main")
	
	# 2. 初始化配置加载器
	config_loader = ConfigLoader.new()
	if logger:
		logger.info("ConfigLoader initialized", "Main")
	
	# 3. 初始化文件系统管理器（单例，已自动管理）
	filesystem_manager = FileSystemManager.new()
	filesystem_manager.name = "FileSystemManager"
	add_child(filesystem_manager)
	if logger:
		logger.info("FileSystemManager initialized", "Main")
	
	# 初始化目录结构
	filesystem_manager.initialize_directory_structure()
	
	# 4. 初始化事件总线（单例，已自动管理）
	event_bus = EventBus.instance
	if event_bus and logger:
		logger.info("EventBus initialized", "Main")
	
	# 5. 初始化UI状态管理器（单例，已自动管理）
	state_manager = UIStateManager.instance
	if state_manager and logger:
		logger.info("UIStateManager initialized", "Main")
	
	# 6. 初始化动画管理器（单例，已自动管理）
	animation_manager = AnimationManager.instance
	if animation_manager and logger:
		logger.info("AnimationManager initialized", "Main")
	
	# 7. 初始化排序引擎（单例，已自动管理）
	sorting_engine = SortingEngine.instance
	if sorting_engine and logger:
		logger.info("SortingEngine initialized", "Main")
	
	# 8. 初始化数据管理器（单例，已自动管理）
	data_manager = DataManager.instance
	if data_manager and logger:
		logger.info("DataManager initialized", "Main")
	
	# 9. 初始化游戏管理器
	gameplay_manager = GameplayManager.new()
	gameplay_manager.name = "GameplayManager"
	add_child(gameplay_manager)
	if logger:
		logger.info("GameplayManager initialized", "Main")
	
	# 10. 初始化音频管理器
	audio_manager = AudioManager.new()
	audio_manager.name = "AudioManager"
	add_child(audio_manager)
	if logger:
		logger.info("AudioManager initialized", "Main")
	
	# 11. 初始化MIDI播放管理器
	midi_playback_manager = MidiPlaybackManager.new()
	midi_playback_manager.name = "MidiPlaybackManager"
	add_child(midi_playback_manager)
	if logger:
		logger.info("MidiPlaybackManager initialized", "Main")
	
	# 12. 初始化键序列管理器
	key_sequence_manager = KeySequenceManager.new()
	key_sequence_manager.name = "KeySequenceManager"
	add_child(key_sequence_manager)
	if logger:
		logger.info("KeySequenceManager initialized", "Main")

	# 13. 初始化并加载UI（确保各管理器已就绪）
	_init_ui()
	
	# 连接信号
	_connect_signals()
	
	# 加载配置
	_load_configuration()
	
	# 异步加载MIDI数据
	_load_midi_data()
	
	print("=== Core Systems Initialized ===")

func _init_ui() -> void:
	# Midi详细界面 (不提前初始化的话，内部的midi list可能收不到信号)
	var Main = get_node_or_null("/root/Main")
	var info_ui = Main.get_node_or_null("InfoUI")
	if not info_ui:
		var info_window = load(midi_view_path).instantiate()
		info_window.visible = false
		Main.add_child(info_window)
		info_ui = Main.get_node_or_null("InfoUI")

	# Midi商店
	var store_page = load(store_view_path).instantiate()
	store_page.visible = false
	store_page.z_index = 10
	Main.add_child(store_page)

	for i in range(30):
		store_page.get_node("StoreMidiList").create_and_add_item("%d" % i, "StoreMidiItem")

	# 音轨界面
	var track_list = load(track_view_path).instantiate()
	track_list.visible = false
	track_list.position = Vector2(track_list.position.x-1080*tan(deg_to_rad(15)), 1080)
	Main.add_child(track_list)
	
	# 设置界面
	var setting_page = load(setting_view_path).instantiate()
	setting_page.visible = false
	Main.add_child(setting_page)


	# 移动返回按钮到上层
	var right_bottom = get_node("RB_Btn")
	move_child(right_bottom ,-1)
	right_bottom.z_index = 20

	# 设置按钮
	var left_top = get_node("LT_Btn")
	move_child(left_top ,-1)
	left_top.z_index = 20
	
	# 播放界面
	var play_page = load(play_view_path).instantiate()
	play_page.visible = false
	play_page.z_index = 21
	Main.add_child(play_page)

## 连接核心系统信号
func _connect_signals() -> void:
	# 数据加载完成信号
	data_manager.data_loaded.connect(_on_data_loaded)
	
	# 状态改变信号
	state_manager.state_changed.connect(_on_state_changed)
	
	# 错误处理
	event_bus.error_occurred.connect(_on_error_occurred)
	
	# 设置变化信号
	event_bus.settings_changed.connect(_on_settings_changed)

## 加载配置文件
func _load_configuration() -> void:
	var config_path = "res://Resources/Config/config.ini"
	var config = config_loader.load_config(config_path)
	
	if not config.is_empty():
		logger.info("Configuration loaded successfully", "Main")
		
		# 应用音频设置
		var master_vol = config_loader.get_int(config, "Audio", "master_volume", 80)
		var music_vol = config_loader.get_int(config, "Audio", "music_volume", 80)
		var sfx_vol = config_loader.get_int(config, "Audio", "effects_volume", 80)
		
		audio_manager.set_master_volume(master_vol)
		audio_manager.set_music_volume(music_vol)
		audio_manager.set_sfx_volume(sfx_vol)
	else:
		logger.warning("Failed to load configuration file", "Main")

## 加载MIDI数据
func _load_midi_data() -> void:
	logger.info("Starting MIDI data load...", "Main")
	
	# 等待 FileSystemManager 资源准备完毕
	var max_wait_frames = 300  # 最多等待5秒（300帧 * 60fps）
	var wait_count = 0
	
	while not filesystem_manager.resources_scanned and wait_count < max_wait_frames:
		await get_tree().process_frame
		wait_count += 1
	
	if not filesystem_manager.resources_scanned:
		logger.warning("FileSystemManager resources timeout - proceeding anyway", "Main")
	else:
		logger.info("FileSystemManager resources scanned, starting MIDI load...", "Main")
	
	data_manager.load_all_midis_async()

## 数据加载完成回调
func _on_data_loaded() -> void:
	logger.info("MIDI data loaded successfully", "Main")
	
	# 发送数据就绪事件
	event_bus.data_loaded_complete.emit()

## UI状态改变回调
func _on_state_changed(old_state: int, new_state: int) -> void:
	var old_name = state_manager.get_state_name(old_state)
	var new_name = state_manager.get_state_name(new_state)
	logger.debug("UI State changed: %s -> %s" % [old_name, new_name], "Main")

## 错误处理回调
func _on_error_occurred(error_code: int, error_message: String) -> void:
	logger.error("Error %d: %s" % [error_code, error_message], "Main")

## 设置变化回调
func _on_settings_changed(setting_name: String, value: Variant) -> void:
	# 通配符 "*" 表示批量设置变更，重新加载所有配置
	if setting_name == "*":
		logger.info("Settings changed, reloading all configurations", "Main")
		_reload_all_settings()
		return
	
	# 处理单个设置项变更
	logger.debug("Setting changed: %s = %s" % [setting_name, value], "Main")
	_apply_single_setting(setting_name, value)

## 重新加载所有设置
func _reload_all_settings() -> void:
	# 从用户配置文件重新加载
	var user_config_path = "user://files/settings.ini"
	if not FileAccess.file_exists(user_config_path):
		logger.warning("User settings file not found, using defaults", "Main")
		return
	
	var config = config_loader.load_config(user_config_path)
	if config.is_empty():
		logger.warning("Failed to load user settings", "Main")
		return
	
	# 应用音频设置
	if config.has("Audio"):
		var audio_section = config["Audio"]
		if audio_manager:
			audio_manager.set_master_volume(int(audio_section.get("master_volume", 80)))
			audio_manager.set_music_volume(int(audio_section.get("music_volume", 80)))
			audio_manager.set_sfx_volume(int(audio_section.get("effects_volume", 80)))
	
	# 应用Gameplay设置（包括SoundFont）
	if config.has("Gameplay"):
		var gameplay_section = config["Gameplay"]
		if audio_manager and gameplay_section.has("soundfont_file"):
			var soundfont_name = gameplay_section.get("soundfont_file", "GeneralUser-GS.sf2")
			midi_playback_manager.set_soundfont(soundfont_name)
	
	# 应用显示设置
	if config.has("Display"):
		var display_section = config["Display"]
		var fullscreen = display_section.get("fullscreen", "true").to_lower() in ["true", "1", "yes"]
		var vsync = display_section.get("vsync_enabled", "true").to_lower() in ["true", "1", "yes"]
		
		if fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	
	logger.info("All settings reloaded and applied", "Main")

## 应用单个设置项
func _apply_single_setting(setting_name: String, value: Variant) -> void:
	# 音频相关设置
	if setting_name in ["master_volume", "music_volume", "effects_volume"]:
		if audio_manager:
			match setting_name:
				"master_volume":
					audio_manager.set_master_volume(int(value))
				"music_volume":
					audio_manager.set_music_volume(int(value))
				"effects_volume":
					audio_manager.set_sfx_volume(int(value))
	
	# SoundFont相关设置
	elif setting_name == "soundfont_select":
		if midi_playback_manager:
			var soundfont_name = str(value)
			midi_playback_manager.set_soundfont(soundfont_name)
	
	# 显示相关设置
	elif setting_name == "fullscreen":
		var is_fullscreen = value in ["1", "true", "True", "yes", "Yes"]
		if is_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	
	elif setting_name == "vsync_enabled":
		var is_vsync = value in ["1", "true", "True", "yes", "Yes"]
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if is_vsync else DisplayServer.VSYNC_DISABLED)

# 在 AspectRatioContainer 的父节点添加脚本
