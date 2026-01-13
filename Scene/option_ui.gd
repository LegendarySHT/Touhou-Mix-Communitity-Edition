extends Polygon2D


func _ready():
	for i in get_node("Option").get_children():
		if i is TextureButton:
			i.toggled.connect(_on_button_toggled.bind(i))
			
			
			
func _on_button_toggled(toggle_on,button):
	
	if toggle_on:
		var selector = get_node("Option/Selector")
		var content=get_node("Content")
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_parallel(true)
	
		if button.get_meta("id")==1:
			tween.tween_property(selector,"position",Vector2(-174,-100),0.15)
			tween.tween_property(content,"position",Vector2(150,130),0.15)
		elif button.get_meta("id")==2:
			tween.tween_property(selector,"position",Vector2(18,-100),0.15)
			tween.tween_property(content,"position",Vector2(-450,130),0.15)
		elif button.get_meta("id")==3:
			tween.tween_property(selector,"position",Vector2(202,-100),0.15)
			tween.tween_property(content,"position",Vector2(-1050,130),0.15)
	else:
		pass
