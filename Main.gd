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
var config_loader: ConfigLoader
var logger: GameLogger

func _ready():
	# 四边拉伸到父级（全屏）
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	
	# 初始化新架构的核心系统
	_initialize_core_systems()

## 初始化核心系统
func _initialize_core_systems() -> void:
	print("=== Initializing Core Systems ===")
	
	# 1. 初始化日志系统
	logger = GameLogger.instance
	logger.name = "GameLogger"
	add_child(logger)
	logger.info("Logger initialized", "Main")
	
	# 2. 初始化配置加载器
	config_loader = ConfigLoader.new()
	config_loader.name = "ConfigLoader"
	add_child(config_loader)
	logger.info("ConfigLoader initialized", "Main")
	
	# 3. 初始化事件总线
	event_bus = EventBus.instance
	event_bus.name = "EventBus"
	add_child(event_bus)
	logger.info("EventBus initialized", "Main")
	
	# 4. 初始化UI状态管理器
	state_manager = UIStateManager.instance
	state_manager.name = "UIStateManager"
	add_child(state_manager)
	logger.info("UIStateManager initialized", "Main")
	
	# 5. 初始化动画管理器
	animation_manager = AnimationManager.instance
	animation_manager.name = "AnimationManager"
	add_child(animation_manager)
	logger.info("AnimationManager initialized", "Main")
	
	# 6. 初始化排序引擎
	sorting_engine = SortingEngine.instance
	sorting_engine.name = "SortingEngine"
	add_child(sorting_engine)
	logger.info("SortingEngine initialized", "Main")
	
	# 7. 初始化数据管理器
	data_manager = DataManager.instance
	data_manager.name = "DataManager"
	add_child(data_manager)
	logger.info("DataManager initialized", "Main")
	
	# 8. 初始化游戏管理器
	gameplay_manager = GameplayManager.new()
	gameplay_manager.name = "GameplayManager"
	add_child(gameplay_manager)
	logger.info("GameplayManager initialized", "Main")
	
	# 9. 初始化音频管理器
	audio_manager = AudioManager.new()
	audio_manager.name = "AudioManager"
	add_child(audio_manager)
	logger.info("AudioManager initialized", "Main")
	
	# 连接信号
	_connect_signals()
	
	# 加载配置
	_load_configuration()
	
	# 异步加载MIDI数据
	_load_midi_data()
	
	print("=== Core Systems Initialized ===")

## 连接核心系统信号
func _connect_signals() -> void:
	# 数据加载完成信号
	data_manager.data_loaded.connect(_on_data_loaded)
	
	# 状态改变信号
	state_manager.state_changed.connect(_on_state_changed)
	
	# 错误处理
	event_bus.error_occurred.connect(_on_error_occurred)

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
		
		# 不注释掉跑不了)
		#audio_manager.set_master_volume(master_vol)
		#audio_manager.set_music_volume(music_vol)
		#audio_manager.set_sfx_volume(sfx_vol)
	else:
		logger.warning("Failed to load configuration file", "Main")

## 加载MIDI数据
func _load_midi_data() -> void:
	logger.info("Starting MIDI data load...", "Main")
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

# 在 AspectRatioContainer 的父节点添加脚本
