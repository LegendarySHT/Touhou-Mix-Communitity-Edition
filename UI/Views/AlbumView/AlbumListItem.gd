## 专辑列表项组件
## 继承自 CoverListItemBase，显示专辑信息
extends CoverListItemBase

const TextScrollHelper = preload("res://UI/Components/TextScrollHelper.gd")

## 引用节点路径
@onready var album_name_label: Label = $NameBox/AlbumName
@onready var name_box: Control = $NameBox
@onready var song_count_label: Label = $SongCount
# cover_texture 继承自 CoverListItemBase，在 _ready() 中赋值

## 专辑数据
var album_data: AlbumData

## 文字滚动状态
var _name_scroll_state: TextScrollHelper.State = null

## 展开动画补间
var expand_tween: Tween:
	set(t):
		expand_tween = t
		_extra_motion_tween = t

var ALBUMBUTTON = "AlbumButton"
signal _init_fin

func _ready() -> void:
	cover_texture = $cover
	await _init_fin

	if not album_data:
		push_error("AlbumListItem: Missing album data")
		return
	album_name_label.text = " %s" % album_data.name if album_data.name else "Unknown"
	song_count_label.text = "%d" % album_data.song_ids.size()

	# 直接开始加载封面（不等列表构建完毕）
	# 命中 WeakRef 缓存时零开销；未命中时同步读盘，但每项创建间隔由 LazyListLoader 控制不阻塞
	# 列表的 trigger_cover_chain 仍处理"释放后重载"场景（状态切换回视图时）
	start_cover_load()
	# 启动文字滚动动画（如名称过长）
	call_deferred("setup_name_scroll")

## 从AlbumData初始化显示
func setup_with_album(parent: AlbumView, album: AlbumData, index:int, bg: ButtonGroup) -> void:
	album_data = album
	item_id = album.id
	item_type = "album"
	item_index = index

	button = get_node(ALBUMBUTTON)
	button.button_group = bg

	enable_selected_animation(button, parent)

	_init_fin.emit()

## 重写基类虚函数：返回专辑封面 Texture2D
## 选择专辑下首个歌曲的首个 MIDI 的封面，否则由 FileSystemManager 返回默认封面
func _get_cover_texture() -> Texture2D:
	if not album_data:
		return null
	var fs_mgr := FileSystemManager.instance
	var data_mgr := DataMGR
	if not fs_mgr or not data_mgr:
		return null
	var songs := data_mgr.get_songs_by_album(album_data.id)
	if songs.is_empty():
		return null
	var midis := data_mgr.get_midis_by_song(songs[0].id)
	if midis.is_empty():
		return null
	return fs_mgr.get_cover_by_midiData(midis[0])

## 专辑按钮切换回调
func on_item_button_toggled(toggled_on: bool) -> void:
	if expand_tween:
		expand_tween.kill()
	
	expand_tween = create_tween()
	expand_tween.set_ease(Tween.EASE_OUT)
	expand_tween.set_trans(Tween.TRANS_SINE)
	expand_tween.set_parallel(true)
	
	var expa: int = 1 if toggled_on else 0
	expand_tween.tween_property(self,"custom_minimum_size",Vector2(600 + expa*350, 150 + 250*expa),0.15)
	expand_tween.tween_property(album_name_label,"theme_override_font_sizes/font_size",25 + 20*expa,0.15)

	if toggled_on:
		parent_node.selected_item = item_index
	
	expand_tween.finished.connect(func ():
		expand_tween.kill()
		expand_tween = null
		# 字号变化后重算滚动布局
		call_deferred("setup_name_scroll")
	)

	# 因为塞在tween里的话，节点在屏幕外似乎无法触发，所以就成下面这样了
	await get_tree().create_timer(0.15).timeout
	if toggled_on and parent_node.selected_item == item_index:
		parent_node.need_snap = true


## 启动/重算专辑名称滚动动画
func setup_name_scroll() -> void:
	if not is_instance_valid(album_name_label) or not is_instance_valid(name_box):
		return
	# 循环等待 NameBox 布局完成（最多 5 帧），确保 size 正确
	var max_wait := 5
	while name_box.size.y <= 10.0 and max_wait > 0:
		await get_tree().process_frame
		max_wait -= 1
	_name_scroll_state = TextScrollHelper.setup(
		album_name_label, name_box, album_name_label.text, _name_scroll_state
	)
