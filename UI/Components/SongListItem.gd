## 歌曲列表项组件
## 继承自 ListItemBase，显示歌曲信息
extends ListItemBase

## 引用节点（需要根据实际场景结构调整）
@onready var song_name_label: Label = $SongName if has_node("SongName") else null
@onready var midi_count_label: Label = $MidiCount if has_node("MidiCount") else null
@onready var button: Button = $Button if has_node("Button") else null

## 歌曲数据
var song_data: SongData

## 选中动画补间
var select_tween: Tween

func _ready() -> void:
	# 连接按钮信号
	if button:
		button.pressed.connect(_on_button_pressed)

## 从SongData初始化显示
func setup_with_song(song: SongData, index: int = 0) -> void:
	song_data = song
	item_id = song.id
	item_type = "song"
	
	# 更新显示
	if song_name_label:
		song_name_label.text = song.name if not song.name.is_empty() else "Unknown"
	
	if midi_count_label:
		midi_count_label.text = "%d MIDI" % song.midi_count
	
	if button:
		button.set_meta("index", index)
	
	# 设置元数据
	set_meta("index", index)
	set_meta("song_id", song.id)

## 按钮按下回调
func _on_button_pressed() -> void:
	_on_song_selected()

## 歌曲选中
func _on_song_selected() -> void:
	# 播放选中动画
	if select_tween and select_tween.is_running():
		select_tween.kill()
	
	select_tween = create_tween()
	select_tween.set_ease(Tween.EASE_OUT)
	select_tween.set_trans(Tween.TRANS_BACK)
	select_tween.set_parallel(true)
	
	# 简单的缩放反馈
	select_tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.1)
	select_tween.chain().tween_property(self, "scale", Vector2(1, 1), 0.1)
	
	# 发射选中信号
	set_selected(true)

## 选中状态改变时调用
func _on_selected() -> void:
	# 可以在这里添加选中视觉效果
	pass

## 取消选中时调用
func _on_deselected() -> void:
	# 可以在这里添加取消选中视觉效果
	pass
