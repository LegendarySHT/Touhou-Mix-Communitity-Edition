extends BaseScrollList
class_name SettingList

var item_separator: String = "res://UI/Views/SettingView/Seperator.tscn"
var setting_items: Dictionary = {}  # 存储所有设置项，键为id，值为SettingItem
var pending_config_updates: Dictionary = {}  # 待提交配置，键为 "section::key"

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
			# for b in btns:
			# 	b.set_block_signals(false)
	)

# 传入配置字典加载界面
func load_settings(setting: Dictionary = {}):
	# 清空现有项目
	clear_items()
	setting_items.clear()
	pending_config_updates.clear()
	separators.clear()
	
	# 遍历所有分组
	for group in setting_groups:
		# 添加分隔符
		_add_separator()
		
		# 添加该组的所有设置项
		for setting_data in group.settings:
			var init_value = setting.get(setting_data.id) if setting.get(setting_data.id) else ""
			add_setting_item(setting_data, init_value)

	# 初始化依赖可见性
	_refresh_play_background_visibility()

var separators = []
func _add_separator():
	# 加载并添加分隔符
	var separator_scene = load(item_separator)
	if separator_scene:
		var separator = separator_scene.instantiate()
		container.add_child(separator)

		separators.append(separator)
		separator = separator_scene.instantiate()
		container.add_child(separator)

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

func add_setting_item(setting_data: Dictionary, init_value: String = ""):
	# 创建设置项
	var setting_item: SettingItem = create_and_add_item(setting_data.id, "SettingItem")
	
	# 解析值类型
	var value_type: SettingItem.ValueType = SettingItem.ValueType.TYPE_LINE_EDIT
	match setting_data.type:
		"TYPE_OPTION":
			value_type = SettingItem.ValueType.TYPE_OPTION
		"TYPE_COLOR":
			value_type = SettingItem.ValueType.TYPE_COLOR
		"TYPE_LINE_EDIT":
			value_type = SettingItem.ValueType.TYPE_LINE_EDIT
	
	# 设置界面语言（这里假设使用中文，可以根据需要调整）
	var language = "zh"  # 可以改为从全局设置获取
	var display_name = setting_data["name_%s" % language] if language in ["en", "zh"] else setting_data.name_en
	var description = setting_data.description
	
	# 设置初始值（从保存的数据或默认值）
	var initial_value = init_value if init_value else setting_data.default_value
	
	# 调用setup_item方法
	setting_item.setup_item(
		setting_data.id,
		display_name,
		description,
		value_type,
		initial_value
	)
	
# 如果是指令类型的设置项，设置选项
	match value_type:
		SettingItem.ValueType.TYPE_OPTION:
			var option_texts = []
			
			# 检查是否为动态options（由SettingView在runtime填充）
			if setting_data.get("dynamic_options", false) and setting_data.get("options", []).is_empty():
				# 动态options为空，先设置空列表，等SettingView调用update_soundfont_options()更新
				option_texts = ["Loading..."]
			elif setting_data.get("is_custom_easing", false):
				# 自定义缓动选项，从EasingMapper动态生成
				var easing_type = setting_data.get("easing_type", "func")  # "func" or "phase"
				var easing_options = []
				
				if easing_type == "func":
					easing_options = EasingMapper.get_func_options()
				elif easing_type == "phase":
					easing_options = EasingMapper.get_phase_options()
				
				# 提取显示名称
				for easing_opt in easing_options:
					option_texts.append(easing_opt.display_name)
			else:
				# 静态options，正常处理
				for option in setting_data.options:
					var option_text = option["text_%s" % language] if language in ["en", "zh"] else option.text_en
					option_texts.append(option_text)
			
			# 设置选项，并选中初始值对应的索引
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
	
		# 如果是颜色类型的设置项，设置颜色选择器选项
		SettingItem.ValueType.TYPE_COLOR:
			var enable_alpha = setting_data.get("edit_alpha", false)
			setting_item.set_color_picker_options(enable_alpha, false, false)
			
			# 设置初始颜色值
			if initial_value is String:
				if initial_value.is_valid_html_color():
					setting_item.set_value(Color(initial_value))
		SettingItem.ValueType.TYPE_LINE_EDIT:
			if setting_data.get("unit"):
				setting_item.set_line_edit_properties("", false, setting_data.unit)

	# 连接值改变信号
	setting_item.connect("value_changed", Callable(self, "_on_setting_value_changed"))
	
	# 存储到字典中
	setting_items[setting_data.id] = setting_item

func _on_setting_value_changed(id: String, value: Variant):
	# 设置项值改变时的处理
	print("Setting '%s' changed to: %s" % [id, value])

	# 主题预设 — 直接交给 ThemeManager
	if id == "theme_preset":
		if ThemeMGR:
			var presets := ThemeMGR.get_available_presets()
			if value >= 0 and value < presets.size():
				ThemeMGR.apply_preset(presets[value])
		return

	# 从SettingsMapper中查找该设置项对应的section和key
	if id in SettingsMapper.mappings:
		var setting_info = SettingsMapper.mappings[id]
		var section = setting_info.get("section", "")
		var key = setting_info.get("key", "")
		var value_type = setting_info.get("value_type", "string")
		
		if not section.is_empty() and not key.is_empty():
			# 根据配置类型转换值（确保类型匹配）
			var converted_value = value

			# 特殊处理：play_background_mode 需要刷新相关项可见性
			if id == "play_background_mode" and value is int:
				converted_value = value
				_refresh_play_background_visibility()
			# 特殊处理：note_fall_mode 需要控制自定义缓动选项的可见性
			elif id == "note_fall_mode" and value is int:
				set_note_fall_mode_and_show_custom_options(value)
				converted_value = value
			# 特殊处理：soundfont_select 需要将索引转换为文件名
			elif id == "soundfont_select" and value is int:
				var display_text = get_option_text(id, value)
				# 去掉 [内置] 标签和 .sf2 扩展名
				var actual_name = display_text.split(" [")[0] if " [" in display_text else display_text
				if actual_name.ends_with(".sf2"):
					actual_name = actual_name.get_basename()
				converted_value = actual_name
				print("[SettingList] Converting soundfont_select index %d to '%s'" % [value, converted_value])
			# 特殊处理：block_skin_preset 需要将索引转换为皮肤名称（保留 [内置] 标记）
			elif id == "block_skin_preset" and value is int:
				var display_text = get_option_text(id, value)
				converted_value = display_text
				print("[SettingList] Converting block_skin_preset index %d to '%s'" % [value, converted_value])
			elif id == "play_background_image_file" and value is int:
				converted_value = get_option_text(id, value)
				print("[SettingList] Converting play_background_image_file index %d to '%s'" % [value, converted_value])
			else:
				match value_type:
					"int":
						converted_value = int(value) if value is not int else value
					"float":
						converted_value = float(value) if value is not float else value
					"bool":
						# 布尔值可能来自int或字符串
						if value is int:
							converted_value = value != 0
						elif value is String:
							converted_value = value.to_lower() in ["1", "true", "yes"]
						else:
							converted_value = bool(value)
					"string":
						converted_value = str(value)
					"color":
						# 颜色保持为Color类型，先校验格式避免编辑过程中的报错
						if value is Color:
							converted_value = value
						elif str(value).is_valid_html_color():
							converted_value = Color(str(value))
						else:
							return  # 颜色值不完整时静默跳过，等待用户输入完成

			# 改为延迟提交：先缓存变更，退出SettingView时统一应用
			var update_id = "%s::%s" % [section, key]
			pending_config_updates[update_id] = {
				"section": section,
				"key": key,
				"value": converted_value
			}
			print("[SettingList] Deferred config update: [%s] %s = %s (type: %s)" % [section, key, str(converted_value), value_type])

func apply_pending_config_updates() -> int:
	var emitted_count = 0
	if pending_config_updates.is_empty():
		return emitted_count

	if EvtBus == null:
		push_warning("[SettingList] EventBus is null, skip applying pending config updates")
		pending_config_updates.clear()
		return emitted_count

	for update_key in pending_config_updates.keys():
		var update = pending_config_updates[update_key]
		if update is Dictionary:
			var section = update.get("section", "")
			var key = update.get("key", "")
			if section.is_empty() or key.is_empty():
				continue
			EvtBus.config_changed.emit(key, section, update.get("value", null))
			emitted_count += 1

	pending_config_updates.clear()
	return emitted_count

func has_pending_changes() -> bool:
	return not pending_config_updates.is_empty()



func _refresh_play_background_visibility() -> void:
	var mode_index = 0
	if setting_items.has("play_background_mode"):
		var mode_item = setting_items["play_background_mode"]
		if mode_item:
			mode_index = int(mode_item.get_value())

	var show_cover_only = mode_index == 0
	var show_image_only = mode_index == 1
	var show_color_only = mode_index == 2
	var show_size_mode = mode_index == 0 or mode_index == 1

	var visibility_rules = {
		"play_background_cover_blur": show_cover_only,
		"play_background_image_file": show_image_only,
		"play_background_color": show_color_only,
		"play_background_size_mode": show_size_mode
	}

	for setting_id in visibility_rules.keys():
		if setting_items.has(setting_id):
			var item = setting_items[setting_id]
			if item:
				var _is_visible = visibility_rules[setting_id]
				item.visible = _is_visible
				if item.value_node:
					item.value_node.visible = _is_visible



func get_all_settings_as_json() -> Dictionary:
	# 返回所有设置项的当前值，格式为 {"设置项ID": "值", ...}
	var result = {}
	
	for setting_id in setting_items.keys():
		var setting_item = setting_items[setting_id]
		if setting_item:
			var value = setting_item.get_value()
			# 将值转换为字符串
			if value is int or value is float:
				result[setting_id] = str(value)
			elif value is Color:
				result[setting_id] = value.to_html()
			else:
				result[setting_id] = str(value)
	
	return result

# 获取特定设置项的值
func get_setting_value(setting_id: String) -> Variant:
	if setting_items.has(setting_id):
		var setting_item = setting_items[setting_id]
		return setting_item.get_value()
	return null

# 设置特定设置项的值
func set_setting_value(setting_id: String, value: Variant) -> bool:
	if setting_items.has(setting_id):
		var setting_item = setting_items[setting_id]
		setting_item.set_value(value)
		return true
	return false

# 获取指定选项型设置的显示文本
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

# 重置所有设置为默认值
func reset_to_defaults():
	for setting_id in setting_items:
		# 查找默认值
		for group in setting_groups:
			for setting_data in group.settings:
				if setting_data.id == setting_id:
					var setting_item = setting_items[setting_id]
					if setting_item:
						setting_item.set_value(setting_data.default_value)
					break

func _gui_input(event: InputEvent) -> void:
	super._gui_input(event)

## 更新soundfont_select的选项（由SettingView调用）
func update_soundfont_options(soundfont_list: Array, current_selection: String = "") -> void:
	"""
	更新soundfont_select的选项列表
	
	Args:
		soundfont_list: 格式为 ["GeneralUser-GS [内置]", "CustomFont", ...]
		current_selection: 当前应该选中的soundfont名称（不带标签）
	"""
	if not setting_items.has("soundfont_select"):
		push_warning("[SettingList] soundfont_select setting item not found")
		return
	
	var setting_item = setting_items["soundfont_select"]
	if setting_item == null:
		push_warning("[SettingList] soundfont_select setting item is null")
		return
	
	# 更新options
	if soundfont_list.is_empty():
		setting_item.set_options(["No Sound Fonts Available"], 0)
		return
	
	setting_item.set_options(soundfont_list, 0)
	
	# 尝试选中current_selection
	if not current_selection.is_empty():
		for i in range(soundfont_list.size()):
			# 处理带标签的情况（e.g., "GeneralUser-GS [内置]"）
			var display_name = soundfont_list[i]
			var font_name = display_name.split(" [")[0]  # 移除 [内置] 标签
			
			if font_name == current_selection or display_name == current_selection:
				setting_item.set_value(i)
				break



## 更新theme_preset的选项（由SettingView调用）
func update_theme_preset_options() -> void:
	if not ThemeMGR:
		return
	var item = setting_items.get("theme_preset")
	if not item:
		return

	var presets := ThemeMGR.get_available_presets()
	var texts: Array[String] = []
	for p in presets:
		texts.append(p)

	var current := ThemeMGR.get_theme_name()
	var idx = max(0, presets.find(current))
	item.set_options(texts, idx)

func update_background_image_options(image_files: Array, current_selection: String = "") -> void:
	if not setting_items.has("play_background_image_file"):
		return

	var setting_item = setting_items["play_background_image_file"]
	if setting_item == null:
		return

	if image_files.is_empty():
		setting_item.set_options([""], 0)
		return

	setting_item.set_options(image_files, 0)

	if not current_selection.is_empty():
		var target_index = image_files.find(current_selection)
		if target_index >= 0:
			setting_item.set_value(target_index)


## 更新音符皮肤选项
func update_note_skin_options(skin_list: Array, current_selection: String = "") -> void:
	"""
	更新音符皮肤选择器的选项列表
	
	Args:
		skin_list: 皮肤名称列表
		current_selection: 当前选中的皮肤名称
	"""
	if not setting_items.has("block_skin_preset"):
		push_warning("[SettingList] block_skin_preset setting item not found")
		return
	
	var setting_item = setting_items["block_skin_preset"]
	if setting_item == null:
		return
	
	# 更新选项
	if skin_list.is_empty():
		setting_item.set_options(["旧版2 [内置]"], 0)
		return
	
	setting_item.set_options(skin_list, 0)
	
	# 尝试选中当前选择
	if not current_selection.is_empty():
		var target_index = skin_list.find(current_selection)
		if target_index >= 0:
			setting_item.set_value(target_index)

## 设置下落模式和控制自定义缓动选项的可见性
func set_note_fall_mode_and_show_custom_options(mode: int) -> void:
	"""
	设置下落模式并控制自定义缓动选项的可见性
	
	Args:
		mode: 0=匀速, 1=加速下落, 2=自定义
	"""
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
				# 当模式为2（自定义）时显示，否则隐藏
				setting_item.visible = (mode == 2)
				if setting_item.value_node:
					setting_item.value_node.visible = (mode == 2)
