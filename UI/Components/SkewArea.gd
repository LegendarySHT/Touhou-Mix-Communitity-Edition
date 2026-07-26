extends Control

@onready var margin = 1080 * tan(deg_to_rad(15))

func _ready() -> void:
	get_window().size_changed.connect(_on_window_resize)
	_on_window_resize()
	
	position.x = margin

func _on_window_resize():
	var rect = get_viewport().get_visible_rect().size

	size = Vector2(rect.x - margin, rect.y / cos(deg_to_rad(15)))
