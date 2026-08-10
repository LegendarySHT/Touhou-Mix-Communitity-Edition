extends Node2D
class_name NoteBatchDrawer

## Block/Slide/Long 音符批量绘制器
## 用单个 Node2D + _draw() 替代 N 个 TextureRect Control 节点
## 消除 Control 布局 / offset_transform / size 重算开销

# 贴图引用（由 FlowArea.set_note_texture 同步）
var _block_tex: Texture2D = null
var _block_core_tex: Texture2D = null
var _slide_tex: Texture2D = null
var _slide_core_tex: Texture2D = null

# Long 长条贴图（head=long_b 头部 / body=long_f 中部 / tail=long_t 尾部）
var _long_head_tex: Texture2D = null
var _long_head_core_tex: Texture2D = null
var _long_body_tex: Texture2D = null
var _long_body_core_tex: Texture2D = null
var _long_tail_tex: Texture2D = null
var _long_tail_core_tex: Texture2D = null

# 每音符颜色由 FlowArea 在 _spawn_note 时写入 note.cached_color，_draw 直接用，无全局颜色字段

# 光效
var _glow_tex: Texture2D = null       # 程序预烘焙的白色 glow 纹理
var _glow_enabled: bool = false
var _glow_intensity: float = 1.0
var _glow_size: float = 20.0
var _glow_layer: Node2D = null        # 加色混合子层

# 光效高斯峰值：加色混合逐通道相加，峰值 ≥0.5 时两个相同颜色的光效叠加就达 1.0（白）
# 0.45 保证两个光效叠加不超过 0.9，不白但接近白；调高更亮更易白，调低更压白
const GLOW_PEAK := 0.45

# 音符尺寸
var _note_width: float = 100.0
var _block_half_height: float = 50.0
var _slide_half_height: float = 50.0
# Long 头/尾半高（按贴图宽高比计算）与 body 贴图原始高度（repeat 分条用）
var _long_head_half_height: float = 50.0
var _long_tail_half_height: float = 50.0
var _long_body_tex_height: float = 50.0
var _long_body_core_tex_height: float = 50.0  # core body 贴图原始高度（与 base 可能不同）
# body 中部贴图应用方式："repeat"（水平拉伸+垂直重复）或 "stretch"（竖直拉伸）
var _long_body_mode: String = "repeat"

# 渲染裁剪参数（与 FlowArea._note_cull_margin_* 对齐）
var _cull_margin_top: float = 120.0
var _cull_margin_bottom: float = 180.0
var _viewport_height: float = 0.0

# 活跃音符列表（FlowArea.add_note / remove_note 维护）
var _notes: Array = []

# 透明纹理回退（贴图缺失时）
var _transparent_tex: Texture2D = null


func _ready() -> void:
	_transparent_tex = _create_transparent_texture()
	_bake_glow_texture()
	_setup_glow_layer()


# ========== 公共 API ==========

func add_note(note) -> void:
	_notes.append(note)

func remove_note(note) -> void:
	_notes.erase(note)
	# 立即触发重绘，确保判定后画面立即清除该音符
	# 不依赖外部 _process 的 request_redraw（输入事件触发的判定与 _process 不同步）
	queue_redraw()
	if _glow_layer:
		_glow_layer.queue_redraw()

func clear() -> void:
	_notes.clear()
	# 清空后必须触发重绘，否则最后一帧画面残留
	queue_redraw()
	if _glow_layer:
		_glow_layer.queue_redraw()

func request_redraw() -> void:
	queue_redraw()
	if _glow_layer:
		_glow_layer.queue_redraw()

func set_textures(block_tex: Texture2D, block_core_tex: Texture2D,
		slide_tex: Texture2D, slide_core_tex: Texture2D) -> void:
	_block_tex = block_tex if block_tex else _transparent_tex
	_block_core_tex = block_core_tex if block_core_tex else _transparent_tex
	_slide_tex = slide_tex if slide_tex else _transparent_tex
	_slide_core_tex = slide_core_tex if slide_core_tex else _transparent_tex
	_recompute_heights()

## 同步 Long 长条贴图（head=long_b 头部 / body=long_f 中部 / tail=long_t 尾部）
func set_long_textures(head_tex: Texture2D, head_core_tex: Texture2D,
		body_tex: Texture2D, body_core_tex: Texture2D,
		tail_tex: Texture2D, tail_core_tex: Texture2D) -> void:
	_long_head_tex = head_tex if head_tex else _transparent_tex
	_long_head_core_tex = head_core_tex if head_core_tex else _transparent_tex
	_long_body_tex = body_tex if body_tex else _transparent_tex
	_long_body_core_tex = body_core_tex if body_core_tex else _transparent_tex
	_long_tail_tex = tail_tex if tail_tex else _transparent_tex
	_long_tail_core_tex = tail_core_tex if tail_core_tex else _transparent_tex
	_recompute_heights()

## 设置 body 中部贴图应用方式（"repeat" / "stretch"）
func set_long_body_mode(mode: String) -> void:
	_long_body_mode = mode

## Long 头/尾半高（spawn 时由 FlowArea 读取）
func get_long_head_half_height() -> float:
	return _long_head_half_height

func get_long_tail_half_height() -> float:
	return _long_tail_half_height

func set_note_width(wid: float) -> void:
	_note_width = wid
	_recompute_heights()

func set_cull_margins(top: float, bottom: float) -> void:
	_cull_margin_top = top
	_cull_margin_bottom = bottom

func set_viewport_height(h: float) -> void:
	_viewport_height = h

func set_glow_enabled(enabled: bool) -> void:
	_glow_enabled = enabled
	if _glow_layer:
		_glow_layer.visible = enabled

func set_glow_params(intensity: float, size_val: float) -> void:
	var new_intensity = clampf(intensity, 0.0, 2.0)
	var new_size = clampf(size_val, 1.0, 30.0)
	if not is_equal_approx(new_size, _glow_size):
		_glow_size = new_size
		_bake_glow_texture()
	_glow_intensity = new_intensity

func get_half_height(note_type: int) -> float:
	# FlowNote.NoteType: Block=0, Slide=1, Long=2
	if note_type == FlowNote.NoteType.Slide:
		return _slide_half_height
	return _block_half_height

## 所有类型音符中的最大半高（FlowArea 计算 _note_max_size_y 用）
func get_max_half_height() -> float:
	return maxf(maxf(_block_half_height, _slide_half_height), maxf(_long_head_half_height, _long_tail_half_height))


# ========== 内部实现 ==========

func _recompute_heights() -> void:
	_block_half_height = _compute_half_height(_block_tex)
	_slide_half_height = _compute_half_height(_slide_tex)
	_long_head_half_height = _compute_half_height(_long_head_tex)
	_long_tail_half_height = _compute_half_height(_long_tail_tex)
	_long_body_tex_height = _compute_tex_height(_long_body_tex)
	_long_body_core_tex_height = _compute_tex_height(_long_body_core_tex)

func _compute_half_height(tex: Texture2D) -> float:
	if tex == null or tex.get_width() <= 0:
		return _note_width * 0.5
	return _note_width * (float(tex.get_height()) / float(tex.get_width())) * 0.5

func _compute_tex_height(tex: Texture2D) -> float:
	# body 贴图原始高度：repeat 分条重复的单位高度；缺失时退化为 note_width（v_repeat=1）
	if tex == null or tex.get_height() <= 0:
		return _note_width
	return float(tex.get_height())

func _create_transparent_texture(size: int = 64) -> Texture2D:
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)

## 程序烘焙白色 glow 纹理
## 高斯径向衰减 exp(-(dist/σ)²)：中心亮、向外平滑衰减、到纹理边缘约 0，无可见圆形边界
## σ 由 _glow_size 映射（1~30 → σ 0.6~1.5，音符半高单位），最大时衰减仍在纹理内结束，不裁边
## 峰值 GLOW_PEAK 直接烤入：保持高斯平滑形状（无平台），加色叠加也不易爆白
func _bake_glow_texture() -> void:
	var size = 128
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = size * 0.5
	var note_half = size / 6.0  # note_uv_half = 0.1667 ≈ 1/6（dist 单位：音符半高）
	var sigma = 0.6 + _glow_size * (1.5 - 0.6) / 30.0
	for y in range(size):
		for x in range(size):
			var nx = (x - center) / note_half
			var ny = (y - center) / note_half
			var dist = sqrt(nx * nx + ny * ny)
			var glow = GLOW_PEAK * exp(-dist * dist / (sigma * sigma))
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(glow, 0.0, 1.0)))
	_glow_tex = ImageTexture.create_from_image(img)

func _setup_glow_layer() -> void:
	if _glow_layer:
		return
	_glow_layer = Node2D.new()
	_glow_layer.name = "GlowLayer"
	_glow_layer.z_index = -1
	_glow_layer.visible = _glow_enabled
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_layer.material = mat
	# 用 script 注入 _draw 逻辑（直接读 parent 字段，避免数据同步）
	_glow_layer.set_script(preload("res://UI/Views/PlayView/GlowLayer.gd"))
	_glow_layer._drawer = self
	add_child(_glow_layer)

func _draw() -> void:
	if _notes.is_empty():
		return
	var view_h = _viewport_height
	var top_limit = -_cull_margin_top
	var bottom_limit = view_h + _cull_margin_bottom

	# 绘制音符贴图（short / instant / long）
	# 只跳过已移除音符：Long 被按住时 is_judged=true 但仍需显示，不能按 is_judged 跳过
	for note in _notes:
		if note.is_removed:
			continue
		if note.type == FlowNote.NoteType.Long:
			_draw_long_note(note, top_limit, bottom_limit)
			continue
		var cy = note.cached_center_y
		var half_h = note.cached_half_height
		if cy + half_h < top_limit or cy - half_h > bottom_limit:
			continue
		var is_slide = note.type == FlowNote.NoteType.Slide
		var tex = _slide_tex if is_slide else _block_tex
		var core_tex = _slide_core_tex if is_slide else _block_core_tex
		var color = note.cached_color  # core 上色区直接按音符颜色上色（模板 core 无 self_modulate，无需提亮通道）

		var rect = Rect2(note.cached_x, cy - half_h, _note_width, half_h * 2.0)
		draw_texture_rect(tex, rect, false)
		draw_texture_rect(core_tex, rect, false, color)

## 批量绘制 Long 长条：绘制顺序 body → tail → head（头尾盖在 body 上）
func _draw_long_note(note, top_limit: float, bottom_limit: float) -> void:
	var x: float = note.cached_x
	var head_cy: float = note.cached_head_center_y
	var tail_cy: float = note.cached_tail_center_y
	var head_half: float = note.cached_head_half_height
	var tail_half: float = note.cached_tail_half_height
	var color: Color = note.cached_color

	# 1) body（长条连接部分）先绘
	var body_top: float = note.cached_body_top_y
	var body_h: float = note.cached_body_height
	if body_h > 0.0 and body_top + body_h >= top_limit and body_top <= bottom_limit:
		var body_rect := Rect2(x, body_top, _note_width, body_h)
		if _long_body_mode == "repeat":
			_draw_long_body_repeat(_long_body_tex, body_rect)
			_draw_long_body_repeat(_long_body_core_tex, body_rect, color, _long_body_core_tex_height)
		else:
			# stretch：整体竖直拉伸
			draw_texture_rect(_long_body_tex, body_rect, false)
			draw_texture_rect(_long_body_core_tex, body_rect, false, color)

	# 2) tail（尾部）
	if tail_cy + tail_half >= top_limit and tail_cy - tail_half <= bottom_limit:
		var tail_rect := Rect2(x, tail_cy - tail_half, _note_width, tail_half * 2.0)
		draw_texture_rect(_long_tail_tex, tail_rect, false)
		draw_texture_rect(_long_tail_core_tex, tail_rect, false, color)

	# 3) head（头部最后绘，盖在 body 上）
	if head_cy + head_half >= top_limit and head_cy - head_half <= bottom_limit:
		var head_rect := Rect2(x, head_cy - head_half, _note_width, head_half * 2.0)
		draw_texture_rect(_long_head_tex, head_rect, false)
		draw_texture_rect(_long_head_core_tex, head_rect, false, color)

## repeat 模式下分条绘制 body：水平拉伸（0-1），垂直按贴图原始高度逐条重复
## 最后一条不足贴图高度时只取贴图顶部剩余部分（与 LongBodyRepeat shader 的 fract(UV.y*v_repeat) 一致）
## tex_height 缺省用 base body 高度；core 贴图高度不同时单独传入
func _draw_long_body_repeat(tex: Texture2D, rect: Rect2, color: Color = Color.WHITE, tex_height: float = -1.0) -> void:
	var tex_h := tex_height if tex_height > 0.0 else _long_body_tex_height
	if tex_h <= 0.0:
		draw_texture_rect(tex, rect, false, color)
		return
	var tex_w := tex.get_width()
	var top := rect.position.y
	var remain := rect.size.y
	var guard := 0
	while remain > 0.01:
		var h := minf(tex_h, remain)
		draw_texture_rect_region(tex,
			Rect2(rect.position.x, top, rect.size.x, h),
			Rect2(0, 0, tex_w, h),
			color)
		top += h
		remain -= h
		guard += 1
		if guard > 256:
			break
