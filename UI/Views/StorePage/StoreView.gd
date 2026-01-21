extends BaseScrollList

class_name StoreView

@onready var state_manager: UIStateManager = UIStateManager.instance

func _ready() -> void:
	work_state = UIStateManager.UIState.STORE_VIEW

	super._ready()

	# 连接状态改变信号
	EventBus.instance.data_loaded_complete.connect(_on_data_loaded)

func _on_data_loaded() -> void:
	var midi:Array[MidiData] = DataManager.instance.get_all_midis()
	for i in range(5):
		container.get_child(i).set_display(midi[i])
# func _process(delta: float) -> void:
# 	super._process(delta)

# func _input(event: InputEvent) -> void:
# 	super._input(event)
