## 精灵图序列帧粒子播放器
## 替代旧的 GPUParticles2D 方块粒子：从粒子包读取序列帧 spritesheet，
## 按配置的帧率/尺寸/循环/淡出逐帧播放，Node2D._draw() 批量绘制当前帧
## 供 PlayView 判定特效与 ParticleAdjust 预览共用
extends Node2D

class_name ParticlePlayer

## 粒子播放完成信号，供对象池回收使用（替代原先的 queue_free）
signal particle_done

## 循环粒子的最大播放时长（秒）：loop=true 的包也必须终结，
## 否则对象池节点被永久占用（FlowArea）或预览节点无限累积（ParticleAdjust）
const _MAX_LOOP_PLAY_SEC := 5.0

# ===== 播放参数（play() 时从粒子包数据填充） =====
## 叠加绘制层 [{texture: Texture2D, half_size: float, rotation: float}]：
## half_size 为显示边长一半（play() 预计算，_draw() 免逐帧换算）；
## 第 0 层为基础动画（rotation 恒 0），其后为叠加粒子动画（按规格随机旋转）
var _layers: Array = []
## 贴图中单帧的像素边长（粒子包 [general] size）
var _source_size: float = 256.0
## 缩放后的显示边长（source_size * scaling_pct / 100）
var _display_size: float = 256.0
var _cols: int = 1      # 网格列数
var _rows: int = 1      # 网格行数
var _frame_count: int = 1
var _fps: float = 30.0
var _loop: bool = false
var _fade_out: bool = true

# ===== 播放状态 =====
var _frame: int = 0
var _frame_time: float = 0.0
var _playing: bool = false
var _play_time: float = 0.0  # 累计播放时长（循环粒子的硬上限计时）

## 播放一次粒子动画
## pack_key: 粒子包键（ParticleMGR.get_particle_list() 中的键）
## judge_type: Perfect / Great / Good / Bad，决定使用哪张精灵图
## scaling_pct: 缩放百分比（100 = 使用配置声明的原始尺寸）
func play(pack_key: String, judge_type: String, scaling_pct: float = 100.0) -> void:
	var data: Dictionary = ParticleMGR.get_particle_data(pack_key)
	if data.is_empty():
		_finish()
		return

	# 解析该判定可用的基础精灵图列表；多图时随机选取一张（同判定不同发射规律的粒子轮换出现）
	var textures := ParticleMGR.get_particle_textures(pack_key, judge_type)
	if textures.is_empty():
		_finish()
		return
	var base_tex: Texture2D = textures[randi() % textures.size()]
	_source_size = float(data.get("size", 0))
	if _source_size <= 0.0:
		_finish()
		return

	_display_size = _source_size * scaling_pct / 100.0

	# 构建绘制层：基础动画（恒不旋转）+ 可选叠加粒子动画（同网格/帧率同步推进，随机旋转）
	# half_size 预计算并存进层数据，_draw() 直接使用避免逐帧换算
	_layers.clear()
	_layers.append({"texture": base_tex, "half_size": _display_size * 0.5, "rotation": 0.0})
	var overlay := ParticleMGR.get_particle_overlay(pack_key, judge_type)
	if not overlay.is_empty():
		var ov_textures: Array = overlay.get("textures", [])
		if not ov_textures.is_empty():
			var ov_scaling := float(overlay.get("scaling", 100.0))
			if ov_scaling <= 0.0:
				ov_scaling = 100.0
			_layers.append({
				"texture": ov_textures[randi() % ov_textures.size()],
				"half_size": _display_size * ov_scaling / 100.0 * 0.5,
				"rotation": _sample_rotation(overlay.get("rotation", null)),
			})

	_fps = float(data.get("fps", 30.0))
	if _fps <= 0.0:
		_fps = 30.0
	_loop = bool(data.get("loop", false))
	_fade_out = bool(data.get("fade_out", true))

	# 网格：优先用配置显式声明的 cols/rows，否则按贴图尺寸 / 单帧尺寸推导
	var tex_w := 0
	var tex_h := 0
	if base_tex != null:
		tex_w = base_tex.get_width()
		tex_h = base_tex.get_height()
	var cfg_cols := int(data.get("cols", 0))
	var cfg_rows := int(data.get("rows", 0))
	if cfg_cols > 0:
		_cols = cfg_cols
	elif tex_w > 0:
		_cols = maxi(1, tex_w / int(_source_size))
	else:
		_cols = 1
	if cfg_rows > 0:
		_rows = cfg_rows
	elif tex_h > 0:
		_rows = maxi(1, tex_h / int(_source_size))
	else:
		_rows = 1

	# 帧数：配置显式声明优先，否则用网格全部帧；超出网格可用帧时截断
	var cfg_frame := int(data.get("frame", 0))
	var available := _cols * _rows
	_frame_count = cfg_frame if cfg_frame > 0 else available
	_frame_count = clampi(_frame_count, 1, available)

	_frame = 0
	_frame_time = 0.0
	_play_time = 0.0
	modulate.a = 1.0
	_playing = true
	visible = true
	queue_redraw()

## 停止播放并回到空闲态（对象池回收/重新播放前调用）
func reset() -> void:
	_playing = false
	visible = false

func _process(delta: float) -> void:
	if not _playing:
		return

	var frame_dur := 1.0 / _fps
	# 帧率驱动：累计经过时间，跨过帧间隔即更新到下一帧
	_frame_time += delta
	var advanced := false
	while _frame_time >= frame_dur:
		_frame_time -= frame_dur
		_frame += 1
		advanced = true
		if _frame >= _frame_count:
			if _loop:
				_frame = 0
			else:
				_finish()
				return
	if advanced:
		queue_redraw()

	# 循环粒子硬上限：达到时长强制终结，避免永久占用对象池/预览节点
	_play_time += delta
	if _loop and _play_time >= _MAX_LOOP_PLAY_SEC:
		_finish()
		return

	# 尾部淡出（仅非循环）
	if _fade_out and not _loop:
		var progress := (_frame + _frame_time / frame_dur) / float(_frame_count)
		if progress > 0.6:
			var fade_t := (progress - 0.6) / 0.4
			modulate.a = clampf(1.0 - fade_t, 0.0, 1.0)

func _finish() -> void:
	_playing = false
	visible = false
	particle_done.emit()

func _draw() -> void:
	if not _playing or _layers.is_empty():
		return
	var region := _get_frame_region(_frame)
	# 逐层绘制：仅旋转非零的层才设 transform（draw_set_transform 以原点=粒子中心旋转）；
	# 全部画完若改过则复位，避免残留变换污染该 canvas item 的后续绘制
	var transformed := false
	for layer in _layers:
		var rot := float(layer.rotation)
		if rot != 0.0:
			draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)
			transformed = true
		var hs := float(layer.half_size)
		draw_texture_rect_region(layer.texture, Rect2(-hs, -hs, hs * 2.0, hs * 2.0), region)
	if transformed:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 计算第 frame 帧在 spritesheet 中的源矩形
func _get_frame_region(frame: int) -> Rect2:
	var col := frame % _cols
	var row := frame / _cols
	return Rect2(col * _source_size, row * _source_size, _source_size, _source_size)

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
