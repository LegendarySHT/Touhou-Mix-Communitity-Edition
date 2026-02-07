extends Control

@onready var beam = load("res://UI/Views/PlayView/beam.tscn").instantiate()
@onready var ani: AnimationManager = AnimationManager.instance

func init_beam(lane_count: int, note_width: float, judge_line_offset_y: float):
	for i in get_children():
		i.free()
	
	var window = get_viewport().get_visible_rect().size
	var beam_h = window.y - judge_line_offset_y
	var anchor_delta = 25 / (note_width + 20)
	
	beam.size = Vector2(note_width + 20, beam_h)
	beam.get_node("Center").anchor_left = anchor_delta
	beam.get_node("Center").anchor_right = 1 - anchor_delta
	beam.self_modulate.a = 0
	beam.get_node("Center").self_modulate.a = 0

	for i in range(lane_count):
		var b: Panel = beam.duplicate()
		
		# 唯一化stylebox
		var style = beam.get_node("Center").get_theme_stylebox("panel").duplicate(true)
		b.get_node("Center").add_theme_stylebox_override("panel", style)

		add_child(b)

		b.set_meta("index", i)
				
		var lane_width = window.x / lane_count
		b.set_deferred("position", Vector2(lane_width * i + (lane_width - note_width - 20)/2, 0))

func init_key_display(key_map: Array[Key]):
	var label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.custom_minimum_size = Vector2(_get_child_by_idx(0).size.x, 100)

	for i in range(key_map.size()):
		var nl = label
		if i < key_map.size() - 1:
			nl = label.duplicate()
		
		nl.text = OS.get_keycode_string(key_map[i])
		var b = _get_child_by_idx(i)
		b.add_child(nl)
		nl.position.y = b.size.y


func _get_child_by_idx(lane_index: int) -> Node:
	return get_children().filter(func(ch):
		if not ch.has_meta("index") or ch.get_meta("index") != lane_index:
			return false
		return true
	)[0]

# 更改光柱不透明度
func set_beam_alpha(alpha: float):
	for node in get_children():
		if not node.has_meta("index"):
			continue
		# 外围	
		var style = node.get_theme_stylebox("panel")
		style.texture.gradient.colors[0].a = alpha * 0.23
		style.texture.gradient.colors[1].a = alpha * 0.05
		
		# 中心
		style = node.get_node("Center").get_theme_stylebox("panel")
		style.texture.gradient.colors[0].a = alpha * 0.8
		style.texture.gradient.colors[1].a = alpha * 0.467

# 点亮指定轨道
func light_lane(lane_index: int, cl: Color = 0):
	var node = _get_child_by_idx(lane_index)
	
	# 颜色
	if cl:
		var style: StyleBox = node.get_node("Center").get_theme_stylebox("panel")
		var node_cl = style.texture.gradient.colors
		style.texture.gradient.colors = [Color(cl.r, cl.g, cl.b, node_cl[0].a), Color(cl.r, cl.g, cl.b, node_cl[1].a)]
	
	# 淡出
	node.self_modulate.a = 1
	var tween = ani._create_tween("lane_beam_%d" % lane_index)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(node, "self_modulate:a", 0.0, 1)
	
	node = node.get_node("Center")
	node.self_modulate.a = 1
	tween = ani._create_tween("lane_beam_center_%d" % lane_index)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(node, "self_modulate:a", 0.0, 1)
