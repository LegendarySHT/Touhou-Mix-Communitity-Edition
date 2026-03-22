extends Control

@onready var ani: AnimationManager = AnimationManager.instance

var play_view = null

var _beam_height: float = 0
var _beam_padding: int = 0
var _beam_lane_width: float = 0
var _beam_note_width: int = 0
var _key_label_overlay: Control = null
var _beam_alpha_scale: float = 1.0

# 共享渐变纹理：所有光柱复用相同纹理 RID，无重复 GPU 上传
var _outer_tex: GradientTexture2D
var _center_tex: GradientTexture2D

# 光柱节点：用单个 Node2D + _draw() 替代原先三层 Panel 树，
# 消除 StyleBoxFlat shadow blur 及 Control 布局开销。
class BeamNode extends Node2D:
	var lane_color: Color = Color.WHITE
	var beam_size: Vector2 = Vector2.ZERO
	var _outer_tex: GradientTexture2D
	var _center_tex: GradientTexture2D

	const CENTER_INSET := 20.0
	const LIGHT_H := 3.0

	func setup(sz: Vector2, outer: GradientTexture2D, center: GradientTexture2D) -> void:
		beam_size = sz
		_outer_tex = outer
		_center_tex = center
		queue_redraw()

	func set_color(cl: Color) -> void:
		lane_color = cl
		queue_redraw()

	func _draw() -> void:
		if beam_size == Vector2.ZERO:
			return
		# 外层白色渐变光柱
		if _outer_tex:
			draw_texture_rect(_outer_tex, Rect2(Vector2.ZERO, beam_size), false)
		# 内层着色渐变光柱
		if _center_tex:
			draw_texture_rect(
				_center_tex,
				Rect2(Vector2(CENTER_INSET, 0.0),
					  Vector2(beam_size.x - CENTER_INSET * 2.0, beam_size.y)),
				false, lane_color
			)
		# 底部高亮横条，用纯色矩形代替原 StyleBoxFlat shadow（无 GPU 模糊开销）
		draw_rect(Rect2(0.0, beam_size.y - LIGHT_H, beam_size.x, LIGHT_H),
				  Color(2.0, 2.0, 2.0, 0.9))


func _make_gradient_tex(c_bottom: Color, c_top: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	grad.colors = PackedColorArray([c_bottom, c_top])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 1.0)
	tex.fill_to   = Vector2(0.0, 0.0)
	return tex


func init_beam(lane_count: int, parent_node) -> void:
	for ch in get_children():
		ch.free()
	_key_label_overlay = null
	play_view = parent_node

	var note_width: int   = play_view.flow_area.note_visual_width
	var padding: int      = play_view.lane_padding
	var window            := get_viewport().get_visible_rect().size
	var beam_h: float     = window.y - play_view.judge_line_offset_y
	var beam_w: float     = note_width + 20.0
	var safe_width: float = max(1.0, window.x - 2.0 * float(padding))
	var lane_step: float = 0.0
	var lane_start_center_x: float = float(padding) + safe_width * 0.5
	if lane_count > 1:
		lane_start_center_x = float(padding) + beam_w * 0.5
		lane_step = max(0.0, (safe_width - beam_w) / float(lane_count - 1))

	_beam_height     = beam_h
	_beam_padding    = padding
	_beam_lane_width = lane_step
	_beam_note_width = note_width

	# 与 beam.tscn 的渐变参数保持一致
	_outer_tex  = _make_gradient_tex(Color(1.0, 1.0, 1.0, 0.235), Color(0.754, 0.754, 0.754, 0.055))
	_center_tex = _make_gradient_tex(Color(1.0, 1.0, 1.0, 0.800), Color(1.0,   1.0,   1.0,   0.467))

	for i in range(lane_count):
		var b := BeamNode.new()
		b.set_meta("index", i)
		b.visible = false
		add_child(b)
		b.setup(Vector2(beam_w, beam_h), _outer_tex, _center_tex)
		var center_x: float = lane_start_center_x + lane_step * i
		b.position = Vector2(
			center_x - beam_w * 0.5,
			0.0
		)


func init_key_display(key_map: Array[Key]) -> void:
	if _key_label_overlay:
		_key_label_overlay.queue_free()
	_key_label_overlay = Control.new()
	_key_label_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_key_label_overlay)

	var beam_width: float = _beam_note_width + 20.0
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.custom_minimum_size  = Vector2(beam_width, 100)

	for i in range(key_map.size()):
		var nl: Label = label if i == key_map.size() - 1 else label.duplicate()
		nl.text = OS.get_keycode_string(key_map[i])
		var beam_node: Node2D = get_lane_by_idx(i) as Node2D
		var label_x := beam_node.position.x
		_key_label_overlay.add_child(nl)
		nl.position = Vector2(label_x, _beam_height)


func get_lane_by_idx(lane_index: int) -> Node:
	return get_children().filter(func(ch):
		return ch.has_meta("index") and ch.get_meta("index") == lane_index
	)[0]


func set_beam_alpha(alpha: float) -> void:
	_beam_alpha_scale = alpha


# 点亮指定轨道：单次 tween 控制整个 BeamNode 的 self_modulate:a，
# 相比原先三条独立 tween 减少 2/3 的 Tween 对象开销。
func light_lane(lane_index: int, cl: Color = Color.WHITE) -> void:
	var beam_node: BeamNode = get_lane_by_idx(lane_index)
	beam_node.set_color(Color(cl.r, cl.g, cl.b, 1.0))
	beam_node.visible = true
	beam_node.self_modulate.a = _beam_alpha_scale
	var tween := ani._create_tween("lane_beam_%d" % lane_index)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(beam_node, "self_modulate:a", 0.0, 0.4)
	tween.finished.connect(func(): beam_node.visible = false)
