extends Control

@onready var ani: AnimationManager = AniMGR

# 轨道分隔线宽度（像素）
const SEPARATOR_WIDTH := 5.0

# 分隔线颜色：轨道之间白色，最左/最右边缘线黄色（突出轨道区域边界）
const SEPARATOR_COLOR := Color(1.0, 1.0, 1.0, 0.6)
const EDGE_SEPARATOR_COLOR := Color(1.0, 0.85, 0.0, 0.9)

var play_view = null

var _beam_height: float = 0
var _beam_padding: int = 0
var _beam_lane_width: float = 0
var _beam_note_width: int = 0
var _key_label_overlay: Control = null
var _beam_alpha_scale: float = 1.0
var _beam_fade_duration_sec: float = 0.4
var _lane_count: int = 0

var _beam_nodes: Array[BeamNode] = []

# 分隔线渐变纹理缓存（同色共用一张，避免每条线各建纹理）
var _sep_tex_cache: Dictionary = {}

# 共享渐变纹理：所有光柱复用相同纹理 RID，无重复 GPU 上传
var _outer_tex: GradientTexture2D
var _center_tex: GradientTexture2D

# 光柱节点：用单个 Node2D + _draw() 替代原先三层 Panel 树，
# 消除 StyleBoxFlat shadow blur 及 Control 布局开销。
# 光效质量固定走 legacy 方案：内容只用两张渐变纹理烤一次（_draw 静态命令），
# 淡出驱动 self_modulate:a —— 引擎（canvas_item.cpp set_self_modulate）只更新渲染期
# alpha，不重跑 _draw()、不重生成绘制命令、无逐帧 shader 开销。
# 相比 shader 模式（每帧 set_shader_parameter("current_time") + 整条轨道高度片段
# shader 逐像素重算）在移动端填充率上省得多，故移除可切换选项、统一此实现。
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
	_beam_nodes.clear()
	_key_label_overlay = null
	play_view = parent_node
	_lane_count = lane_count

	var note_width: int   = play_view.flow_area.note_visual_width
	var padding: int      = play_view.lane_padding
	var window            := get_viewport().get_visible_rect().size
	var beam_h: float     = window.y - play_view.judge_line_offset_y
	# 轨道光效宽度模式 (0=跟随音符宽度, 1=跟随轨道间距)
	var beam_width_mode = ConfigManager.instance.get_int("Appearance", "beam_width_mode", 0)
	var beam_w: float     = note_width + 20.0
	var safe_width: float = max(1.0, window.x - 2.0 * float(padding))
	# 中间间距（键盘模式 + 偶数键位）：从可用宽度中扣除，再在中间插入，保证总宽不超屏幕
	var mid_gap: int = play_view.get_mid_lane_gap()
	var lane_step: float = 0.0
	var lane_start_center_x: float = float(padding) + safe_width * 0.5
	if lane_count > 1:
		lane_start_center_x = float(padding) + beam_w * 0.5
		lane_step = max(0.0, (safe_width - float(mid_gap) - beam_w) / float(lane_count - 1))

	# 当光效宽度模式为跟随轨道间距时，使用轨道间距作为光效宽度
	if beam_width_mode == 1 and lane_step > 0:
		beam_w = lane_step

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
		b.setup(Vector2(beam_w, beam_h), _outer_tex, _center_tex)
		add_child(b)
		var center_x: float = lane_start_center_x + lane_step * i
		# 中间间距：右半侧整体右移（间距已在 lane_step 中扣除，总宽不变，不超出屏幕）
		if mid_gap > 0 and i >= int(lane_count / 2):
			center_x += mid_gap
		b.position = Vector2(center_x - beam_w * 0.5, 0.0)
		_beam_nodes.append(b)

	# 轨道分隔线（仅键盘模式 + 选项开启时生成；init_beam 开头已 free 全部旧子节点 = 自动清理）
	if play_view != null and play_view.get_lane_separator_enabled():
		_create_separator_lines()


## 分隔线布局：
## - 相邻轨道之间：中心距 ≤ 2×标准间距 → 单线（两轨正中，正常画法）；
##   中心距 > 2×标准间距 → 双线（左轨右缘线 + 右轨左缘线，各距轨道中心 lane_step/2）
## - 中间间距（mid_gap）让中间两轨中心距变成 lane_step+mid_gap，因此：
##   mid_gap ≤ lane_step → 单线；mid_gap > lane_step → 双线
## - 最左/最右外框线距轨道中心 lane_step/2（夹取到屏幕内，防止小轨道数越界）
func _create_separator_lines() -> void:
	if _beam_nodes.is_empty():
		return
	# 单轨道：直接框住光束左右缘（两条都是边缘线 → 黄色）
	if _lane_count <= 1:
		_create_separator_line(_beam_nodes[0].position.x, EDGE_SEPARATOR_COLOR)
		_create_separator_line(_beam_nodes[0].position.x + _beam_nodes[0].beam_size.x, EDGE_SEPARATOR_COLOR)
		return

	var sep_half: float = _beam_lane_width * 0.5
	var viewport_x: float = get_viewport().get_visible_rect().size.x
	var right_limit: float = maxf(SEPARATOR_WIDTH * 0.5, viewport_x - SEPARATOR_WIDTH * 0.5)

	# 最左外框：最左轨道左缘（距轨道中心 sep_half，边缘线 → 黄色）
	_create_separator_line(clampf(_center_x_of(_beam_nodes[0]) - sep_half, SEPARATOR_WIDTH * 0.5, right_limit), EDGE_SEPARATOR_COLOR)

	# 相邻轨道之间
	for i in range(_lane_count - 1):
		var a := _beam_nodes[i]
		var b := _beam_nodes[i + 1]
		var ca := _center_x_of(a)
		var cb := _center_x_of(b)
		var spacing := cb - ca
		if spacing <= sep_half * 2.0:
			# 单线：两轨道正中（正常画法，间距未拉开时避免双线贴脸）
			_create_separator_line(ca + spacing * 0.5)
		else:
			# 双线：左轨右缘线 + 右轨左缘线（间距拉开后各归各的）
			_create_separator_line(ca + sep_half, EDGE_SEPARATOR_COLOR)
			_create_separator_line(cb - sep_half, EDGE_SEPARATOR_COLOR)

	# 最右外框：最右轨道右缘（距轨道中心 sep_half，边缘线 → 黄色）
	_create_separator_line(clampf(_center_x_of(_beam_nodes[_lane_count - 1]) + sep_half, SEPARATOR_WIDTH * 0.5, right_limit), EDGE_SEPARATOR_COLOR)


## 轨道光束中心 x（左缘 + 半宽）
func _center_x_of(b: BeamNode) -> float:
	return b.position.x + b.beam_size.x * 0.5


func _create_separator_line(x: float, color: Color = SEPARATOR_COLOR) -> void:
	var line := TextureRect.new()
	line.position = Vector2(x - SEPARATOR_WIDTH * 0.5, 0.0)
	line.size = Vector2(SEPARATOR_WIDTH, _beam_height)
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.texture = _get_separator_tex(color)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)


## 分隔线垂直渐变纹理：底部不透明 → 顶部透明（向上逐渐淡出；同色缓存复用）
func _get_separator_tex(color: Color) -> GradientTexture2D:
	if _sep_tex_cache.has(color):
		return _sep_tex_cache[color]
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(color.r, color.g, color.b, color.a),  # 底部：不透明
		Color(color.r, color.g, color.b, 0.0),      # 顶部：透明
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 1.0)  # 底部
	tex.fill_to   = Vector2(0.0, 0.0)  # 顶部
	_sep_tex_cache[color] = tex
	return tex


func init_key_display(key_map: Array[Key], display_names: Array[String] = []) -> void:
	if _key_label_overlay:
		_key_label_overlay.queue_free()
	_key_label_overlay = Control.new()
	_key_label_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_key_label_overlay)

	# key_map 为空时无需创建任何标签（也避免 label 泄漏）
	if key_map.is_empty():
		return

	var beam_width: float = _beam_note_width + 20.0
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.custom_minimum_size  = Vector2(beam_width, 100)
	label.size = Vector2(beam_width, 100)

	for i in range(key_map.size()):
		var nl: Label = label if i == key_map.size() - 1 else label.duplicate()
		# 优先使用自定义显示名，为空则回退到按键默认名
		var custom_name := display_names[i] if i < display_names.size() else ""
		nl.text = custom_name if not custom_name.is_empty() else OS.get_keycode_string(key_map[i])
		var beam_node: Node2D = get_lane_by_idx(i) as Node2D
		if beam_node == null:
			continue
		var label_x := beam_node.position.x
		_key_label_overlay.add_child(nl)
		nl.position = Vector2(label_x, _beam_height)


func get_lane_by_idx(lane_index: int) -> Node:
	if lane_index < 0 or lane_index >= _beam_nodes.size():
		push_error("[LaneEffect] 指定的轨道编号超出范围")
		return _beam_nodes[lane_index % _beam_nodes.size()]
	return _beam_nodes[lane_index]


func set_beam_alpha(alpha: float) -> void:
	# 淡出起点 alpha：light_lane 里 self_modulate:a 从此值淡到 0（BeamNode 无 per-node 字段）
	_beam_alpha_scale = alpha


# 点亮指定轨道：单次 tween 控制整个 BeamNode 的 self_modulate:a，
# 相比原先三条独立 tween 减少 2/3 的 Tween 对象开销。
func light_lane(lane_index: int, cl: Color = Color.WHITE) -> void:
	var beam_node: BeamNode = get_lane_by_idx(lane_index)
	if beam_node == null:
		return
	beam_node.set_color(Color(cl.r, cl.g, cl.b, 1.0))
	beam_node.visible = true
	beam_node.self_modulate.a = _beam_alpha_scale
	var tween := ani._create_tween("lane_beam_%d" % lane_index)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(beam_node, "self_modulate:a", 0.0, _beam_fade_duration_sec)
	tween.finished.connect(func():
		if (beam_node):
			beam_node.visible = false
	)
