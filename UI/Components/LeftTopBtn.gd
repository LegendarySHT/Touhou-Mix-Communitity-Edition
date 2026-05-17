extends Panel

class_name LT_Btn

static var instance:LT_Btn

enum ShowStat {
	NONE = 0,
	SETTING_BTN,
	ARROW_LEFT,
	ARROW_RIGHT,
	RETRY_BTN
}

@onready var ani: AnimationManager = AniMGR.instance
@onready var ui: UIStateManager = UIStateManager.instance
@onready var eb: EventBus = EventBus.instance

@onready var vboxc: VBoxContainer = $VBoxC
@onready var arrow: TextureRect = $VBoxC/C2/Arrow
@onready var btn: Button = $Button

func _ready() -> void:
	instance = self
	ui.state_changed.connect(_on_state_change)

	# 右下角按钮点击事件
	eb.page_right.connect(switch_display.bind(ShowStat.ARROW_LEFT))

func _on_state_change(_old_state, new_state: UIStateManager.UIState):
	if new_state in [ui.UIState.SETTINGS_VIEW]:
		switch_display(ShowStat.ARROW_LEFT)
	elif new_state in [ui.UIState.STORE_VIEW, ui.UIState.PLAY_VIEW]:
		switch_display(ShowStat.NONE)
	elif new_state in [ui.UIState.SCORE_VIEW]:
		switch_display(ShowStat.RETRY_BTN)
	else:
		switch_display(ShowStat.SETTING_BTN)

var _current_stat: ShowStat = ShowStat.SETTING_BTN
var _visible: bool = true
var _arrow_left: bool = false
var _rot_tween: Tween = null
func switch_display(content_to_show: ShowStat = ShowStat.SETTING_BTN):
	if content_to_show == _current_stat:
		return

	# 控制按钮框架是否可见
	if content_to_show == ShowStat.NONE:
		if _visible:
			ani.animate_position(self, position + Vector2(-500, -134), 0.5, "LT_VISBLE")
	else:
		if not _visible:
			ani.animate_position(self, position - Vector2(-500, -134), 0.5, "LT_VISBLE")
	_visible = content_to_show != ShowStat.NONE
	
	if _rot_tween:
		await _rot_tween.finished

	var event = InputEventKey.new()
	# 控制内容显示
	match content_to_show:
		ShowStat.RETRY_BTN:
			ani.animate_position(vboxc, Vector2(vboxc.position.x, 55), 0.35, "LT_ICON")
			event.keycode = KEY_R
		ShowStat.SETTING_BTN:
			ani.animate_position(vboxc, Vector2(vboxc.position.x, -390), 0.35, "LT_ICON")
			event.keycode = KEY_U
		ShowStat.ARROW_RIGHT:
			ani.animate_position(vboxc, Vector2(vboxc.position.x, -835), 0.35, "LT_ICON")
			if _arrow_left:
				_rot_tween = ani.animate_rotation(arrow, arrow.rotation + PI, 0.2, "LT_ARROW_ROT")
				_arrow_left = false
			event.keycode = KEY_E
		ShowStat.ARROW_LEFT:
			ani.animate_position(vboxc, Vector2(vboxc.position.x, -835), 0.35, "LT_ICON")
			if not _arrow_left:
				_rot_tween = ani.animate_rotation(arrow, arrow.rotation + PI, 0.2, "LT_ARROW_ROT")
				_arrow_left = true
			event.keycode = KEY_Q
	
	if _rot_tween:
		_rot_tween.finished.connect(func ():
			_rot_tween = null
		)

	# 快捷键
	btn.shortcut.events[0] = event
	_current_stat = content_to_show

func _on_button_pressed() -> void:
	match ui.current_state:
		ui.UIState.SETTINGS_VIEW:
			var rb: RB_Btn = RB_Btn.instance
			if _arrow_left:
				rb.switch_display(rb.ShowStat.ARROW_RIGHT)
				switch_display(ShowStat.ARROW_RIGHT)
				eb.page_left.emit()
			else:
				rb.switch_display(rb.ShowStat.BACK_BTN)
				switch_display(ShowStat.ARROW_LEFT)
				eb.page_right.emit()
		ui.UIState.SCORE_VIEW:
			ui.change_state(ui.UIState.PLAY_VIEW, false)
			#await get_tree().create_timer(0.3).timeout
			get_node("/root/Main/PlayView").retry_btn.pressed.emit()
		_:
			ui.change_state(ui.UIState.SETTINGS_VIEW)
