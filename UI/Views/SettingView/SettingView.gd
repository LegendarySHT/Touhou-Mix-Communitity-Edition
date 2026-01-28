extends Control
@onready var setting_list: SettingList = $Node2D/HBoxC/SettingList
@onready var short_cut_btn = $Node2D/HBoxC/ShortCut

## ConfigLoader 引用
var config_loader: ConfigLoader = null

## 配置文件路径
const CONFIG_PATH = "user://files/settings.ini"
const DEFAULT_CONFIG_PATH = "res://Resources/Config/config.ini"


func _ready() -> void:
	var idx: int = 0
	for btn:Button in short_cut_btn.get_children():
		btn.pressed.connect(_on_button_pressed.bind(idx))
		idx += 1

	# 设置按钮信号链接
	var setting_btn = get_node("/root/Main/LT_Btn/Button")
	if setting_btn:
		setting_btn.pressed.connect(
			func():
				if UIStateManager.instance.current_state != UIStateManager.UIState.SETTINGS_VIEW:
					UIStateManager.instance.change_state(UIStateManager.UIState.SETTINGS_VIEW)
				else:
					UIStateManager.instance.go_back()
		)

	# 从 ConfigLoader 加载配置
	_load_config_from_file()

## 从文件加载配置
func _load_config_from_file() -> void:
	# 创建 ConfigLoader 实例
	config_loader = ConfigLoader.new()
	
	# 优先从用户配置文件加载，如果不存在则使用默认配置
	var config_path = CONFIG_PATH if FileAccess.file_exists(CONFIG_PATH) else DEFAULT_CONFIG_PATH
	var ini_config = config_loader.load_config(config_path)
	
	if ini_config.is_empty():
		push_error("[SettingView] Failed to load config from: %s" % config_path)
		# 使用空字典，让 SettingList 使用默认值
		setting_list.load_settings({})
		return
	
	# 检查并迁移配置版本
	ini_config = config_loader.check_and_migrate(ini_config, config_path)
	
	# 转换 INI 格式为 SettingList 格式
	var settings_dict = SettingsMapper.ini_to_settings(ini_config)
	
	# 加载到 SettingList
	setting_list.load_settings(settings_dict)
	
	print("[SettingView] Loaded %d settings from: %s" % [settings_dict.size(), config_path])

## 保存配置到文件（由 AnimationManager 在退出时调用）
func save_config_to_file() -> bool:
	if config_loader == null:
		config_loader = ConfigLoader.new()
	
	# 获取当前 UI 中的配置
	var settings_dict = setting_list.get_all_settings_as_json()
	
	# 转换为 INI 格式
	var ini_config = SettingsMapper.settings_to_ini(settings_dict)
	
	# 确保有 Game 节（包含版本号）
	if not ini_config.has("Game"):
		ini_config["Game"] = {}
	ini_config["Game"]["config_version"] = ConfigLoader.CONFIG_VERSION
	
	# 保存到用户配置文件
	var success = config_loader.save_config(CONFIG_PATH, ini_config)
	
	if success:
		print("[SettingView] Saved %d settings to: %s" % [settings_dict.size(), CONFIG_PATH])
	else:
		push_error("[SettingView] Failed to save config to: %s" % CONFIG_PATH)
	
	return success

# 左侧快速跳转按钮的事件
func _on_button_pressed(idx: int):
	var target_idx = idx*2
	var c_idx = 0

	var settingList: SettingList = get_node("Node2D/HBoxC/SettingList")
	for node in settingList.container.get_children():
		if node is Separator:
			if c_idx == target_idx:
				var tween = create_tween()
				tween.tween_property(settingList, "scroll_vertical", node.position.y, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				settingList.scroll_velocity = 0.0
			c_idx += 1

# 获取当前ui中的配置
func _get_config():
	var config = setting_list.get_all_settings_as_json()
	return config
