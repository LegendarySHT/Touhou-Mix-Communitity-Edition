## 排序MIDI列表项组件
## 继承自 ListItemBase，显示排序视图中的MIDI谱面信息
extends ListItemBase

## 引用节点
@onready var status_label: Label = $MC/MC/status if has_node("MC/MC/status") else null
@onready var midi_name_label: Label = $MC/VBox/MidiName if has_node("MC/VBox/MidiName") else null
@onready var author_label: Label = $MC/VBox/Author if has_node("MC/VBox/Author") else null
@onready var button: Button = $Button if has_node("Button") else null
@onready var line: Line2D = $Line2D if has_node("Line2D") else null

@onready var state_manager:UIStateManager = UIStateManager.instance

## MIDI数据
var midi_data: MidiData

## 是否被选中（用于双击检测）
var be_selected: int = 0

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
	status_label.text = midi_data.status
	midi_name_label.text = midi_data.name
	author_label.text = midi_data.artist_name if not midi_data.artist_name.is_empty() else "Unknown"

## 从MidiData初始化显示
func setup_with_midi(midi: MidiData, index: int, bg:ButtonGroup) -> void:
	midi_data = midi
	item_id = midi.id
	item_type = "sorted_midi"
	
	# 更新显示
	_update_display()

	button.set_meta("index", index)
	button.button_group = bg
	
	# 设置元数据
	set_meta("index", index)

## 按钮切换回调
func _on_button_toggled(toggled_on: bool) -> void:
	if select_tween and select_tween.is_running():
		select_tween.kill()
	
	select_tween = create_tween()
	select_tween.set_ease(Tween.EASE_IN_OUT)
	select_tween.set_trans(Tween.TRANS_SINE)
	select_tween.set_parallel(true)
	
	if toggled_on and be_selected:
		print("选中：%s / %s" % [midi_data.song_data.name, midi_data.name])
		var event_bus = EventBus.instance
		if event_bus and midi_data:
			state_manager.change_state(UIStateManager.UIState.MIDI_VIEW)
			event_bus.emit_midi_selected(midi_data.id, midi_data)

	be_selected = 1 if toggled_on else 0

	select_tween.tween_property(self, "scale", Vector2(1 +0.07 *be_selected, 1+0.07 *be_selected), 0.15)
	select_tween.tween_property(line, "default_color", Color("#938aff" if be_selected else "ffffff"), 0.15)
		

## 选中状态改变时调用
func _on_selected() -> void:
	pass

## 取消选中时调用
func _on_deselected() -> void:
	pass
