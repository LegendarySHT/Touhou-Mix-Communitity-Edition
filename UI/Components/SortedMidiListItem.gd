## 排序MIDI列表项组件
## 继承自 ListItemBase，显示排序视图中的MIDI谱面信息
extends ListItemBase

## 引用节点
@onready var status_label: Label = $MC/MC/status if has_node("MC/MC/status") else null
@onready var midi_name_label: Label = $MC/VBox/MidiName if has_node("MC/VBox/MidiName") else null
@onready var author_label: Label = $MC/VBox/Author if has_node("MC/VBox/Author") else null
@onready var button: Button = $Button if has_node("Button") else null
@onready var line: Line2D = $Line2D if has_node("Line2D") else null

## MIDI数据
var midi_data: MidiData

## 是否被选中（用于双击检测）
var be_selected: int = 0

## 选择动画补间
var select_tween: Tween

func _ready() -> void:
	# 连接按钮信号
	if button:
		button.toggled.connect(_on_button_toggled)

## 从MidiData初始化显示
func setup_with_midi(midi: MidiData, index: int = 0) -> void:
	midi_data = midi
	item_id = midi.id
	item_type = "sorted_midi"
	
	# 更新显示
	if status_label:
		status_label.text = midi.status
	
	if midi_name_label:
		midi_name_label.text = midi.name
	
	if author_label:
		author_label.text = midi.artist_name if not midi.artist_name.is_empty() else "Unknown"
	
	if button:
		button.set_meta("index", index)
	
	# 设置元数据
	set_meta("index", index)
	set_meta("id", midi.id)
	set_meta("album", midi.album_data.name if midi.album_data else "")
	set_meta("song", midi.song_data.name if midi.song_data else "")

## 按钮切换回调
func _on_button_toggled(toggled_on: bool) -> void:
	_select(toggled_on)

## 选择动画
func _select(toggled_on: bool) -> void:
	if select_tween and select_tween.is_running():
		select_tween.kill()
	
	select_tween = create_tween()
	select_tween.set_ease(Tween.EASE_IN_OUT)
	select_tween.set_trans(Tween.TRANS_SINE)
	select_tween.set_parallel(true)
	
	if toggled_on:
		# 双击检测：如果已经选中，则触发导航
		if be_selected:
			print("选中：%s / %s" % [get_meta("album"), get_meta("song")])
			var event_bus = EventBus.instance
			if event_bus and midi_data:
				event_bus.emit_midi_selected(midi_data.id, midi_data)
			# 可以在这里触发UI切换（原Global.switch(02)）
			# 现在通过EventBus和UIStateManager处理
		
		# 选中动画
		select_tween.tween_property(self, "scale", Vector2(1.07, 1.07), 0.15)
		if line:
			select_tween.tween_property(line, "default_color", Color("#938aff"), 0.15)
		
		be_selected = 1
		set_selected(true)
	else:
		# 取消选中动画
		select_tween.tween_property(self, "scale", Vector2(1, 1), 0.25)
		if line:
			select_tween.tween_property(line, "default_color", Color("#ffffff"), 0.25)
		
		be_selected = 0
		set_selected(false)

## 选中状态改变时调用
func _on_selected() -> void:
	pass

## 取消选中时调用
func _on_deselected() -> void:
	pass
