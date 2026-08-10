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
var _texture: Texture2D = null
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

	_texture = ParticleMGR.get_particle_texture(pack_key, judge_type)
	_source_size = float(data.get("size", 0))
	if _source_size <= 0.0:
		_finish()
		return

	_display_size = _source_size * scaling_pct / 100.0
	_fps = float(data.get("fps", 30.0))
	if _fps <= 0.0:
		_fps = 30.0
	_loop = bool(data.get("loop", false))
	_fade_out = bool(data.get("fade_out", true))

	# 网格：优先用配置显式声明的 cols/rows，否则按贴图尺寸 / 单帧尺寸推导
	var tex_w := 0
	var tex_h := 0
	if _texture != null:
		tex_w = _texture.get_width()
		tex_h = _texture.get_height()
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
	if not _playing or _texture == null:
		return
	var region := _get_frame_region(_frame)
	var half := _display_size * 0.5
	# 居中绘制当前帧，目标尺寸为显示尺寸（原尺寸已由单帧像素决定）
	draw_texture_rect_region(_texture, Rect2(-half, -half, _display_size, _display_size), region)

## 计算第 frame 帧在 spritesheet 中的源矩形
func _get_frame_region(frame: int) -> Rect2:
	var col := frame % _cols
	var row := frame / _cols
	return Rect2(col * _source_size, row * _source_size, _source_size, _source_size)
