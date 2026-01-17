extends VBoxContainer
var need_initial = 1
var counter = 0

var snaping = null # 当前的展开的节点
var last_selection = null # 上一次选中的节点

# 管理器引用
@onready var data_manager = DataManager.instance
@onready var state_manager = UIStateManager.instance
@onready var event_bus = EventBus.instance

# 指示当前是否有拖拽操作
var is_dragging := false
# 当鼠标开始拖拽至松手前，计算列表滚动值的
var drag_pos1 = 0
var drag_detla = 0
# 开始拖拽时的列表滚动值
var start_scroll_v_pos = 0

# 路径
var INDICATOR = "/root/Main/InfoUI/Right/Right/Indicator"

# 这个玩意也没正常工作
func _input(event):
	if state_manager.current_state != state_manager.UIState.MIDI_VIEW or snaping:
		if snaping and not snaping.get_node("Button").button_pressed:
			_show_midi_list()
		return

	# 检测鼠标释放或触摸结束
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# 停止拖拽
			if not event.pressed:
				is_dragging = false
			# 开始拖拽
			else:
				is_dragging = true
				start_scroll_v_pos = get_parent().scroll_vertical
				drag_pos1 = event.global_position.y
	# 左键拖拽
	elif event is InputEventMouseMotion:
		if is_dragging:
			drag_detla = event.global_position.y - drag_pos1
			if drag_detla != 0:
				get_parent().scroll_vertical = -drag_detla * 1.5 + start_scroll_v_pos

func _ready():
	if event_bus:
		event_bus.song_selected.connect(_on_song_selected)

func _process(_delta):
	if need_initial and state_manager.current_state == state_manager.UIState.MIDI_VIEW:
		_load_midis()
	elif need_initial == 0 and state_manager.current_state != state_manager.UIState.MIDI_VIEW:
		is_dragging = false
		need_initial = 1
		counter = 0
		for i in get_children():
			i.queue_free()
		var indicator = get_node_or_null(INDICATOR)
		if indicator:
			for i in indicator.get_children():
				i.queue_free()
	
	# 吸附
	if snaping != null and abs(snaping.position.y - get_parent().scroll_vertical + 15) > 7:
		get_parent().scroll_vertical += (snaping.position.y - get_parent().scroll_vertical + 15) / 6
		if not snaping.get_node("Button").button_pressed:
			_show_midi_list()

func _load_midis():
	if not data_manager:
		print("MidiList: DataManager not available")
		return
	
	# 使用 DataManager 获取 MIDI
	var midis = data_manager.get_midis_by_song(Global.song_id)
	if midis.is_empty():
		print("MidiList: No MIDIs found for song ID:", Global.song_id)
		return
	
	# 清空现有节点
	for child in get_children():
		child.queue_free()
	
	var InfoUI = get_node("/root/Main/InfoUI")
	if not InfoUI:
		return
	
	var midi_list = InfoUI.get_node("MidiWindow/SC/VBOX")
	if not midi_list:
		return
	
	# 清空指示器
	var indicator = get_node(INDICATOR)
	if indicator:
		for child in indicator.get_children():
			child.queue_free()
	
	var bg = load("res://ButtonGroup/MidiButton.tres")
	counter = 0
	
	for midi_data in midis:
		# 初始化页面指示器
		if indicator:
			var point = load("res://Scene/indicator_point.tscn").instantiate()
			indicator.add_child(point)
		
		var temp = load("res://Scene/midi_node.tscn").instantiate()
		print(midi_data)
		# 从 MidiData 对象获取数据
		temp.set_meta("status", midi_data.status)
		temp.set_meta("artistName", midi_data.artist_name)
		temp.set_meta("trialCount", midi_data.trial_count)
		temp.set_meta("upCount", midi_data.up_count)
		temp.set_meta("avgAccuracy", midi_data.avg_accuracy)
		temp.set_meta("name", midi_data.name)
		temp.set_meta("desc", midi_data.description)
		temp.set_meta("id", midi_data.id)
		temp.set_meta("hash", midi_data.file_hash)
		temp.set_meta("index", counter)
		temp.set_meta("midi_data", midi_data)  # 存储整个对象以备后用
		
		counter += 1
		
		temp.snap_target.connect(_snap)
		temp.get_node("Button").button_group = bg
		midi_list.add_child(temp)
		
		# 设置节点文本显示
		_update_midi_node_display(temp, midi_data)
	
	if need_initial and counter > 0:
		get_child(0).get_node("Button").button_pressed = true
		need_initial = 0
	
	print("MidiList: Loaded", counter, "MIDIs for song:", Global.song_id)

func _update_midi_node_display(node, midi_data: MidiData):
	# 更新节点的文本显示
	var name_label = node.get_node("Title/Name") as Label
	var artist_label = node.get_node("Title/Artist") as Label
	var stats_label = node.get_node("Status/Stats") as Label
	
	if name_label:
		name_label.text = midi_data.name if midi_data.name else "Unknown"
	
	if artist_label:
		artist_label.text = "by " + (midi_data.artist_name if midi_data.artist_name else "Unknown")
	
	if stats_label:
		stats_label.text = "↑%d ⚡%d" % [midi_data.up_count, midi_data.trial_count]

func _snap(midi_node):
	snaping = midi_node

func _show_midi_list() -> void:
	if snaping != null:
		snaping.get_node("Button").button_pressed = false
		last_selection = snaping
		snaping = null
	elif last_selection != null:
		snaping = last_selection
		snaping.get_node("Button").button_pressed = true
		last_selection = null

func _previous() -> void:
	if last_selection:
		_show_midi_list()

	if snaping:
		# 收起上一个展开的节点
		get_child(snaping.get_meta("index")).get_node("Button").button_pressed = false
		
		var Tindex = (snaping.get_meta("index") - 1) % counter
		get_child(Tindex).get_node("Button").button_pressed = true

func _next() -> void:
	if last_selection:
		_show_midi_list()

	if snaping:
		get_child(snaping.get_meta("index")).get_node("Button").button_pressed = false
		
		var Tindex = (snaping.get_meta("index") + 1) % counter
		get_child(Tindex).get_node("Button").button_pressed = true

func _on_song_selected(song_id: String, song_data: SongData):
	Global.song_id = song_id
	need_initial = 1  # 重置初始化状态
