extends Panel
class_name RB_Btn

static var instance: RB_Btn

enum ShowStat {
	NONE = 0,
	BACK_BTN,
	STORE_BTN,
	ARROW_RIGHT,
}

@onready var ani:AnimationManager = AniMGR
@onready var ui:UIStateManager = UiStatMGR
@onready var eb: EventBus = EvtBus

@onready var vboxc: VBoxContainer = $VBoxC
@onready var btn: Button = $Button

func _ready():
	instance = self
	# RB_Btn 旋转 30° 后，内部 Button 的本地 rect 在全局坐标中与可见图标位置可能不重合，
	# 导致点击可见图标时 Button 不响应。设置 RB_Btn 为 STOP 接收 _gui_input 作为后备：
	# 点击落在 Button 本地 rect 内由 Button 处理（pressed 信号）；
	# 落在 Button rect 外但在 RB_Btn rect 内（如旋转后偏移的图标）由 _gui_input 处理。
	mouse_filter = Control.MOUSE_FILTER_STOP
	ui.state_changed.connect(_on_state_change)

	eb.page_right.connect(func ():
		if ui.current_state == ui.UIState.SETTINGS_VIEW:
			switch_display(ShowStat.BACK_BTN)
	)
	eb.page_left.connect(func ():
		if ui.current_state == ui.UIState.SETTINGS_VIEW:
			switch_display(ShowStat.ARROW_RIGHT)
	)

## 后备点击处理：Button 旋转后部分可见图标落在 Button 本地 rect 外，
## 此处捕获 RB_Btn 整个 rect 内的左键点击，确保图标可点。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_on_button_pressed()
		accept_event()

func _on_state_change(_old_state, new_state: UIStateManager.UIState):
	if new_state in [ui.UIState.ALBUM_VIEW, ui.UIState.SONG_VIEW]:
		switch_display(ShowStat.STORE_BTN)
	elif new_state in [ui.UIState.PLAY_VIEW]:
		switch_display(ShowStat.NONE)
	else:
		switch_display(ShowStat.BACK_BTN)

var _current_stat: ShowStat = ShowStat.STORE_BTN

## 读取当前显示状态（外部只读统一走此方法，避免跨类直读私有字段，TMX-019）
func get_current_stat() -> ShowStat:
	return _current_stat

var _visible: bool = true

# 文本输入时禁用快捷键，避免字母键触发跳转（由 LeftTopBtn 统一驱动）
var _saved_shortcut: Shortcut = null

## 按钮点击的覆盖回调：设置后点击按钮优先调用此回调，用于外部接管（如 PlayerInfo 展开时）
var pressed_override: Callable = Callable()

## 禁用/恢复自身快捷键（禁用时移除 shortcut，恢复时还原）
func _set_shortcut_enabled(enabled: bool) -> void:
	if enabled:
		if _saved_shortcut:
			btn.shortcut = _saved_shortcut
			_saved_shortcut = null
	else:
		if btn.shortcut:
			_saved_shortcut = btn.shortcut
			btn.shortcut = null

func switch_display(content_to_show: ShowStat = ShowStat.NONE):
	if content_to_show == _current_stat:
		return

	# 控制按钮框架是否可见
	if content_to_show == ShowStat.NONE:
		if _visible:
			ani.animate_offset_to(self, Vector2(500, 134), 0.5, "RB_VISBLE")
			_visible = false
	else:
		if not _visible:
			ani.animate_offset_back(self, 0.5, "RB_VISBLE")
			_visible = true

	var event = InputEventKey.new()
	# 控制内容显示
	match content_to_show:
		ShowStat.BACK_BTN:
			ani.animate_offset_to(vboxc, Vector2(0, -430))
			event.keycode = KEY_ESCAPE
		ShowStat.STORE_BTN:
			ani.animate_offset_to(vboxc, Vector2(0, 0))
			event.keycode = KEY_O
		ShowStat.ARROW_RIGHT:
			ani.animate_offset_to(vboxc, Vector2(0, -860))
			event.keycode = KEY_RIGHT
	
	# 快捷键：shortcut 被禁用时更新到 _saved_shortcut，恢复后即生效
	var target := btn.shortcut if btn.shortcut else _saved_shortcut
	if target:
		if target.events.is_empty():
			target.events = [event]
		else:
			target.events[0] = event
	_current_stat = content_to_show

func _on_button_pressed() -> void:
	if pressed_override.is_valid():
		pressed_override.call()
		return
	match _current_stat:
		ShowStat.BACK_BTN:
			UiStatMGR.go_back()
		ShowStat.STORE_BTN:
			UiStatMGR.change_state(UiStatMGR.UIState.STORE_VIEW)
		ShowStat.ARROW_RIGHT:
			eb.page_right.emit()
