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

@onready var ani: AnimationManager = AniMGR
@onready var ui: UIStateManager = UiStatMGR
@onready var eb: EventBus = EvtBus

@onready var vboxc: VBoxContainer = $VBoxC
@onready var arrow: TextureRect = $VBoxC/C2/Arrow
@onready var btn: Button = $Button
@onready var lag_label: Label = $Lag

func _ready() -> void:
	instance = self
	ui.state_changed.connect(_on_state_change)

	# 右下角按钮点击事件
	eb.page_right.connect(switch_display.bind(ShowStat.ARROW_LEFT))

	# 在线状态显示
	eb.online_state_changed.connect(_on_online_state_changed)
	_update_lag_display()


## 在线状态变化回调：更新 Lag 标签显示
func _on_online_state_changed(state: int, latency_ms: int) -> void:
	_update_lag_display(state, latency_ms)


## 根据 NetManager 连接状态更新 Lag 显示
## state == -1 时从 NetManager 读取当前状态（初始化时使用）
func _update_lag_display(state: int = -1, latency_ms: int = -1) -> void:
	if state == -1:
		# 初始化时从 NetManager 读取当前状态
		if NetManager.instance != null:
			state = NetManager.instance.connect_state
			latency_ms = NetManager.instance._latency_ms
		else:
			state = NetManager.ConnectState.OFFLINE_MODE
	match state:
		NetManager.ConnectState.OFFLINE_MODE:
			lag_label.visible = false
		NetManager.ConnectState.CONNECTING:
			lag_label.visible = true
			lag_label.text = "正在\n连接"
		NetManager.ConnectState.ONLINE:
			lag_label.visible = true
			lag_label.text = "%d\nms" % latency_ms
		NetManager.ConnectState.FAILED:
			lag_label.visible = true
			lag_label.text = "连接\n失败"

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

# 文本输入时禁用快捷键，避免字母键触发跳转
var _saved_shortcut: Shortcut = null
var _shortcuts_blocked: bool = false

## 根据焦点控件状态，禁用/恢复 LeftTopBtn 与 RightBottomBtn 的快捷键
## 当 LineEdit/TextEdit 获得焦点时禁用，避免输入字符时触发快捷按钮跳转
func _process(_delta: float) -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	var should_block := focus_owner is LineEdit or focus_owner is TextEdit
	if should_block == _shortcuts_blocked:
		return
	_shortcuts_blocked = should_block
	_set_shortcut_enabled(not should_block)
	if RB_Btn.instance:
		RB_Btn.instance._set_shortcut_enabled(not should_block)

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

func switch_display(content_to_show: ShowStat = ShowStat.SETTING_BTN):
	if content_to_show == _current_stat:
		return

	# 控制按钮框架是否可见
	if content_to_show == ShowStat.NONE:
		if _visible:
			ani.animate_offset_to(self, Vector2(-500, -134), 0.5, "LT_VISBLE")
	else:
		if not _visible:
			ani.animate_offset_back(self, 0.5, "LT_VISBLE")
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

	# 快捷键：shortcut 被禁用时更新到 _saved_shortcut，恢复后即生效
	var target := btn.shortcut if btn.shortcut else _saved_shortcut
	if target:
		if target.events.is_empty():
			target.events = [event]
		else:
			target.events[0] = event
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
