extends Control

@onready var margin = 1080 * tan(deg_to_rad(15))

func _ready() -> void:
	get_window().size_changed.connect(_on_window_resize)
	_on_window_resize()
	
	position.x = margin

func _on_window_resize():
	var rect = get_viewport().get_visible_rect().size

	size = Vector2(rect.x - margin, rect.y / cos(deg_to_rad(15)))
	
	await get_tree().process_frame
	var setting_list = get_node_or_null("SettingView/HBoxC/SettingList")
	if setting_list:
		setting_list.update_column_width(size.x)
