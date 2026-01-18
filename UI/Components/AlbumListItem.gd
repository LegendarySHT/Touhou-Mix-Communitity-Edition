## 专辑列表项组件
## 继承自 ListItemBase，显示专辑信息
extends ListItemBase

## 引用节点路径
@onready var album_name_label: Label = get_node("PC/Polygon2D/AlbumName") if has_node("PC/Polygon2D/AlbumName") else null
@onready var song_count_label: Label = get_node("PC/Polygon2D/CountBase/SongCount") if has_node("PC/Polygon2D/CountBase/SongCount") else null
@onready var cover_texture: TextureRect = get_node("PC/Polygon2D/cover") if has_node("PC/Polygon2D/cover") else null
@onready var album_button: Button = get_node("PC/Polygon2D/AlbumButton") if has_node("PC/Polygon2D/AlbumButton") else null
@onready var polygon: Polygon2D = get_node("PC/Polygon2D") if has_node("PC/Polygon2D") else null
@onready var line: Line2D = get_node("PC/line") if has_node("PC/line") else null
@onready var decorated_line: Node = $PC/Polygon2D/DecoratedLine if has_node("PC/Polygon2D/DecoratedLine") else null

## 专辑数据
var album_data: AlbumData

## 是否展开
var is_expanded: bool = false

## 展开动画补间
var expand_tween: Tween

var ALBUMBUTTON = "PC/Polygon2D/AlbumButton"

func _ready() -> void:
	# 连接按钮信号
	if album_button:
		album_button.toggled.connect(_on_album_button_toggled)

## 从AlbumData初始化显示
func setup_with_album(parent: AlbumView, album: AlbumData, index:int, bg: ButtonGroup) -> void:
	album_data = album
	item_id = album.id
	item_type = "album"

	set_meta("index", index)
	
	# 更新显示
	album_name_label = get_node("PC/Polygon2D/AlbumName")
	album_name_label.text = " %s" % album.name if album.name else "Unknown"
	
	song_count_label = get_node("PC/Polygon2D/CountBase/SongCount")
	song_count_label.text = "%d" % album.song_ids.size()

	var button = get_node(ALBUMBUTTON)
	button.button_group = bg
	button.set_meta("album_id",album_data.id)
	button.set_meta("index", index)
	button.toggled.connect(parent._on_button_toggled.bind(button))

## 处理_process中的视觉效果
func _process(_delta: float) -> void:
	# 图片位移效果
	if cover_texture and cover_texture.visible and abs(global_position.y - 800)<= 1500:
		cover_texture.position = Vector2(35, 250 - cover_texture.global_position.y / 1080.0 * 650.0)

## 专辑按钮切换回调
func _on_album_button_toggled(toggled_on: bool) -> void:
	if expand_tween and expand_tween.is_running():
		expand_tween.kill()
	
	expand_tween = create_tween()
	expand_tween.set_ease(Tween.EASE_OUT)
	expand_tween.set_trans(Tween.TRANS_SINE)
	expand_tween.set_parallel(true)
	
	is_expanded = toggled_on
	_animate_expand(expand_tween, toggled_on)

func _update_point(np,i):
	var target= get_node("PC/line")
	if target is Line2D:
		target.points[i]=np;

func _animate_expand(tween: Tween, expand: bool) -> void:
	get_node("PC/Polygon2D/DecoratedLine").visible = expand
	var expa: int = 1 if expand else 0
		
	# 矩形
	tween.tween_property(self,"custom_minimum_size",Vector2(615 + expa*345,144 + 251*expa),0.15)
	tween.tween_property(get_node("PC/VE"),"rect",Rect2(0,0,700 + 400*expa,1000),0.15)
	
	# 线框
	tween.tween_method(func(t):_update_point(t,1),line.points[1],Vector2(114,153 + 251*expa),0.15);
	tween.tween_method(func(t):_update_point(t,2),line.points[2],Vector2(722 +348*expa,153 + 251*expa),0.15);
	tween.tween_method(func(t):_update_point(t,3),line.points[3],Vector2(722 +348*expa,12),0.15);

	# 字体
	tween.tween_property(album_name_label,"theme_override_font_sizes/font_size",25 + 20*expa,0.15)
	tween.tween_property(album_name_label,"position",Vector2(70 + 10*expa,375 +265*expa),0.15)
	tween.tween_property(album_name_label,"custom_minimum_size",Vector2(660 +395*expa,40),0.15)

	# 专辑的歌曲数字
	tween.tween_property(get_node("PC/Polygon2D/CountBase"),"position",Vector2(550 +430*expa,287),0.15)
	
	# 专辑图片放大
	tween.tween_property(cover_texture,"scale",Vector2(1+0.57*expa,1+0.57*expa),0.15)
	
	#按钮放大
	tween.tween_property(album_button,"scale",Vector2(1 +0.7*expa,1 +1.49*expa),0.15)
	tween.tween_property(album_button,"position",Vector2(40 -70 *expa,260+10*expa),0.15)

## 更新线框点位置的辅助函数
func _update_line_point(new_pos: Vector2, index: int) -> void:
	if line and index < line.points.size():
		line.points[index] = new_pos

## 选中状态改变时调用
func _on_selected() -> void:
	# 已通过动画处理
	pass

## 取消选中时调用
func _on_deselected() -> void:
	# 已通过动画处理
	pass
