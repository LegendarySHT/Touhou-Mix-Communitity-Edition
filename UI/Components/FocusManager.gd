extends Control

class_name FocusManager

@onready var ui: UIStateManager = UIStateManager.instance
@onready var ani: AnimationManager = AnimationManager.instance

func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_change)
	ani.scene_transition_fin.connect(_on_state_enter)

func _on_focus_change(_node: Control):
	# print("[FocusMGR] Focus changed to: %s" % node.name)
	return

func _on_state_enter():
	if ui.current_state in [ui.UIState.ALBUM_VIEW, ui.UIState.SONG_VIEW, ui.UIState.SORTED_VIEW]:
		var nd = get_node(ani.ui_path_map[ani.ui_path_map.keys()[ui.current_state]])
		if nd.selected_item == -1:
			nd.select_item(0)
			# nd.selected_item = 0
		nd.get_selected_node().button.grab_focus()



# func _input(event: InputEvent) -> void:
# 	if ui.current_state in [ui.UIState.ALBUM_VIEW, ui.UIState.SONG_VIEW, ui.UIState.SORTED_VIEW]:
# 		if event is InputEventKey and event.pressed:
# 			if event.keycode in [KEY_TAB]:
# 				get_node("/root/Main/skew/C/ShortCutMenu/Btns/Search").grab_focus()
# 				accept_event()
