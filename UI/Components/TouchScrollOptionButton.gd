extends OptionButton
class_name TouchScrollOptionButton

## 让 OptionButton 的原生 PopupMenu 支持触摸拖动滚动。
##
## 机制：
##   1. items → PASS → 事件穿透到 ScrollContainer 实现原生触摸拖拽
##   2. hide_on_item_selection=false → 阻止自动关闭
##   3. 监听 ScrollContainer gui_input 检测拖拽
##   4. item_selected 信号中判断：拖拽→回退选中项，非拖拽→正常
##   5. 关闭 popup 时用 set_v_scroll(get_v_scroll()) 清除 ScrollContainer 卡住的拖拽状态

var _drag_detected := false
var _pre_popup_selected := -1

func _ready() -> void:
	var popup := get_popup()

	GLogger.info("TSOB _ready: connections=%d" % popup.index_pressed.get_connections().size(), "TSOB")

	# 阻止 activate_item 自动关闭弹窗（OptionButton 用 radio check items，
	# activate_item 检查的是 hide_on_checkable_item_selection 而非 hide_on_item_selection）
	popup.hide_on_checkable_item_selection = false
	popup.popup_hide.connect(_on_popup_hide)
	toggled.connect(_on_toggled)
	item_selected.connect(_on_item_selected)

	# items → PASS：事件穿透到 ScrollContainer 实现原生触摸拖拽
	var scroll := _find_scroll_container(popup)
	if scroll:
		_set_mouse_filter_recursive(scroll, Control.MOUSE_FILTER_PASS, true)
		scroll.gui_input.connect(_on_scroll_gui_input)
		GLogger.info("TSOB scroll configured", "TSOB")
	else:
		GLogger.warning("TSOB scroll NOT found", "TSOB")

func _on_toggled(_pressed: bool) -> void:
	if _pressed:
		_drag_detected = false
		_pre_popup_selected = selected

func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_drag_detected = true
	elif event is InputEventScreenDrag:
		_drag_detected = true

func _on_item_selected(idx: int) -> void:
	GLogger.info("TSOB item_selected: idx=%d drag=%s pre=%d" % [idx, _drag_detected, _pre_popup_selected], "TSOB")
	if _drag_detected:
		_drag_detected = false
		# 拖拽后松手：恢复到之前的选择，弹窗保持打开
		if _pre_popup_selected >= 0 and _pre_popup_selected != idx:
			select(_pre_popup_selected)
		return
	# 正常点击：关闭弹窗
	get_popup().hide()

func _on_popup_hide() -> void:
	# 重置父级 ScrollContainer 的卡住状态
	var parent_scroll := _find_parent_scroll()
	if parent_scroll:
		parent_scroll.set_v_scroll(parent_scroll.get_v_scroll())

	# 重置 popup 内部 ScrollContainer 的卡住状态
	var scroll := _find_scroll_container(get_popup())
	if scroll:
		scroll.set_v_scroll(scroll.get_v_scroll())

func _find_parent_scroll() -> ScrollContainer:
	var node := get_parent()
	while node:
		if node is ScrollContainer:
			return node
		node = node.get_parent()
	return null

func _find_scroll_container(node: Node) -> ScrollContainer:
	for child in node.get_children(true):
		if child is ScrollContainer:
			return child
		var found := _find_scroll_container(child)
		if found:
			return found
	return null

func _set_mouse_filter_recursive(node: Node, filter: int, skip_root: bool = false) -> void:
	if not skip_root and node is Control:
		node.mouse_filter = filter
	for child in node.get_children(true):
		_set_mouse_filter_recursive(child, filter, false)
