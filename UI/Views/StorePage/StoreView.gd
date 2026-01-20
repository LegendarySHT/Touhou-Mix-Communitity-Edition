extends BaseScrollList

class_name StoreView

@onready var state_manager: UIStateManager = UIStateManager.instance

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	if state_manager.current_state != state_manager.UIState.STORE_VIEW:
		return
	super._process(delta)

func _input(event: InputEvent) -> void:
	if state_manager.current_state != state_manager.UIState.STORE_VIEW:
		return
	super._input(event)
