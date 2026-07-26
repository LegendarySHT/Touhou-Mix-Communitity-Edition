extends ListItemBase
class_name SettingItem

var item_value_line_edit: String = "res://UI/Views/SettingView/ValueLineEdit.tscn"
var item_value_color: String = "res://UI/Views/SettingView/ValueColor.tscn"
var item_value_option: String = "res://UI/Views/SettingView/ValueOption.tscn"

var id: String = ""

enum ValueType {
	TYPE_OPTION,
	TYPE_COLOR,
	TYPE_LINE_EDIT
}

var value_type: ValueType
var value_node: Control

var _can_edit_alpha: bool = false

# 添加信号，用于通知值改变
signal value_changed(id: String, value: Variant)
signal option_popup_about_to_show(id: String)

func setup_item(ID: String, content: String, desc: String, valueType: ValueType, initial_value: Variant = null) -> Control:
	self.id = ID
	self.value_type = valueType  # 设置value_type
	
	# 设置标题和描述
	var name_label = get_node_or_null("name")
	if name_label:
		name_label.text = content
	
	var desc_label = get_node_or_null("desc")
	if desc_label:
		desc_label.text = desc
	
	# 创建对应的值控件
	var v_node: Control = null
	match valueType:
		ValueType.TYPE_OPTION:
			v_node = load(item_value_option).instantiate()
			var option_btn: OptionButton = v_node
			option_btn.connect("item_selected", Callable(self, "_on_option_selected"))

			var popup_menu: PopupMenu = option_btn.get_popup()
			popup_menu.about_to_popup.connect(_on_popup_menu_popup.bind(popup_menu))
	
		ValueType.TYPE_COLOR:
			v_node = load(item_value_color).instantiate()
			var btn: ColorPickerButton = v_node.get_node("ColorPickerButton")

			var color_edit: LineEdit = v_node.get_node("HexColor")
			btn.color_changed.connect(_on_color_changed.bind(color_edit))
			color_edit.text_changed.connect(_on_color_changed.bind(btn))

			var pk: ColorPicker = btn.get_picker()

			pk.edit_intensity = false
			pk.can_add_swatches = false
			pk.sampler_visible = false
			pk.presets_visible = false
		
		ValueType.TYPE_LINE_EDIT:
			v_node = load(item_value_line_edit).instantiate()
			var line_edit: LineEdit = v_node.get_node("LineEdit")
			if line_edit:
				line_edit.connect("text_changed", Callable(self, "_on_text_changed"))
	
	value_node = v_node

	# 父节点是grid容器，所以添加到父节点	
	get_parent().add_child(v_node)
	
	# 设置初始值
	if initial_value != null:
		set_value(initial_value)
	
	return v_node

# 更新弹出菜单样式
func _on_popup_menu_popup(popup_menu: PopupMenu) -> void:
	option_popup_about_to_show.emit(id)
	await get_tree().process_frame
	popup_menu.position.y += 20
	popup_menu.position.x -= 20

# 获取当前值
func get_value() -> Variant:
	if not value_node:
		return null
	
	match value_type:
		ValueType.TYPE_OPTION:
			var option_btn: OptionButton = value_node
			if option_btn:
				return option_btn.selected
			return 0
		
		ValueType.TYPE_COLOR:
			var color_btn: ColorPickerButton = value_node.get_node("ColorPickerButton")
			if color_btn:
				return color_btn.color
			return Color.WHITE
		
		ValueType.TYPE_LINE_EDIT:
			var line_edit: LineEdit = value_node.get_node("LineEdit")
			if line_edit:
				return line_edit.text
			return ""
	
	return null

# 设置值
func set_value(value: Variant) -> void:
	if not value_node:
		return
	
	match value_type:
		ValueType.TYPE_OPTION:
			var option_btn: OptionButton = value_node
			if option_btn and value is int:
				option_btn.select(value)
		
		ValueType.TYPE_COLOR:
			var color_btn: ColorPickerButton = value_node.get_node("ColorPickerButton")
			if color_btn:
				if value is Color:
					color_btn.color = value
				elif value is String and value.is_valid_html_color():
					color_btn.color = Color(value)
				value_node.get_node("HexColor").text = "#%s" % (value if value is String else value.to_html(_can_edit_alpha))
		
		ValueType.TYPE_LINE_EDIT:
			var line_edit: LineEdit = value_node.get_node("LineEdit")
			if line_edit:
				line_edit.text = str(value)

# 设置选项（仅用于TYPE_OPTION）
func set_options(options: Array, default_index: int = 0) -> void:
	if value_type != ValueType.TYPE_OPTION or not value_node:
		return
	
	var option_btn: OptionButton = value_node
	if option_btn:
		option_btn.clear()
		for i in range(options.size()):
			option_btn.add_item(options[i], i)
		
		if default_index >= 0 and default_index < options.size():
			option_btn.select(default_index)

# 设置颜色按钮参数
func set_color_picker_options(edit_alpha: bool = true, presets_visible: bool = false, sampler_visible: bool = false) -> void:
	if value_type != ValueType.TYPE_COLOR or not value_node:
		return
	
	_can_edit_alpha = edit_alpha

	var color_btn: ColorPickerButton = value_node.get_node("ColorPickerButton")
	if color_btn:
		var pk: ColorPicker = color_btn.get_picker()
		if pk:
			pk.edit_alpha = edit_alpha
			pk.presets_visible = presets_visible
			pk.sampler_visible = sampler_visible

# 设置行编辑属性
func set_line_edit_properties(placeholder: String = "", secret: bool = false, unit: String = "") -> void:
	if value_type != ValueType.TYPE_LINE_EDIT or not value_node:
		return
	
	var line_edit: LineEdit = value_node.get_node("LineEdit")
	if line_edit:
		line_edit.placeholder_text = placeholder
		line_edit.secret = secret
		
		var un: Label = value_node.get_node("Label")
		if not unit.is_empty():
			un.text = unit
			un.visible = true


# 信号处理函数
func _on_option_selected(index: int) -> void:
	emit_signal("value_changed", id, index)

func _on_color_changed(color, node) -> void:
	node.set_block_signals(true)

	if node is LineEdit:
		node.text = "#%s"% color.to_html(_can_edit_alpha)
	elif node is ColorPickerButton and color.is_valid_html_color():
		node.color = color

	node.set_block_signals(false)
	emit_signal("value_changed", id, color)

func _on_text_changed(new_text: String) -> void:
	emit_signal("value_changed", id, new_text)

# 启用/禁用设置项
func set_enabled(enabled: bool) -> void:
	match value_type:
		ValueType.TYPE_OPTION:
			var option_btn: OptionButton = value_node
			if option_btn:
				option_btn.disabled = not enabled
		
		ValueType.TYPE_COLOR:
			var color_btn: ColorPickerButton = value_node.get_node("ColorPickerButton")
			if color_btn:
				color_btn.disabled = not enabled
		
		ValueType.TYPE_LINE_EDIT:
			var line_edit: LineEdit = value_node.get_node("LineEdit")
			if line_edit:
				line_edit.editable = enabled

# 清理函数
func _exit_tree() -> void:
	if value_node:
		value_node.queue_free()
