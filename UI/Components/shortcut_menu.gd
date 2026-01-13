extends Polygon2D
var view = 0 #为1或2时表示切换到对应页
signal menu_closed

func _sort_button_pressed() -> void:
	print("sort button clicked")
	switch_table(1)

func _SongList_button_pressed() -> void:
	print("song list button clicked")
	switch_table(2)
func _process(_delta):
	if not (Global.UI==0 or Global.UI==1 or Global.UI==-1) and view!=0:
		switch_table(view)
	if view==0 and Global.Sort!=0 and (Global.UI==1 or Global.UI==0):
		get_node("Page/SortPage/SortButton/Data").button_pressed=false
		get_node("Page/SortPage/SortButton/Time").button_pressed=false
		get_node("Page/SortPage/SortButton").select=0
		Global.Sort=0
		Global.SortHeadPTR=Global.default
		print("关闭筛选")
func switch_table(page):
	var tween =create_tween();
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_parallel(true)
	#需要收起菜单
	if view==page:
		view=0
		
		menu_closed.emit()
		
		restore(1)
		restore(2)
		tween.tween_method(func(t):_update_polygon(t,1),polygon[1],Vector2(1318,152),0.5);
		tween.tween_method(func(t):_update_polygon(t,2),polygon[2],Vector2(1443,152),0.5);
		tween.tween_method(func(t):_update_polygon(t,3),polygon[3],Vector2(1473,43),0.5);
	else:
		Global.Sort=1
		print("开启筛选")
		#框展开
		tween.tween_method(func(t):_update_polygon(t,1),polygon[1],Vector2(1318-0.2679*660,812),0.5);
		tween.tween_method(func(t):_update_polygon(t,2),polygon[2],Vector2(1443-0.2679*660+406,812),0.5);
		tween.tween_method(func(t):_update_polygon(t,3),polygon[3],Vector2(1473+406,43),0.5);
		#展开sort页
		if page==1:	
			#恢复第二页的状态
			if view==2:
				restore(2)
			view=1
			#按钮移动及缩放
			tween.tween_property(get_parent().get_node("Sort"),"custom_minimum_size",Vector2(400,150),0.5)
			tween.tween_method(func(t):_update_polygon1(t,2),get_parent().get_node("Sort/Polygon2D").polygon[2],Vector2(1443+220,152),0.5);
			tween.tween_method(func(t):_update_polygon1(t,3),get_parent().get_node("Sort/Polygon2D").polygon[3],Vector2(1473+220,43),0.5);
			#白线框
			tween.tween_method(func(t):_update_point1(t,2),get_parent().get_node("Sort/Line2D").points[2],Vector2(1457+265,179),0.5);
			tween.tween_method(func(t):_update_point1(t,3),get_parent().get_node("Sort/Line2D").points[3],Vector2(1492+265,44),0.5);
			#页面移动
			tween.tween_property(get_node("Page"),"position",Vector2(1290,170),0.6);
			
		elif page==2:
			#恢复第一页的状态
			if view==1:
				restore(1)
			view=2
			#按钮移动及缩放
			tween.tween_property(get_parent().get_node("SongList"),"custom_minimum_size",Vector2(400,150),0.5)
			tween.tween_method(func(t):_update_polygon2(t,2),get_parent().get_node("SongList/Polygon2D").polygon[2],Vector2(1443+220,152),0.5);
			tween.tween_method(func(t):_update_polygon2(t,3),get_parent().get_node("SongList/Polygon2D").polygon[3],Vector2(1473+220,43),0.5);
			#白线框
			tween.tween_method(func(t):_update_point2(t,2),get_parent().get_node("SongList/Line2D").points[2],Vector2(1457+265,179),0.5);
			tween.tween_method(func(t):_update_point2(t,3),get_parent().get_node("SongList/Line2D").points[3],Vector2(1492+265,44),0.5);
			#页面
			tween.tween_property(get_node("Page"),"position",Vector2(690,170),0.6);

func restore(page):
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_parallel(true)
	
	if page==1 or page==0:
		tween.tween_property(get_parent().get_node("Sort"),"custom_minimum_size",Vector2(180,150),0.5)
		tween.tween_method(func(t):_update_polygon1(t,2),get_parent().get_node("Sort/Polygon2D").polygon[2],Vector2(1443,152),0.5);
		tween.tween_method(func(t):_update_polygon1(t,3),get_parent().get_node("Sort/Polygon2D").polygon[3],Vector2(1473,43),0.5);
		
		tween.tween_method(func(t):_update_point1(t,2),get_parent().get_node("Sort/Line2D").points[2],Vector2(1457,179),0.5);
		tween.tween_method(func(t):_update_point1(t,3),get_parent().get_node("Sort/Line2D").points[3],Vector2(1492,44),0.5);
	if page==2 or page==0:
		tween.tween_property(get_parent().get_node("SongList"),"custom_minimum_size",Vector2(180,150),0.5)
		tween.tween_method(func(t):_update_polygon2(t,2),get_parent().get_node("SongList/Polygon2D").polygon[2],Vector2(1443,152),0.5);
		tween.tween_method(func(t):_update_polygon2(t,3),get_parent().get_node("SongList/Polygon2D").polygon[3],Vector2(1473,43),0.5);
		
		tween.tween_method(func(t):_update_point2(t,2),get_parent().get_node("SongList/Line2D").points[2],Vector2(1457,179),0.5);
		tween.tween_method(func(t):_update_point2(t,3),get_parent().get_node("SongList/Line2D").points[3],Vector2(1492,44),0.5);

func _update_polygon(np:Vector2,i):
	polygon[i]=np;
	
func _update_polygon1(np:Vector2,i):
	get_parent().get_node("Sort/Polygon2D").polygon[i]=np;
	
func _update_point1(np,i):
	var target= get_parent().get_node("Sort/Line2D")
	if target is Line2D:
		target.points[i]=np;


func _update_polygon2(np:Vector2,i):
	get_parent().get_node("SongList/Polygon2D").polygon[i]=np;
	
func _update_point2(np,i):
	var target= get_parent().get_node("SongList/Line2D")
	if target is Line2D:
		target.points[i]=np;
