## 歌曲列表项组件
## 继承自 ListItemBase，显示歌曲信息
extends ListItemBase

## 引用节点（需要根据实际场景结构调整）
@onready var song_name_label: Label = $PC/Shader/SongName if has_node("PC/Shader/SongName") else null
@onready var midi_count_label: Label = $PC/CountBase/SongCount if has_node("PC/CountBase/SongCount") else null
@onready var cover: TextureRect = $PC/Shader/cover if has_node("PC/Shader/cover") else null
@onready var line: Line2D = $PC/line

@onready var animation_manager: AnimationManager = AnimationManager.instance

var _grad: Gradient

## 歌曲数据
var song_data: SongData

func _ready() -> void:
	_grad = line.gradient

func _update_display() -> void:
	# 初始化显示
	if not song_name_label:
		song_name_label = get_node("PC/Shader/SongName")
	if not midi_count_label:
		midi_count_label = get_node("PC/CountBase/SongCount")
	song_name_label.text = " %s" % song_data.name if song_data.name else "Unknown"
	midi_count_label.text = "%d" % song_data.midi_ids.size()

## 从SongData初始化显示
func setup_with_song(parent: SongView, song: SongData, index: int, bg: ButtonGroup) -> void:
	song_data = song
	item_id = song.id
	item_type = "song"
	item_index = index

	_update_display()
	_load_cover_image()

	button = get_node("PC/Shader/SongButton")
	button.button_group = bg
	
	enable_selected_animation(button, parent)

func alpha_ani(alpha: float, duration: float):
	var tween:Tween = animation_manager._create_tween("song_select %f" % alpha)
	if not _grad:
		_grad = line.gradient
	var new_grad:Gradient = _grad

	for i in range(4):
		new_grad.colors[i] = Color(_grad.colors[i].r, _grad.colors[i].g, _grad.colors[i].b, alpha)
	tween.tween_property(line, "gradient", new_grad, duration)

func width_ani(wid: int):
	var tween:Tween = animation_manager._create_tween("song_select_width %d" % wid)
	tween.tween_property(line, "width", wid, 0.2)

func _on_button_toggled(toggled_on: bool):
	if toggled_on:
		alpha_ani(1, 0.5)
		width_ani(20)
	else:
		alpha_ani(0.6, 0.5)
		width_ani(8)

## 加载封面图片：选择该歌曲下第一个有封面的 MIDI，找不到则用默认
func _load_cover_image() -> void:
	if not cover:
		cover = get_node_or_null("PC/Shader/cover")
	if not cover:
		return

	var fs_mgr := FileSystemManager.instance
	var data_mgr := DataManager.instance
	if not fs_mgr or not data_mgr:
		return

	var midis := data_mgr.get_midis_by_song(song_data.id)
	cover.texture = fs_mgr.get_cover_by_midiData(midis[get_meta("index")])
