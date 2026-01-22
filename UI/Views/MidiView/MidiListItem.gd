## MIDI列表项组件
## 继承自 ListItemBase，显示MIDI谱面信息
extends ListItemBase

## 引用节点
@onready var status_label: Label = $MC/MC/status if has_node("MC/MC/status") else null
@onready var midi_name_label: Label = $MC/VBox/MidiName if has_node("MC/VBox/MidiName") else null
@onready var author_label: Label = $MC/VBox/Author if has_node("MC/VBox/Author") else null
@onready var vbox: VBoxContainer = $MC/VBox if has_node("MC/VBox") else null
@onready var line: Line2D = $MC/VBox/Line2D if has_node("MC/VBox/Line2D") else null
@onready var margin_container: MarginContainer = $MC if has_node("MC") else null
@onready var cover: TextureRect = $cover if has_node("cover") else null

## MIDI数据
var midi_data: MidiData

## 展开动画补间
var expand_tween: Tween

## 吸附目标信号（用于滚动吸附）
signal snap_node_target(midi_node_index)

func _ready() -> void:
	if not button:
		button = get_node_or_null("Button")
		btn_toggled.connect(_on_button_toggled)
		init_btn(button)

func _update_display() -> void:
	# 初始化显示
	if not status_label:
		status_label = get_node("MC/MC/status")
	if not midi_name_label:
		midi_name_label = get_node("MC/VBox/MidiName")
	if not author_label:
		author_label = get_node("MC/VBox/Author")
	status_label.text = midi_data.status
	midi_name_label.text = midi_data.name
	author_label.text = midi_data.artist_name if not midi_data.artist_name.is_empty() else "Unknown"

## 从MidiData初始化显示
func setup_with_midi(parent: MidiView, midi: MidiData, index: int, bg:ButtonGroup) -> void:
	print("[MidiListItem] setup_with_midi called for: %s" % midi.name)
	midi_data = midi
	item_id = midi.id
	item_type = "midi"

	button = get_node("Button")
	button.button_group = bg
	button.set_meta("index", index)

	_update_display()
	_load_cover_image()
	
	# 信号
	snap_node_target.connect(parent._snap)

	if index == 0:
		button.button_pressed = true

	# 设置元数据（用于其他系统访问）
	set_meta("index", index)

## 加载封面图片
func _load_cover_image() -> void:
	print("[MidiListItem] _load_cover_image called")
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
	
	is_selected = toggled_on
	print ("indx : %d state : %s" % [get_meta("index"),toggled_on])

	var indicator=get_node("/root/Main/InfoUI/Right/Right/Indicator")
	var expa = 1 if toggled_on else 0
	tween.tween_property(self,"custom_minimum_size",Vector2(900,150 + 350*expa),0.5)
	tween.tween_property(get_node("MC"),"theme_override_constants/margin_bottom",10 +110*expa,0.15)
	#文字
	tween.tween_property(get_node("MC/VBox/MidiName"),"theme_override_font_sizes/font_size",30 +10*expa,0.25)
	tween.tween_property(get_node("MC/VBox"),"theme_override_constants/separation",15+15*expa,0.15)
	tween.tween_property(get_node("MC/VBox/Line2D"),"position",Vector2(-135,-10 +32*expa),0.15)
	#指示器
	tween.tween_property(indicator.get_child(get_meta("index")),"color",Color(0.129, 0.412, 0.702) if expa else Color(1, 1, 1) ,0.15)
	tween.tween_property(indicator,"position",Vector2(186.9,214-(get_meta("index")+1)*20-get_meta("index")*9),0.35)
	
	if toggled_on:
		snap_node_target.emit(get_meta("index"))
		_update_data_display()

## 更新信息面板
func _update_data_display() -> void:
	var info_node = get_node_or_null("/root/Main/InfoUI/Status/Panel/GC")
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
