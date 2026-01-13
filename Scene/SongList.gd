extends ScrollContainer
var initial=0
var index=0

signal storeButtonSwitch(showBackButton:bool)

#指示当前是否有拖拽操作
var is_dragging := false
#当鼠标开始拖拽至松手前，计算列表滚动值的
var drag_pos1=0;
var drag_pos2=0;
#开始拖拽时的列表滚动值
var start_scroll_v_pos=0

func _process(_delta: float):
	if Global.UI!=1:
		return
	
	if initial==0:
		var button_group=ButtonGroup.new()
		var temp=get_node("/root/Main/Album/AlbumList/VBox").get_child(Global.album).get_meta("sourceAlbumName")
		Global.sourceAlbumName=temp;
		print("Select Album: ",temp)
		index=0
		for i in Global.data[temp]:
			var song=load("res://Scene/songNode.tscn").instantiate()
			song.set_meta("index",index)
			song.set_meta("sourceSongName",i)
			song.set_meta("midiCount",Global.data[temp][i].size())
			song.get_node("PC/CountBase/SongCount").text="%d"%song.get_meta("midiCount")
			index+=1
			
			var SongName=song.get_node("PC/Shader/SongName")
			SongName.text=i
			if SongName.text=="":
				SongName.text="Unknow"
			
			var button=song.get_node("PC/Shader/SongButton")
			button.button_group = button_group
			button.toggled.connect(_on_button_toggled.bind(button))
			get_child(0).add_child(song);
		initial=1
			
	#图片移动
	for cover in get_child(0).get_children():
		cover=cover.get_node("PC/Shader/cover")
		cover.position.y=250-((1.0*cover.get_parent().get_parent().get_parent().get_meta("index")/index)*800)

func back():
	Global.switch(10)

#按钮组
func _on_button_toggled(toggled_on: bool, button):
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_SINE);
	tween.set_parallel(true)
	
	var songNode=button.get_parent().get_parent().get_parent()
	if toggled_on:
		print(Global.song)
		if Global.song==songNode.get_meta("index"):
			Global.sourceSongName=songNode.get_meta("sourceSongName");
			print("Select Song: ",songNode.get_meta("sourceSongName"))
			Global.switch(12)
			
		tween.tween_property(songNode,"scale",Vector2(1.05,1.05),0.1)
		Global.song=songNode.get_meta("index")
	else:
		tween.tween_property(songNode,"scale",Vector2(1,1),0.25)
func _update_polygon(np:Vector2,i,polygon):
	polygon.polygon[i]=np;

func _on_scrolling():
	# 用户正在滚动时标记为拖拽中
	is_dragging = true
	start_scroll_v_pos=scroll_vertical;


func _input(event):
	if Global.UI!=1:
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
				scroll_vertical=-drag_pos2*1.5+start_scroll_v_pos
