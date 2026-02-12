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
var config_loader: ConfigManager
var logger: GameLogger
var filesystem_manager: FileSystemManager
var _is_reloading_settings: bool = false

# UI组件路径
@export var midi_view_path: String
@export var store_view_path: String
@export var track_view_path: String
@export var play_view_path: String
@export var score_view_path: String
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
	
	# 2. 初始化配置管理器（单例，已自动管理）
	config_loader = ConfigManager.instance
	if logger:
		logger.info("ConfigManager initialized", "Main")
	
	# 2.5. **关键**：立即加载并设置当前配置，以便后续 Manager 初始化时能读取配置
	# 必须在其他 Manager 初始化之前调用
	config_loader.clear_cache()
	config_loader.load_and_set_current()
	if logger:
		logger.info("Configuration pre-loaded before Manager initialization", "Main")
	
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
	var SkewArea = Main.get_node("skew/C")

	var info_window = load(midi_view_path).instantiate()
	info_window.visible = false
	SkewArea.add_child(info_window)

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
	SkewArea.add_child(track_list)
	
	# 设置界面
	var setting_page = load(setting_view_path).instantiate()
	setting_page.visible = false
	SkewArea.add_child(setting_page)

	# 结算界面
	var score_page = load(score_view_path).instantiate()
	score_page.visible = false
	Main.add_child(score_page)

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
	
	# 配置变更信号（新增）
	event_bus.config_changed.connect(_on_config_changed)

## 加载配置文件（验证和应用）
func _load_configuration() -> void:
	# 配置已在 _initialize_core_systems() 中预加载
	# 这里仅进行验证和应用
	var config = config_loader.get_current_config()
	
	if config.is_empty():
		logger.warning("Current configuration is empty", "Main")
		return
	
	logger.info("Configuration loaded successfully, sections: %d" % config.size(), "Main")
	
	# 检查版本并迁移（如必要）
	config_loader.check_and_migrate()
	
	# 应用音频设置
	var master_vol = config_loader.get_int("Audio", "master_volume", 80)
	var music_vol = config_loader.get_int("Audio", "music_volume", 80)
	var sfx_vol = config_loader.get_int("Audio", "effects_volume", 80)
	
	logger.debug("Audio config: master=%d, music=%d, sfx=%d" % [master_vol, music_vol, sfx_vol], "Main")
	
	audio_manager.set_master_volume(master_vol)
	audio_manager.set_music_volume(music_vol)
	audio_manager.set_sfx_volume(sfx_vol)

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
	if _is_reloading_settings:
		return
	_is_reloading_settings = true
	# 重新加载配置
	config_loader.reload_config()
	
	# 应用音频设置
	if audio_manager:
		var master_vol = config_loader.get_int("Audio", "master_volume", 80)
		var music_vol = config_loader.get_int("Audio", "music_volume", 80)
		var sfx_vol = config_loader.get_int("Audio", "effects_volume", 80)
		
		audio_manager.set_master_volume(master_vol)
		audio_manager.set_music_volume(music_vol)
		audio_manager.set_sfx_volume(sfx_vol)
	
	# 应用Gameplay设置（包括SoundFont）
	if midi_playback_manager:
		var soundfont_name = config_loader.get_value("Gameplay", "soundfont_file", "GeneralUser-GS.sf2")
		midi_playback_manager.set_soundfont(soundfont_name)
	
	# 应用显示设置
	var fullscreen = config_loader.get_bool("Display", "fullscreen", true)
	var vsync = config_loader.get_bool("Display", "vsync_enabled", true)
	
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	
	logger.info("All settings reloaded and applied", "Main")
	_is_reloading_settings = false

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

	# MIDI后端设置
	elif setting_name == "midi_backend":
		if midi_playback_manager:
			var backend_value = str(value)
			# 如果是选项索引，转换为对应的字符串值
			if backend_value == "0":
				backend_value = "addons"
			elif backend_value == "1":
				backend_value = "meltysynth"
			midi_playback_manager.set_backend(backend_value)
	
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

## 配置变更回调（新增）
func _on_config_changed(key: String, section: String, value: Variant) -> void:
	if _is_reloading_settings:
		return
	# 通配符 "*" 和 "all" 表示全量配置重新加载
	if key == "*" or section == "all":
		logger.info("Configuration changed (batch), reloading all settings", "Main")
		_reload_all_settings()
		return
	
	# 处理单个配置项变更
	logger.debug("Configuration changed: [%s] %s = %s" % [section, key, str(value)], "Main")
	
	# 根据 section 和 key 应用相应的配置
	match section:
		"Audio":
			if key in ["master_volume", "music_volume", "effects_volume"] and audio_manager:
				match key:
					"master_volume":
						audio_manager.set_master_volume(int(value))
					"music_volume":
						audio_manager.set_music_volume(int(value))
					"effects_volume":
						audio_manager.set_sfx_volume(int(value))
		
		"Gameplay":
			# MIDI播放管理器监听这些配置
			if key == "soundfont_file" and midi_playback_manager:
				midi_playback_manager.set_soundfont(str(value))
			elif key == "midi_backend" and midi_playback_manager:
				midi_playback_manager.set_backend(str(value))
		
		"Display":
			if key == "fullscreen":
				var is_fullscreen = value in ["1", "true", "True", "yes", "Yes"]
				if is_fullscreen:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			elif key == "vsync_enabled":
				var is_vsync = value in ["1", "true", "True", "yes", "Yes"]
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if is_vsync else DisplayServer.VSYNC_DISABLED)


# 在 AspectRatioContainer 的父节点添加脚本
