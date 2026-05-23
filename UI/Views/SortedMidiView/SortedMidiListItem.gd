## 排序MIDI列表项组件
## 继承自 ListItemBase，显示排序视图中的MIDI谱面信息
extends ListItemBase

## 引用节点
@onready var status_label: Label = $Panel/HBoxC/status
@onready var midi_name_label: Label = $Panel/MidiName
@onready var author_label: Label = $Panel/HBoxC/Author
@onready var line: Line2D = $Panel/HBoxC/Line2D
@onready var cover_texture: TextureRect = $Panel/cover

@onready var state_manager:UIStateManager = UIStateManager.instance

## MIDI数据
var midi_data: MidiData

## 选择动画补间
var select_tween: Tween
var _last_cover_offset: float = 0.0

signal _init_fin

func _ready() -> void:
	await _init_fin

	# 显示MIDI信息
	get_node("Panel/Data").text = "%d %d %d %d" % [midi_data.download_count, midi_data.trial_count, midi_data.up_count, midi_data.love_count]
	status_label.text = midi_data.status
	midi_name_label.text = midi_data.name.strip_edges()
	author_label.text = midi_data.artist_name if not midi_data.artist_name.is_empty() else "Unknown"

	# 封面
	var fs_mgr := FileSystemManager.instance
	cover_texture.texture = fs_mgr.get_cover_by_midiData(midi_data)

func _process(_delta: float) -> void:
	if parent_node == null:
		return
	if parent_node.scroll_velocity == 0 and parent_node.snap_tween == null:
		return
	var new_offset: float = -(global_position.y / max(parent_node.size.y, 1.0)) * max(cover_texture.size.y - size.y, 0.0)
	if not is_equal_approx(new_offset, _last_cover_offset):
		cover_texture.position.y = new_offset
		_last_cover_offset = new_offset

## 从MidiData初始化显示
func setup_with_midi(midi: MidiData, index: int, bg:ButtonGroup) -> void:
	midi_data = midi
	item_id = midi.id
	item_type = "sorted_midi"
	item_index = index

	# 初始化按钮
	button = get_node("Panel/Button")
	button.button_group = bg

	enable_selected_animation(button, get_parent().get_parent())

	_init_fin.emit()
