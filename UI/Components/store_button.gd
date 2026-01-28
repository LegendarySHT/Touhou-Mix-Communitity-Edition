extends Panel
var ShowBackButton=false

var RIGHTBOTTOM="/root/Main/RB_Btn"
@onready var animation_manager:AnimationManager = AniMGR.instance
@onready var event_bus:EventBus = EvtBus.instance

func _ready():
	event_bus.storeButtonSwitch.connect(_animate_switch_btn)
	_animate_switch_btn(ShowBackButton)

func _animate_switch_btn(showBackButton: bool):
	ShowBackButton = showBackButton
	var expa = 1 if showBackButton else 0
	var rb = get_node(RIGHTBOTTOM)

	animation_manager.animate_position(rb.get_node("Store"), Vector2(3, 430 +550*expa), 0.25, "SBP1")
	animation_manager.animate_position(rb.get_node("Back"), Vector2(3, -30 +450*expa), 0.25, "SBP2")

	# 设置快捷键
	var event = InputEventKey.new()
	if showBackButton:
		event.keycode = KEY_ESCAPE
	var btn = rb.get_node("Button")
	btn.shortcut.events[1] = event

func _on_button_pressed() -> void:
	if ShowBackButton:
		UiStatMGR.go_back()
	else:
		UiStatMGR.change_state(UiStatMGR.UIState.STORE_VIEW)
