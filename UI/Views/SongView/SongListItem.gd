## 歌曲列表项组件
## 继承自 ListItemBase，显示歌曲信息
extends ListItemBase

## 引用节点（需要根据实际场景结构调整）
@onready var song_name_label: Label = $PC/Shader/SongName if has_node("PC/Shader/SongName") else null
@onready var midi_count_label: Label = $PC/CountBase/SongCount if has_node("PC/CountBase/SongCount") else null
@onready var button: Button = $PC/Shader/SongButton if has_node("PC/Shader/SongButton") else null
@onready var cover: TextureRect = $PC/Shader/cover if has_node("PC/Shader/cover") else null

const DEFAULT_COVER_PATH := "res://Resources/song_cover/1.jpg"

## 歌曲数据
var song_data: SongData

## 选中动画补间
var tween: Tween

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

	_update_display()
	_load_cover_image()

	var btn = get_node("PC/Shader/SongButton")
	btn.button_group = bg
	btn.toggled.connect(parent._on_button_toggled.bind(self, song_data.id))
	# btn.toggled.connect(_on_song_button_toggled.bind(self))
	
	enable_selected_animation(btn)
	# 设置元数据
	btn.set_meta("index", index)
	set_meta("index", index)

## 加载封面图片：选择该歌曲下第一个有封面的 MIDI，找不到则用默认
func _load_cover_image() -> void:
	if not cover:
		cover = get_node_or_null("PC/Shader/cover")
	if not cover:
		return

	var fs_mgr := FileSystemManager.instance
	var data_mgr := DataManager.instance
	if not fs_mgr or not data_mgr:
		_set_default_cover()
		return

	var charts_index := fs_mgr.get_charts_index()
	var midis := data_mgr.get_midis_by_song(song_data.id)
	var cover_path := ""

	for midi in midis:
		cover_path = _find_cover_for_midi(midi, charts_index)
		if not cover_path.is_empty():
			break

	if not cover_path.is_empty() and FileAccess.file_exists(cover_path):
		var img := Image.load_from_file(cover_path)
		if img:
			cover.texture = ImageTexture.create_from_image(img)
			return

	_set_default_cover()

## 在索引中查找对应 MIDI 的封面
func _find_cover_for_midi(midi: MidiData, charts_index: Dictionary) -> String:
	for folder_name in charts_index.keys():
		var metadata: Dictionary = charts_index[folder_name]
		var chart_id: String = metadata.get("id", "")
		if chart_id == midi.file_hash or metadata.get("data", {}).get("_id", "") == midi.id:
			var path: String = metadata.get("cover_path", "")
			if not path.is_empty():
				return path
	return ""

func _set_default_cover() -> void:
	if cover:
		cover.texture = load(DEFAULT_COVER_PATH)


# 动画
# func _on_song_button_toggled(toggled_on: bool, songNode) -> void:
# 	tween = create_tween()
# 	tween.set_ease(Tween.EASE_OUT)
# 	tween.set_trans(Tween.TRANS_SINE)
# 	tween.set_parallel(true)

# 	var expa = 1 if toggled_on else 0
# 	tween.tween_property(songNode, "scale", Vector2(1+ expa *0.05, 1+ expa *0.05), 0.1)
	# pulse_animation(toggled_on)
