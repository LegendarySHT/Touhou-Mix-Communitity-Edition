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

# UI组件路径
@export var midi_view_path: String

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
	
	_init_ui()

	# 1. 初始化日志系统（单例，已自动管理）
	logger = GameLogger.instance
	if logger:
		logger.info("Logger initialized", "Main")
	
	# 2. 初始化配置加载器
	config_loader = ConfigLoader.new()
	if logger:
		logger.info("ConfigLoader initialized", "Main")
	
	# 3. 初始化事件总线（单例，已自动管理）
	event_bus = EventBus.instance
	if event_bus and logger:
		logger.info("EventBus initialized", "Main")
	
	# 4. 初始化UI状态管理器（单例，已自动管理）
	state_manager = UIStateManager.instance
	if state_manager and logger:
		logger.info("UIStateManager initialized", "Main")
	
	# 5. 初始化动画管理器（单例，已自动管理）
	animation_manager = AnimationManager.instance
	if animation_manager and logger:
		logger.info("AnimationManager initialized", "Main")
	
	# 6. 初始化排序引擎（单例，已自动管理）
	sorting_engine = SortingEngine.instance
	if sorting_engine and logger:
		logger.info("SortingEngine initialized", "Main")
	
	# 7. 初始化数据管理器（单例，已自动管理）
	data_manager = DataManager.instance
	if data_manager and logger:
		logger.info("DataManager initialized", "Main")
	
	# 8. 初始化游戏管理器
	gameplay_manager = GameplayManager.new()
	gameplay_manager.name = "GameplayManager"
	add_child(gameplay_manager)
	if logger:
		logger.info("GameplayManager initialized", "Main")
	
	# 9. 初始化音频管理器
	audio_manager = AudioManager.new()
	audio_manager.name = "AudioManager"
	add_child(audio_manager)
	if logger:
		logger.info("AudioManager initialized", "Main")
	
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
		
		audio_manager.set_master_volume(master_vol)
		audio_manager.set_music_volume(music_vol)
		audio_manager.set_sfx_volume(sfx_vol)
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
