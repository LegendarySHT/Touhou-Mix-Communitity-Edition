extends OptionButton

# 创建新主题并覆盖样式
func _ready():
	var flat_bg = StyleBoxFlat.new()
	flat_bg.bg_color = Color("#2d2d2d")
	flat_bg.corner_radius_top_left = 5
	flat_bg.corner_radius_bottom_right = 5
	flat_bg.border_width_bottom = 2
	flat_bg.border_color = Color("#4a4a4a")

	# 创建悬停效果
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color("#3a3a3a")

	# 应用主题
	var theme = Theme.new()
	theme.set_stylebox("panel", "PopupMenu", flat_bg)
	theme.set_stylebox("hover", "PopupMenu", hover_style)
	theme.set_color("font_color", "PopupMenu", Color.WHITE)
	get_popup().theme = theme
	
