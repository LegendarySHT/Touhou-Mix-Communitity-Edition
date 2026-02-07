extends Control

@onready var beam: Resource = load("res://UI/Views/PlayView/beam.tscn")
@onready var ani: AnimationManager = AnimationManager.instance

func init_beam(lane_count: int, note_width: float, judge_line_offset_y: float):
	for i in get_children():
		i.queue_free()
	
	var window = get_viewport().get_visible_rect().size
	var beam_h = window.y - judge_line_offset_y
	
	print(beam_h)
	for i in range(lane_count):
		var b = beam.instantiate()
		add_child(b)
		b.set_meta("index", i)
		b.visible = false
		
		b.set_deferred("size", Vector2(note_width + 20, beam_h))
		var anchor_delta = 25 / (note_width + 20)
		b.get_node("Center").anchor_left = anchor_delta
		b.get_node("Center").anchor_right = 1 - anchor_delta
		var lane_width = window.x / lane_count
		b.set_deferred("position", Vector2(lane_width * i + (lane_width - note_width - 20)/2, 0))

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

func light_lane(lane_index: int, cl: Color):
	var node = get_children().filter(func(ch):
		if not ch.has_meta("index"):
			return false
		
		if ch.get_meta("index") == lane_index:
			return true
	)
	node = node[0]
	
	# 颜色
	var style: StyleBox = node.get_node("Center").get_theme_stylebox("panel")
	var node_cl = style.texture.gradient.colors
	style.texture.gradient.colors = [Color(cl.r, cl.g, cl.b, node_cl[0].a), Color(cl.r, cl.g, cl.b, node_cl[1].a)]
	
	# 淡出
	node.modulate.a = 1
	node.visible = true
	ani.animate_fade_out(node, 1, "lane_%d_beam" % lane_index)
	
	
