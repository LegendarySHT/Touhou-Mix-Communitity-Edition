## 歌曲列表项组件
## 继承自 ListItemBase，显示歌曲信息
extends ListItemBase

const TextScrollHelper = preload("res://UI/Components/TextScrollHelper.gd")

## 引用节点（需要根据实际场景结构调整）
@onready var song_name_label: Label = $HBoxC/PN/NameBox/SongName
@onready var name_box: Control = $HBoxC/PN/NameBox
@onready var midi_count_label: Label = $HBoxC/CountBase/SongCount
@onready var cover: TextureRect = $HBoxC/PN/cover

@onready var animation_manager: AnimationManager = AniMGR

## 歌曲数据
var song_data: SongData

## 文字滚动状态
var _name_scroll_state: TextScrollHelper.State = null

signal _init_fin

func _ready() -> void:
	await _init_fin

	song_name_label.text = " %s" % song_data.name if song_data.name else "Unknown"
	midi_count_label.text = "%d" % song_data.midi_ids.size()

	_load_cover_image()
	# 启动文字滚动动画（如名称过长）
	call_deferred("_setup_name_scroll")


## 启动/重算歌曲名称滚动动画
func _setup_name_scroll() -> void:
	if not is_instance_valid(song_name_label) or not is_instance_valid(name_box):
		return
	# 循环等待 NameBox 布局完成（最多 5 帧），确保 size 正确
	var max_wait := 5
	while name_box.size.y <= 10.0 and max_wait > 0:
		await get_tree().process_frame
		max_wait -= 1
	_name_scroll_state = TextScrollHelper.setup(
		song_name_label, name_box, song_name_label.text, _name_scroll_state
	)

## 从SongData初始化显示
func setup_with_song(parent: SongView, song: SongData, index: int, bg: ButtonGroup) -> void:
	song_data = song
	item_id = song.id
	item_type = "song"
	item_index = index

	button = get_node("SongButton")
	button.button_group = bg
	
	enable_selected_animation(button, parent)
	
	_init_fin.emit()

## 加载封面图片：选择该歌曲下第一个有封面的 MIDI，找不到则用默认
func _load_cover_image() -> void:
	if not cover:
		return

	var fs_mgr := FileSystemManager.instance
	var data_mgr := DataMGR
	if not fs_mgr or not data_mgr:
		return

	var midis := data_mgr.get_midis_by_song(song_data.id)
	if midis.is_empty():
		return
	cover.texture = fs_mgr.get_cover_by_midiData(midis[get_meta("index")])

	cover.offset_transform_position.y = -(floori(self.size.y * item_index) % int(cover.size.y-self.size.y))
