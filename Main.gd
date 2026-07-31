extends Control

# Root 节点脚本
# 重构后的主节点，负责初始化核心系统

## 核心系统引用
var data_manager: DataManager
var event_bus: EventBus
var state_manager: UIStateManager
var animation_manager: AnimationManager
var sorting_engine: SortingEngine
var score_calculator: ScoreCalculator
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

@onready var _orientation_reverse: bool = Input.get_gravity().y > 0

func _ready():	
	# Android 平台：请求存储权限（fire-and-forget，外部私有目录实际不需要运行时权限）
	if PathHelper.is_android():
		print("=== Android platform detected ===")
		print("=== Base dir: %s ===" % PathHelper.get_base_dir())
		OS.request_permissions()
	
	# 桌面端：无重力传感器，立即关闭自动旋转 _process，避免 2 秒无意义等待
	if not PathHelper.is_android():
		if Input.get_gravity() == Vector3.ZERO:
			print("自动旋转屏幕方向功能已关闭")
			set_process(false)
		# 桌面端无需等待，直接开始初始化
		_initialize_core_systems()
		return
	
	# Android 平台：先初始化核心系统，再等待传感器就绪
	_initialize_core_systems()
	
	# 短暂等待传感器数据可用（远少于 2 秒，传感器通常 100ms 内就绪）
	await get_tree().create_timer(0.3).timeout
	if Input.get_gravity() == Vector3.ZERO:
		print("自动旋转屏幕方向功能已关闭")
		set_process(false)

var timer = 0
# 如果需要在这个_process里处理其它东西，请先改关闭自动旋转屏幕功能的逻辑
func _process(_delta: float) -> void:
	timer += 1
	if timer > 60:
		timer = 0
		if abs(Input.get_gravity().y) < 4:
			return
		var _now_rot = Input.get_gravity().y > 0
		if _now_rot != _orientation_reverse:
			_orientation_reverse = _now_rot
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_REVERSE_LANDSCAPE if _orientation_reverse else DisplayServer.SCREEN_LANDSCAPE)

## Android 系统返回键
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		# 应用退出时关闭 CoverLoader 线程池，确保所有后台线程 wait_to_finish
		if CoverLoader:
			CoverLoader.shutdown()

## 桌面端 Esc 键（仅在无其他控件消费事件时触发）
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		_handle_back_request()

## 统一的返回/退出处理
func _handle_back_request() -> void:
	var popup = PopupWindow.instance
	# 主界面 → 显示退出确认
	if state_manager.current_state == UIStateManager.UIState.ALBUM_VIEW:
		if popup:
			if await popup.show_message("确定要退出游戏吗？", true):
				get_tree().quit()
		return

	# 打歌界面 → 先弹出暂停菜单（与桌面端 Esc 行为一致）
	if state_manager.current_state == UIStateManager.UIState.PLAY_VIEW:
		var play_view = get_node_or_null("PlayView")
		# 游戏中 → 弹出暂停菜单
		if play_view and not play_view.is_pause:
			play_view.show_or_hide_menu()
			return

	# 其他层级 → 返回上一级
	state_manager.go_back()

## 初始化核心系统
func _initialize_core_systems() -> void:
	print("=== Initializing Core Systems ===")

	# 1. 初始化日志系统（单例，已自动管理）
	logger = GLogger
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

	# 2.75. ThemeManager 已通过 autoload 自动实例化
	if ThemeMGR and ThemeMGR.is_loaded():
		logger.info("ThemeManager initialized with theme: %s" % ThemeMGR.get_theme_name(), "Main")

	# 3. 初始化文件系统管理器（单例，已自动管理）
	filesystem_manager = FileSystemManager.new()
	filesystem_manager.name = "FileSystemManager"
	add_child(filesystem_manager)
	if logger:
		logger.info("FileSystemManager initialized", "Main")
	
	# 初始化目录结构
	filesystem_manager.initialize_directory_structure()
	
	# 4. 初始化事件总线（单例，已自动管理）
	event_bus = EvtBus
	if event_bus and logger:
		logger.info("EventBus initialized", "Main")
	
	# 5. 初始化UI状态管理器（单例，已自动管理）
	state_manager = UiStatMGR
	if state_manager and logger:
		logger.info("UIStateManager initialized", "Main")
	
	# 6. 初始化动画管理器（单例，已自动管理）
	animation_manager = AniMGR
	if animation_manager and logger:
		logger.info("AnimationManager initialized", "Main")
	
	# 7. 初始化排序引擎（单例，已自动管理）
	sorting_engine = SortEngine
	if sorting_engine and logger:
		logger.info("SortingEngine initialized", "Main")
	
	# 8. 初始化数据管理器（单例，已自动管理）
	data_manager = DataMGR
	if data_manager and logger:
		logger.info("DataManager initialized", "Main")

	# 8.5 初始化收藏夹管理器（需在 DataManager 之后，因为它依赖 data_loaded_complete 验证 midi 引用）
	var favorite_manager := FavoriteManager.new()
	favorite_manager.name = "FavoriteManager"
	add_child(favorite_manager)
	if logger:
		logger.info("FavoriteManager initialized", "Main")

	# 9.5 初始化分数计算器
	score_calculator = ScoreCalculator.new()
	score_calculator.name = "ScoreCalculator"
	add_child(score_calculator)
	if logger:
		logger.info("ScoreCalculator initialized", "Main")
	
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
	
	# 让出帧：MeltySynth 后端初始化（场景加载 + C# _Ready）较重，
	# 让引擎先渲染一帧再继续 UI 初始化，避免单帧卡顿
	await get_tree().process_frame

	# 12. 初始化键序列管理器
	key_sequence_manager = KeySequenceManager.new()
	key_sequence_manager.name = "KeySequenceManager"
	add_child(key_sequence_manager)
	if logger:
		logger.info("KeySequenceManager initialized", "Main")

	# 13. 初始化并加载UI（确保各管理器已就绪）
	_init_ui()

	# 让出帧：让引擎先渲染 Main.tscn 内嵌视图，再继续信号连接和数据加载
	# （6 个 _init_ui 视图已改为懒加载，启动阶段不再实例化）
	await get_tree().process_frame

	# 13.5. 预加载 SoundFont 到后端（~30MB，同步阻塞 3-5 秒）
	# 放在 UI 渲染后、信号连接/MIDI 数据加载前，确保阻塞发生在启动阶段而非用户交互阶段
	midi_playback_manager._preload_soundfont_to_backend()

	# 连接信号
	_connect_signals()
	
	# 加载配置
	_load_configuration()
	
	# 异步加载MIDI数据
	_load_midi_data()
	
	print("=== Core Systems Initialized ===")

func _init_ui() -> void:
	# 6 个视图（MidiView/StoreView/TrackView/SettingView/ScoreView/PlayView）改为懒加载，
	# 由 UIStateManager.ensure_view_loaded() 在首次 change_state 时实例化
	# 3 个 Main.tscn 内嵌视图（AlbumView/SongView/SortedMidiView）保持预加载
	# 注：z_index 处理（STORE_VIEW=10, PLAY_VIEW=21）已迁移到 UIStateManager.ensure_view_loaded()

	# 移动返回按钮到上层
	var right_bottom = get_node("RB_Btn")
	move_child(right_bottom ,-1)
	right_bottom.z_index = 20

	# 设置按钮
	var left_top = get_node("LT_Btn")
	move_child(left_top ,-1)
	left_top.z_index = 20

	# 应用主题（Theme 资源 + 主界面组件；背景不在此刷新，由各视图/refresh_backgrounds 处理）
	# Main 注册为主题应用者，首次自调 apply_theme，再由 refresh_theme_only 广播给所有已注册视图/组件
	if ThemeMGR:
		ThemeMGR.register_theme_applier(self)
		apply_theme()
		ThemeMGR.refresh_theme_only()

## 应用主题色到主框架组件（由 ThemeManager 广播调用 + _init_ui 首次自调）
func apply_theme() -> void:
	# LT_Btn — 蓝 (primary)
	var lt := get_node_or_null("LT_Btn")
	if lt:
		ThemeMGR._modify_panel_color(lt, "primary")
	# RB_Btn — 淡蓝 (primary_light)
	var rb := get_node_or_null("RB_Btn")
	if rb:
		ThemeMGR._modify_panel_color(rb, "primary_light")
	# ShortCutMenu 面板 — 蓝 (primary)
	var sc_panel := get_node_or_null("skew/C/ShortCutMenu/Panel")
	if sc_panel:
		ThemeMGR._modify_panel_color(sc_panel, "primary")
	# PlayerInfo 面板 — 暗色 (primary_dark)
	var info_panel := get_node_or_null("PlayerInfo/Info/Panel")
	if info_panel:
		ThemeMGR._modify_panel_color(info_panel, "primary_dark")

## 连接核心系统信号
func _connect_signals() -> void:
	# 数据加载完成信号
	data_manager.data_loaded.connect(_on_data_loaded)
	
	# 状态改变信号
	state_manager.state_changed.connect(_on_state_changed)

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

	# 应用HDR设置
	var hdr_enabled = config_loader.get_int("Appearance", "hdr_2d", 0) == 1
	get_tree().root.use_hdr_2d = hdr_enabled
	logger.debug("HDR 2D: %s" % ("enabled" if hdr_enabled else "disabled"), "Main")

## 加载MIDI数据
func _load_midi_data() -> void:
	logger.info("=== Starting MIDI Data Load ===", "Main")
	logger.info("Platform: %s" % OS.get_name(), "Main")
	logger.info("User data path: %s" % OS.get_user_data_dir(), "Main")
	
	# 诊断：检查 res:// 资源是否存在
	var resources_to_check = [
		"res://Resources/Config/config.ini",
		"res://Resources/Charts/",
		"res://Resources/Soundfont/",
		"res://Resources/BackgroundImage/"
	]
	
	for res in resources_to_check:
		var exists = false
		if res.ends_with("/"):
			exists = DirAccess.dir_exists_absolute(res)
		else:
			exists = FileAccess.file_exists(res)
		logger.info("Resource check [%s]: %s" % [res, "✓" if exists else "✗"], "Main")
		if not exists:
			logger.error("Critical resource missing - Check export settings!", "Main")
	
	logger.info("Waiting for FileSystemManager resources...", "Main")
	
	# 等待 FileSystemManager 资源准备完毕
	var max_wait_frames = 300  # 最多等待5秒（300帧 * 60fps）
	var wait_count = 0
	
	while not filesystem_manager.resources_scanned and wait_count < max_wait_frames:
		await get_tree().process_frame
		wait_count += 1
	
	if not filesystem_manager.resources_scanned:
		logger.warning("FileSystemManager resources timeout - proceeding anyway", "Main")
	else:
		logger.info("FileSystemManager resources scanned (%d frames), starting MIDI load..." % wait_count, "Main")
	
	# 输出 charts_index 信息用于诊断
	var charts_count = filesystem_manager.charts_index.size()
	logger.info("Charts index contains %d entries" % charts_count, "Main")
	
	logger.info("Loading all MIDI files asynchronously...", "Main")
	data_manager.load_all_midis_async()
	logger.info("=== MIDI Data Load Initiated ===", "Main")

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
	# SoundFont相关设置
	if setting_name == "soundfont_select":
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
		"Gameplay":
			# MIDI播放管理器监听这些配置
			if key == "soundfont_file" and midi_playback_manager:
				midi_playback_manager.set_soundfont(str(value))
		
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

		"Appearance":
			if key == "hdr_2d":
				var hdr_on = value in [1, "1", "true", "True"]
				get_tree().root.use_hdr_2d = hdr_on
				logger.info("HDR 2D set to: %s" % ("enabled" if hdr_on else "disabled"), "Main")
