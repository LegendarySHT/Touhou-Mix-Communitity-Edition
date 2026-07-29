extends PopupPanel

class_name PopupWindow

static var instance: PopupWindow

@onready var _window_bg_shader: ColorRect = get_parent().get_node_or_null("PopupWindowShader")
# @onready var _window_bg: PanelContainer = $PC/WindowBG
@onready var _tab_c: TabContainer = $TabC
@onready var _ani: AnimationManager = AniMGR

# 默认页
@onready var _message: Label = $TabC/Default/Content/Label
@onready var _cancel_btn: Button = $TabC/Default/Btns/Cancel
@onready var _confirm_btn: Button = $TabC/Default/Btns/Confirm
@onready var _option_btn: OptionButton = $TabC/Default/Content/OptionButton

# 延迟校准页
@onready var _delay_indicator: Panel = $TabC/DelayAdjust/DelayIndicator
@onready var _center_line: PanelContainer = $TabC/DelayAdjust/DelayIndicator/CenterLine
@onready var _adjust_line: PanelContainer = $TabC/DelayAdjust/DelayIndicator/AdjustLine
@onready var _delay_value: Label = $TabC/DelayAdjust/HBoxC/Value
@onready var delay_btn: Button = $TabC/DelayAdjust/Button # 主题管理器访问了这个

# 皮肤修改页
@onready var _note_preview_hboxc: HBoxContainer = $TabC/NoteSkinAdjust/NotePreview/HBoxC
@onready var _note_block_node: TextureRect = $TabC/NoteSkinAdjust/NotePreview/HBoxC/VBoxC/block
@onready var _note_slide_node: TextureRect = $TabC/NoteSkinAdjust/NotePreview/HBoxC/VBoxC/slide
@onready var _note_long_node: Control = $TabC/NoteSkinAdjust/NotePreview/HBoxC/long
@onready var _skin_option_btn: OptionButton = $TabC/NoteSkinAdjust/VBoxC/OptionButton

signal window_close

var _confirm: bool = false

# ===== 延迟校准状态 =====
## 校准是否进行中
var _calib_active: bool = false
## 已采集的延迟样本（单位：ms，正=音频延迟需正向补偿，负=负向补偿）
var _calib_samples: Array[float] = []
## AdjustLine 循环动画 Tween 引用
var _adjust_line_tween: Tween = null
## 连续稳定样本计数（与前一个样本差值 ≤ _STABLE_MAX_DIFF 的连续次数）
var _stable_count: int = 0
## 上一个样本值（用于差值计算）
var _last_sample: float = NAN

## AdjustLine 单向运动范围（绝对值，单位：像素，1 像素 = 1 ms）
const _ADJUST_LINE_RANGE: float = 310.0
## AdjustLine 单程时间
const _ADJUST_LINE_DURATION: float = 1.0
## 进入稳定状态所需连续稳定次数（3个连续样本 = _stable_count >= 2 时开始移动 CenterLine）
const _STABLE_START_THRESHOLD: int = 2
## 校准完成所需连续稳定次数（8个连续样本 = _stable_count >= 7 时完成）
const _CALIB_DONE_STABLE: int = 7
## 样本间允许的最大差值（ms），超过则视为不稳定
const _STABLE_MAX_DIFF: float = 50.0

func _ready() -> void:
	instance = self
	# 默认窗口按钮
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	# 延迟校准按钮
	delay_btn.pressed.connect(_on_delay_btn_pressed)
	# 皮肤选项切换
	_skin_option_btn.item_selected.connect(_on_skin_option_selected)

	# 监听内置 popup 生命周期信号
	about_to_popup.connect(func() -> void: _window_popup_animate(true))
	# 点击窗口外部时 Godot 会自动隐藏 popup 并发出 popup_hide，此处兜底处理
	popup_hide.connect(func() -> void:
		_stop_calibration()
		_window_popup_animate(false)
	)

func _on_cancel_pressed() -> void:
	_confirm = false
	hide()

func _on_confirm_pressed() -> void:
	_confirm = true
	hide()

func _window_popup_animate(is_popup: bool) -> Tween:
	var popup_tween : Tween = null
	if is_popup:
		_confirm = false
		# 窗口内容
		for nd in get_children():
			nd.offset_transform_scale = Vector2.ZERO if is_popup else Vector2.ONE
			_ani.animate_offset_scale(nd, Vector2.ZERO if not is_popup else Vector2.ONE, 0.4, "popup_%s_scale" % nd.name)

		# 背景
		popup_tween = _ani.animate_fade_in(_window_bg_shader, 0.3, "popup_bg_fade")
	else:
		popup_tween = _ani.animate_fade_out(_window_bg_shader, 0.3, "popup_bg_fade")
		popup_tween.finished.connect(func() -> void: window_close.emit())
	return popup_tween

func _set_option(options: Array):
	_option_btn.clear()
	var idx: int = 0
	for i in options:
		_option_btn.add_item(i, idx)
		idx += 1
	
	_option_btn.visible = true if idx else false

# ===== 延迟校准 =====

# 启动校准：重置数据 + 启动 AdjustLine 单向循环动画
func _start_calibration() -> void:
	_calib_active = true
	_calib_samples.clear()
	_stable_count = 0
	_last_sample = NAN
	
	_update_center_line(float(_delay_value.text))
	# 启动 AdjustLine 单向循环动画
	# AdjustLine 本身不可见，仅作为位置跟踪器，点击时在当前位置生成残影
	_adjust_line.offset_transform_position = Vector2(_ADJUST_LINE_RANGE, 0)
	if _adjust_line_tween and _adjust_line_tween.is_valid():
		_adjust_line_tween.kill()
	_adjust_line_tween = _ani.create_sequence("popup_adjust_line_loop")
	_adjust_line_tween.set_loops()
	_adjust_line_tween.set_trans(Tween.TRANS_LINEAR)

	_adjust_line_tween.tween_property(_adjust_line, "offset_transform_position:x", 0, _ADJUST_LINE_DURATION)
	_adjust_line_tween.tween_callback(func(): _play_beat_sound())
	_adjust_line_tween.tween_property(_adjust_line, "offset_transform_position:x", -_ADJUST_LINE_RANGE, _ADJUST_LINE_DURATION)
	_adjust_line_tween.tween_callback(func(): _adjust_line.offset_transform_position = Vector2(_ADJUST_LINE_RANGE, 0))

# 停止校准：终止动画
func _stop_calibration() -> void:
	if not _calib_active:
		return
	_calib_active = false
	if _adjust_line_tween and _adjust_line_tween.is_valid():
		_adjust_line_tween.kill()
	_adjust_line_tween = null

## 占位函数：AdjustLine 经过 0 时调用，正常应播放节拍音
## TODO: 接入实际音频播放
func _play_beat_sound() -> void:
	pass

# 点击校准按钮：记录当前 AdjustLine 位置作为延迟样本
func _on_delay_btn_pressed() -> void:
	if not _calib_active:
		return
	var click_x: float = _adjust_line.offset_transform_position.x
	# 生成 AdjustLine 残影并播放淡出动画（视觉反馈）
	_spawn_adjust_line_ghost(click_x)
	# 记录样本：左（负 x）= 正延迟，右（正 x）= 负延迟 → 取反
	var delay: float = -click_x
	_calib_samples.append(delay)
	# 稳定性检测：与前一个样本的差值 ≤ 50ms → 计数器 +1，否则归零
	if not is_nan(_last_sample):
		if abs(delay - _last_sample) <= _STABLE_MAX_DIFF:
			_stable_count += 1
		else:
			_stable_count = 0
	_last_sample = delay
	# 进入稳定状态（连续3个样本稳定，即 _stable_count >= 2）→ 开始更新 CenterLine 和 LineEdit
	if _stable_count >= _STABLE_START_THRESHOLD:
		var avg: float = _compute_stable_average()
		_set_delay_value(avg)
	# 连续8个样本稳定（_stable_count >= 7）→ 校准完成
	if _stable_count >= _CALIB_DONE_STABLE:
		_finish_calibration()

# 在指定位置生成 AdjustLine 残影（点击瞬间的视觉反馈，1秒淡出）
func _spawn_adjust_line_ghost(pos_x: float) -> void:
	var ghost: PanelContainer = _adjust_line.duplicate()
	ghost.visible = true
	ghost.offset_transform_position = Vector2(pos_x, 0)
	_delay_indicator.add_child(ghost)
	var ghost_tween := _ani.animate_fade_out(ghost, 1.0, "popup_adjust_ghost_%d" % Time.get_ticks_msec())
	ghost_tween.finished.connect(func() -> void:
		if is_instance_valid(ghost):
			ghost.queue_free()
	)

# 计算当前稳定窗口内样本的平均值（窗口 = _stable_count + 1 个连续稳定样本）
func _compute_stable_average() -> float:
	var window_size: int = _stable_count + 1
	var start: int = maxi(0, _calib_samples.size() - window_size)
	var sum: float = 0.0
	for i in range(start, _calib_samples.size()):
		sum += _calib_samples[i]
	return sum / float(_calib_samples.size() - start)

# 更新 CenterLine 位置（中间=0，左=正延迟，右=负延迟，1像素=1ms）
func _update_center_line(delay_ms: float) -> void:
	_center_line.offset_transform_position = Vector2(-delay_ms, 0)

# 统一设置延迟值：更新 Label 和 CenterLine
func _set_delay_value(delay_ms: float) -> void:
	_delay_value.text = str(roundi(delay_ms))
	_update_center_line(delay_ms)

# 手动拖动 DelayIndicator：在面板范围内点击/拖动 → CenterLine 移动到手指位置并更新延迟
func _input(event: InputEvent) -> void:
	if not visible or _tab_c.current_tab != 1:
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	# 忽略松开事件
	if event is InputEventScreenTouch and not event.pressed:
		return
	var rect := _delay_indicator.get_global_rect()
	if not rect.has_point(event.position):
		return
	# 计算手指相对于 DelayIndicator 中心的 x 偏移（1 像素 = 1 ms）
	var local_x: float = event.position.x - rect.get_center().x
	# 限制在面板范围内
	local_x = clampf(local_x, -rect.size.x / 2.0, rect.size.x / 2.0)
	# 左 = 正延迟，右 = 负延迟 → 取反
	_set_delay_value(-local_x)

# 校准完成
func _finish_calibration() -> void:
	_stop_calibration()
	hide()  # → 触发 popup_hide → 播放退出动画 → emit window_close

# ===== 公共函数 =====

# 设置默认窗口的选项
func get_selected() -> String:
	return _option_btn.get_item_text(_option_btn.get_selected_id())

# 用默认窗口显示消息，要获取确认状态需await
func show_message(message: String, cancel_visible: bool = false, options: Array = []) -> bool:
	size = Vector2(850, 600)
	_tab_c.current_tab = 0
	_message.text = message
	_cancel_btn.modulate.a = 0 if not cancel_visible else 1
	_set_option(options)
	popup()  # 内置 popup() → 触发 about_to_popup → 播放进入动画

	await window_close
	return _confirm

# 弹出延迟校准窗口
func show_delay_adjust(current_delay: int = 0) -> int:
	size = Vector2(850, 600)
	_tab_c.current_tab = 1
	_delay_value.text = str(current_delay)
	_start_calibration()
	popup()  # 内置 popup() → 触发 about_to_popup → 播放进入动画

	await window_close
	return int(_delay_value.text)

# ===== 皮肤修改 =====

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
	_ani.stop_tween("popup_skin_switch_up")
	_ani.stop_tween("popup_skin_switch_down")
	_ani.stop_tween("popup_skin_switch_fade_out")
	_ani.stop_tween("popup_skin_switch_fade_in")
	# 第一段：上移 + 淡出（并行）
	var move_up := _ani.animate_offset_to(_note_preview_hboxc, Vector2(0, -80), 0.25, "popup_skin_switch_up")
	var fade_out := _ani.create_sequence("popup_skin_switch_fade_out")
	fade_out.tween_property(_note_preview_hboxc, "modulate:a", 0.0, 0.25)
	await move_up.finished
	# 应用新皮肤到预览节点
	_apply_skin_to_preview(skin_name)
	# 通过 ConfigManager 即时触发 config_changed → PlayView 的 flow_area.load_note_skin()
	# （相当于把设置保存时进行的皮肤应用提前到这里）
	ConfigManager.instance.set_value_and_notify("Appearance", "block_skin_preset", skin_name)
	# 重置到下方位置（瞬间）
	_note_preview_hboxc.offset_transform_position = Vector2(0, 80)
	# 第二段：从下方上移 + 淡入（并行）
	_ani.animate_offset_to(_note_preview_hboxc, Vector2.ZERO, 0.25, "popup_skin_switch_down")
	var fade_in := _ani.create_sequence("popup_skin_switch_fade_in")
	fade_in.tween_property(_note_preview_hboxc, "modulate:a", 1.0, 0.25)

# 弹出皮肤修改窗口
func show_note_skin_adjust() -> String:
	size = Vector2(1500, 700)
	_tab_c.current_tab = 2
	_refresh_skin_options()
	var current := ConfigManager.instance.get_string("Appearance", "block_skin_preset", "旧版2 [内置]")
	_apply_skin_to_preview(current)
	# 重置预览容器位置和透明度（防止上次切换动画残留）
	_note_preview_hboxc.offset_transform_position = Vector2.ZERO
	_note_preview_hboxc.modulate.a = 1.0
	popup()  # 内置 popup() → 触发 about_to_popup → 播放进入动画
	await window_close
	return _skin_option_btn.get_item_text(_skin_option_btn.selected)
