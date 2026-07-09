## 歌曲列表项组件
## 继承自 ListItemBase，显示歌曲信息
extends ListItemBase

## 引用节点（需要根据实际场景结构调整）
@onready var song_name_label: Label = $PC/HBoxC/PC/SongName
@onready var midi_count_label: Label = $PC/HBoxC/CountBase/SongCount
@onready var cover: TextureRect = $PC/HBoxC/PC/cover

@onready var animation_manager: AnimationManager = AniMGR

## 歌曲数据
var song_data: SongData

signal _init_fin

func _ready() -> void:
	await _init_fin
	
	song_name_label.text = " %s" % song_data.name if song_data.name else "Unknown"
	midi_count_label.text = "%d" % song_data.midi_ids.size()

	_load_cover_image()

## 从SongData初始化显示
func setup_with_song(parent: SongView, song: SongData, index: int, bg: ButtonGroup) -> void:
	song_data = song
	item_id = song.id
	item_type = "song"
	item_index = index

	button = get_node("PC/SongButton")
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
	cover.texture = fs_mgr.get_cover_by_midiData(midis[get_meta("index")])

	cover.position.y = -(floori(self.size.y * item_index) % int(cover.size.y-self.size.y))
