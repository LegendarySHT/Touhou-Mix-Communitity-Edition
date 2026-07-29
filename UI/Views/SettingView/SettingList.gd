extends BaseScrollList
class_name SettingList

var item_separator: String = "res://UI/Views/SettingView/Seperator.tscn"
var setting_items: Dictionary = {}  # 存储所有设置项，键为id，值为SettingItem

# 进入 SettingView 时的配置快照（setting_id → 原始值，类型已转换好）
var _initial_config: Dictionary = {}
# 当前待保存的配置（setting_id → 已转换好类型的最终值）
var _pending_config: Dictionary = {}

var setting_groups: Array = []

func _ready() -> void:
	setting_groups = SettingGroupsData.get_setting_groups()
	work_state = UIStateManager.UIState.SETTINGS_VIEW
	super._ready()
	get_v_scroll_bar().value_changed.connect(func (_v):
		var btns = get_parent().get_parent().short_cut_btn.get_children()
		var idx = _get_current_para_sepa_idx()
		# 边界检查：分组索引超出快捷按钮数量时跳过
		if idx < 0 or idx >= btns.size():
			return
		var tBtn: Button = btns[idx]
		# await get_tree().process_frame
		if tBtn.get_parent().has_meta("snaping"):
			return

		if tBtn and not tBtn.button_pressed:
			for b in btns:
				b.set_block_signals(true)
				b.call_deferred("set_block_signals", false)
			tBtn.button_pressed = true
	)

# 传入配置字典加载界面
func load_settings(setting: Dictionary = {}):
	# 清空现有项目
	clear_items()
	setting_items.clear()
	separators.clear()

	# 初始化配置快照和待保存配置
	_initial_config = setting.duplicate(true)
	_pending_config = setting.duplicate(true)

	# 遍历所有分组
	for group in setting_groups:
		# 添加分隔符
		_add_separator()

		# 添加该组的所有设置项
		for setting_data in group.settings:
			var init_value = _pending_config.get(setting_data.id, setting_data.default_value)
			add_setting_item(setting_data, init_value)

var separators = []
@onready var separator_scene = load(item_separator)
func _add_separator():
	# 加载并添加分隔符
	if separator_scene:
		var separator = separator_scene.instantiate()
		container.add_child(separator)
		separators.append(separator)
		separator = separator_scene.instantiate()
		container.add_child(separator)
		separators.append(separator)

func _get_current_para_sepa_idx():
	var lower: int = separators.filter(func (s):
		if s.global_position.y >= -s.size.y/2:
			return true
		return false
	).size()
	lower = clampi(lower+1, 1, separators.size())
	return separators.size() - lower

func _process(delta: float) -> void:
	super._process(delta)

func add_setting_item(setting_data: Dictionary, init_value: Variant = ""):
	# 创建设置项
	var setting_item: SettingItem = create_and_add_item(setting_data.id, "SettingItem")
	# 注入 SettingList 引用，供 on_click / options_provider 回调使用
	setting_item.setting_list = self

	# 解析值类型
	var value_type: SettingItem.ValueType = SettingItem.ValueType.TYPE_LINE_EDIT
	match setting_data.type:
		"TYPE_OPTION":
			value_type = SettingItem.ValueType.TYPE_OPTION
		"TYPE_COLOR":
			value_type = SettingItem.ValueType.TYPE_COLOR
		"TYPE_LINE_EDIT":
			value_type = SettingItem.ValueType.TYPE_LINE_EDIT
		"TYPE_BUTTON":
			value_type = SettingItem.ValueType.TYPE_BUTTON

	# 设置界面语言（这里假设使用中文，可以根据需要调整）
	var language = "zh"  # 可以改为从全局设置获取
	var display_name = setting_data["name_%s" % language] if language in ["en", "zh"] else setting_data.name_en
	var description = setting_data.description

	# 设置初始值（从保存的数据或默认值）
	var initial_value = init_value if init_value != null and str(init_value) != "" else setting_data.default_value

	# 读取 JSON 中声明的回调方法名
	var on_click_method := String(setting_data.get("on_click", ""))
	var options_provider_method := String(setting_data.get("options_provider", ""))

	# 调用 setup_item 方法（传入回调方法名供自动连接）
	setting_item.setup_item(
		setting_data.id,
		display_name,
		description,
		value_type,
		initial_value,
		on_click_method,
		options_provider_method
	)

	# 处理未声明 options_provider 的 TYPE_OPTION（静态 options / dynamic_options 空列表 / 自定义缓动）
	if value_type == SettingItem.ValueType.TYPE_OPTION and options_provider_method == "":
		_setup_static_options(setting_item, setting_data, initial_value, language)
	elif value_type == SettingItem.ValueType.TYPE_COLOR:
		var enable_alpha = setting_data.get("edit_alpha", false)
		setting_item.set_color_picker_options(enable_alpha, false, false)
		# 设置初始颜色值
		if initial_value is String and initial_value.is_valid_html_color():
			setting_item.set_value(Color(initial_value))
	elif value_type == SettingItem.ValueType.TYPE_LINE_EDIT:
		if setting_data.get("unit"):
			setting_item.set_line_edit_properties("", false, setting_data.unit)

	# 连接值改变信号（按钮类型若声明了 on_click 则不走 value_changed，但仍连接以兼容）
	setting_item.connect("value_changed", Callable(self, "_on_setting_value_changed"))

	# 存储到字典中
	setting_items[setting_data.id] = setting_item

# 为未声明 options_provider 的 TYPE_OPTION 设置静态选项
func _setup_static_options(setting_item: SettingItem, setting_data: Dictionary, initial_value: Variant, language: String) -> void:
	var option_texts = []

	if setting_data.get("dynamic_options", false) and setting_data.get("options", []).is_empty():
		# 动态 options 为空且未声明 provider，先占位
		option_texts = ["Loading..."]
	elif setting_data.get("is_custom_easing", false):
		# 自定义缓动选项，从 EasingMapper 动态生成
		var easing_type = setting_data.get("easing_type", "func")
		var easing_options = []
		if easing_type == "func":
			easing_options = EasingMapper.get_func_options()
		elif easing_type == "phase":
			easing_options = EasingMapper.get_phase_options()
		for easing_opt in easing_options:
			option_texts.append(easing_opt.display_name)
	else:
		# 静态 options
		for option in setting_data.options:
			var option_text = option["text_%s" % language] if language in ["en", "zh"] else option.text_en
			option_texts.append(option_text)

	# 选中初始值对应的索引
	var default_index = 0
	if setting_data.get("is_custom_easing", false) and initial_value is String:
		var easing_type = setting_data.get("easing_type", "func")
		var easing_options = []
		if easing_type == "func":
			easing_options = EasingMapper.get_func_options()
		elif easing_type == "phase":
			easing_options = EasingMapper.get_phase_options()
		for i in range(easing_options.size()):
			if easing_options[i].name.to_upper() == initial_value.to_upper():
				default_index = i
				break
	elif initial_value is String and initial_value.is_valid_int():
		default_index = int(initial_value)
	elif initial_value is String:
		var matched_index = -1
		for i in range(setting_data.get("options", []).size()):
			var option_data = setting_data.get("options", [])[i]
			if option_data.has("value") and str(option_data["value"]).to_lower() == initial_value.to_lower():
				matched_index = i
				break
		if matched_index >= 0:
			default_index = matched_index
		else:
			var idx = option_texts.find(initial_value)
			default_index = idx if idx >= 0 else 0

	setting_item.set_options(option_texts, default_index)

func _on_setting_value_changed(id: String, value: Variant):
	# 按钮类型若声明了 on_click 已直接走 on_click 回调，不会触发此分支
	# 未声明 on_click 的按钮会 emit value_changed(id, null)，此处忽略
	var item: SettingItem = setting_items.get(id)
	if item and item.value_type == SettingItem.ValueType.TYPE_BUTTON:
		return

	print("Setting '%s' changed to: %s" % [id, value])

	# theme_preset 即时应用到 ThemeManager
	if id == "theme_preset" and value is int:
		if ThemeMGR:
			var presets := ThemeMGR.get_available_presets()
			if value >= 0 and value < presets.size():
				ThemeMGR.apply_preset(presets[value])
		_pending_config[id] = value
		return

	# 转换值（索引→实际值、类型转换）
	var converted_value = _convert_setting_value(id, value)
	if converted_value == null:
		return  # 转换失败（如颜色不完整），跳过

	_pending_config[id] = converted_value
	print("[SettingList] Pending config: %s = %s" % [id, str(converted_value)])

	# 即时可见性刷新
	if id == "note_fall_mode":
		set_note_fall_mode_and_show_custom_options(int(value))

# 将 UI 控件返回的值转换为配置存储用的值（索引→文件名、类型转换等）
# 返回 null 表示值不完整，调用方应跳过本次写入
func _convert_setting_value(id: String, value: Variant) -> Variant:
	# 自定义缓动选项：索引→名称（LINEAR / IN 等）
	var setting_data := _find_setting_data(id)
	if not setting_data.is_empty() and setting_data.get("is_custom_easing", false) and value is int:
		var easing_type = setting_data.get("easing_type", "func")
		var easing_options: Array = []
		if easing_type == "func":
			easing_options = EasingMapper.get_func_options()
		elif easing_type == "phase":
			easing_options = EasingMapper.get_phase_options()
		if value >= 0 and value < easing_options.size():
			return easing_options[value].name
		return null

	# soundfont_select: 索引→文件名（去 .sf2 和 [内置] 标签）
	if id == "soundfont_select" and value is int:
		var display_text = get_option_text(id, value)
		var actual_name = display_text.split(" [")[0] if " [" in display_text else display_text
		if actual_name.ends_with(".sf2"):
			actual_name = actual_name.get_basename()
		return actual_name
	# 其他走 SettingsMapper 类型转换
	if SettingsMapper.mappings.has(id):
		var info = SettingsMapper.mappings[id]
		var value_type = info.get("value_type", "string")
		match value_type:
			"int":
				return int(value) if value is not int else value
			"float":
				return float(value) if value is not float else value
			"bool":
				if value is int:
					return value != 0
				elif value is String:
					return value.to_lower() in ["1", "true", "yes"]
				else:
					return bool(value)
			"string":
				return str(value)
			"color":
				if value is Color:
					return value
				elif str(value).is_valid_html_color():
					return Color(str(value))
				else:
					return null  # 颜色不完整时跳过
	# 未在 mappings 中的项（如 theme_preset）原样返回
	return value

# 在 setting_groups 中查找指定 id 的 setting_data 字典
func _find_setting_data(id: String) -> Dictionary:
	for group in setting_groups:
		for setting_data in group.settings:
			if setting_data.id == id:
				return setting_data
	return {}

# 弹出皮肤修改窗口，关闭后将选中皮肤名缓存到 _pending_config
# PopupWindow 内部已通过 ConfigManager.set_value_and_notify 即时应用到 PlayView
# _pending_config 仅确保退出 SettingView 时保存到配置文件
func _popup_note_skin_adjust() -> void:
	var skin_name := await PopupWindow.instance.show_note_skin_adjust()
	if skin_name.is_empty():
		return
	_pending_config["block_skin_preset"] = skin_name
	print("[SettingList] block_skin_preset selected: '%s' (pending save)" % skin_name)

# ===== 各视图背景设置弹窗入口 =====
# 每个视图一个 TYPE_BUTTON 入口，调用统一的 _popup_view_background_adjust(view_name)
# 配置即时保存到 theme.ini 的 [backgrounds] 段（由 ThemeManager.set_view_background 处理）
# 不走 _pending_config（不走 config.ini），因此退出 SettingView 时无需 diff 保存

func _popup_play_background_adjust() -> void:
	await _popup_view_background_adjust("play")

func _popup_main_background_adjust() -> void:
	await _popup_view_background_adjust("main")

func _popup_store_background_adjust() -> void:
	await _popup_view_background_adjust("store")

func _popup_score_background_adjust() -> void:
	await _popup_view_background_adjust("score")

func _popup_track_background_adjust() -> void:
	await _popup_view_background_adjust("track")

func _popup_midi_background_adjust() -> void:
	await _popup_view_background_adjust("midi")

func _popup_setting_background_adjust() -> void:
	await _popup_view_background_adjust("setting")

## 统一的视图背景设置弹窗
## view_name: main/store/score/play/track/midi/setting
## 仅 play 视图允许选择"封面"类型（allow_cover=true）
func _popup_view_background_adjust(view_name: String) -> void:
	var allow_cover := (view_name == "play")
	var result := await PopupWindow.instance.show_image_adjust(view_name, allow_cover)
	if result.is_empty():
		return
	# 转换为 ThemeManager 期望的格式（值统一为 String，与 theme.ini 读取时一致）
	var type_str := "image"
	match int(result.get("type", 0)):
		ImageAdjust.IMG_TYPE_IMAGE: type_str = "image"
		ImageAdjust.IMG_TYPE_GRADIENT: type_str = "gradient"
		ImageAdjust.IMG_TYPE_SOLID: type_str = "solid"
		ImageAdjust.IMG_TYPE_COVER: type_str = "cover"
	var config: Dictionary = {
		"type": type_str,
		"image_path": str(result.get("image_file", "")),
		"image_stretch": "cover" if int(result.get("fill_mode", 0)) == 0 else "fit",
		"solid_color": (result.get("solid_color") as Color).to_html(true),
		"gradient_top": (result.get("start_color") as Color).to_html(true),
		"gradient_bottom": (result.get("end_color") as Color).to_html(true),
	}
	var from: Vector2 = result.get("from", Vector2(0, 0))
	var to: Vector2 = result.get("to", Vector2(0, 1))
	config["gradient_from_x"] = str(from.x)
	config["gradient_from_y"] = str(from.y)
	config["gradient_to_x"] = str(to.x)
	config["gradient_to_y"] = str(to.y)
	if allow_cover:
		config["cover_blur"] = str(result.get("cover_blur", 0.35))
	# 即时保存到 theme.ini + 轻量刷新背景（refresh_backgrounds，不触发完整主题刷新）
	# PlayView 的 cover 模式由 PlayView 在切回 PLAY_VIEW 时通过 _apply_play_background 处理
	ThemeMGR.set_view_background(view_name, config)
	print("[SettingList] %s background updated: type=%s" % [view_name, type_str])

# 重置内置资源：调用 FileSystemManager 重新复制默认资源
func _reload_builtin_resources() -> void:
	if FileSystemManager.instance:
		print("[SettingList] Reloading built-in resources...")
		await FileSystemManager.instance.reload_default_resources()
		print("[SettingList] Built-in resources reloaded")
	else:
		push_warning("[SettingList] FileSystemManager not available")

## ========== options_provider 方法（供 SettingListItem 通过 Callable 调用） ==========

# 提供 theme_preset 选项
func _provide_theme_preset_options() -> Array:
	if not ThemeMGR:
		return []
	var presets := ThemeMGR.get_available_presets()
	var texts: Array = []
	for p in presets:
		texts.append(p)
	return texts

# 提供 soundfont_select 选项
func _provide_soundfont_options() -> Array:
	var sf_list = _scan_all_soundfonts()
	if sf_list.is_empty():
		sf_list = ["GeneralUser-GS [内置]"]
	return sf_list

## ========== 文件扫描方法（从 SettingView 移入） ==========

## 扫描所有 SoundFont 文件（user 优先）
func _scan_all_soundfonts() -> Array[String]:
	var soundfonts: Dictionary = {}  # {filename_without_ext: {display_name, path, is_builtin}}

	# 第一步：扫描用户音源目录（user 优先）
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

	# 第二步：扫描 res://Resources/Soundfont/（仅添加 user 中没有的）
	var res_dir = "res://Resources/Soundfont/"
	if DirAccess.open(res_dir) != null:
		var dir = DirAccess.open(res_dir)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".sf2"):
					var font_name = file_name.get_basename()
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
		return a < b
	)

	return result

## 验证 SoundFont 文件是否存在
func _verify_soundfont_exists(soundfont_name: String) -> bool:
	var user_path = PathHelper.get_soundfont_dir().path_join(soundfont_name + ".sf2")
	if FileAccess.file_exists(user_path):
		return true
	var res_path = ("res://Resources/Soundfont/").path_join(soundfont_name + ".sf2")
	if ResourceLoader.exists(res_path):
		return true
	return false

## 获取 SoundFont 的实际路径
func _get_soundfont_path(soundfont_name: String) -> String:
	var user_path = PathHelper.get_soundfont_dir().path_join(soundfont_name + ".sf2")
	if FileAccess.file_exists(user_path):
		return user_path
	var res_path = ("res://Resources/Soundfont/").path_join(soundfont_name + ".sf2")
	if ResourceLoader.exists(res_path):
		return res_path
	return ""

## ========== 配置保存与应用 ==========

## 退出 SettingView 时调用：emit config_changed 信号应用变更
## 仅 emit 与 _initial_config 不同的项
func apply_pending_config_updates() -> int:
	var emitted_count = 0
	if EvtBus == null:
		push_warning("[SettingList] EventBus is null, skip applying pending config updates")
		return emitted_count

	for setting_id in _pending_config:
		if not SettingsMapper.mappings.has(setting_id):
			continue  # theme_preset 等不在 mappings 中的跳过
		var mapping = SettingsMapper.mappings[setting_id]
		var section = mapping.get("section", "")
		var key = mapping.get("key", "")
		if section.is_empty() or key.is_empty():
			continue
		var value = _pending_config[setting_id]
		var old_value = _initial_config.get(setting_id, null)
		# 仅 emit 变更项
		if str(old_value) == str(value):
			continue
		EvtBus.config_changed.emit(key, section, value)
		emitted_count += 1

	return emitted_count

## 是否有待保存的变更
func has_pending_changes() -> bool:
	for setting_id in _pending_config:
		var old_value = _initial_config.get(setting_id, null)
		if str(old_value) != str(_pending_config[setting_id]):
			return true
	return false

## 获取当前所有待保存配置的副本（供外部查询用）
func get_all_settings_as_json() -> Dictionary:
	return _pending_config.duplicate(true)

## 获取特定设置项的待保存值
func get_setting_value(setting_id: String) -> Variant:
	return _pending_config.get(setting_id, null)

## 设置特定设置项的值（同时更新 _pending_config）
func set_setting_value(setting_id: String, value: Variant) -> bool:
	if setting_items.has(setting_id):
		var setting_item = setting_items[setting_id]
		setting_item.set_value(value)
		_pending_config[setting_id] = value
		return true
	return false

## 获取指定选项型设置的显示文本
func get_option_text(setting_id: String, index: int) -> String:
	if not setting_items.has(setting_id):
		return ""
	var setting_item = setting_items[setting_id]
	if setting_item == null:
		return ""
	if not setting_item.value_node or not (setting_item.value_node is OptionButton):
		return ""
	var option_btn: OptionButton = setting_item.value_node
	if index < 0 or index >= option_btn.item_count:
		return ""
	return option_btn.get_item_text(index)

## 重置所有设置为默认值
func reset_to_defaults():
	for setting_id in setting_items:
		for group in setting_groups:
			for setting_data in group.settings:
				if setting_data.id == setting_id:
					var setting_item = setting_items[setting_id]
					if setting_item:
						setting_item.set_value(setting_data.default_value)
					break

## ========== 可见性控制 ==========

## 设置下落模式和控制自定义缓动选项的可见性
func set_note_fall_mode_and_show_custom_options(mode: int) -> void:
	var custom_easing_ids = [
		"note_fall_easing_before_func",
		"note_fall_easing_before_phase",
		"note_fall_easing_after_func",
		"note_fall_easing_after_phase"
	]

	for easing_id in custom_easing_ids:
		if setting_items.has(easing_id):
			var setting_item = setting_items[easing_id]
			if setting_item and setting_item.value_node:
				setting_item.visible = (mode == 2)
				if setting_item.value_node:
					setting_item.value_node.visible = (mode == 2)

## ========== 主题化 ==========

## 对所有 TYPE_BUTTON 设置项应用主题色（由 ThemeManager 调用）
func apply_button_theme(color: Color) -> void:
	for setting_id in setting_items:
		var item: SettingItem = setting_items[setting_id]
		if item and item.value_type == SettingItem.ValueType.TYPE_BUTTON and item.value_node is Button:
			var btn := item.value_node as Button
			btn.get_theme_stylebox("normal").bg_color = color
			btn.get_theme_stylebox("pressed").bg_color = color.darkened(0.25)
			btn.get_theme_stylebox("hover").bg_color = color.lightened(0.15)
