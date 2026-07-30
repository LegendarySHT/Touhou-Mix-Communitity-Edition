extends BaseScrollList

class_name StoreView

@onready var _top_bar: Control = get_parent().get_node("TopBar")
@onready var _bottom_bar: Control = get_parent().get_node("Bottom")

var _top_tween: Tween
var _bottom_tween: Tween
var _scroll_tween: Tween
var _top_visible := false
var _bottom_visible := false
var _last_scroll_vertical := 0

func _ready() -> void:
	work_state = UIStateManager.UIState.STORE_VIEW
	# 设置直接相邻状态：切到不在此集合的状态时释放所有列表项封面
	# STORE_VIEW 相邻：ALBUM_VIEW（侧栏返回）
	set_adjacent_states([
		UIStateManager.UIState.ALBUM_VIEW,
	])
	super._ready()

	# TopBar/Bottom 的进入动画由 AnimationManager.animate_ui_in("Store_View") 负责，
	# 这里不再设置 offset_top/offset_bottom 或调用 _toggle_top/_toggle_bottom，
	# 避免与 AnimationManager 的 offset_transform_position 动画冲突（懒加载时序下两者同时执行会导致 UI 异常）
	# _toggle_top/_toggle_bottom 仅在 _process 滚动检测时使用

	_load_demo_data()

	UiStatMGR.state_changed.connect(_on_state)

	if ThemeMGR:
		ThemeMGR.register_theme_applier(self)
		apply_theme()

## 应用主题色（由 ThemeManager 广播调用 + _ready 首次自调）
func apply_theme() -> void:
	var store := get_parent()
	if not store:
		return
	# TopBar — 垂直渐变 primary → primary_dark
	var topbar := store.get_node_or_null("TopBar") as Panel
	if topbar:
		var sb := topbar.get_theme_stylebox("panel")
		if sb is StyleBoxTexture:
			var tex := sb.texture as GradientTexture2D
			if tex and tex.gradient:
				tex.gradient.set_color(0, ThemeMGR.get_color("primary"))
				tex.gradient.set_color(1, ThemeMGR.get_color("primary_dark"))
	# TopBar/C/Search/Base — 四点 vertex_colors
	var search_base := store.get_node_or_null("TopBar/C/Search/Base") as Polygon2D
	if search_base:
		var p := ThemeMGR.get_color("primary")
		var pd := ThemeMGR.get_color("primary_dark")
		search_base.vertex_colors = PackedColorArray([
			p.lightened(0.1), p, pd, p.lightened(0.2),
		])
	# Bottom/Previ + Next — primary_dark 基调
	for btn_name in ["Previ", "Next"]:
		var btn := store.get_node_or_null("Bottom/" + btn_name) as Button
		ThemeMGR._style_button_set_bg_color(btn, ThemeMGR.get_color("primary_dark"))
	# Bottom/Indicate — 页码标签背景 primary_light
	var indicate := store.get_node_or_null("Bottom/Indicate") as Label
	if indicate:
		var sb := indicate.get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			sb.bg_color = ThemeMGR.get_color("primary_light")

func _exit_tree() -> void:
	if ThemeMGR:
		ThemeMGR.unregister_theme_applier(self)

## 加载演示数据（创建列表项 + 填充前 5 个 midi）
## 首次 _ready 和重新进入 STORE_VIEW（列表为空时）调用
func _load_demo_data() -> void:
	for i in range(36):
		create_and_add_item("%d" % i, "StoreMidiItem")

	# 懒加载兼容：若数据已加载完成（启动后首次进入 StoreView），不再 await 一次性信号
	if DataMGR.is_loading:
		await EvtBus.data_loaded_complete
	var test_midis:Array[MidiData] = DataMGR.get_all_midis()

	#演示代码
	for i in range(5):
		if i < test_midis.size():
			container.get_child(i).set_display(test_midis[i])

	_last_scroll_vertical = scroll_vertical

func _on_state(old: UIStateManager.UIState, new: UIStateManager.UIState) -> void:
	if new == UIStateManager.UIState.STORE_VIEW:
		# 重新进入时若列表项已被 _cleanup 清空，重新加载演示数据
		if list_items.is_empty():
			_load_demo_data()
		return_to_top()
	# 退出 STORE_VIEW 时释放列表项
	if old == UIStateManager.UIState.STORE_VIEW and new != UIStateManager.UIState.STORE_VIEW:
		_cleanup()

## 释放视图内部资源（列表项），保留节点壳和信号连接
## 重新进入时由 _on_state 检测列表为空并调用 _load_demo_data 重新加载
func _cleanup() -> void:
	clear_items()

func return_to_top() -> void:
	if _scroll_tween and _scroll_tween.is_running():
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(self, "scroll_vertical", 0, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toggle_top(true)
	_toggle_bottom(false)

func _process(delta: float) -> void:
	super._process(delta)

	# 根据滚动方向触发
	if scroll_vertical > _last_scroll_vertical:
		_toggle_top(false)
		_toggle_bottom(true)
	elif scroll_vertical < _last_scroll_vertical:
		_toggle_top(true)
		_toggle_bottom(false)

	_last_scroll_vertical = scroll_vertical

func _toggle_top(_show: bool) -> void:
	if _top_visible == _show:
		return
	if _top_tween and _top_tween.is_running():
		_top_tween.kill()
		_top_tween = null
	_top_visible = _show
	var h := 150
	_top_tween = _slide(_top_bar, -h if not _show else 0, -h if not _show else 0)

func _toggle_bottom(_show: bool) -> void:
	if _bottom_visible == _show:
		return
	if _bottom_tween and _bottom_tween.is_running():
		_bottom_tween.kill()
		_bottom_tween = null
	_bottom_visible = _show
	var h := 90
	_bottom_tween = _slide(_bottom_bar, 5 if not _show else -h, h if not _show else 0)

func _slide(bar: Control, off_top: float, off_bottom: float) -> Tween:
	var t := create_tween().set_parallel()
	t.tween_property(bar, "offset_top", off_top, 0.45).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(bar, "offset_bottom", off_bottom, 0.45).set_trans(Tween.TRANS_CUBIC)
	return t

func _input(event: InputEvent) -> void:
	super._gui_input(event)

func on_midi_select(midi: MidiData):
	print("select %s" % midi.name)
