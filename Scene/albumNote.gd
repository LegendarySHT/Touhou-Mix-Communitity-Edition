extends MarginContainer

var INDEX=0
var is_inflated = false

#json里读取的
#var id
#var uploaderName
#var desc
#
#var status

var sourceAlbumName
#var sourceSongName
#var sourceArtistName
#
#var trialCount
#var downloadCount
#var loveCount
#var voteCount
#var upCount
#var downCount
#var hash_
var songCount=0

#路径
var ALBUMNAME= "PC/Polygon2D/AlbumName"
var ALBUMBUTTON="PC/Polygon2D/AlbumButton"

func _ready():
	get_node(ALBUMNAME).text=" %s" % get_meta("sourceAlbumName")
	if get_meta("sourceAlbumName")=="" or get_meta("sourceAlbumName")==null:
		get_node(ALBUMNAME).text="Unknow"
	get_node("PC/Polygon2D/CountBase/SongCount").text="%d"%get_meta("songCount")
	get_node(ALBUMBUTTON).set_meta("index",get_meta("index"))
	
func _process(_delta):
	#图片位移效果
	var child = get_node("PC/Polygon2D/cover");
	if child is TextureRect and child.visible:
		child.position=Vector2(35,250-child.global_position.y/1080 *650)
		
	#var parent= get_parent().get_parent()
		##if parent.get_screen_position().y>-1000 and child.get_screen_position().y<2000 and Global.UI == 0:
	#parent.add_theme_constant_override("margin_left",130-int(parent.get_screen_position().y*0.26795))

#更新多边形点的位置的
func _update_polygon(np:Vector2,i):
	get_node("PC/Polygon2D").polygon[i]=np;

#更新线框的点的位置的
func _update_point(np,i):
	var target= get_node("PC/line")
	if target is Line2D:
		target.points[i]=np;


func _on_album_button_toggled(toggled_on):
	var tween = create_tween();
	tween.set_ease(Tween.EASE_OUT);
	tween.set_trans(Tween.TRANS_SINE);
	tween.set_parallel(true);
	var line_point = get_node("PC/line");
	#var poly=get_node("PC/Polygon2D")
	
	if toggled_on:
		is_inflated=true
		tween.tween_property(self,"custom_minimum_size",Vector2(960,395),0.15)#框的大小
		tween.tween_property(get_node("PC/VE"),"rect",Rect2(0,0,1100,1000),0.15)#VE的大小
		
		get_node("PC/Polygon2D/DecoratedLine").visible =true
		
		#线框
		if line_point is Line2D:
			tween.tween_method(func(t):_update_point(t,1),line_point.points[1],Vector2(114,404),0.15);
			tween.tween_method(func(t):_update_point(t,2),line_point.points[2],Vector2(1070,404),0.15);
			tween.tween_method(func(t):_update_point(t,3),line_point.points[3],Vector2(1070,12),0.15);
			
		#字体
		tween.tween_property(get_node(ALBUMNAME),"theme_override_font_sizes/font_size",45,0.15)
		tween.tween_property(get_node(ALBUMNAME),"position",Vector2(80,640),0.15)
		tween.tween_property(get_node(ALBUMNAME),"custom_minimum_size",Vector2(1055,40),0.15)
		
		#专辑的歌曲数字
		tween.tween_property(get_node("PC/Polygon2D/CountBase"),"position",Vector2(980,287),0.15)
		
		#专辑图片放大
		tween.tween_property(get_node("PC/Polygon2D/cover"),"scale",Vector2(1.57,1.57),0.15)

		#按钮放大
		tween.tween_property(get_node(ALBUMBUTTON),"scale",Vector2(1.7,2.49),0.15)
		tween.tween_property(get_node(ALBUMBUTTON),"position",Vector2(-30,270),0.15)

	else:
		is_inflated=false

		tween.tween_property(self,"custom_minimum_size",Vector2(615,144),0.15)
		tween.tween_property(get_node("PC/VE"),"rect",Rect2(0,0,700,1000),0.15)
		
		get_node("PC/Polygon2D/DecoratedLine").visible =false
		
		if line_point is Line2D:
			tween.tween_method(func(t):_update_point(t,1),line_point.points[1],Vector2(114,153),0.15);
			tween.tween_method(func(t):_update_point(t,2),line_point.points[2],Vector2(722,153),0.15);
			tween.tween_method(func(t):_update_point(t,3),line_point.points[3],Vector2(722,12),0.15);
		
		#tween.tween_property(get_node(ALBUMNAME),"scale",Vector2(1,1),0.15)
		tween.tween_property(get_node(ALBUMNAME),"theme_override_font_sizes/font_size",25,0.15)
		tween.tween_property(get_node(ALBUMNAME),"position",Vector2(70,375),0.15)
		tween.tween_property(get_node(ALBUMNAME),"custom_minimum_size",Vector2(660,40),0.15)
		
		tween.tween_property(get_node("PC/Polygon2D/CountBase"),"position",Vector2(550,287),0.15)
		
		tween.tween_property(get_node("PC/Polygon2D/cover"),"scale",Vector2(1,1),0.15)
		
		tween.tween_property(get_node(ALBUMBUTTON),"scale",Vector2(1,1),0.15)
		tween.tween_property(get_node(ALBUMBUTTON),"position",Vector2(40,260),0.15)
		
