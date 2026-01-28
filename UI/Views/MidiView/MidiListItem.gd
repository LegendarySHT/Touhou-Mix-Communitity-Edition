## MIDI列表项组件
## 继承自 ListItemBase，显示MIDI谱面信息
extends ListItemBase

## 引用节点
@onready var status_label: Label = $VBoxC/HBoxC/status
@onready var midi_name_label: Label = $VBoxC/MidiName
@onready var author_label: Label = $VBoxC/HBoxC/Author
@onready var line: Line2D = $VBoxC/Line2D
@onready var cover: TextureRect = $cover

## MIDI数据
var midi_data: MidiData

## 展开动画补间
var expand_tween: Tween

## 吸附目标信号（用于滚动吸附）
signal snap_node_target(midi_node_index)

var INDICATOR = "/root/Main/InfoUI/Base/LeftArea/InfoWindow/HBoxC/Right/Center/Indicator"

func _update_display() -> void:
	# 初始化显示
	if not status_label:
		status_label = get_node("VBoxC/HBoxC/status")
	if not midi_name_label:
		midi_name_label = get_node("VBoxC/MidiName")
	if not author_label:
		author_label = get_node("VBoxC/HBoxC/Author")
	status_label.text = midi_data.status
	midi_name_label.text = midi_data.name
	author_label.text = midi_data.artist_name if not midi_data.artist_name.is_empty() else "Unknown"

## 从MidiData初始化显示
func setup_with_midi(parent: MidiView, midi: MidiData, index: int, bg:ButtonGroup) -> void:
	midi_data = midi
	item_id = midi.id
	item_type = "midi"
	item_index = index

	button = get_node("Button")
	button.button_group = bg

	init_btn(button, parent)

	_update_display()
	_load_cover_image()
	
	# 信号
	snap_node_target.connect(
		func(midi_node_index) -> void:
			parent.selected_item = midi_node_index
	)
	btn_confirmed.connect(parent._show_midi_list)

	# if index == 0:
	# 	button.button_pressed = true

## 加载封面图片
func _load_cover_image() -> void:
	if not cover:
		cover = get_node_or_null("cover")
	
	if not cover:
		print("[MidiListItem] Cover node not found!")
		return
	
	# 从 FileSystemManager 获取封面路径
	var fs_manager = FileSystemManager.instance
	if not fs_manager:
		print("[MidiListItem] FileSystemManager not found, using default cover")
		return
	cover.texture = fs_manager.get_cover_by_midiData(midi_data)	

## 按钮切换回调
func _on_button_toggled(toggled_on: bool):
	var tween =create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_parallel(true)
	
	print ("indx : %d state : %s" % [item_index,toggled_on])

	var indicator=get_node(INDICATOR)
	var expa = 1 if toggled_on else 0
	tween.tween_property(self,"custom_minimum_size",Vector2(750,150 + 240*expa),0.5)
	tween.tween_property(get_node("VBoxC/MC"),"theme_override_constants/margin_bottom",20 * expa, 0.15)
	#文字
	tween.tween_property(midi_name_label,"theme_override_font_sizes/font_size",30 +10*expa,0.25)
	tween.tween_property(line,"position",Vector2(-50,12 - 5*expa),0.15)
	#指示器
	tween.tween_property(indicator.get_child(item_index),"color",Color(0.129, 0.412, 0.702) if expa else Color(1, 1, 1) ,0.15)
	tween.tween_property(indicator,"position",Vector2(30,100 -item_index*24),0.35)
	
	if toggled_on:
		snap_node_target.emit(item_index)
		_update_data_display()

## 更新信息面板
func _update_data_display() -> void:
	var info_node = get_node_or_null("/root/Main/InfoUI/Base/LeftArea/DetailData")
	if not info_node:
		print("Info node not found!")
		return
	
	# info_node.get_node("Time/Label")
	# info_node.get_node("BPM/Label")
	# info_node.get_node("Note/Label")
	# info_node.get_node("MPP/Label") # note per minute

	info_node.get_node("Play/Label").text = "%d" % midi_data.trial_count
	info_node.get_node("UpCount/Label").text = "%d" % midi_data.up_count
	info_node.get_node("AvgAcc/Label").text = "%.2f" % midi_data.avg_accuracy
	# info_node.get_node("AvgPP/Label") 这个没用上
