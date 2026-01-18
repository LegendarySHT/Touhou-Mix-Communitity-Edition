## MIDI视图
## 显示选中歌曲下的所有MIDI谱面列表
extends BaseScrollList

class_name MidiView

## 当前显示的MIDI列表
var current_midis: Array[MidiData] = []

var snaping = null # 当前的展开的节点
var last_selection = null # 上一次选中的节点

## 管理器引用
@onready var data_manager: DataManager = DataManager.instance
@onready var event_bus: EventBus = EventBus.instance
@onready var state_manager = UIStateManager.instance

# 路径
var INDICATOR = "/root/Main/InfoUI/Right/Right/Indicator"

var scroll: GeneralScroll = GeneralScroll.new(self)

func _ready() -> void:
	super._ready()
	
	# 获取管理器引用
	if not data_manager or not event_bus:
		push_error("MidiView: Missing manager instances")
		return
	
	# 连接事件
	event_bus.song_selected.connect(_load_midis)

## 加载指定歌曲的MIDI谱面
func _load_midis(song_id: String) -> void:
	if not data_manager:
		return

	current_midis = data_manager.get_midis_by_song(song_id)
	if current_midis:
		_refresh_display()

## 刷新显示
func _refresh_display() -> void:
	# 清空现有项
	_clear_list()
	
	# 添加新项
	var counter = 0
	var bg = load("res://Resources/ButtonGroup/MidiButton.tres")
	var point = load("res://Scene/indicator_point.tscn")
	for midi in current_midis:
		var item = create_and_add_item(midi.id, "midi")
		if item:
			# 添加指示器点
			var indicator = get_node(INDICATOR)
			indicator.add_child(point.instantiate())

			item.setup_with_midi(self, midi, counter, bg)
			container.add_child(item)
			if counter==0:
				item.get_node("Button").button_pressed = true
			counter += 1


	# container.get_child(0).get_node("Button").button_pressed = true
	print("加载了%d个MIDI谱面" % counter)

func _on_button_toggled(toggled_on: bool, midiNode, midi_id: String):
	pass

## 清空列表
func _clear_list() -> void:
	if container == null:
		return
	
	for item in container.get_children():
		item.queue_free()
	
	list_items.clear()
	
	# 清空指示器
	var indicator = get_node(INDICATOR)
	if indicator:
		for child in indicator.get_children():
			child.queue_free()
	
	snaping = null
	print("清空了MIDI谱面列表")

## 列表项选中回调
func _on_item_selected(item_id: String) -> void:
	if event_bus:
		# 查找对应的MIDI
		for midi in current_midis:
			if midi.id == item_id:
				event_bus.emit_midi_selected(item_id, midi)
				break

## 列表项悬停回调
func _on_item_hovered(item_id: String) -> void:
	pass

## 列表项取消悬停回调
func _on_item_unhovered() -> void:
	pass

func _input(event):
	if state_manager.current_state != state_manager.UIState.MIDI_VIEW or snaping:
		if snaping and not snaping.get_node("Button").button_pressed:
			_show_midi_list()
		return
	else:
		scroll.input(event)

func _process(_delta):
	if state_manager.current_state != state_manager.UIState.MIDI_VIEW:
		return
	
	scroll.process(_delta)

	# 吸附
	if snaping != null and abs(snaping.position.y - scroll_vertical + 15) > 7:
		scroll_vertical += (snaping.position.y - scroll_vertical + 15) / 6
		if not snaping.get_node("Button").button_pressed:
			_show_midi_list()

# 吸附
func _snap(midi_node):
	if snaping == midi_node and snaping != last_selection:
		_show_midi_list()
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
		container.get_child(snaping.get_meta("index")).get_node("Button").button_pressed = false
		
		var Tindex = (snaping.get_meta("index") - 1) % current_midis.size()
		container.get_child(Tindex).get_node("Button").button_pressed = true

func _next() -> void:
	if last_selection:
		_show_midi_list()

	if snaping:
		container.get_child(snaping.get_meta("index")).get_node("Button").button_pressed = false
		
		var Tindex = (snaping.get_meta("index") + 1) % current_midis.size()
		container.get_child(Tindex).get_node("Button").button_pressed = true
