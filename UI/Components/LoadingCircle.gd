extends TextureRect

var need_rotate: bool = true

func _ready():
	start_rotation()

func start_rotation():
	need_rotate = true
	visible = true

func stop_rotation():
	need_rotate = false
	visible = false

func _process(_delta):
	if need_rotate:
		rotation_degrees += 2
