extends ScrollContainer

@export var item_height: float = 173

## 指示当前是否有拖拽操作
var is_dragging := false
# 当鼠标开始拖拽至松手前，计算列表滚动值的
var drag_pos1 = 0;
var drag_pos2 = 0;
# 开始拖拽时的列表滚动值
var start_scroll_v_pos = 0

# 滚动速度
var scroll_velocity = 0

#var timer=Timer.new();
var need_snap = false # 指示是否需要吸附
var snap_velocity = 800 # 开始吸附的速度临界值
var snap_index = -1 # 当需要吸附且该值为1时，就近吸附，否则吸附到指定位置
var snap_distant = 0 # 用于指示距离吸附完成位置的距离

# 计算释放前一刻鼠标垂直方向位移的
var release_delta1 = 0
var release_delta2 = 0

# 指示鼠标是否在区域内
#var mouse_in=false


var counter = 0

# 路径
var ALBUMBUTTON = "PC/Polygon2D/AlbumButton"

# DataManager引用
@onready var data_manager = DataManager.instance

func _ready():
	# 等待DataManager加载数据
	if data_manager.is_loading:
		data_manager.data_loaded.connect(_initialize_album_list, CONNECT_ONE_SHOT)
	else:
		_initialize_album_list()

func _initialize_album_list():
	# 从DataManager获取专辑数据
	var albums = data_manager.get_all_albums()
	
	if albums.is_empty():
		print("警告: 没有找到专辑数据")
		return
	
	# 创建按钮组
	var bg = ButtonGroup.new()
	
	# 遍历专辑数据创建节点
	for i in range(albums.size()):
		var album_data = albums[i]
		
		# 从场景创建专辑节点
		var song = load("res://Scene/albumNode.tscn").instantiate()
		var button = song.get_node(ALBUMBUTTON)
		
		# 设置元数据
		song.set_meta("index", counter)
		song.set_meta("sourceAlbumName", album_data.name)
		song.set_meta("songCount", data_manager.get_songs_by_album(album_data.id).size())
		
		# 配置按钮
		button.button_group = bg
		button.toggled.connect(get_node("/root/Main/Album/AlbumList")._on_button_toggled.bind(button))
		
		# 添加到容器
		get_child(0).add_child(song)
		
		# 如果需要，可以设置专辑封面（根据你的UI结构调整）
		# _set_album_cover(song, album_data)
		
		counter += 1
	
	print("成功读取", counter, "个专辑")

func _process(delta):
	if UiStatMGR.current_state != UiStatMGR.UIState.ALBUM_VIEW or Global.Sort:
		return
	if is_dragging:
		release_delta1 = release_delta2;
		if release_delta2 == release_delta1 and release_delta1 == 0:
			release_delta1 = scroll_vertical
		release_delta2 = scroll_vertical;
	else:
		if need_snap:
			# 获取一个吸附对象
			if snap_index == -1:
				scroll_velocity = 0
				if Global.album == -1:
					snap_index = round((scroll_vertical + item_height) / (item_height))
				else:
					snap_index = Global.album

			var temp = get_node("/root/Main/Album/AlbumList/VBox").get_child(snap_index)
			if temp.is_inflated == false:
				#print("emited")
				temp.get_node(ALBUMBUTTON).button_pressed = true

			snap_distant = get_child(0).get_child(snap_index).global_position.y - item_height
			if abs(snap_distant) < 2 or (snap_index == 0):
				_stop_snap()
		# 低速时吸附
		elif abs(scroll_velocity) < snap_velocity and (abs(get_child(0).get_child(Global.album).global_position.y - 200) > 20 or Global.album == -1):
			need_snap = true
		
		var temp = get_child(0).get_child(Global.album)
		# 吸附时的移动
		if need_snap:
			scroll_vertical += floor((snap_distant) / 6)
		# 选中的曲子在屏幕外时缩小
		elif temp.is_inflated and (temp.global_position.y < 0 or temp.global_position.y > 1080):
			reset_selection()
		else:
			if scroll_vertical < 800:
				scroll_velocity = scroll_velocity * 0.5;
			else:
				scroll_velocity = scroll_velocity * (1 - 0.9 * delta);
			scroll_vertical = scroll_vertical + scroll_velocity * delta


func _on_scrolling():
	# 用户正在滚动时标记为拖拽中
	is_dragging = true
	start_scroll_v_pos = scroll_vertical;

# 拖拽滚动条时清除松手速度
func _scrollbar_input(event):
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		scroll_velocity = 0;

func _input(event):
	if UiStatMGR.current_state != UIStateManager.UIState.ALBUM_VIEW or Global.Sort:
		return
	# 检测鼠标释放或触摸结束
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_stop_snap()
			# 停止拖拽
			if not event.pressed:
				is_dragging = false
				# 释放速度
				scroll_velocity = 70 * (release_delta2 - release_delta1);
				if scroll_velocity > 7000: scroll_velocity = 6500; # 速度上限
				if release_delta1 == release_delta2:
					return
				reset_selection()

				release_delta1 = 0
				release_delta2 = 0
			# 开始拖拽
			else:
				_on_scrolling()
				drag_pos1 = event.global_position.y;
				drag_pos2 = drag_pos1
		# 鼠标滚轮
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_stop_snap()
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				# scroll_vertical-=35;
				scroll_velocity -= 450
			else: 
				# scroll_vertical+=35;
				scroll_velocity += 450
	# 左键拖拽
	elif event is InputEventMouseMotion:
		if is_dragging:
			drag_pos2 = event.global_position.y - drag_pos1;
			if drag_pos2 != 0:
				scroll_vertical = -drag_pos2 * 1.5 + start_scroll_v_pos
				reset_selection()
			

func _stop_snap():
	need_snap = false;
	snap_index = -1;
	
func reset_selection():
	if Global.album != -1:
		var temp = get_child(0).get_child(Global.album)
		temp.get_node(ALBUMBUTTON).button_pressed = false

		Global.album = -1

func _on_button_toggled(toggled_on: bool, button):
	if toggled_on:
		if Global.album == button.get_meta("index") and Global.album != -1:
			UiStatMGR.change_state(UiStatMGR.UIState.SONG_VIEW)
		need_snap = true;
		snap_index = button.get_meta("index")
		
		Global.album = button.get_meta("index")

# 辅助方法：设置专辑封面（可选）
func _set_album_cover(album_node, album_data):
	if album_data.cover_url and not album_data.cover_url.is_empty():
		# 提取封面文件名（从URL中提取最后一部分）
		var cover_filename = album_data.cover_url.get_file()
		if cover_filename:
			# 构建本地路径（假设封面图片存储在本地）
			var local_cover_path = "res://Resources/Covers/%s" % cover_filename
			
			# 尝试加载封面
			var texture = load(local_cover_path)
			if texture:
				# 根据你的UI结构设置封面
				var cover_texture = album_node.get_node("PC/Polygon2D/CoverTexture") as TextureRect
				if cover_texture:
					cover_texture.texture = texture
