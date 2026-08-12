extends Control

class_name FocusManager

@onready var ui: UIStateManager = UiStatMGR
@onready var ani: AnimationManager = AniMGR

var _last_input_was_keyboard := false
var _skew_c: Control = null

func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_change)
	ani.scene_transition_fin.connect(_on_state_enter)
	_skew_c = get_node_or_null(PathRegistry.SKEW_C)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_last_input_was_keyboard = true
	elif event is InputEventScreenTouch and event.pressed:
		_last_input_was_keyboard = false

func _on_focus_change(node: Control):
	# print("[FocusMGR] Focus changed to: %s" % node.name)
	if node == null:
		return
	# 焦点落到 skew/C（视图容器）或其下的列表容器时，按当前 UI 状态转发给选中项。
	# 触发场景：ShortCutMenu 搜索按钮 focus_neighbor_left → AlbumList（按左方向键）、
	# _on_state_enter 进入视图时把焦点交给 skew/C。
	if node == _skew_c or ("selected_item" in node):
		_redirect_focus_by_state()

## 按当前 UI 状态把焦点转发到激活列表的选中项（列表焦点逻辑的唯一入口）
func _redirect_focus_by_state() -> void:
	match ui.current_state:
		ui.UIState.ALBUM_VIEW:
			_grab_list_selected(PathRegistry.ALBUM_LIST)
		ui.UIState.SONG_VIEW:
			_grab_list_selected(PathRegistry.SONG_LIST)
		ui.UIState.SORTED_VIEW:
			_grab_list_selected(PathRegistry.SORTED_MIDIS_LIST)

## 让列表的选中项获得焦点：无选中项时选首项兜底；列表为空则不做动作
func _grab_list_selected(list_path: String) -> void:
	var nd = get_node_or_null(list_path)
	if nd == null or not ("selected_item" in nd):
		return
	if nd.selected_item == -1:
		# 列表正在滚动/吸附中时，选中态可能刚被滚动逻辑清除（reset_selection），
		# 强制选首项会让吸附突然跳到列表头（"滚动中点一下停住 → 吸附到第一项"）。
		# 此时跳过兜底，让列表自然停下，由各视图 _process 的 need_snap 自动吸附到当前可见项。
		if nd.has_method("is_scrolling") and nd.is_scrolling():
			return
		nd.select_item(0)
	if nd.selected_item < 0 or nd.selected_item >= nd.list_items.size():
		return
	var selected_node = nd.get_selected_node()
	if selected_node == null:
		return
	selected_node.button.grab_focus()
	GLogger.debug("[FocusMGR] 焦点转发 → %s 选中项 #%d" % [list_path, nd.selected_item], "FocusMGR")

func _on_state_enter():
	# 移动端（Android/iOS）使用触屏操作，不需要键盘焦点导航
	var is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")

	match ui.current_state:
		ui.UIState.ALBUM_VIEW, ui.UIState.SONG_VIEW, ui.UIState.SORTED_VIEW:
			var nd = get_node(ani.ui_path_map[ani.ui_path_map.keys()[ui.current_state]])
			# 防御：nd 可能因键序变化取到无 selected_item 的普通节点（如按钮），先校验
			if nd == null or not ("selected_item" in nd):
				return
			# 焦点转移到 skew/C，由 _on_focus_change → _redirect_focus_by_state 统一
			# 转发给选中项（含 select_item(0) 兜底），这里不再重复"获取选中项"逻辑
			if _skew_c:
				_skew_c.grab_focus()
		ui.UIState.SETTINGS_VIEW:
			if not is_mobile:
				get_node(PathRegistry.SETTING_VIEW).short_cut_btn.grab_focus()
		ui.UIState.STORE_VIEW:
			# 防御性检查：列表项可能已被 _cleanup 清空（懒加载重新进入时）
			var store_list = get_node_or_null(PathRegistry.STORE_MIDI_LIST)
			if store_list and store_list.get_child_count() > 0:
				var container_node = store_list.get_child(0)
				if container_node and container_node.get_child_count() > 0:
					var first_item = container_node.get_child(0)
					if first_item and "button" in first_item:
						var first_btn: Button = first_item.button
						if _last_input_was_keyboard and is_instance_valid(first_btn):
							first_btn.grab_focus()

# func _input(event: InputEvent) -> void:
# 	if ui.current_state in [ui.UIState.ALBUM_VIEW, ui.UIState.SONG_VIEW, ui.UIState.SORTED_VIEW]:
# 		if event is InputEventKey and event.pressed:
# 			if event.keycode in [KEY_TAB]:
# 				get_node(PathRegistry.SHORTCUT_MENU_SEARCH).grab_focus()
# 				accept_event()
