extends VBoxContainer
var need_initial=1
var counter =0

var snaping=null
var last_selection=null

#指示当前是否有拖拽操作
var is_dragging := false
#当鼠标开始拖拽至松手前，计算列表滚动值的
var drag_pos1=0;
var drag_pos2=0;
#开始拖拽时的列表滚动值
var start_scroll_v_pos=0


func _on_scrolling():
	# 用户正在滚动时标记为拖拽中
	is_dragging = true
	start_scroll_v_pos=get_parent().scroll_vertical;

#路径
var INDICATOR="/root/Main/InfoUI/Right/Right/Indicator"

func _input(event):
	if Global.UI!=2 or snaping:
		return
	# 检测鼠标释放或触摸结束
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			#停止拖拽
			if not event.pressed:
				is_dragging = false
			#开始拖拽
			else:
				_on_scrolling()
				drag_pos1=event.global_position.y;
				drag_pos2=drag_pos1
	#左键拖拽
	elif event is InputEventMouseMotion:
		if  is_dragging:
			drag_pos2=event.global_position.y-drag_pos1;
			if drag_pos2!=0:
				get_parent().scroll_vertical=-drag_pos2*1.5+start_scroll_v_pos


func _ready():
	if not get_node("/root/Main/SS/SS/InfoUI/MainButton"):
		pass

func _process(_delta):
	if need_initial and Global.UI==2:
		#读取midi
		#var album_list=get_node("/root/Main/album_list2")
		#var song_list=get_node("/root/Main/song_list")
		var InfoUI=get_node("/root/Main/InfoUI")
		var midi_list=InfoUI.get_node("MidiWindow/SC/VBOX")
		var temp
		
		var bg=load("res://ButtonGroup/MidiButton.tres")
		if Global.Sort==0:
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
		else:
			for i in get_node("/root/Main/SortedMidi/List/VBox").get_children():
				#初始化页面指示器
				var indicator=get_node(INDICATOR)
				var point=load("res://Scene/indicator_point.tscn").instantiate()
				indicator.add_child(point)
				
				temp=load("res://Scene/midi_node.tscn").instantiate()
				
				temp.set_meta("status",i.get_meta("status"))
				temp.set_meta("artistName",i.get_meta("artistName"))
				temp.set_meta("trialCount",i.get_meta("trialCount"))
				temp.set_meta("upCount",i.get_meta("upCount"))
				
				temp.set_meta("avgAccuracy",i.get_meta("avgAccuracy"))
				temp.set_meta("name",i.get_meta("name"))
				temp.set_meta("desc",i.get_meta("desc"))
				temp.set_meta("id",i.get_meta("id"))
				temp.set_meta("hash",i.get_meta("hash"))
				temp.set_meta("index",counter)
				counter+=1
				
				temp.snap_target.connect(_snap)
				temp.get_node("Button").button_group=bg
				midi_list.add_child(temp)
				
				if i.get_meta("id")==Global.select_midi:
					temp.get_node("Button").button_pressed=true
				if need_initial:
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
	print("Prev")
	var Tindex #TargetIndex
	if snaping:
		Tindex=snaping.get_meta("index")-1
	elif last_selection:
		Tindex=last_selection.get_meta("index")-1
	if snaping or last_selection:
		if Tindex<0:
			Tindex=counter-1
		get_child(Tindex).get_node("Button").button_pressed=true
		


func _next() -> void:
	print("Next")
	var Tindex
	if snaping:
		Tindex=snaping.get_meta("index")+1
	elif last_selection:
		Tindex=last_selection.get_meta("index")+1
	if snaping or last_selection:
		if Tindex>counter-1:
			Tindex=0
		get_child(Tindex).get_node("Button").button_pressed=true
		
