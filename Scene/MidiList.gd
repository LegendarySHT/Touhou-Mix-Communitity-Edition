extends VBoxContainer
var need_initial=1
var counter =0

var snaping=null #当前的展开的节点
var last_selection=null #上一次选中的节点

#指示当前是否有拖拽操作
var is_dragging := false
#当鼠标开始拖拽至松手前，计算列表滚动值的
var drag_pos1=0;
var drag_detla=0;
#开始拖拽时的列表滚动值
var start_scroll_v_pos=0

# 这个玩意没在工作
func _on_scrolling():
	pass

#路径
var INDICATOR="/root/Main/InfoUI/Right/Right/Indicator"

# 这个玩意也没正常工作
func _input(event):
	if Global.UI!=2 or snaping:
		if snaping and not snaping.get_node("Button").button_pressed:
			_show_midi_list()
		return

	# 检测鼠标释放或触摸结束
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			#停止拖拽
			if not event.pressed:
				is_dragging = false
			#开始拖拽
			else:
				is_dragging = true
				start_scroll_v_pos=get_parent().scroll_vertical;
				drag_pos1=event.global_position.y;
	#左键拖拽
	elif event is InputEventMouseMotion:
		if  is_dragging:
			drag_detla=event.global_position.y-drag_pos1;
			if drag_detla!=0:
				get_parent().scroll_vertical=-drag_detla*1.5+start_scroll_v_pos


func _ready():
	if not get_node("/root/Main/SS/SS/InfoUI/MainButton"):
		pass

func _process(_delta):
	if need_initial and Global.UI==2:
		#读取midi
		var InfoUI=get_node("/root/Main/InfoUI")
		var midi_list=InfoUI.get_node("MidiWindow/SC/VBOX")
		var temp
		
		var bg=load("res://ButtonGroup/MidiButton.tres")
		var data=Global.data[Global.sourceAlbumName][Global.sourceSongName]
		for i in data.keys():
			#初始化页面指示器
			var indicator=get_node(INDICATOR)
			var point=load("res://Scene/indicator_point.tscn").instantiate()
			indicator.add_child(point)
			
			temp=load("res://Scene/midi_node.tscn").instantiate()
			
			var dic=data[i]
			
			temp.set_meta("status",dic["status"])
			temp.set_meta("artistName",dic["artistName"])
			temp.set_meta("trialCount",dic["trialCount"])
			temp.set_meta("upCount",dic["upCount"])
			
			temp.set_meta("avgAccuracy",dic["avgAccuracy"])
			temp.set_meta("name",dic["name"])
			temp.set_meta("desc",dic["desc"])
			temp.set_meta("id",dic["_id"])
			temp.set_meta("hash",dic["hash"])
			temp.set_meta("index",counter)
			counter+=1
			
			temp.snap_target.connect(_snap)
			temp.get_node("Button").button_group=bg
			midi_list.add_child(temp)
			if need_initial:
				get_child(0).get_node("Button").button_pressed=true
				need_initial=0;
			
	elif need_initial==0 and Global.UI!=2:
		is_dragging=false
		need_initial=1;
		counter=0
		for i in get_children():
			i.queue_free()
		for i in get_node(INDICATOR).get_children():
			i.queue_free()
	
	#吸附
	if snaping!=null and abs(snaping.position.y-get_parent().scroll_vertical+15)>7:
		get_parent().scroll_vertical+=(snaping.position.y-get_parent().scroll_vertical+15)/6
		if not snaping.get_node("Button").button_pressed:
			_show_midi_list()

func _snap(midi_node):
	snaping=midi_node

func _show_midi_list() -> void:
	if snaping!=null:
		snaping.get_node("Button").button_pressed=false
		last_selection=snaping
		snaping=null
	elif last_selection!=null:
		snaping=last_selection
		snaping.get_node("Button").button_pressed=true
		last_selection=null


func _previous() -> void:
	if last_selection:
		_show_midi_list()

	# 收起上一个展开的节点
	get_child(snaping.get_meta("index")).get_node("Button").button_pressed=false
	
	var Tindex # 目标索引
	Tindex=(snaping.get_meta("index")-1) % counter
	get_child(Tindex).get_node("Button").button_pressed=true

func _next() -> void:
	if last_selection:
		_show_midi_list()

	get_child(snaping.get_meta("index")).get_node("Button").button_pressed=false

	var Tindex
	Tindex=(snaping.get_meta("index")+1) % counter
	get_child(Tindex).get_node("Button").button_pressed=true
