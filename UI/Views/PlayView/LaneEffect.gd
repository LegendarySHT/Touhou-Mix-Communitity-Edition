extends Control

# 这个beam除了用来搞光效，按键显示及音符生成也需要它
@onready var beam = load("res://UI/Views/PlayView/beam.tscn").instantiate()
@onready var ani: AnimationManager = AnimationManager.instance

var play_view = null

# 存储 beam 布局参数，供 init_key_display 在 overlay 中独立定位标签
var _beam_height: float = 0
var _beam_padding: int = 0
var _beam_lane_width: float = 0
var _beam_note_width: int = 0
# 键盘按键标签的独立 overlay，不作为 beam 子节点，避免 beam visible=false 时将标签一起隐藏
var _key_label_overlay: Control = null
# 光柱峰值亮度缩放（由 set_beam_alpha 写入，light_lane 动画时读取）
var _beam_alpha_scale: float = 1.0

func init_beam(lane_count: int, parent_node):
	for i in get_children():
		i.free()
	_key_label_overlay = null
	play_view = parent_node

	var note_width = play_view.flow_area.note_visual_width
	var padding = play_view.lane_padding

	var window = get_viewport().get_visible_rect().size
	var beam_h = window.y - play_view.judge_line_offset_y
	
	beam.size = Vector2(note_width + 20, beam_h)
	beam.self_modulate.a = 0
	beam.get_node("Center").self_modulate.a = 0

	beam.get_node("Light").self_modulate.a = 0
	var lane_width = (window.x - 2*padding) / lane_count

	# 存储布局数据供 init_key_display 使用
	_beam_height = beam_h
	_beam_padding = padding
	_beam_lane_width = lane_width
	_beam_note_width = note_width

	for i in range(lane_count):
		var b: Panel = beam.duplicate()
		
		# 唯一化stylebox
		var style = beam.get_node("Center").get_theme_stylebox("panel").duplicate(true)
		b.get_node("Center").add_theme_stylebox_override("panel", style)

		add_child(b)
		# 默认隐藏，仅在 light_lane 触发时显示，避免 GPU 对透明全屏节点的无效填充
		b.visible = false

		b.set_meta("index", i)
				
		b.set_deferred("position", Vector2(padding + lane_width * i + (lane_width - note_width - 20)/2, 0))

func init_key_display(key_map: Array[Key]):
	# 使用独立 overlay 存放按键标签，避免随 beam visible=false 被一同隐藏
	if _key_label_overlay:
		_key_label_overlay.queue_free()
	_key_label_overlay = Control.new()
	_key_label_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_key_label_overlay)

	var beam_width: float = _beam_note_width + 20  # 与 beam.size.x 一致
	var label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.custom_minimum_size = Vector2(beam_width, 100)

	for i in range(key_map.size()):
		var nl = label
		if i < key_map.size() - 1:
			nl = label.duplicate()
		
		nl.text = OS.get_keycode_string(key_map[i])
		# 直接计算在 LaneEffect 坐标系中的位置，与 beam 节点位置公式相同
		var label_x: float = _beam_padding + _beam_lane_width * i + (_beam_lane_width - beam_width) / 2
		_key_label_overlay.add_child(nl)
		nl.position = Vector2(label_x, _beam_height)


func get_lane_by_idx(lane_index: int) -> Node:
	return get_children().filter(func(ch):
		if not ch.has_meta("index") or ch.get_meta("index") != lane_index:
			return false
		return true
	)[0]

# 更改光柱峰值亮度（在 light_lane 动画时生效）
# 不直接修改 GradientTexture2D.gradient.colors，避免每次调用触发 GPU 纹理重传
func set_beam_alpha(alpha: float):
	_beam_alpha_scale = alpha

# 点亮指定轨道
func light_lane(lane_index: int, cl: Color = 0):
	var beam_node: Panel = get_lane_by_idx(lane_index)
	
	# 用 modulate（仅影响自身，白色 gradient 乘以 cl 即得目标色）替代直接修改
	# GradientTexture2D.gradient.colors，避免每次按键触发 GPU 纹理重传
	var center_node: Panel = beam_node.get_node("Center")
	center_node.modulate = Color(cl.r, cl.g, cl.b, 1.0)
	
	# 淡出前先设为可见，动画结束后隐藏（避免透明节点持续占用 GPU 填充率）
	beam_node.visible = true
	beam_node.self_modulate.a = _beam_alpha_scale
	var tween = ani._create_tween("lane_beam_%d" % lane_index)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(beam_node, "self_modulate:a", 0.0, 1)
	tween.finished.connect(func(): beam_node.visible = false)
	
	center_node.self_modulate.a = _beam_alpha_scale
	tween = ani._create_tween("lane_beam_center_%d" % lane_index)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(center_node, "self_modulate:a", 0.0, 1)

	var light_node: Panel = beam_node.get_node("Light")
	light_node.self_modulate.a = 1
	tween = ani._create_tween("lane_light_center_%d" % lane_index)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(light_node, "self_modulate:a", 0.0, 1)
