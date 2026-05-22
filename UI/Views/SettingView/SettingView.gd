extends Control
@onready var setting_list: SettingList = $HBoxC/SettingList
@onready var short_cut_btn = $HBoxC/ShortCut

## ConfigLoader 引用
var config_loader: ConfigManager = null

## 配置文件路径（通过 PathHelper 动态获取，兼容 Android）
## 使用 getter 确保运行时才求值
static var CONFIG_PATH: String:
	get: return PathHelper.get_user_config_path()
const DEFAULT_CONFIG_PATH = "res://Resources/Config/config.ini"


func _ready() -> void:
	var idx: int = 0
	for btn:Button in short_cut_btn.get_children():
		btn.toggled.connect(_on_button_toggled.bind(idx))
		btn.focus_entered.connect(_btn_focus_entered.bind(btn))
		idx += 1

	# 页面切换
	EventBus.instance.page_left.connect(switch_page.bind(-1))
	EventBus.instance.page_right.connect(switch_page.bind(1))

	# 转移焦点至导航按钮
	short_cut_btn.focus_entered.connect(func():
		var btn: Button = short_cut_btn.get_child(0)
		for i in short_cut_btn.get_children():
			if i is Button and i.button_pressed:
				break
		btn.grab_focus()
	)

	# 从 ConfigLoader 加载配置
	_load_config_from_file()

func get_all_child_nodes(c: Container):
	var node_array = []
	for i in c.get_children():
		node_array.append(i)
		if i.get_children():
			node_array += get_all_child_nodes(i)
	return node_array

func get_nearest_focusable_node(pos_y) -> Control:
	var nearest_node: Control = null
	var min_distance = INF
	
	# 获取GridContainer的全局位置
	var c: Container = setting_list.container
	
	
	# 遍历GridContainer的所有子节点
	var na = get_all_child_nodes(c)
	if not na:
		return null

	for child in na:
		# 确保节点是Control类型且可以聚焦
		if child.focus_mode != Control.FOCUS_NONE and child.global_position.y > 0 and child.global_position.y < c.get_global_rect().size.y:
			# 计算节点的中心点全局坐标
			var node_y = child.get_global_rect().position.y
			
			# 计算距离
			var distance = abs(node_y - pos_y)
			
			# 更新最近节点
			if distance < min_distance:
				min_distance = distance
				nearest_node = child

	return nearest_node

func _btn_focus_entered(btn: Button):
	if not btn.button_pressed:
		short_cut_btn.set_meta("snaping", true)
		btn.button_pressed = true
	
	for i in btn.get_parent().get_children():
		if i is Button and i != btn:
			i.z_index = 0
		else:
			i.z_index = 1

## 从文件加载配置
func _load_config_from_file() -> void:
	# 使用 ConfigManager 单例
	var config_manager = ConfigManager.instance
	
	# 优先从用户配置文件加载，如果不存在则使用默认配置
	var config_path = CONFIG_PATH if FileAccess.file_exists(CONFIG_PATH) else DEFAULT_CONFIG_PATH
	var ini_config = config_manager.load_config(config_path)
	
	if ini_config.is_empty():
		push_error("[SettingView] Failed to load config from: %s" % config_path)
		# 使用空字典，让 SettingList 使用默认值
		setting_list.load_settings({})
		return
	
	# 检查并迁移配置版本
	ini_config = config_manager.check_and_migrate(ini_config, config_path)
	
	# 转换 INI 格式为 SettingList 格式
	var settings_dict = SettingsMapper.ini_to_settings(ini_config)
	
	# 加载到 SettingList
	setting_list.load_settings(settings_dict)

	# 初始化主题预设选项
	setting_list.update_theme_preset_options()
	
	print("[SettingView] Loaded %d settings from: %s" % [settings_dict.size(), config_path])
	
	# 初始化SoundFont列表
	_initialize_soundfont_options(settings_dict)
	_initialize_background_image_options(settings_dict)
	_initialize_note_skin_options(settings_dict)

	# 初始化下落模式和缓动选项可见性
	var note_fall_mode = settings_dict.get("note_fall_mode", "0")
	var mode_value = int(note_fall_mode) if note_fall_mode.is_valid_int() else 0
	setting_list.set_note_fall_mode_and_show_custom_options(mode_value)
## 保存配置到文件（由 AnimationManager 在退出时调用）
func save_config_to_file() -> bool:
	var config_manager = ConfigManager.instance
	var base_config_path = CONFIG_PATH if FileAccess.file_exists(CONFIG_PATH) else DEFAULT_CONFIG_PATH
	var base_config = config_manager.load_config(base_config_path).duplicate(true)
	
	# 获取当前 ui 中的配置
	var settings_dict = setting_list.get_all_settings_as_json()
	
	# 特殊处理 midi_backend：将选项索引转换为实际值
	if settings_dict.has("midi_backend"):
		var raw_value = settings_dict["midi_backend"]
		print("[SettingView] midi_backend raw value from ui: %s (type: %s)" % [raw_value, typeof(raw_value)])
		if raw_value is int or (raw_value is String and raw_value.is_valid_int()):
			var index = int(raw_value)
			# 0 -> "addons", 1 -> "meltysynth"
			var converted = "addons" if index == 0 else "meltysynth"
			print("[SettingView] Converting midi_backend index %d to '%s'" % [index, converted])
			settings_dict["midi_backend"] = converted

	# 特殊处理 melty_audio_output_backend：将选项索引转换为实际值
	if settings_dict.has("melty_audio_output_backend"):
		var raw_output_value = settings_dict["melty_audio_output_backend"]
		if raw_output_value is int or (raw_output_value is String and raw_output_value.is_valid_int()):
			var output_index = clamp(int(raw_output_value), 0, 2)
			var converted_output = ["auto", "godot", "fmod"][output_index]
			print("[SettingView] Converting melty_audio_output_backend index %d to '%s'" % [output_index, converted_output])
			settings_dict["melty_audio_output_backend"] = converted_output

	# 特殊处理缓动选项：将选项索引转换为缓动函数/相位的名称
	var easing_options_to_convert = [
		"note_fall_easing_before_func",
		"note_fall_easing_before_phase",
		"note_fall_easing_after_func",
		"note_fall_easing_after_phase"
	]

	for easing_id in easing_options_to_convert:
		if settings_dict.has(easing_id):
			var easing_raw_value = settings_dict[easing_id]
			if easing_raw_value is int or (easing_raw_value is String and easing_raw_value.is_valid_int()):
				var easing_index = int(easing_raw_value)
				var easing_options = []

				# 根据ID类型选择options
				if "func" in easing_id:
					easing_options = EasingMapper.get_func_options()
				elif "phase" in easing_id:
					easing_options = EasingMapper.get_phase_options()

				# 转换索引为名称
				if easing_index >= 0 and easing_index < easing_options.size():
					var easing_name = easing_options[easing_index]["name"]
					settings_dict[easing_id] = easing_name
					print("[SettingView] Converting %s index %d to '%s'" % [easing_id, easing_index, easing_name])
	
	
	# 特殊处理soundfont_select：转换为实际文件名
	if settings_dict.has("soundfont_select"):
		var soundfont_raw_value = settings_dict["soundfont_select"]
		var display_name = ""
		if soundfont_raw_value is int or (soundfont_raw_value is String and soundfont_raw_value.is_valid_int()):
			var index = int(soundfont_raw_value)
			display_name = setting_list.get_option_text("soundfont_select", index)
		else:
			display_name = str(soundfont_raw_value)
		# 去掉 [内置] 标签，获取实际文件名
		var actual_name = display_name.split(" [")[0] if " [" in display_name else display_name
		if actual_name.ends_with(".sf2"):
			actual_name = actual_name.get_basename()
		settings_dict["soundfont_select"] = actual_name

	# 特殊处理 block_skin_preset：将选项索引转换为皮肤名称（保留 [内置] 标记）
	if settings_dict.has("block_skin_preset"):
		var skin_raw_value = settings_dict["block_skin_preset"]
		var skin_name = ""
		if skin_raw_value is int or (skin_raw_value is String and skin_raw_value.is_valid_int()):
			var index = int(skin_raw_value)
			skin_name = setting_list.get_option_text("block_skin_preset", index)
		else:
			skin_name = str(skin_raw_value)
		settings_dict["block_skin_preset"] = skin_name

	# 特殊处理 play_background_image_file：将选项索引转换为文件名
	if settings_dict.has("play_background_image_file"):
		var background_raw_value = settings_dict["play_background_image_file"]
		if background_raw_value is int or (background_raw_value is String and background_raw_value.is_valid_int()):
			var bg_index = int(background_raw_value)
			settings_dict["play_background_image_file"] = setting_list.get_option_text("play_background_image_file", bg_index)
	
	# 验证soundfont文件存在性，若不存在则回退
	if settings_dict.has("soundfont_select"):
		var soundfont_name = settings_dict["soundfont_select"]
		if not _verify_soundfont_exists(soundfont_name):
			print("[SettingView] Soundfont '%s' not found, falling back to default" % soundfont_name)
			settings_dict["soundfont_select"] = "GeneralUser-GS.sf2"
	
	# 转换为 INI 格式，并增量合并到现有配置中，避免未暴露设置被重置
	var ini_config = SettingsMapper.settings_to_ini(settings_dict)
	for section in ini_config.keys():
		if not base_config.has(section) or not (base_config[section] is Dictionary):
			base_config[section] = {}
		var section_dict = ini_config[section]
		if section_dict is Dictionary:
			for key in section_dict.keys():
				base_config[section][key] = section_dict[key]

	# 确保有 Game 节（包含版本号）
	if not base_config.has("Game"):
		base_config["Game"] = {}
	base_config["Game"]["config_version"] = ConfigManager.CONFIG_VERSION

	# 保存前打印信息
	print("[SettingView] About to save config. Gameplay section: %s" % base_config.get("Gameplay", {}))
	
	# 保存到用户配置文件
	var success = config_manager.save_config(CONFIG_PATH, base_config)
	
	if success:
		print("[SettingView] Saved %d settings to: %s" % [settings_dict.size(), CONFIG_PATH])
		# 仅在成功保存后统一应用配置变更，避免输入过程频繁触发重逻辑
		if setting_list and setting_list.has_method("apply_pending_config_updates"):
			var applied_count = setting_list.apply_pending_config_updates()
			print("[SettingView] Applied %d deferred config updates" % applied_count)
		# 保存后立即验证（使用单例缓存）
		var verify_config = config_manager.load_config(CONFIG_PATH)
		if verify_config.has("Gameplay"):
			print("[SettingView] Verification: midi_backend in saved file = '%s'" % verify_config["Gameplay"].get("midi_backend", "NOT_FOUND"))
	else:
		push_error("[SettingView] Failed to save config to: %s" % CONFIG_PATH)
	
	return success

var _snap_tween: Tween = null
# 左侧快速跳转按钮的事件
func _on_button_toggled(_toggled_on: bool, idx: int):
	var target_idx = idx*2
	var c_idx = 0
	
	for node in setting_list.container.get_children():
		if node is Separator:
			if c_idx == target_idx:
				if _snap_tween:
					_snap_tween.kill()
				_snap_tween = create_tween()
				_snap_tween.tween_property(setting_list, "scroll_vertical", node.position.y + node.size.y, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				setting_list.scroll_velocity = 0.0
				_snap_tween.finished.connect(func ():
					_snap_tween = null
					short_cut_btn.remove_meta("snaping")
					var btn = short_cut_btn.get_child(idx)
					var neighbor = get_nearest_focusable_node(btn.get_global_position().y)
					if neighbor:
						btn.focus_neighbor_right = neighbor.get_path()
				)
			c_idx += 1

# 获取当前ui中的配置
func _get_config():
	var config = setting_list.get_all_settings_as_json()
	return config

## ========== SoundFont 相关方法 ==========

## 初始化SoundFont选项（在load_settings后调用）
func _initialize_soundfont_options(loaded_settings: Dictionary) -> void:
	"""
	扫描并初始化SoundFont选项
	
	Args:
		loaded_settings: 从配置文件加载的设置字典
	"""
	var soundfont_list = _scan_all_soundfonts()
	
	if soundfont_list.is_empty():
		print("[SettingView] No soundfonts found, using default")
		soundfont_list = ["GeneralUser-GS [内置]"]
	
	# 获取当前应该选中的soundfont
	var current_selection = loaded_settings.get("soundfont_select", "GeneralUser-GS.sf2")
	if current_selection is String and current_selection.ends_with(".sf2"):
		current_selection = current_selection.get_basename()
	
	# 更新SettingList中的选项
	setting_list.update_soundfont_options(soundfont_list, current_selection)
	
	print("[SettingView] Initialized %d soundfont options" % soundfont_list.size())


func _initialize_background_image_options(loaded_settings: Dictionary) -> void:
	var image_files = _scan_background_images()
	var current_selection = str(loaded_settings.get("play_background_image_file", ""))
	setting_list.update_background_image_options(image_files, current_selection)

## 初始化音符皮肤选项
func _initialize_note_skin_options(loaded_settings: Dictionary) -> void:
	"""
	扫描并初始化音符皮肤选项
	
	Args:
		loaded_settings: 从配置文件加载的设置字典
	"""
	# 如果 FileSystemManager 还未完成资源扫描，等待扫描完成
	if FileSystemManager.instance and not FileSystemManager.instance.resources_scanned:
		print("[SettingView] Waiting for FileSystemManager to scan resources...")
		# 连接信号，等待扫描完成
		var fs_mgr = FileSystemManager.instance
		if not fs_mgr.resources_ready.is_connected(_on_skin_resources_ready):
			fs_mgr.resources_ready.connect(_on_skin_resources_ready.bind(loaded_settings))
		return
	
	_load_note_skin_options(loaded_settings)

func _on_skin_resources_ready(loaded_settings: Dictionary) -> void:
	_load_note_skin_options(loaded_settings)

func _load_note_skin_options(loaded_settings: Dictionary) -> void:
	"""
	实际加载音符皮肤选项
	
	Args:
		loaded_settings: 从配置文件加载的设置字典
	"""
	# 从 FileSystemManager 获取可用皮肤列表
	var skin_list = []
	if FileSystemManager.instance:
		skin_list = FileSystemManager.instance.get_available_skins()
	
	if skin_list.is_empty():
		print("[SettingView] No note skins found, using default")
		skin_list = ["旧版2 [内置]"]
	
	# 获取当前应该选中的皮肤
	var current_selection = loaded_settings.get("block_skin_preset", "旧版2 [内置]")
	
	# 更新SettingList中的选项
	setting_list.update_note_skin_options(skin_list, current_selection)
	
	print("[SettingView] Initialized %d note skin options" % skin_list.size())


func _scan_background_images() -> Array[String]:
	var result: Array[String] = []
	var image_dir = PathHelper.get_background_dir()
	var dir = DirAccess.open(image_dir)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and not file_name.begins_with("."):
			var ext = file_name.get_extension().to_lower()
			if ext in ["jpg", "jpeg", "png", "webp"]:
				result.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	result.sort()
	return result

## 扫描所有SoundFont文件（user优先）
func _scan_all_soundfonts() -> Array[String]:
	"""
	聚合扫描结果：user://files/Soundfont/ 和 res://Resources/Soundfont/
	user目录中的文件会覆盖res中的同名文件
	
	Returns:
		Array[String]: 格式为 ["GeneralUser-GS", "CustomFont [内置]", ...]
	"""
	var soundfonts: Dictionary = {}  # {filename_without_ext: {display_name, path}}
	
	# 第一步：扫描用户音源目录 （user优先）
	var user_dir = PathHelper.get_soundfont_dir()
	if DirAccess.open(user_dir) != null:
		var dir = DirAccess.open(user_dir)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			
			while file_name != "":
				if file_name.ends_with(".sf2"):
					var font_name = file_name.get_basename()
					soundfonts[font_name] = {
						"display_name": font_name,
						"path": user_dir.path_join(file_name),
						"is_builtin": false
					}
				file_name = dir.get_next()
			dir.list_dir_end()
	
	# 第二步：扫描res://Resources/Soundfont/ （仅添加user中没有的）
	var res_dir = "res://Resources/Soundfont/"
	if DirAccess.open(res_dir) != null:
		var dir = DirAccess.open(res_dir)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			
			while file_name != "":
				if file_name.ends_with(".sf2"):
					var font_name = file_name.get_basename()
					
					# 仅在user中不存在时添加，并标记为[内置]
					if not soundfonts.has(font_name):
						soundfonts[font_name] = {
							"display_name": font_name + " [内置]",
							"path": res_dir.path_join(file_name),
							"is_builtin": true
						}
				file_name = dir.get_next()
			dir.list_dir_end()
	
	# 第三步：整理返回列表
	var result: Array[String] = []
	for font_name in soundfonts.keys():
		result.append(soundfonts[font_name]["display_name"])
	
	# 排序：用户文件优先，内置文件在后
	result.sort_custom(func(a: String, b: String) -> bool:
		var a_is_builtin = " [内置]" in a
		var b_is_builtin = " [内置]" in b
		if a_is_builtin != b_is_builtin:
			return a_is_builtin  # 内置的排在后面
		return a < b  # 同类型按名称排序
	)
	
	return result

## 验证SoundFont文件是否存在
func _verify_soundfont_exists(soundfont_name: String) -> bool:
	"""
	检查soundfont文件是否存在（user优先）
	
	Args:
		soundfont_name: 文件名，不带.sf2扩展名和[内置]标签
	
	Returns:
		bool: 文件是否存在
	"""
	# 第一步：检查用户音源目录
	var user_path = PathHelper.get_soundfont_dir().path_join(soundfont_name + ".sf2")
	if FileAccess.file_exists(user_path):
		return true
	
	# 第二步：检查res://
	var res_path = ("res://Resources/Soundfont/").path_join(soundfont_name + ".sf2")
	if ResourceLoader.exists(res_path):
		return true
	
	return false

## 获取SoundFont的实际路径
func _get_soundfont_path(soundfont_name: String) -> String:
	"""
	获取soundfont文件的完整路径（user优先）
	
	Args:
		soundfont_name: 文件名，不带.sf2扩展名
	
	Returns:
		String: 完整文件路径，若不存在返回空字符串
	"""
	# 第一步：检查用户音源目录
	var user_path = PathHelper.get_soundfont_dir().path_join(soundfont_name + ".sf2")
	if FileAccess.file_exists(user_path):
		return user_path
	
	# 第二步：检查res://
	var res_path = ("res://Resources/Soundfont/").path_join(soundfont_name + ".sf2")
	if ResourceLoader.exists(res_path):
		return res_path
	
	return ""

## 获取特定设置的值
## 此方法由其他模块（如TrackView）调用，用于查询当前设置值
func get_setting_value(setting_id: String) -> Variant:
	if setting_list == null:
		push_warning("[SettingView] SettingList not initialized when querying: %s" % setting_id)
		return null
	
	# 从SettingList的设置项字典中查询
	if setting_list.setting_items.has(setting_id):
		var setting_item = setting_list.setting_items[setting_id]
		if setting_item and setting_item.has_method("get_value"):
			return setting_item.get_value()
	
	# 如果找不到，尝试从配置加载器的缓存中读取
	if config_loader != null:
		var config_path = CONFIG_PATH if FileAccess.file_exists(CONFIG_PATH) else DEFAULT_CONFIG_PATH
		var ini_config = config_loader.load_config(config_path)
		if not ini_config.is_empty():
			var settings_dict = SettingsMapper.ini_to_settings(ini_config)
			if settings_dict.has(setting_id):
				var value_str = settings_dict[setting_id]
				# 根据类型转换值
				match setting_id:
					"default_midi_volume", "default_vocal_volume", "audio_sync_threshold":
						if value_str.is_valid_int():
							return int(value_str)
				return value_str
	
	print("[SettingView] Setting not found: %s" % setting_id)
	return null

@onready var setting_page = $HBoxC
@onready var delete_page = $DelView
@onready var ani: AnimationManager = AnimationManager.instance
func switch_page(direction: int = 0):
	var op: bool = true
	if direction == -1:
		op = false
		delete_page.visible = true
	else:
		setting_page.visible = true

	var wid = setting_page.size.x + 600
	ani.animate_position(setting_page, Vector2(wid * 1 if not op else 0, 0), 0.5, "SV_PAGE_SW_1")
	await ani.animate_position(delete_page, Vector2(-wid * 1 if op else 0, 0), 0.5, "SV_PAGE_SW_2").finished

	setting_page.visible = op
	delete_page.visible = not op

func has_pending_changes() -> bool:
	return setting_list and setting_list.has_pending_changes()

func switch_page_instant() -> void:
	setting_page.visible = true
	delete_page.visible = false
