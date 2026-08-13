## 精灵图序列帧粒子批绘器
## 替代旧的逐粒子实例化 + 对象池：全部粒子由单个 Node2D 统一维护，
## _process() 推进动画状态，_draw() 一次批量绘制所有粒子
## 供 PlayView 判定特效与 ParticleAdjust 预览共用
extends Node2D

class_name ParticleBatchDrawer

## 循环粒子的最大播放时长（秒）：loop=true 的包也必须终结，
## 否则粒子长期残留、越积越多
const _MAX_LOOP_PLAY_SEC := 5.0

# ===== 单粒子运行时状态（轻量 RefCounted，非节点） =====
class ActiveParticle:
	## 叠加绘制层 [{texture: Texture2D, half_size: float, rotation: float}]：
	## half_size 为显示边长一半（spawn 预计算，_draw 免逐帧换算）；
	## 第 0 层为基础动画（rotation 恒 0），其后为叠加粒子动画（按规格随机旋转）
	var layers: Array = []
	## 贴图中单帧的像素边长（粒子包 [general] size）
	var source_size: float = 256.0
	var cols: int = 1      # 网格列数
	var rows: int = 1      # 网格行数
	var frame_count: int = 1
	var fps: float = 30.0
	var loop: bool = false
	var fade_out: bool = true
	# ===== 播放状态 =====
	var frame: int = 0
	var frame_time: float = 0.0
	var play_time: float = 0.0  # 累计播放时长（循环粒子的硬上限计时）
	var position: Vector2 = Vector2.ZERO
	var base_tex_id: int = 0  # 基础层贴图 RID id（_draw 按贴图分组排序用）

## 活跃粒子列表（spawn 追加，播完由 _process 移除）
var _active: Array[ActiveParticle] = []
## 排序脏标记：新粒子生成时置位，_draw 需要按贴图分组绘制时重排（静置/移除不破坏排序）
var _order_dirty := false


# ========== 公共 API ==========

## 生成一个粒子
## pack_key: 粒子包键（ParticleMGR.get_particle_list() 中的键）
## judge_type: Perfect / Great / Good / Bad，决定使用哪张精灵图
## pos: 粒子位置（本节点局部坐标）
## scaling_pct: 缩放百分比（100 = 使用配置声明的原始尺寸）
func spawn(pack_key: String, judge_type: String, pos: Vector2, scaling_pct: float = 100.0) -> void:
	var data: Dictionary = ParticleMGR.get_particle_data(pack_key)
	if data.is_empty():
		return

	# 解析该判定可用的基础精灵图列表；多图时随机选取一张（同判定不同发射规律的粒子轮换出现）
	var textures := ParticleMGR.get_particle_textures(pack_key, judge_type)
	if textures.is_empty():
		return
	var base_tex: Texture2D = textures[randi() % textures.size()]
	var source_size := float(data.get("size", 0))
	if source_size <= 0.0:
		return

	var p := ActiveParticle.new()
	p.position = pos
	p.source_size = source_size
	p.base_tex_id = int(base_tex.get_rid().get_id())

	# 构建绘制层：基础动画（恒不旋转）+ 可选叠加粒子动画（同网格/帧率同步推进，随机旋转）
	# half_size 预计算并存进层数据，_draw 直接使用避免逐帧换算
	var display_size := source_size * scaling_pct / 100.0
	p.layers.append({"texture": base_tex, "half_size": display_size * 0.5, "rotation": 0.0})
	var overlay := ParticleMGR.get_particle_overlay(pack_key, judge_type)
	if not overlay.is_empty():
		var ov_textures: Array = overlay.get("textures", [])
		if not ov_textures.is_empty():
			var ov_scaling := float(overlay.get("scaling", 100.0))
			if ov_scaling <= 0.0:
				ov_scaling = 100.0
			p.layers.append({
				"texture": ov_textures[randi() % ov_textures.size()],
				"half_size": display_size * ov_scaling / 100.0 * 0.5,
				"rotation": _sample_rotation(overlay.get("rotation", null)),
			})

	p.fps = float(data.get("fps", 30.0))
	if p.fps <= 0.0:
		p.fps = 30.0
	p.loop = bool(data.get("loop", false))
	p.fade_out = bool(data.get("fade_out", true))

	# 网格：优先用配置显式声明的 cols/rows，否则按贴图尺寸 / 单帧尺寸推导
	var tex_w := 0
	var tex_h := 0
	if base_tex != null:
		tex_w = base_tex.get_width()
		tex_h = base_tex.get_height()
	var cfg_cols := int(data.get("cols", 0))
	var cfg_rows := int(data.get("rows", 0))
	if cfg_cols > 0:
		p.cols = cfg_cols
	elif tex_w > 0:
		p.cols = maxi(1, tex_w / int(source_size))
	else:
		p.cols = 1
	if cfg_rows > 0:
		p.rows = cfg_rows
	elif tex_h > 0:
		p.rows = maxi(1, tex_h / int(source_size))
	else:
		p.rows = 1

	# 帧数：配置显式声明优先，否则用网格全部帧；超出网格可用帧时截断
	var cfg_frame := int(data.get("frame", 0))
	var available := p.cols * p.rows
	p.frame_count = cfg_frame if cfg_frame > 0 else available
	p.frame_count = clampi(p.frame_count, 1, available)

	if _active.is_empty():
		set_process(true)
	_active.append(p)
	_order_dirty = true
	queue_redraw()


## 清空全部粒子（游戏结束/清场时调用）
func clear() -> void:
	if _active.is_empty():
		return
	_active.clear()
	_order_dirty = false
	set_process(false)
	queue_redraw()


# ========== 帧驱动 ==========

func _process(delta: float) -> void:
	if _active.is_empty():
		return
	var i := _active.size() - 1
	while i >= 0:
		if _advance(_active[i], delta):
			_active.remove_at(i)
		i -= 1
	if _active.is_empty():
		set_process(false)
	else:
		queue_redraw()


## 推进单个粒子一帧，返回是否已播放结束（需移除）
func _advance(p: ActiveParticle, delta: float) -> bool:
	var frame_dur := 1.0 / p.fps
	p.frame_time += delta
	while p.frame_time >= frame_dur:
		p.frame_time -= frame_dur
		p.frame += 1
		if p.frame >= p.frame_count:
			if p.loop:
				p.frame = 0
			else:
				return true

	# 循环粒子硬上限：达到时长强制终结，避免长期残留
	p.play_time += delta
	if p.loop and p.play_time >= _MAX_LOOP_PLAY_SEC:
		return true
	return false


# ========== 批量绘制 ==========

func _draw() -> void:
	if _active.is_empty():
		return
	# 两趟 + 贴图分组绘制：先画全部基础层（第 0 层），再画全部叠加层（第 1 层起）。
	# 渲染端（RendererCanvasRenderRD）对同一 CanvasItem 内相邻且同贴图的
	# draw_texture_rect_region 会合并成一次实例化绘制，贴图一切换就拆批。若逐粒子
	# 「base→overlay→base→overlay…」交替画，几百个粒子会拆出几百次 draw call——掉帧主因。
	# 这里每趟前先按贴图 RID 排序，保证同贴图命令连续，批数量降到贴图种数（通常 2~5 次）。
	# 排序只在 _order_dirty 时发生（新粒子生成），静置/移除不破坏排序，避免逐帧排序开销。
	if _order_dirty:
		_active.sort_custom(_sort_by_base_tex)
		_order_dirty = false
	# 第 1 趟：全部基础层（旋转恒 0，draw_set_transform 仅平移）
	for p in _active:
		var region := _get_frame_region(p, p.frame)
		var alpha := _current_alpha(p)
		var color := Color(1.0, 1.0, 1.0, alpha)
		var layer: Dictionary = p.layers[0]
		var hs := float(layer.half_size)
		draw_set_transform(p.position, float(layer.rotation), Vector2.ONE)
		draw_texture_rect_region(layer.texture, Rect2(-hs, -hs, hs * 2.0, hs * 2.0), region, color)
	# 第 2 趟：全部叠加层（叠加图与基础图同网格取样，region 复用）
	for p in _active:
		if p.layers.size() <= 1:
			continue
		var region := _get_frame_region(p, p.frame)
		var alpha := _current_alpha(p)
		var color := Color(1.0, 1.0, 1.0, alpha)
		for li in range(1, p.layers.size()):
			var layer: Dictionary = p.layers[li]
			var hs := float(layer.half_size)
			draw_set_transform(p.position, float(layer.rotation), Vector2.ONE)
			draw_texture_rect_region(layer.texture, Rect2(-hs, -hs, hs * 2.0, hs * 2.0), region, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 按基础层贴图 RID id 排序（_draw 分组绘制用，保证同贴图命令连续）
func _sort_by_base_tex(a: ActiveParticle, b: ActiveParticle) -> bool:
	return a.base_tex_id < b.base_tex_id


## 计算第 frame 帧在 spritesheet 中的源矩形
func _get_frame_region(p: ActiveParticle, frame: int) -> Rect2:
	var col := frame % p.cols
	var row := frame / p.cols
	return Rect2(col * p.source_size, row * p.source_size, p.source_size, p.source_size)


## 当前透明度（尾部淡出：最后 40% 线性降到 0）
func _current_alpha(p: ActiveParticle) -> float:
	if not p.fade_out or p.loop:
		return 1.0
	var progress := (p.frame + p.frame_time * p.fps) / float(p.frame_count)
	if progress > 0.6:
		return clampf(1.0 - (progress - 0.6) / 0.4, 0.0, 1.0)
	return 1.0


## 从旋转规格中采样一次叠加粒子的旋转角度（返回弧度）
## spec 为 ParticleMGR._parse_rotation 的产物：null→0；{mode:"fixed"}→固定角；
## {mode:"range"}→连续范围随机；{mode:"set"}→离散集随机；未知→0
func _sample_rotation(spec) -> float:
	if spec == null or not (spec is Dictionary):
		return 0.0
	match spec.get("mode", ""):
		"fixed":
			return deg_to_rad(float(spec.get("value", 0.0)))
		"range":
			return deg_to_rad(randf_range(float(spec.get("min", 0.0)), float(spec.get("max", 0.0))))
		"set":
			var values: Array = spec.get("values", [])
			if values.is_empty():
				return 0.0
			return deg_to_rad(float(values[randi() % values.size()]))
	return 0.0
