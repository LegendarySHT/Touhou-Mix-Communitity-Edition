## MIDI列表项组件
## 继承自 ListItemBase，显示MIDI谱面信息
extends ListItemBase

## 引用节点
@onready var status_label: Label = $MC/MC/status if has_node("MC/MC/status") else null
@onready var midi_name_label: Label = $MC/VBox/MidiName if has_node("MC/VBox/MidiName") else null
@onready var author_label: Label = $MC/VBox/Author if has_node("MC/VBox/Author") else null
@onready var button: Button = $Button if has_node("Button") else null
@onready var vbox: VBoxContainer = $MC/VBox if has_node("MC/VBox") else null
@onready var line: Line2D = $MC/VBox/Line2D if has_node("MC/VBox/Line2D") else null
@onready var margin_container: MarginContainer = $MC if has_node("MC") else null

## MIDI数据
var midi_data: MidiData

## 展开动画补间
var expand_tween: Tween

## 吸附目标信号（用于滚动吸附）
signal snap_target(midi_node)

func _ready() -> void:
	# 连接按钮信号
	if button:
		button.toggled.connect(_on_button_toggled)

## 从MidiData初始化显示
func setup_with_midi(midi: MidiData, index: int = 0) -> void:
	midi_data = midi
	item_id = midi.id
	item_type = "midi"
	
	# 更新显示
	if status_label:
		status_label.text = midi.status
	
	if midi_name_label:
		midi_name_label.text = midi.name
	
	if author_label:
		author_label.text = midi.artist_name if not midi.artist_name.is_empty() else "Unknown"
	
	if button:
		button.set_meta("index", index)
	
	# 设置元数据（用于其他系统访问）
	set_meta("index", index)
	set_meta("name", midi.name)
	set_meta("trialCount", midi.trial_count)
	set_meta("upCount", midi.up_count)
	set_meta("avgAccuracy", midi.avg_accuracy)

## 按钮切换回调
func _on_button_toggled(toggled_on: bool) -> void:
	if expand_tween and expand_tween.is_running():
		expand_tween.kill()
	
	expand_tween = create_tween()
	expand_tween.set_ease(Tween.EASE_OUT)
	expand_tween.set_trans(Tween.TRANS_QUINT)
	expand_tween.set_parallel(true)
	
	var indicator = get_node_or_null("/root/Main/InfoUI/Right/Right/Indicator")
	var index = get_meta("index", 0)
	
	if toggled_on:
		print("select: ", get_meta("name"))
		
		# 展开动画
		_animate_expand(expand_tween)
		
		# 指示器动画
		if indicator and index < indicator.get_child_count():
			expand_tween.tween_property(indicator.get_child(index), "color", Color(0.129, 0.412, 0.702), 0.15)
			expand_tween.tween_property(indicator, "position", Vector2(186.9, 214 - (index + 1) * 20 - index * 9), 0.35)
		
		# 读取并显示数据
		_update_info_panel()
		
		# 发射吸附信号和选中信号
		snap_target.emit(self)
		set_selected(true)
	else:
		# 收起动画
		_animate_collapse(expand_tween)
		
		# 恢复指示器颜色
		if indicator and index < indicator.get_child_count():
			expand_tween.tween_property(indicator.get_child(index), "color", Color(1, 1, 1), 0.15)
		
		set_selected(false)

## 展开动画
func _animate_expand(tween: Tween) -> void:
	tween.tween_property(self, "custom_minimum_size", Vector2(900, 500), 0.5)
	
	if margin_container:
		tween.tween_property(margin_container, "theme_override_constants/margin_bottom", 120, 0.15)
	
	if midi_name_label:
		tween.tween_property(midi_name_label, "theme_override_font_sizes/font_size", 40, 0.25)
	
	if vbox:
		tween.tween_property(vbox, "theme_override_constants/separation", 30, 0.15)
	
	if line:
		tween.tween_property(line, "position", Vector2(-135, 22), 0.15)

## 收起动画
func _animate_collapse(tween: Tween) -> void:
	tween.tween_property(self, "custom_minimum_size", Vector2(900, 150), 0.5)
	
	if margin_container:
		tween.tween_property(margin_container, "theme_override_constants/margin_bottom", 10, 0.15)
	
	if midi_name_label:
		tween.tween_property(midi_name_label, "theme_override_font_sizes/font_size", 30, 0.5)
	
	if vbox:
		tween.tween_property(vbox, "theme_override_constants/separation", 0, 0.5)
	
	if line:
		tween.tween_property(line, "position", Vector2(-135, -10), 0.15)

## 更新信息面板
func _update_info_panel() -> void:
	var info_node = get_node_or_null("/root/Main/InfoUI/Status/Panel/GC")
	if info_node:
		var trial_count = get_meta("trialCount", 0)
		var up_count = get_meta("upCount", 0)
		var avg_accuracy = get_meta("avgAccuracy", 0.0)
		
		print("Read: ", trial_count, up_count, avg_accuracy)
		
		if info_node.has_node("Play/Label"):
			info_node.get_node("Play/Label").text = "%d" % trial_count
		
		if info_node.has_node("UpCount/Label"):
			info_node.get_node("UpCount/Label").text = "%d" % up_count
		
		if info_node.has_node("AvgAcc/Label"):
			info_node.get_node("AvgAcc/Label").text = "%.2f" % avg_accuracy

## 选中状态改变时调用
func _on_selected() -> void:
	pass

## 取消选中时调用
func _on_deselected() -> void:
	pass
