# 这个文件已经废弃，如果没有使用，需要删除

extends ScrollContainer

#指示当前是否有拖拽操作
var is_dragging := false
#当鼠标开始拖拽至松手前，计算列表滚动值的
var drag_pos1=0;
var drag_pos2=0;
#开始拖拽时的列表滚动值
var start_scroll_v_pos=0

#滚动速度
var scroll_velocity=0

#计算释放前一刻鼠标垂直方向位移的
var release_delta1=0
var release_delta2=0

func _process(delta: float):
	if is_dragging:
		release_delta1=release_delta2;
		if release_delta2==release_delta1 and release_delta1 ==0:
			release_delta1=scroll_vertical
		release_delta2=scroll_vertical;
	else:
		if scroll_vertical<800:
			scroll_velocity = scroll_velocity*0.5;
		else:
			scroll_velocity = scroll_velocity*(1-0.9*delta);
		scroll_vertical=scroll_vertical+scroll_velocity*delta

func _on_scrolling():
	# 用户正在滚动时标记为拖拽中
	is_dragging = true
	start_scroll_v_pos=scroll_vertical;

#拖拽滚动条时清除松手速度
func _scrollbar_input(event):
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		scroll_velocity=0;

func _input(event):
	# 检测鼠标释放或触摸结束
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			#停止拖拽
			if not event.pressed:
				is_dragging = false
				#释放速度
				scroll_velocity=70*(release_delta2-release_delta1);
				if scroll_velocity>7000: scroll_velocity=6500; #速度上限
				if release_delta1 == release_delta2:
					return

				release_delta1=0
				release_delta2=0
			#开始拖拽
			else:
				_on_scrolling()
				drag_pos1=event.global_position.y;
				drag_pos2=drag_pos1
		#鼠标滚轮
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN or event.button_index==MOUSE_BUTTON_WHEEL_UP:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP:
				scroll_velocity-=450
			else: 
				scroll_velocity+=450
	#左键拖拽
	elif event is InputEventMouseMotion:
		if  is_dragging:
			drag_pos2=event.global_position.y-drag_pos1;
			if drag_pos2!=0:
				scroll_vertical=-drag_pos2*1.5+start_scroll_v_pos
			
