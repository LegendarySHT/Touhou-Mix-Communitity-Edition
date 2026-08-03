extends Node2D
class_name NoteBatchDrawer

## Block/Slide 音符批量绘制器
## 用单个 Node2D + _draw() 替代 N 个 TextureRect Control 节点
## 消除 Control 布局 / offset_transform / size 重算开销
## Long 音符仍走 Control 对象池（结构复杂，同屏数量少）

# 贴图引用（由 FlowArea.set_note_texture 同步）
var _block_tex: Texture2D = null
var _block_core_tex: Texture2D = null
var _slide_tex: Texture2D = null
var _slide_core_tex: Texture2D = null

# 颜色（由 FlowArea.set_note_color / refresh_note_colors 同步）
# _block_color / _slide_color = 用户设置的 modulate 颜色（GlowLayer 也用此值）
var _block_color: Color = Color.WHITE
var _slide_color: Color = Color.WHITE
# self_modulate 提亮系数（对应 tscn 中 core 节点的 self_modulate，通常 Color(2,2,2,1)）
# _draw core 贴图时用 color * self_modulate 还原旧 Control 路径的提亮效果
var _block_self_modulate: Color = Color.WHITE
var _slide_self_modulate: Color = Color.WHITE

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

## 同步 core 节点的 self_modulate 提亮系数（从 tscn 模板读取）
func set_self_modulates(block_sm: Color, slide_sm: Color) -> void:
	_block_self_modulate = block_sm
	_slide_self_modulate = slide_sm

func set_colors(block_color: Color, slide_color: Color) -> void:
	_block_color = block_color
	_slide_color = slide_color

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


# ========== 内部实现 ==========

func _recompute_heights() -> void:
	_block_half_height = _compute_half_height(_block_tex)
	_slide_half_height = _compute_half_height(_slide_tex)

func _compute_half_height(tex: Texture2D) -> float:
	if tex == null or tex.get_width() <= 0:
		return _note_width * 0.5
	return _note_width * (float(tex.get_height()) / float(tex.get_width())) * 0.5

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

	# 第一遍：所有外层贴图（short / instant）
	for note in _notes:
		if note.is_judged or note.is_removed:
			continue
		var cy = note.cached_center_y
		var half_h = note.cached_half_height
		if cy + half_h < top_limit or cy - half_h > bottom_limit:
			continue
		var is_slide = note.type == FlowNote.NoteType.Slide
		var tex = _slide_tex if is_slide else _block_tex
		var rect = Rect2(note.cached_x, cy - half_h, _note_width, half_h * 2.0)
		draw_texture_rect(tex, rect, false)

	# 第二遍：所有 core 贴图（modulate by resolved color * self_modulate）
	for note in _notes:
		if note.is_judged or note.is_removed:
			continue
		var cy = note.cached_center_y
		var half_h = note.cached_half_height
		if cy + half_h < top_limit or cy - half_h > bottom_limit:
			continue
		var is_slide = note.type == FlowNote.NoteType.Slide
		var tex = _slide_core_tex if is_slide else _block_core_tex
		# 还原旧 Control 路径: 最终颜色 = texture * modulate * self_modulate
		var color = (_slide_color * _slide_self_modulate) if is_slide else (_block_color * _block_self_modulate)
		var rect = Rect2(note.cached_x, cy - half_h, _note_width, half_h * 2.0)
		draw_texture_rect(tex, rect, false, color)
