extends BaseScrollList

class_name StoreView

func _ready() -> void:
	work_state = UIStateManager.UIState.STORE_VIEW

	super._ready()

	# 一页36个项
	for i in range(36):
		create_and_add_item("%d" % i, "StoreMidiItem")
	
	# 连接状态改变信号
	await EventBus.instance.data_loaded_complete
	var test_midis:Array[MidiData] = DataManager.instance.get_all_midis()
	# 临时填充五个
	for i in range(5):
		container.get_child(i).set_display(test_midis[i])

func _process(delta: float) -> void:
	super._process(delta)

func _input(event: InputEvent) -> void:
	super._gui_input(event)

# 歌曲选中
func on_midi_select(midi: MidiData):
	print("select %s" % midi.name)
