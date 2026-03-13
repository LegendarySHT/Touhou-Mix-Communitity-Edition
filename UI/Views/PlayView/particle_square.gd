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

func set_particle_scale(scl: float):
	scale = Vector2(scl, scl)

	get_node("Base").process_material.scale_min = scl * 0.6
	get_node("Base").process_material.scale_max = scl * 0.6
	
	get_node("Square").process_material.scale_min = scl * 1.2
	get_node("Square").process_material.scale_max = scl * 1.2

	get_node("EmitSolid").process_material.scale_min = scl * 0.12
	get_node("EmitSolid").process_material.scale_max = scl * 0.3
	get_node("EmitSolid").process_material.initial_velocity_max = scl * 350

	get_node("EmitBorder").process_material.scale_min = scl * 0.12
	get_node("EmitBorder").process_material.scale_max = scl * 0.3
	get_node("EmitBorder").process_material.initial_velocity_max = scl * 350
