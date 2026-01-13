extends Camera2D
var view=0;

func _process(_delta: float):
	if Input.is_action_pressed("ui_up"):
		self.position.y-=10
	elif Input.is_action_pressed("ui_down"):
		self.position.y+=10
	elif Input.is_action_pressed("ui_left"):
		self.position.x-=10
	elif Input.is_action_pressed("ui_right"):
		self.position.x+=10

func _switch_to_store():
	var tween = create_tween();
	tween.set_trans(Tween.TRANS_EXPO);    # 过渡类型（如弹性、正弦等）
	tween.set_ease(Tween.EASE_OUT) ;    # 缓动模式（缓入缓出）
	
	view=(view+1)%2;
	print(view);
	if view==0:
		tween.tween_property(self, "position", Vector2(0, 0), 0.25)
	else:
		tween.tween_property(self, "position", Vector2(1920, 0), 0.15); 
