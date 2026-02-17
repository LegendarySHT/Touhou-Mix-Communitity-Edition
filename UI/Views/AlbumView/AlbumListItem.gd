## 专辑列表项组件
## 继承自 ListItemBase，显示专辑信息
extends ListItemBase

## 引用节点路径
@onready var album_name_label: Label = $PN/AlbumName
@onready var song_count_label: Label = $PN/CountBase/SongCount
@onready var cover_texture: TextureRect = $PN/PN/cover

## 专辑数据
var album_data: AlbumData

## 展开动画补间
var expand_tween: Tween

var ALBUMBUTTON = "PN/AlbumButton"
signal _init_fin

func _ready() -> void:
	await _init_fin

	if not album_data:
		push_error("AlbumListItem: Missing album data")
		return
	album_name_label.text = " %s" % album_data.name if album_data.name else "Unknown"
	song_count_label.text = "%d" % album_data.song_ids.size()
	
	_load_cover_image()

func _process(_delta: float) -> void:
	process_item_cover_move()

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

## 加载封面图片：选择专辑下首个存在封面的 MIDI，否则默认
func _load_cover_image() -> void:
	if not cover_texture:
		push_error("Cover texture not found.")
		return

	var fs_mgr := FileSystemManager.instance
	var data_mgr := DataManager.instance
	if not fs_mgr or not data_mgr:
		push_error("FileSystemManager or DataManager not found.")
		return

	var songs := data_mgr.get_songs_by_album(album_data.id)
	var midis := data_mgr.get_midis_by_song(songs[0].id)
	cover_texture.texture = fs_mgr.get_cover_by_midiData(midis[0])

## 专辑按钮切换回调
func on_item_button_toggled(toggled_on: bool) -> void:
	if expand_tween:
		expand_tween.kill()
	
	expand_tween = create_tween()
	expand_tween.set_ease(Tween.EASE_OUT)
	expand_tween.set_trans(Tween.TRANS_SINE)
	expand_tween.set_parallel(true)
	
	var expa: int = 1 if toggled_on else 0
	expand_tween.tween_property(self.get_node("PN"),"custom_minimum_size",Vector2(600 + expa*350, 150 + 250*expa),0.15)
	expand_tween.tween_property(album_name_label,"theme_override_font_sizes/font_size",25 + 20*expa,0.15)

	if toggled_on:
		parent_node.selected_item = item_index
	
	expand_tween.finished.connect(func ():
		expand_tween.kill()
		expand_tween = null
	)

	
	await get_tree().create_timer(0.15).timeout
	if toggled_on and parent_node.selected_item == item_index:
		parent_node.need_snap = true
