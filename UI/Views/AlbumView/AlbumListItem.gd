## 专辑列表项组件
## 继承自 ListItemBase，显示专辑信息
extends ListItemBase

## 引用节点路径
@onready var album_name_label: Label = $PC/Polygon2D/AlbumName if has_node("PC/Polygon2D/AlbumName") else null
@onready var song_count_label: Label = $PC/Polygon2D/CountBase/SongCount if has_node("PC/Polygon2D/CountBase/SongCount") else null
@onready var cover_texture: TextureRect = $PC/Polygon2D/cover if has_node("PC/Polygon2D/cover") else null
@onready var polygon: Polygon2D = $PC/Polygon2D if has_node("PC/Polygon2D") else null
@onready var line: Line2D = $PC/line if has_node("PC/line") else null
@onready var decorated_line: Node = $PC/Polygon2D/DecoratedLine if has_node("PC/Polygon2D/DecoratedLine") else null

## 专辑数据
var album_data: AlbumData

## 展开动画补间
var expand_tween: Tween

var ALBUMBUTTON = "PC/Polygon2D/AlbumButton"

func _ready() -> void:
	# 连接按钮信号
	if not button:
		button = get_node_or_null(ALBUMBUTTON)
	if button:
		btn_toggled.connect(_on_album_button_toggled)

func _update_display() -> void:
	# 初始化显示
	if not album_name_label:
		album_name_label = get_node("PC/Polygon2D/AlbumName")
	if not song_count_label:
		song_count_label = get_node("PC/Polygon2D/CountBase/SongCount")

	album_name_label.text = " %s" % album_data.name if album_data.name else "Unknown"
	song_count_label.text = "%d" % album_data.song_ids.size()

## 从AlbumData初始化显示
func setup_with_album(parent: AlbumView, album: AlbumData, index:int, bg: ButtonGroup) -> void:
	album_data = album
	item_id = album.id
	item_type = "album"

	_update_display()
	_load_cover_image()

	var btn = get_node(ALBUMBUTTON)
	btn.button_group = bg
	btn.set_meta("index", index)
	btn_toggled.connect(parent._on_button_toggled.bind(index, album_data.id))
	enable_selected_animation(btn)

## 加载封面图片：选择专辑下首个存在封面的 MIDI，否则默认
func _load_cover_image() -> void:
	if not cover_texture:
		cover_texture = get_node_or_null("PC/Polygon2D/cover")
	if not cover_texture:
		return

	var fs_mgr := FileSystemManager.instance
	var data_mgr := DataManager.instance
	if not fs_mgr or not data_mgr:
		return

	var songs := data_mgr.get_songs_by_album(album_data.id)

	if songs:
		var midis := data_mgr.get_midis_by_song(songs[0].id)
	
		cover_texture.texture = fs_mgr.get_cover_by_midiData(midis[0])
	
## 专辑按钮切换回调
func _on_album_button_toggled(toggled_on: bool) -> void:
	if expand_tween and expand_tween.is_running():
		expand_tween.kill()
	
	expand_tween = create_tween()
	expand_tween.set_ease(Tween.EASE_OUT)
	expand_tween.set_trans(Tween.TRANS_SINE)
	expand_tween.set_parallel(true)
	
	is_selected = toggled_on
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
	tween.tween_property(album_name_label,"position",Vector2(20 + 30*expa,115 +285*expa),0.15)
	tween.tween_property(album_name_label,"custom_minimum_size",Vector2(660 +395*expa,40),0.15)

	# 专辑的歌曲数字
	tween.tween_property(get_node("PC/Polygon2D/CountBase"),"position",Vector2(550 +400*expa,20),0.15)
	
	# 专辑图片放大
	tween.tween_property(cover_texture,"scale",Vector2(1+0.57*expa,1+0.57*expa),0.15)
	
	#按钮放大
	tween.tween_property(button,"scale",Vector2(1 +0.7*expa,1 +1.49*expa),0.15)
	tween.tween_property(button,"position",Vector2(40 -70 *expa,40+10*expa),0.15)

## 选中状态改变时调用
func _on_selected() -> void:
	# 已通过动画处理
	pass

## 取消选中时调用
func _on_deselected() -> void:
	# 已通过动画处理
	pass
