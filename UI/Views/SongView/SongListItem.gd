## 歌曲列表项组件
## 继承自 ListItemBase，显示歌曲信息
extends ListItemBase

## 引用节点（需要根据实际场景结构调整）
@onready var song_name_label: Label = $PC/Shader/SongName if has_node("PC/Shader/SongName") else null
@onready var midi_count_label: Label = $PC/CountBase/SongCount if has_node("PC/CountBase/SongCount") else null
@onready var button: Button = $PC/Shader/SongButton if has_node("PC/Shader/SongButton") else null

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

	var btn = get_node("PC/Shader/SongButton")
	btn.button_group = bg
	btn.toggled.connect(parent._on_button_toggled.bind(self, song_data.id))
	# btn.toggled.connect(_on_song_button_toggled.bind(self))
	
	enable_selected_animation(btn)
	# 设置元数据
	btn.set_meta("index", index)
	set_meta("index", index)


# 动画
# func _on_song_button_toggled(toggled_on: bool, songNode) -> void:
# 	tween = create_tween()
# 	tween.set_ease(Tween.EASE_OUT)
# 	tween.set_trans(Tween.TRANS_SINE)
# 	tween.set_parallel(true)

# 	var expa = 1 if toggled_on else 0
# 	tween.tween_property(songNode, "scale", Vector2(1+ expa *0.05, 1+ expa *0.05), 0.1)
	# pulse_animation(toggled_on)
