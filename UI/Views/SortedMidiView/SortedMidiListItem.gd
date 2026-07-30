## 排序MIDI列表项组件
## 继承自 CoverListItemBase，显示排序视图中的MIDI谱面信息
extends CoverListItemBase

class_name SortedMidiListItem

## 引用节点
@onready var status_label: Label = $HBoxC/status
@onready var midi_name_label: Label = $MidiName
@onready var author_label: Label = $HBoxC/Author
@onready var line: Line2D = $HBoxC/Line2D
# cover_texture 继承自 CoverListItemBase，在 _ready() 中赋值

@onready var state_manager:UIStateManager = UiStatMGR

## MIDI数据
var midi_data: MidiData

## 选择动画补间
var select_tween: Tween

signal _init_fin

var _has_ready: bool = false

func _ready() -> void:
	cover_texture = $cover
	await _init_fin
	_refresh_display()
	_has_ready = true

## 刷新显示数据并重新加载封面（新建与复用共用）
## 复用时先 release_cover 释放旧 texture，再 start_cover_load 加载新封面；
## 新建节点 _cover_loaded=false，release_cover 仅置空 null texture（无副作用）
func _refresh_display() -> void:
	# 显示MIDI信息
	get_node("Data").text = "%d %d %d %d" % [midi_data.download_count, midi_data.trial_count, midi_data.up_count, midi_data.love_count]
	status_label.text = midi_data.status
	midi_name_label.text = midi_data.name.strip_edges()
	author_label.text = midi_data.artist_name if not midi_data.artist_name.is_empty() else "Unknown"

	# 释放可能残留的旧封面后重新加载
	release_cover()
	start_cover_load()

## 重写基类虚函数：返回 MIDI 封面 Texture2D
func _get_cover_texture() -> Texture2D:
	if not midi_data:
		return null
	return FileSystemManager.instance.get_cover_by_midiData(midi_data)

## 从MidiData初始化显示
## 新建节点（_has_ready=false）：emit _init_fin 触发 _ready 中的 await 继续
## 复用节点（_has_ready=true）：直接调 _refresh_display 刷新数据
func setup_with_midi(midi: MidiData, index: int, bg:ButtonGroup) -> void:
	midi_data = midi
	item_id = midi.id
	item_type = "sorted_midi"
	item_index = index

	# 初始化按钮（复用时 button 已存在，跳过重复初始化）
	if not button:
		button = get_node("Button")
		enable_selected_animation(button, get_node("/root/Main/skew/C/SortedMidisList"))
	button.button_group = bg

	if _has_ready:
		# 复用：清理残留 tween + 重置选中状态 + 刷新显示
		# pulse_tween 为 infinite loop，必须 kill 避免持续占用 CPU
		if pulse_tween:
			pulse_tween.kill()
			pulse_tween = null
		if press_tween:
			press_tween.kill()
		offset_transform_scale = Vector2.ONE
		if button:
			button.set_pressed_no_signal(false)
		is_selected = false
		_refresh_display()
	else:
		# 新建：触发 _ready 中的 await 继续
		_init_fin.emit()
