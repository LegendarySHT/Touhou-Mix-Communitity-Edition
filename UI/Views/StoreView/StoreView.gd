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
	super._ready()

	# 初始移出屏幕
	_top_bar.offset_top = -_top_bar.size.y
	_top_bar.offset_bottom = 0
	_bottom_bar.offset_top = 0
	_bottom_bar.offset_bottom = _bottom_bar.size.y

	for i in range(36):
		create_and_add_item("%d" % i, "StoreMidiItem")

	await EvtBus.data_loaded_complete
	var test_midis:Array[MidiData] = DataMGR.get_all_midis()
	for i in range(5):
		container.get_child(i).set_display(test_midis[i])

	_last_scroll_vertical = scroll_vertical
	# 入场动画
	_toggle_top(true)
	_toggle_bottom(true)

	UiStatMGR.state_changed.connect(_on_state)

func _on_state(_old: UIStateManager.UIState, new: UIStateManager.UIState) -> void:
	if new == UIStateManager.UIState.STORE_VIEW:
		return_to_top()

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
