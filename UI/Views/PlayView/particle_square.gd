extends Node2D

## 粒子播放完成信号，供对象池回收使用（替代原先的 queue_free）
signal particle_done

# 基础的方块粒子
@onready var base_emitter: GPUParticles2D = $Base
# 边框粒子
@onready var square: GPUParticles2D = $Square
# 散射的实体方块粒子
@onready var border_emitter: GPUParticles2D = $EmitBorder
# 散射的方框粒子
@onready var solid_emitter: GPUParticles2D = $EmitSolid

# 从 tscn 读取的各发射器基准值（首次调用 _apply_emitter_scale 时自动保存）
var _base_scale_min: Dictionary = {}
var _base_scale_max: Dictionary = {}
var _base_velocity_min: Dictionary = {}
var _base_velocity_max: Dictionary = {}
var _base_gravity: Dictionary = {}

func play(type: String) -> void:
	var sq_emit := false
	match type:
		"Perfect":
			sq_emit = true
		"Great":
			sq_emit = true
			square.texture = load("res://Resources/Particle/great_sq.png")
	square.emitting = sq_emit
	base_emitter.emitting = true
	solid_emitter.emitting = true
	border_emitter.emitting = true
	# CONNECT_ONE_SHOT 保证每次播放只触发一次回收，不累积连接
	border_emitter.finished.connect(particle_done.emit, CONNECT_ONE_SHOT)

func set_particle_scale(size: int) -> void:
	var scl: float = float(size) / 400.0

	_apply_emitter_scale("Base", scl)
	_apply_emitter_scale("Square", scl)
	_apply_emitter_scale("EmitSolid", scl)
	_apply_emitter_scale("EmitBorder", scl)

func _apply_emitter_scale(emitter_name: String, k: float) -> void:
	var emitter := get_node(emitter_name) as GPUParticles2D
	var mat := emitter.process_material as ParticleProcessMaterial
	# 首次调用：独立化 material（池中共享同一份）并保存基准值
	if not emitter_name in _base_scale_min:
		mat = mat.duplicate(true)
		emitter.process_material = mat
		_base_scale_min[emitter_name] = mat.scale_min
		_base_scale_max[emitter_name] = mat.scale_max
		_base_velocity_min[emitter_name] = mat.initial_velocity_min
		_base_velocity_max[emitter_name] = mat.initial_velocity_max
		_base_gravity[emitter_name] = mat.gravity
	mat.scale_min = _base_scale_min[emitter_name] * k
	mat.scale_max = _base_scale_max[emitter_name] * k
	if _base_velocity_max[emitter_name] > 0.0:
		mat.initial_velocity_min = _base_velocity_min[emitter_name] * k
		mat.initial_velocity_max = _base_velocity_max[emitter_name] * k
	mat.gravity = _base_gravity[emitter_name] * k
