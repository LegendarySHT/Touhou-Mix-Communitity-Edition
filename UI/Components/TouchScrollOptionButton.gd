extends OptionButton
class_name TouchScrollOptionButton

## 使用自定义可滚动弹出面板替代原生 PopupMenu，
## 统一处理点击选择和拖动滚动（触摸+鼠标），全平台一致体验。

var _native_popup: PopupMenu

# 自定义弹出面板节点
var _overlay: ColorRect = null
var _panel: _PopupPanel = null
var _is_open: bool = false
var _native_blocked: bool = false

# 样式缓存（从 PopupMenu 主题获取，保持视觉一致）
var _style_panel: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _style_normal: StyleBoxFlat
var _popup_font_size: int = 32

const WIDTH_MULTIPLIER: float = 2.0  # 宽度为按钮宽度的倍数


func _ready() -> void:
	_native_popup = get_popup()
	_cache_styles()
	# 拦截原生 PopupMenu：about_to_popup 时改用自定义面板
	_native_popup.about_to_popup.connect(_on_native_about_to_popup)
	_native_popup.popup_hide.connect(_on_native_popup_hide)


func _cache_styles() -> void:
	var sb := _native_popup.get_theme_stylebox("panel", "PopupMenu")
	if sb is StyleBoxFlat:
		_style_panel = (sb as StyleBoxFlat).duplicate()
	else:
		_style_panel = StyleBoxFlat.new()
		_style_panel.bg_color = ThemeMGR.get_color("primary_dark")

	var sbh := _native_popup.get_theme_stylebox("hover", "PopupMenu")
	if sbh is StyleBoxFlat:
		_style_hover = (sbh as StyleBoxFlat).duplicate()
	else:
		_style_hover = StyleBoxFlat.new()
		_style_hover.bg_color = ThemeMGR.get_color("primary")

	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0, 0, 0, 0)

	var fs := _native_popup.get_theme_font_size("font_size", "PopupMenu")
	if fs > 0:
		_popup_font_size = fs


# 拦截原生 PopupMenu 弹出
func _on_native_about_to_popup() -> void:
	if _native_blocked:
		return
	_native_blocked = true
	# 延迟隐藏原生 popup（它已开始显示流程，下一帧强制关闭）
	_native_popup.hide.call_deferred()
	_open_custom_popup()


func _on_native_popup_hide() -> void:
	_native_blocked = false


func _open_custom_popup() -> void:
	if get_item_count() == 0:
		return
	if not _panel:
		_build_popup()
	_panel.refresh(self)
	_place_popup_initial()
	_overlay.visible = true
	_panel.visible = true
	_is_open = true
	_panel.set_process_input(true)
	_panel.refine.call_deferred()


func _close_custom_popup() -> void:
	if _overlay:
		_overlay.visible = false
	_is_open = false
	if _panel:
		_panel.visible = false
		_panel.set_process_input(false)


func _build_popup() -> void:
	# 用 CanvasLayer 确保面板在最上层
	var layer := CanvasLayer.new()
	layer.layer = 100
	get_tree().root.add_child(layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0, 0, 0, 0.4)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	# 遮罩点击关闭
	_overlay.gui_input.connect(_on_overlay_gui_input)
	layer.add_child(_overlay)

	# 自定义面板：统一处理点击选择和触摸拖动滚动
	_panel = _PopupPanel.new()
	_panel.setup(self, _style_panel, _style_hover, _style_normal, _popup_font_size)
	_panel.visible = false
	_overlay.add_child(_panel)


func _place_popup_initial() -> void:
	var btn_rect := get_global_rect()
	var vp_size := get_viewport().get_visible_rect().size
	var width := btn_rect.size.x * WIDTH_MULTIPLIER
	# 高度=屏幕高度，宽度=按钮宽度×2，水平居中于按钮，从底部延伸至顶部
	var pos_x := btn_rect.position.x + btn_rect.size.x / 2.0 - width / 2.0
	pos_x = clampf(pos_x, 0.0, vp_size.x - width)
	_panel.position = Vector2(pos_x, 0.0)
	_panel.size = Vector2(width, vp_size.y)


func _on_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_custom_popup()
	elif event is InputEventScreenTouch and event.pressed:
		_close_custom_popup()


func _on_item_selected_from_panel(index: int) -> void:
	select(index)
	item_selected.emit(index)
	_close_custom_popup()


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		_close_custom_popup()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()


# ===== 自定义弹出面板 =====
## 统一处理点击选择和触摸拖动滚动。
## 关键：用 _input 而非 _gui_input 接收触摸事件（_gui_input 对 ScreenTouch 支持不可靠），
## 手动做命中检测区分点击和拖动。
class _PopupPanel extends Panel:
	var owner_btn: TouchScrollOptionButton = null
	var scroll: ScrollContainer = null
	var vbox: VBoxContainer = null
	var item_labels: Array[Label] = []
	var style_hover: StyleBoxFlat = null
	var style_normal: StyleBoxFlat = null
	var font_size: int = 32
	var font: Font = null

	# 拖动/点击状态
	var _pressing: bool = false
	var _press_pos: Vector2 = Vector2.ZERO
	var _scroll_start: int = 0
	var _drag_moved: bool = false
	var _velocity: float = 0.0
	const DRAG_THRESHOLD: float = 10.0
	const VELOCITY_DECAY: float = 0.92
	const MIN_VELOCITY: float = 10.0

	func setup(btn: TouchScrollOptionButton, sp: StyleBoxFlat, sh: StyleBoxFlat, sn: StyleBoxFlat, fs: int) -> void:
		owner_btn = btn
		style_hover = sh
		style_normal = sn
		font_size = fs
		font = btn._native_popup.get_theme_font("font", "PopupMenu")
		add_theme_stylebox_override("panel", sp)
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP

		scroll = ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
		# IGNORE：ScrollContainer 不接收输入，仅作内容裁剪容器，滚动由本面板手动控制
		scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(scroll)

		vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 0)
		scroll.add_child(vbox)
		set_process_input(false)
		set_process(false)

	func refresh(btn: TouchScrollOptionButton) -> void:
		for lbl in item_labels:
			lbl.queue_free()
		item_labels.clear()
		for i in btn.get_item_count():
			var lbl := Label.new()
			lbl.text = btn.get_item_text(i)
			lbl.add_theme_font_override("font", font)
			lbl.add_theme_font_size_override("font_size", font_size)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.custom_minimum_size = Vector2(0, font_size + 24)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if i == btn.selected:
				lbl.add_theme_stylebox_override("normal", style_hover)
			else:
				lbl.add_theme_stylebox_override("normal", style_normal)
			vbox.add_child(lbl)
			item_labels.append(lbl)

	func refine() -> void:
		await get_tree().process_frame
		if not owner_btn or not is_instance_valid(owner_btn) or not owner_btn._is_open:
			return
		var vp_size := owner_btn.get_viewport().get_visible_rect().size
		var btn_rect := owner_btn.get_global_rect()
		var width := btn_rect.size.x * WIDTH_MULTIPLIER
		# 高度=屏幕高度，宽度=按钮宽度×2，水平居中于按钮
		var pos_x := btn_rect.position.x + btn_rect.size.x / 2.0 - width / 2.0
		pos_x = clampf(pos_x, 0.0, vp_size.x - width)
		size = Vector2(width, vp_size.y)
		position = Vector2(pos_x, 0.0)
		if owner_btn.selected >= 0 and owner_btn.selected < item_labels.size():
			scroll.scroll_vertical = int(item_labels[owner_btn.selected].position.y)

	# 用 _input 统一接收触摸和鼠标事件，手动命中检测
	func _input(event: InputEvent) -> void:
		if not visible:
			return
		var rect := get_global_rect()

		# 触摸：按下/释放
		if event is InputEventScreenTouch:
			var inside := rect.has_point(event.position)
			if event.pressed and inside:
				_begin_press(event.position)
				get_viewport().set_input_as_handled()
			elif not event.pressed and _pressing:
				_end_press(event.position)
				get_viewport().set_input_as_handled()

		# 触摸：拖动
		elif event is InputEventScreenDrag and _pressing:
			_update_drag(event.position, event.velocity.y)
			get_viewport().set_input_as_handled()

		# 鼠标：按下（左键）/滚轮
		elif event is InputEventMouseButton and rect.has_point(event.position):
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_begin_press(event.position)
				elif _pressing:
					_end_press(event.position)
				get_viewport().set_input_as_handled()
			elif event.pressed:
				if event.button_index == MOUSE_BUTTON_WHEEL_UP:
					scroll.scroll_vertical -= 60
					get_viewport().set_input_as_handled()
				elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					scroll.scroll_vertical += 60
					get_viewport().set_input_as_handled()

		# 鼠标：拖动
		elif event is InputEventMouseMotion and _pressing:
			_update_drag(event.position, event.velocity.y)
			get_viewport().set_input_as_handled()

	# 开始按下：记录起点与初始滚动位置
	func _begin_press(pos: Vector2) -> void:
		_pressing = true
		_press_pos = pos
		_scroll_start = scroll.scroll_vertical
		_drag_moved = false
		_velocity = 0.0
		set_process(false)

	# 拖动更新：超阈值后滚动并记录速度
	func _update_drag(pos: Vector2, vel_y: float) -> void:
		var delta_y: float = pos.y - _press_pos.y
		if abs(delta_y) > DRAG_THRESHOLD:
			_drag_moved = true
		if _drag_moved:
			scroll.scroll_vertical = int(_scroll_start - delta_y)
			# 惯性方向与拖动一致：向下拖 vel_y>0，scroll 应继续减小
			_velocity = vel_y

	# 释放：未拖动则选中命中项，已拖动且有速度则启动惯性
	func _end_press(pos: Vector2) -> void:
		if not _drag_moved:
			var idx := _get_item_at(pos)
			if idx >= 0:
				owner_btn._on_item_selected_from_panel(idx)
		_pressing = false
		if _drag_moved and abs(_velocity) > MIN_VELOCITY:
			set_process(true)
		else:
			_drag_moved = false

	func _process(delta: float) -> void:
		if abs(_velocity) > MIN_VELOCITY:
			var displacement: float = _velocity * delta
			if abs(displacement) > 0.5:
				# 与拖动一致：velocity.y>0（下拖）→ scroll_vertical 减小
				scroll.scroll_vertical -= int(displacement)
				_velocity *= VELOCITY_DECAY
			else:
				_velocity = 0.0
		else:
			_velocity = 0.0
			set_process(false)

	# 将全局坐标转换为列表项索引
	func _get_item_at(global_pos: Vector2) -> int:
		if item_labels.is_empty():
			return -1
		# 全局坐标 -> 面板内坐标 -> vbox 内坐标（加 scroll 偏移）
		var y_in_vbox: float = global_pos.y - global_position.y + scroll.scroll_vertical
		for i in item_labels.size():
			var lbl := item_labels[i]
			if y_in_vbox >= lbl.position.y and y_in_vbox < lbl.position.y + lbl.size.y:
				return i
		return -1
