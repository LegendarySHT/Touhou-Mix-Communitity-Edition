extends ColorRect
var ShowBackButton=false

signal  switch_to_store

var RIGHTBOTTOM="/root/Main/RightBottom/Store_Button"
@onready var animation_manager:AnimationManager = AniMGR.instance
@onready var event_bus:EventBus = EvtBus.instance

func _ready():
	event_bus.storeButtonSwitch.connect(_animate_switch_btn)

func _animate_switch_btn(showBackButton: bool):
	ShowBackButton = showBackButton
	var expa = 1 if showBackButton else 0
	var rb = get_node(RIGHTBOTTOM)

	animation_manager.animate_position(rb.get_node("Store"), Vector2(12, 410 +550*expa), 0.25, "SBP1")
	animation_manager.animate_position(rb.get_node("Back"), Vector2(12, -50 +450*expa), 0.25, "SBP2")

func _on_button_pressed() -> void:
	if ShowBackButton:
		event_bus.storeButtonSwitch.emit(false)
		if UiStatMGR.current_state == UiStatMGR.UIState.SORTED_VIEW:
			UiStatMGR.change_state(UiStatMGR.previous_state)
		else:
			UiStatMGR.change_state(UiStatMGR.UIState.SONG_VIEW)
	else:
		switch_to_store.emit()
