extends Node2D
# 基础的方块粒子
@onready var base_emitter: GPUParticles2D = $Base
# 边框粒子
@onready var square: GPUParticles2D = $Square
# 散射的实体方块粒子
@onready var border_emitter: GPUParticles2D = $EmitBorder
# 散射的方框粒子
@onready var solid_emitter: GPUParticles2D = $EmitSolid

func play(type: String):
	var sq_emit = false
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
	await border_emitter.finished
	queue_free()

func set_particle_scale(scl: float):
	scale *= scl
	print(scale)
	#get_node("Base").process_material.scale_min *= scl
	#get_node("Base").process_material.scale_max *= scl
	#
	#get_node("Square").process_material.scale_min *= scl
	#get_node("Square").process_material.scale_max *= scl
#
	#get_node("EmitSolid").process_material.scale_min *= scl
	#get_node("EmitSolid").process_material.scale_max *= scl
#
	#get_node("EmitBorder").process_material.scale_min *= scl
	#get_node("EmitBorder").process_material.scale_max *= scl
