extends TextureRect
# Background 节点（ColorRect 或 TextureRect）
func _ready():
	# 全屏拉伸
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	# 如果是 TextureRect，设置拉伸模式
	stretch_mode = TextureRect.STRETCH_SCALE
