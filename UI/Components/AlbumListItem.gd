## 专辑列表项组件
## 继承自 ListItemBase，显示专辑信息
extends ListItemBase

## 引用节点路径
@onready var album_name_label: Label = $PC/Polygon2D/AlbumName if has_node("PC/Polygon2D/AlbumName") else null
@onready var song_count_label: Label = $"PC/Polygon2D/CountBase/SongCount" if has_node("PC/Polygon2D/CountBase/SongCount") else null
@onready var cover_texture: TextureRect = $PC/Polygon2D/cover if has_node("PC/Polygon2D/cover") else null
@onready var album_button: Button = $PC/Polygon2D/AlbumButton if has_node("PC/Polygon2D/AlbumButton") else null
@onready var polygon: Polygon2D = $PC/Polygon2D if has_node("PC/Polygon2D") else null
@onready var line: Line2D = $PC/line if has_node("PC/line") else null
@onready var decorated_line: Node = $PC/Polygon2D/DecoratedLine if has_node("PC/Polygon2D/DecoratedLine") else null

## 专辑数据
var album_data: AlbumData

## 是否展开
var is_expanded: bool = false

## 展开动画补间
var expand_tween: Tween

func _ready() -> void:
	# 连接按钮信号
	if album_button:
		album_button.toggled.connect(_on_album_button_toggled)

## 从AlbumData初始化显示
func setup_with_album(album: AlbumData) -> void:
	album_data = album
	item_id = album.id
	item_type = "album"
	
	# 更新显示
	if album_name_label:
		album_name_label.text = " %s" % album.name if album.name else "Unknown"
	
	if song_count_label:
		song_count_label.text = "%d" % album.song_count

## 处理_process中的视觉效果
func _process(_delta: float) -> void:
	# 图片位移效果
	if cover_texture and cover_texture.visible:
		cover_texture.position = Vector2(35, 250 - cover_texture.global_position.y / 1080.0 * 650.0)

## 专辑按钮切换回调
func _on_album_button_toggled(toggled_on: bool) -> void:
	if expand_tween and expand_tween.is_running():
		expand_tween.kill()
	
	expand_tween = create_tween()
	expand_tween.set_ease(Tween.EASE_OUT)
	expand_tween.set_trans(Tween.TRANS_SINE)
	expand_tween.set_parallel(true)
	
	if toggled_on:
		is_expanded = true
		_animate_expand(expand_tween)
		# 发射选中信号
		set_selected(true)
	else:
		is_expanded = false
		_animate_collapse(expand_tween)
		set_selected(false)

## 展开动画
func _animate_expand(tween: Tween) -> void:
	tween.tween_property(self, "custom_minimum_size", Vector2(960, 395), 0.15)
	
	if has_node("PC/VE"):
		tween.tween_property(get_node("PC/VE"), "rect", Rect2(0, 0, 1100, 1000), 0.15)
	
	if decorated_line:
		decorated_line.visible = true
	
	# 线框动画
	if line:
		tween.tween_method(_update_line_point.bind(1), line.points[1], Vector2(114, 404), 0.15)
		tween.tween_method(_update_line_point.bind(2), line.points[2], Vector2(1070, 404), 0.15)
		tween.tween_method(_update_line_point.bind(3), line.points[3], Vector2(1070, 12), 0.15)
	
	# 字体动画
	if album_name_label:
		tween.tween_property(album_name_label, "theme_override_font_sizes/font_size", 45, 0.15)
		tween.tween_property(album_name_label, "position", Vector2(80, 640), 0.15)
		tween.tween_property(album_name_label, "custom_minimum_size", Vector2(1055, 40), 0.15)
	
	# 专辑歌曲数位置
	if has_node("PC/Polygon2D/CountBase"):
		tween.tween_property(get_node("PC/Polygon2D/CountBase"), "position", Vector2(980, 287), 0.15)
	
	# 专辑图片放大
	if cover_texture:
		tween.tween_property(cover_texture, "scale", Vector2(1.57, 1.57), 0.15)
	
	# 按钮放大
	if album_button:
		tween.tween_property(album_button, "scale", Vector2(1.7, 2.49), 0.15)
		tween.tween_property(album_button, "position", Vector2(-30, 270), 0.15)

## 收起动画
func _animate_collapse(tween: Tween) -> void:
	tween.tween_property(self, "custom_minimum_size", Vector2(615, 144), 0.15)
	
	if has_node("PC/VE"):
		tween.tween_property(get_node("PC/VE"), "rect", Rect2(0, 0, 700, 1000), 0.15)
	
	if decorated_line:
		decorated_line.visible = false
	
	# 线框动画（恢复原状）
	if line:
		tween.tween_method(_update_line_point.bind(1), line.points[1], Vector2(114, 154), 0.15)
		tween.tween_method(_update_line_point.bind(2), line.points[2], Vector2(685, 154), 0.15)
		tween.tween_method(_update_line_point.bind(3), line.points[3], Vector2(685, 12), 0.15)
	
	# 字体动画（恢复）
	if album_name_label:
		tween.tween_property(album_name_label, "theme_override_font_sizes/font_size", 30, 0.15)
		tween.tween_property(album_name_label, "position", Vector2(50, 400), 0.15)
		tween.tween_property(album_name_label, "custom_minimum_size", Vector2(655, 40), 0.15)
	
	# 恢复专辑歌曲数位置
	if has_node("PC/Polygon2D/CountBase"):
		tween.tween_property(get_node("PC/Polygon2D/CountBase"), "position", Vector2(595, 120), 0.15)
	
	# 恢复专辑图片
	if cover_texture:
		tween.tween_property(cover_texture, "scale", Vector2(1, 1), 0.15)
	
	# 恢复按钮
	if album_button:
		tween.tween_property(album_button, "scale", Vector2(1, 1.6), 0.15)
		tween.tween_property(album_button, "position", Vector2(-18, 110), 0.15)

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
