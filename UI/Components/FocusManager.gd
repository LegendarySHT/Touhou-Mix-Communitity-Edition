extends Control

class_name FocusManager

@onready var ui: UIStateManager = UiStatMGR
@onready var ani: AnimationManager = AniMGR

var _last_input_was_keyboard := false

func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_change)
	ani.scene_transition_fin.connect(_on_state_enter)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_last_input_was_keyboard = true
	elif event is InputEventMouseButton and event.pressed:
		_last_input_was_keyboard = false

func _on_focus_change(_node: Control):
	# print("[FocusMGR] Focus changed to: %s" % node.name)
	return

func _on_state_enter():
	# 移动端（Android/iOS）使用触屏操作，不需要键盘焦点导航
	var is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")

	match ui.current_state:
		ui.UIState.ALBUM_VIEW, ui.UIState.SONG_VIEW, ui.UIState.SORTED_VIEW:
			var nd = get_node(ani.ui_path_map[ani.ui_path_map.keys()[ui.current_state]])
			if nd.selected_item == -1:
				nd.select_item(0)
				var selected_node = nd.get_selected_node()
				if selected_node == null:
					return
				selected_node.button.grab_focus()
		ui.UIState.SETTINGS_VIEW:
			if not is_mobile:
				get_node("/root/Main/skew/C/SettingView").short_cut_btn.grab_focus()
		ui.UIState.STORE_VIEW:
			var first_btn: Button = get_node("/root/Main/Store/StoreMidiList").get_child(0).get_child(0).button
			if _last_input_was_keyboard:
				first_btn.grab_focus()

# func _input(event: InputEvent) -> void:
# 	if ui.current_state in [ui.UIState.ALBUM_VIEW, ui.UIState.SONG_VIEW, ui.UIState.SORTED_VIEW]:
# 		if event is InputEventKey and event.pressed:
# 			if event.keycode in [KEY_TAB]:
# 				get_node("/root/Main/skew/C/ShortCutMenu/Btns/Search").grab_focus()
# 				accept_event()
