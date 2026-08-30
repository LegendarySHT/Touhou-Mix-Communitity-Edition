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
# 加色混合子层（PlayView.tscn 预挂节点：GlowLayer.gd，z_index=-1 保证在音符之下、背景之上）
@onready var _glow_layer: GlowLayer = $GlowLayer

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
# body 中部贴图应用方式："repeat"（水平拉伸+垂直重复）或 "stretch"（竖直拉伸）
var _long_body_mode: String = "repeat"

# 渲染裁剪参数（与 FlowArea._note_cull_margin_* 对齐）
var _cull_margin_top: float = 120.0
var _cull_margin_bottom: float = 180.0
var _viewport_height: float = 0.0

# 活跃音符来源：FlowArea._note_buckets 引用（set_notes_source 注入，_draw 直接遍历同一字典，省去同步簿记）
# 结构：type_key(Block/Slide/Long) -> { color -> Array[int] }  桶元素为 seq 索引
var _note_buckets: Dictionary = {}

# 平行数组宿主（FlowArea 注入）：_draw 读 flow_area._rt_* 取运行态，无需音符对象
var flow_area: Object = null

# 透明纹理回退（贴图缺失时）
var _transparent_tex: Texture2D = null

# 预合成贴图缓存：type_key -> { color -> { part -> Texture2D } }，part ""=Block/Slide
# core 纯白 + alpha 蒙版，预合成 = base + 着色 core 逐像素合并，绘制时单贴图即可上色
# 颜色来自共享数组（有界 2~8 种），Color 值本身可作键；换肤（set_textures/set_long_textures）时整体清空
var _composite_cache: Dictionary = {}

# _draw 遍历用：复用常量，避免每帧分配 [Block, Slide] 数组字面量
const _BLOCK_SLIDE_TYPES: Array = [FlowNote.NoteType.Block, FlowNote.NoteType.Slide]


func _ready() -> void:
	_transparent_tex = _create_transparent_texture()
	_bake_glow_texture()
	_setup_glow_layer()


# ========== 公共 API ==========

## 注入活跃音符来源分桶字典（FlowArea._note_buckets，按引用共享）。
## 之后 _draw 直接遍历该字典，FlowArea 的增删无需再同步到 drawer。
func set_notes_source(notes: Dictionary) -> void:
	_note_buckets = notes

func clear() -> void:
	# 字典本身由 FlowArea.clear_flow_area 清空（_note_buckets 是同一引用），此处只触发重绘
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
	_clear_composite_cache()

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
	_clear_composite_cache()

## 设置 body 中部贴图应用方式（"repeat" / "stretch"）
func set_long_body_mode(mode: String) -> void:
	_long_body_mode = mode

## 获取 (type, color, part) 的预合成贴图（不存在则构建并缓存；part ""=Block/Slide）
func get_composite(type_key: int, color: Color, part: String = "") -> Texture2D:
	if not _composite_cache.has(type_key):
		_composite_cache[type_key] = {}
	var by_color: Dictionary = _composite_cache[type_key]
	if not by_color.has(color):
		by_color[color] = {}
	var by_part: Dictionary = by_color[color]
	if not by_part.has(part):
		by_part[part] = _build_composite(type_key, color, part)
	return by_part[part]

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

func _clear_composite_cache() -> void:
	_composite_cache.clear()

func _base_tex_for(type_key: int, part: String) -> Texture2D:
	match type_key:
		FlowNote.NoteType.Long:
			match part:
				"head": return _long_head_tex
				"tail": return _long_tail_tex
				_: return _long_body_tex
		FlowNote.NoteType.Slide: return _slide_tex
		_: return _block_tex

func _core_tex_for(type_key: int, part: String) -> Texture2D:
	match type_key:
		FlowNote.NoteType.Long:
			match part:
				"head": return _long_head_core_tex
				"tail": return _long_tail_core_tex
				_: return _long_body_core_tex
		FlowNote.NoteType.Slide: return _slide_core_tex
		_: return _block_core_tex

## 构建 (type, color, part) 的预合成贴图：core 纯白 + alpha 蒙版 ⇒
## 用纯色 tint 按 core 蒙版 blend 进 base，与 draw_texture_rect(core, rect, false, color) 逐像素等价
func _build_composite(type_key: int, color: Color, part: String) -> Texture2D:
	if _transparent_tex == null:
		_transparent_tex = _create_transparent_texture()
	var base_tex: Texture2D = _base_tex_for(type_key, part)
	var core_tex: Texture2D = _core_tex_for(type_key, part)
	if base_tex == null or core_tex == null:
		return _transparent_tex  # 防御：贴图未设置时回退透明

	var base_img := base_tex.get_image()
	if base_img == null:
		return base_tex  # 防御：贴图不可读时回退原贴图
	if base_img.is_compressed():
		base_img.decompress()
	base_img.convert(Image.FORMAT_RGBA8)

	var core_img := core_tex.get_image()
	if core_img == null:
		core_img = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		core_img.fill(Color(0, 0, 0, 0))
	if core_img.is_compressed():
		core_img.decompress()
	core_img.convert(Image.FORMAT_RGBA8)

	var w: int = base_img.get_width()
	var h: int = base_img.get_height()
	if core_img.get_width() != w or core_img.get_height() != h:
		core_img.resize(w, h, Image.INTERPOLATE_BILINEAR)  # 与 draw_texture_rect 拉伸一致

	var tint := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	tint.fill(Color(color.r, color.g, color.b, color.a))
	base_img.blend_rect_mask(tint, core_img, Rect2i(0, 0, w, h), Vector2i.ZERO)
	return ImageTexture.create_from_image(base_img)

func _recompute_heights() -> void:
	_block_half_height = _compute_half_height(_block_tex)
	_slide_half_height = _compute_half_height(_slide_tex)
	_long_head_half_height = _compute_half_height(_long_head_tex)
	_long_tail_half_height = _compute_half_height(_long_tail_tex)
	_long_body_tex_height = _compute_tex_height(_long_body_tex)

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

## 绑定 tscn 预挂的 GlowLayer 节点（节点结构在 PlayView.tscn 声明：z_index=-1、ADD 混合材质）
## 此处只注入 _drawer 引用（GlowLayer._draw 直接读本节点字段，避免数据同步）并同步可见性
func _setup_glow_layer() -> void:
	if _glow_layer == null:
		return
	_glow_layer._drawer = self
	_glow_layer.visible = _glow_enabled

func _draw() -> void:
	if _note_buckets.is_empty():
		return
	var view_h = _viewport_height
	var top_limit = -_cull_margin_top
	var bottom_limit = view_h + _cull_margin_bottom
	# 平行数组宿主引用（_draw 每个元素热读，缓存到局部减少动态查找）
	var fa = flow_area
	if fa == null:
		return
	var flags: PackedByteArray = fa._rt_flags
	var rt_cy: PackedFloat32Array = fa._rt_cy
	var rt_x: PackedFloat32Array = fa._rt_x
	var rt_half: PackedFloat32Array = fa._rt_half
	var REMOVED: int = fa.F_REMOVED

	# 绘制音符贴图（short / instant / long）
	# 只跳过已移除音符：Long 被按住时 is_judged=true 但仍需显示，不能按 is_judged 跳过
	# 分桶遍历：类型桶 → 颜色桶，同色连续绘制同一预合成贴图（利于 CanvasItem 批处理）
	# 预合成 = base + 着色 core 像素级合并（_build_composite），每音符从 2 次绘制降到 1 次
	for type_key in _BLOCK_SLIDE_TYPES:
		var type_bucket: Dictionary = _note_buckets[type_key]  # set_notes_source 后三级键必存在，免 .get 每次构造空字典
		for color_key in type_bucket:
			var bucket: Array = type_bucket[color_key]
			var comp: Texture2D = get_composite(type_key, color_key)
			for note_index in bucket:
				if flags[note_index] & REMOVED:
					continue
				var cy: float = rt_cy[note_index]
				var half_h: float = rt_half[note_index]
				if cy + half_h < top_limit or cy - half_h > bottom_limit:
					continue
				draw_texture_rect(comp, Rect2(rt_x[note_index], cy - half_h, _note_width, half_h * 2.0), false)

	# Long：同色桶内 body→tail→head 三遍绘制，最大化同贴图批处理（每音符自身层序仍 body<tail<head）
	var long_bucket: Dictionary = _note_buckets[FlowNote.NoteType.Long]
	for color_key in long_bucket:
		var bucket: Array = long_bucket[color_key]
		var comp_body: Texture2D = get_composite(FlowNote.NoteType.Long, color_key, "body")
		var comp_tail: Texture2D = get_composite(FlowNote.NoteType.Long, color_key, "tail")
		var comp_head: Texture2D = get_composite(FlowNote.NoteType.Long, color_key, "head")
		for note_index in bucket:
			if not flags[note_index] & REMOVED:
				_draw_long_body(note_index, fa, top_limit, bottom_limit, comp_body)
		for note_index in bucket:
			if not flags[note_index] & REMOVED:
				_draw_long_tail(note_index, fa, top_limit, bottom_limit, comp_tail)
		for note_index in bucket:
			if not flags[note_index] & REMOVED:
				_draw_long_head(note_index, fa, top_limit, bottom_limit, comp_head)

## 绘制 Long body（长条连接部分）：
## repeat → 按贴图原始高度分条重复；stretch → 整体竖直拉伸。
## comp 为 (Long, color, "body") 预合成贴图（合成即 base 尺寸，core 高光随 base 周期重复）
## note_index 为平行数组 seq 索引，运行态经 fa（FlowArea）读取
func _draw_long_body(note_index: int, fa: Object, top_limit: float, bottom_limit: float, comp: Texture2D) -> void:
	var body_top: float = fa._rt_body_top[note_index]
	var body_h: float = fa._rt_body_h[note_index]
	if body_h <= 0.0 or body_top + body_h < top_limit or body_top > bottom_limit:
		return
	var body_rect := Rect2(fa._rt_x[note_index], body_top, _note_width, body_h)
	if _long_body_mode == "repeat":
		_draw_long_body_repeat(comp, body_rect)
	else:
		# stretch：整体竖直拉伸
		draw_texture_rect(comp, body_rect, false)

## 绘制 Long tail（尾部）
func _draw_long_tail(note_index: int, fa: Object, top_limit: float, bottom_limit: float, comp: Texture2D) -> void:
	var tail_cy: float = fa._rt_tail_cy[note_index]
	var tail_half: float = fa._rt_tail_half[note_index]
	if tail_cy + tail_half < top_limit or tail_cy - tail_half > bottom_limit:
		return
	var tail_rect := Rect2(fa._rt_x[note_index], tail_cy - tail_half, _note_width, tail_half * 2.0)
	draw_texture_rect(comp, tail_rect, false)

## 绘制 Long head（头部，盖在 body 上）
func _draw_long_head(note_index: int, fa: Object, top_limit: float, bottom_limit: float, comp: Texture2D) -> void:
	var head_cy: float = fa._rt_head_cy[note_index]
	var head_half: float = fa._rt_head_half[note_index]
	if head_cy + head_half < top_limit or head_cy - head_half > bottom_limit:
		return
	var head_rect := Rect2(fa._rt_x[note_index], head_cy - head_half, _note_width, head_half * 2.0)
	draw_texture_rect(comp, head_rect, false)

## repeat 模式下分条绘制 body：水平拉伸（0-1），垂直按贴图原始高度逐条重复
## 最后一条不足贴图高度时只取贴图顶部剩余部分（与 LongBodyRepeat shader 的 fract(UV.y*v_repeat) 一致）
## comp 为预合成贴图，分条周期取 base body 原始高度 _long_body_tex_height
func _draw_long_body_repeat(comp: Texture2D, rect: Rect2) -> void:
	var tex_h := _long_body_tex_height
	if tex_h <= 0.0:
		draw_texture_rect(comp, rect, false)
		return
	var tex_w := comp.get_width()
	var top := rect.position.y
	var remain := rect.size.y
	var guard := 0
	while remain > 0.01:
		var h := minf(tex_h, remain)
		draw_texture_rect_region(comp,
			Rect2(rect.position.x, top, rect.size.x, h),
			Rect2(0, 0, tex_w, h))
		top += h
		remain -= h
		guard += 1
		if guard > 256:
			break
