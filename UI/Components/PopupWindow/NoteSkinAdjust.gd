extends HBoxContainer

class_name NoteSkinAdjust

const NOTE_GLOW_SHADER: Shader = preload("res://UI/Components/PopupWindow/NoteGlow.gdshader")
const LONG_BODY_REPEAT_SHADER: Shader = preload("res://UI/Components/PopupWindow/LongBodyRepeat.gdshader")

@onready var _note_preview_hboxc: HBoxContainer = $NotePreview/HBoxC
@onready var _note_block_node: TextureRect = $NotePreview/HBoxC/VBoxC/block
@onready var _note_slide_node: TextureRect = $NotePreview/HBoxC/VBoxC/slide
@onready var _note_long_node: Control = $NotePreview/HBoxC/long
@onready var _skin_option_btn: OptionButton = $VBoxC/OptionButton

# 新增设置项控件
@onready var _l_conn_mode_btn: OptionButton = $VBoxC/OtherOptions/LConnMode
@onready var _l_repeat_mode_btn: OptionButton = $VBoxC/OtherOptions/LRepeatMode
@onready var _enable_glow_cb: CheckBox = $VBoxC/OtherOptions/EnableLightEffect
@onready var _custom_color_cb: CheckBox = $VBoxC/OtherOptions/CustomColor
@onready var _block_color_cb: CheckBox = $VBoxC/OtherOptions/BlockColor/CheckBox
@onready var _block_color_picker: ColorPickerButton = $VBoxC/OtherOptions/BlockColor/ColorPickerButton
@onready var _random_block_cb: CheckBox = $VBoxC/OtherOptions/RandomBlockColor
@onready var _slide_color_cb: CheckBox = $VBoxC/OtherOptions/SlideColor/CheckBox
@onready var _slide_color_picker: ColorPickerButton = $VBoxC/OtherOptions/SlideColor/ColorPickerButton
@onready var _random_slide_cb: CheckBox = $VBoxC/OtherOptions/RandomSlideColor
@onready var _long_color_cb: CheckBox = $VBoxC/OtherOptions/LongColor/CheckBox
@onready var _long_color_picker: ColorPickerButton = $VBoxC/OtherOptions/LongColor/ColorPickerButton
@onready var _random_long_cb: CheckBox = $VBoxC/OtherOptions/RandomLongColor

# 当前编辑中的皮肤配置工作副本（结构同 SkinManager.get_skin_config 的返回）
var _working_config: Dictionary = {}
# 当前选中的皮肤名（含 [内置] 后缀）
var _current_skin_name: String = ""

func _ready() -> void:
	_skin_option_btn.item_selected.connect(_on_skin_option_selected)
	# 新增控件信号 — 任意变化都触发：读 UI → 更新工作副本 → 刷新预览
	_l_conn_mode_btn.item_selected.connect(_on_setting_changed)
	_l_repeat_mode_btn.item_selected.connect(_on_setting_changed)
	_enable_glow_cb.toggled.connect(_on_setting_changed)
	# 自定义颜色总开关：单独处理，联动启用/禁用后续颜色子项
	_custom_color_cb.toggled.connect(_on_custom_color_toggled)
	_block_color_cb.toggled.connect(_on_setting_changed)
	_block_color_picker.color_changed.connect(_on_setting_changed)
	# 随机颜色：勾选时若对应音符颜色未勾选，自动勾选
	_random_block_cb.toggled.connect(_on_random_color_toggled.bind(_block_color_cb))
	_slide_color_cb.toggled.connect(_on_setting_changed)
	_slide_color_picker.color_changed.connect(_on_setting_changed)
	_random_slide_cb.toggled.connect(_on_random_color_toggled.bind(_slide_color_cb))
	_long_color_cb.toggled.connect(_on_setting_changed)
	_long_color_picker.color_changed.connect(_on_setting_changed)
	_random_long_cb.toggled.connect(_on_random_color_toggled.bind(_long_color_cb))

## 自定义颜色总开关 toggled：联动启用/禁用所有颜色子项，再走通用变更流程
func _on_custom_color_toggled(pressed: bool) -> void:
	_update_color_controls_state()
	_on_setting_changed(pressed)

## 随机颜色 toggled：勾选时若对应音符颜色未勾选，自动勾选（不触发信号避免递归）
func _on_random_color_toggled(pressed: bool, enable_cb: CheckBox) -> void:
	if pressed and not enable_cb.button_pressed:
		enable_cb.set_pressed_no_signal(true)
	_on_setting_changed(pressed)

## 根据 CustomColor 勾选状态启用/禁用所有颜色子项（保持布局稳定，仅灰显）
func _update_color_controls_state() -> void:
	var enabled: bool = _custom_color_cb.button_pressed
	_block_color_cb.disabled = not enabled
	_block_color_picker.disabled = not enabled
	_random_block_cb.disabled = not enabled
	_slide_color_cb.disabled = not enabled
	_slide_color_picker.disabled = not enabled
	_random_slide_cb.disabled = not enabled
	_long_color_cb.disabled = not enabled
	_long_color_picker.disabled = not enabled
	_random_long_cb.disabled = not enabled

## 由 PopupWindow.show_note_skin_adjust 调用：刷新选项 + 应用当前皮肤到预览 + 加载工作副本
func init_adjust() -> void:
	_refresh_skin_options()
	_current_skin_name = ConfigManager.instance.get_string("Appearance", "block_skin_preset", "旧版2 [内置]")
	_apply_skin_to_preview(_current_skin_name)
	# 加载当前皮肤的配置到工作副本
	_working_config = SkinMGR.get_skin_config(_current_skin_name).duplicate(true)
	if _working_config.is_empty():
		# 皮肤未找到，用默认配置兜底
		_working_config = _build_default_working_config()
	_sync_ui_from_config()
	# 重置预览容器位置和透明度（防止上次切换动画残留）
	_note_preview_hboxc.offset_transform_position = Vector2.ZERO
	_note_preview_hboxc.modulate.a = 1.0
	# 等一帧让布局稳定后应用预览（长条 head/tail 尺寸才能正确读取）
	await get_tree().process_frame
	_apply_preview_from_config()

## 返回当前选中的皮肤名（供 PopupWindow.show_note_skin_adjust 返回）
func get_selected_skin() -> String:
	return _skin_option_btn.get_item_text(_skin_option_btn.selected)

## 持久化工作副本到 skin.ini 并触发 FlowArea 重载
## 由 PopupWindow 在 window_close 后调用
func save_config() -> void:
	if _current_skin_name.is_empty():
		return
	# 读一次 UI 确保工作副本是最新值（防止有信号未触发的边界情况）
	_read_ui_to_config()
	SkinMGR.save_skin_config(_current_skin_name, _working_config)
	# 通过 config_changed 触发 PlayView 的 flow_area.load_note_skin() 重载
	# set_value_and_notify 在值未变化时不发通知——只改了光效/颜色等皮肤配置而没换皮肤时，
	# block_skin_preset 不变，不会触发重载，导致切换光效要换一次皮肤才生效。
	# 这里用 set_value 写值 + 强制 emit 一次，保证皮肤配置任何改动关闭弹窗后立即应用到游戏端
	ConfigManager.instance.set_value("Appearance", "block_skin_preset", _current_skin_name)
	if EvtBus:
		EvtBus.config_changed.emit("block_skin_preset", "Appearance", _current_skin_name)

## 构造一个默认的工作副本配置（皮肤未找到时兜底）
func _build_default_working_config() -> Dictionary:
	return {
		"general": {"enable_glow": false, "custom_color": false},
		"short": {"enable_color": false, "color": Color.WHITE, "random_color": false},
		"instant": {"enable_color": false, "color": Color.WHITE, "random_color": false},
		"long": {"enable_color": false, "color": Color.WHITE, "random_color": false, "long_connect_mode": SkinMGR.LONG_CONNECT_MODE_EDGE, "long_f_mode": SkinMGR.LONG_F_MODE_REPEAT}
	}

## 将 _working_config 同步到所有 UI 控件（不触发信号）
func _sync_ui_from_config() -> void:
	var gen: Dictionary = _working_config.get("general", {})
	_set_checkbox_no_signal(_enable_glow_cb, bool(gen.get("enable_glow", false)))
	_set_checkbox_no_signal(_custom_color_cb, bool(gen.get("custom_color", false)))

	var short_sec: Dictionary = _working_config.get("short", {})
	_set_checkbox_no_signal(_block_color_cb, bool(short_sec.get("enable_color", false)))
	_block_color_picker.color = short_sec.get("color", Color.WHITE)
	_set_checkbox_no_signal(_random_block_cb, bool(short_sec.get("random_color", false)))

	var instant_sec: Dictionary = _working_config.get("instant", {})
	_set_checkbox_no_signal(_slide_color_cb, bool(instant_sec.get("enable_color", false)))
	_slide_color_picker.color = instant_sec.get("color", Color.WHITE)
	_set_checkbox_no_signal(_random_slide_cb, bool(instant_sec.get("random_color", false)))

	var long_sec: Dictionary = _working_config.get("long", {})
	_set_checkbox_no_signal(_long_color_cb, bool(long_sec.get("enable_color", false)))
	_long_color_picker.color = long_sec.get("color", Color.WHITE)
	_set_checkbox_no_signal(_random_long_cb, bool(long_sec.get("random_color", false)))

	# 长条连接模式：UI 0=edge, 1=center
	var conn_mode = long_sec.get("long_connect_mode", SkinMGR.LONG_CONNECT_MODE_EDGE)
	_l_conn_mode_btn.select(1 if conn_mode == SkinMGR.LONG_CONNECT_MODE_CENTER else 0)
	# 长条延伸模式：UI 0=stretch, 1=repeat（注意顺序与 conn_mode 相反）
	var f_mode = long_sec.get("long_f_mode", SkinMGR.LONG_F_MODE_REPEAT)
	_l_repeat_mode_btn.select(1 if f_mode == SkinMGR.LONG_F_MODE_REPEAT else 0)

	# 根据 CustomColor 总开关状态联动启用/禁用颜色子项
	# set_pressed_no_signal 不触发 toggled，需手动同步一次控件可用状态
	_update_color_controls_state()

## 从所有 UI 控件读取值写入 _working_config
func _read_ui_to_config() -> void:
	if not _working_config.has("general"):
		_working_config["general"] = {}
	_working_config["general"]["enable_glow"] = _enable_glow_cb.button_pressed
	_working_config["general"]["custom_color"] = _custom_color_cb.button_pressed

	_read_note_section_to_config("short", _block_color_cb, _block_color_picker, _random_block_cb)
	_read_note_section_to_config("instant", _slide_color_cb, _slide_color_picker, _random_slide_cb)
	_read_note_section_to_config("long", _long_color_cb, _long_color_picker, _random_long_cb)
	# 长条独有字段
	if not _working_config.has("long"):
		_working_config["long"] = {}
	_working_config["long"]["long_connect_mode"] = SkinMGR.LONG_CONNECT_MODE_CENTER if _l_conn_mode_btn.selected == 1 else SkinMGR.LONG_CONNECT_MODE_EDGE
	_working_config["long"]["long_f_mode"] = SkinMGR.LONG_F_MODE_REPEAT if _l_repeat_mode_btn.selected == 1 else SkinMGR.LONG_F_MODE_STRETCH

func _read_note_section_to_config(key: String, enable_cb: CheckBox, picker: ColorPickerButton, random_cb: CheckBox) -> void:
	if not _working_config.has(key):
		_working_config[key] = {}
	_working_config[key]["enable_color"] = enable_cb.button_pressed
	_working_config[key]["color"] = picker.color
	_working_config[key]["random_color"] = random_cb.button_pressed

## 任意设置项变化时：读 UI → 刷新预览
func _on_setting_changed(_v) -> void:
	_read_ui_to_config()
	_apply_preview_from_config()

## 根据工作副本应用预览：颜色、光效、长条连接模式、长条延伸模式
func _apply_preview_from_config() -> void:
	var gen: Dictionary = _working_config.get("general", {})
	var custom_color_on: bool = bool(gen.get("custom_color", false))
	var enable_glow: bool = bool(gen.get("enable_glow", false))

	# 1. 颜色：custom_color OFF → 白色；ON + enable_color ON → 配置色；ON + enable_color OFF → 白色
	var block_color := Color.WHITE
	var slide_color := Color.WHITE
	var long_color := Color.WHITE
	if custom_color_on:
		block_color = _resolve_preview_color("short", _block_color_cb, _block_color_picker, _random_block_cb)
		slide_color = _resolve_preview_color("instant", _slide_color_cb, _slide_color_picker, _random_slide_cb)
		long_color = _resolve_preview_color("long", _long_color_cb, _long_color_picker, _random_long_cb)
	_note_block_node.get_node("core").modulate = block_color
	_note_slide_node.get_node("core").modulate = slide_color
	for child in _note_long_node.get_node("VBoxC").get_children():
		child.get_node("core").modulate = long_color

	# 2. 光效：enable_glow=true 时挂 shader 并设颜色；false 时清除 material
	_apply_preview_glow(_note_block_node, block_color, enable_glow)
	_apply_preview_glow(_note_slide_node, slide_color, enable_glow)
	if _note_long_node.has_node("VBoxC"):
		for child in _note_long_node.get_node("VBoxC").get_children():
			if child is TextureRect:
				_apply_preview_glow(child, long_color, enable_glow)

	# 3. 长条连接模式：center → head/tail 各向 body 偏移半高；edge → 重置
	var long_sec: Dictionary = _working_config.get("long", {})
	var conn_mode = long_sec.get("long_connect_mode", SkinMGR.LONG_CONNECT_MODE_EDGE)
	var head_node = _note_long_node.get_node_or_null("VBoxC/head")
	var tail_node = _note_long_node.get_node_or_null("VBoxC/tail")
	if head_node and tail_node:
		if conn_mode == SkinMGR.LONG_CONNECT_MODE_CENTER:
			head_node.offset_transform_position.y = -head_node.size.y * 0.5
			tail_node.offset_transform_position.y = tail_node.size.y * 0.5
		else:
			head_node.offset_transform_position.y = 0.0
			tail_node.offset_transform_position.y = 0.0

	# 4. 长条延伸模式：repeat → 挂 LongBodyRepeat shader；stretch → 清除 material
	var f_mode = long_sec.get("long_f_mode", SkinMGR.LONG_F_MODE_REPEAT)
	var body_node = _note_long_node.get_node_or_null("VBoxC/body")
	var body_core_node = _note_long_node.get_node_or_null("VBoxC/body/core")
	_apply_preview_long_f_mode(body_node, f_mode)
	_apply_preview_long_f_mode(body_core_node, f_mode)

## 解析预览颜色：随机模式时生成一个临时随机色（仅用于预览，不写回配置）
func _resolve_preview_color(key: String, enable_cb: CheckBox, picker: ColorPickerButton, random_cb: CheckBox) -> Color:
	if not enable_cb.button_pressed:
		return Color.WHITE
	if random_cb.button_pressed:
		# 预览时用基于 key 的固定种子，避免每次刷新都变颜色
		var seed_val: int = hash(key) % 360
		return Color.from_hsv(seed_val / 360.0, 0.8, 1.0)
	return picker.color

## 给预览节点的 _glow 子节点应用或清除 NoteGlow shader
func _apply_preview_glow(note_root: Node, glow_color: Color, enable_glow: bool) -> void:
	var glow = note_root.get_node_or_null("_glow")
	if glow == null:
		return
	if not enable_glow:
		glow.material = null
		return
	note_root.z_index = 1
	if glow.material == null or not (glow.material is ShaderMaterial) or (glow.material as ShaderMaterial).shader != NOTE_GLOW_SHADER:
		var mat := ShaderMaterial.new()
		mat.shader = NOTE_GLOW_SHADER
		glow.material = mat
	var mat2 := glow.material as ShaderMaterial
	mat2.set_shader_parameter("glow_color", glow_color)
	mat2.set_shader_parameter("glow_intensity", 1.0)
	mat2.set_shader_parameter("glow_size", 8.0)
	mat2.set_shader_parameter("glow_stretch", 1.0)
	mat2.set_shader_parameter("note_uv_center", Vector2(0.5, 0.5))
	mat2.set_shader_parameter("note_uv_half", Vector2(0.1667, 0.1667))

## 给预览 body 节点应用或清除 LongBodyRepeat shader
func _apply_preview_long_f_mode(body_node: Node, f_mode: String) -> void:
	if not (body_node is TextureRect):
		return
	if f_mode == SkinMGR.LONG_F_MODE_REPEAT:
		var mat = body_node.material
		if mat == null or not (mat is ShaderMaterial) or (mat as ShaderMaterial).shader != LONG_BODY_REPEAT_SHADER:
			var new_mat := ShaderMaterial.new()
			new_mat.shader = LONG_BODY_REPEAT_SHADER
			body_node.material = new_mat
	else:
		body_node.material = null

## 不触发信号设置 CheckBox 状态
func _set_checkbox_no_signal(cb: CheckBox, pressed: bool) -> void:
	cb.set_pressed_no_signal(pressed)

# 创建完全透明的纹理用于缺失贴图回退
func _create_transparent_texture(width: int = 64, height: int = 64) -> Texture2D:
	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)

# 应用指定皮肤的贴图到 NotePreview 预览节点
# 复用 FlowArea.set_note_texture 的节点路径约定：
#   block/slide: 根 texture + core 子节点 texture
#   long: VBoxC/{head,head/core,body,body/core,tail,tail/core}
func _apply_skin_to_preview(skin_name: String) -> void:
	var skin_textures: Dictionary = {}
	skin_textures = SkinMGR.get_skin_textures(skin_name)

	var _transparent := _create_transparent_texture()
	# 纹理数组顺序与 FlowArea.load_note_skin 一致
	var tex_arr: Array = [
		skin_textures.get("short"),
		skin_textures.get("short_core"),
		skin_textures.get("instant"),
		skin_textures.get("instant_core"),
		skin_textures.get("long_b"),
		skin_textures.get("long_b_core"),
		skin_textures.get("long_f"),
		skin_textures.get("long_f_core"),
		skin_textures.get("long_t"),
		skin_textures.get("long_t_core")
	]

	# block
	_note_block_node.texture = tex_arr[0] if tex_arr[0] else _transparent
	_note_block_node.get_node("core").texture = tex_arr[1] if tex_arr[1] else _transparent

	# slide
	_note_slide_node.texture = tex_arr[2] if tex_arr[2] else _transparent
	_note_slide_node.get_node("core").texture = tex_arr[3] if tex_arr[3] else _transparent

	# long: head / body / tail
	_note_long_node.get_node("VBoxC/head").texture = tex_arr[4] if tex_arr[4] else _transparent
	_note_long_node.get_node("VBoxC/head/core").texture = tex_arr[5] if tex_arr[5] else _transparent
	_note_long_node.get_node("VBoxC/body").texture = tex_arr[6] if tex_arr[6] else _transparent
	_note_long_node.get_node("VBoxC/body/core").texture = tex_arr[7] if tex_arr[7] else _transparent
	_note_long_node.get_node("VBoxC/tail").texture = tex_arr[8] if tex_arr[8] else _transparent
	_note_long_node.get_node("VBoxC/tail/core").texture = tex_arr[9] if tex_arr[9] else _transparent

# 填充皮肤选项列表，选中当前配置的皮肤
func _refresh_skin_options() -> void:
	var skin_list: Array = SkinMGR.get_available_skins()
	if skin_list.is_empty():
		skin_list = ["旧版2 [内置]"]
	var current := ConfigManager.instance.get_string("Appearance", "block_skin_preset", "旧版2 [内置]")
	_skin_option_btn.clear()
	for skin in skin_list:
		_skin_option_btn.add_item(skin)
	var idx := skin_list.find(current)
	_skin_option_btn.select(maxi(0, idx))

# 选项切换：播放上移+淡出→换皮肤→从下方上移+淡入动画，并即时应用皮肤到 PlayView
# 注意：不能用 animate_fade_out/in，因为它们会设置 visible=false（fade_out 完成后）
# 和 modulate.a=0（fade_in 开头），会导致第二段动画期间节点不可见。
# 改用 create_sequence + tween_property 直接 tween modulate:a，避免 visible 副作用。
func _on_skin_option_selected(_index: int) -> void:
	var skin_name: String = _skin_option_btn.get_item_text(_skin_option_btn.selected)
	# 若有动画在跑，先 kill
	AniMGR.stop_tween("popup_skin_switch_up")
	AniMGR.stop_tween("popup_skin_switch_down")
	AniMGR.stop_tween("popup_skin_switch_fade_out")
	AniMGR.stop_tween("popup_skin_switch_fade_in")
	# 第一段：上移 + 淡出（并行）
	var move_up := AniMGR.animate_offset_to(_note_preview_hboxc, Vector2(0, -80), 0.25, "popup_skin_switch_up")
	var fade_out := AniMGR.create_sequence("popup_skin_switch_fade_out")
	fade_out.tween_property(_note_preview_hboxc, "modulate:a", 0.0, 0.25)
	await move_up.finished
	# 应用新皮肤到预览节点
	_apply_skin_to_preview(skin_name)
	# 切换工作副本到新皮肤（丢弃旧皮肤的未保存修改）
	_current_skin_name = skin_name
	_working_config = SkinMGR.get_skin_config(skin_name).duplicate(true)
	if _working_config.is_empty():
		_working_config = _build_default_working_config()
	_sync_ui_from_config()
	# 通过 ConfigManager 即时触发 config_changed → PlayView 的 flow_area.load_note_skin()
	# （相当于把设置保存时进行的皮肤应用提前到这里）
	ConfigManager.instance.set_value_and_notify("Appearance", "block_skin_preset", skin_name)
	# 重置到下方位置（瞬间）
	_note_preview_hboxc.offset_transform_position = Vector2(0, 80)
	# 第二段：从下方上移 + 淡入（并行）
	AniMGR.animate_offset_to(_note_preview_hboxc, Vector2.ZERO, 0.25, "popup_skin_switch_down")
	var fade_in := AniMGR.create_sequence("popup_skin_switch_fade_in")
	fade_in.tween_property(_note_preview_hboxc, "modulate:a", 1.0, 0.25)
	# 等一帧让布局稳定后应用预览（颜色/光效/长条模式）
	await get_tree().process_frame
	_apply_preview_from_config()
