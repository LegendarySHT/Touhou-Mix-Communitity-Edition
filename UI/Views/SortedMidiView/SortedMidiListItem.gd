## 排序MIDI列表项组件
## 继承自 ListItemBase，显示排序视图中的MIDI谱面信息
extends ListItemBase

## 引用节点
@onready var status_label: Label = $MC/MC/status if has_node("MC/MC/status") else null
@onready var midi_name_label: Label = $MC/VBox/MidiName if has_node("MC/VBox/MidiName") else null
@onready var author_label: Label = $MC/VBox/Author if has_node("MC/VBox/Author") else null
@onready var line: Line2D = $Line2D if has_node("Line2D") else null
@onready var cover_texture: TextureRect = $Polygon2D/cover if has_node("Polygon2D/cover") else null

@onready var state_manager:UIStateManager = UIStateManager.instance

## MIDI数据
var midi_data: MidiData

## 选择动画补间
var select_tween: Tween

func _update_display() -> void:
	# 初始化显示
	if not status_label:
		status_label = get_node("MC/MC/status")
	if not midi_name_label:
		midi_name_label = get_node("MC/VBox/MidiName")
	if not author_label:
		author_label = get_node("MC/VBox/Author")
	if not button:
		button = get_node("Button")

	# 显示MIDI信息
	get_node("MC/Data").text = "%d %d %d %d" % [midi_data.download_count, midi_data.trial_count, midi_data.up_count, midi_data.love_count]
	status_label.text = midi_data.status
	midi_name_label.text = midi_data.name
	author_label.text = midi_data.artist_name if not midi_data.artist_name.is_empty() else "Unknown"

## 从MidiData初始化显示
func setup_with_midi(midi: MidiData, index: int, bg:ButtonGroup) -> void:
	midi_data = midi
	item_id = midi.id
	item_type = "sorted_midi"
	item_index = index
	
	# 更新显示
	_update_display()
	_load_cover_image()

	button.button_group = bg

	enable_selected_animation(button, get_parent().get_parent())
	
## 按钮切换回调
func _on_button_toggled(toggled_on: bool) -> void:
	
	select_tween = create_tween()
	select_tween.set_trans(Tween.TRANS_SINE)
	
	select_tween.tween_property(line, "default_color", Color("#938aff" if toggled_on else "ffffff"), 0.15)
		
func _load_cover_image() -> void:
	if not cover_texture:
		cover_texture = get_node_or_null("Polygon2D/cover")
	if not cover_texture:
		return

	var fs_mgr := FileSystemManager.instance
	cover_texture.texture = fs_mgr.get_cover_by_midiData(midi_data)

## 选中状态改变时调用
func _on_selected() -> void:
	pass

## 取消选中时调用
func _on_deselected() -> void:
	pass
