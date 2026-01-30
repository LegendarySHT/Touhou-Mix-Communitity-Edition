extends VBoxContainer

func _ready():
	# 连接选项卡按钮
	for i in get_node("TabBtn").get_children():
		if i is Button:
			i.toggled.connect(_on_button_toggled.bind(i))
			i.focus_entered.connect(func ():
				if not i.button_pressed:
					i.button_pressed = true
			)
	
## 选项卡切换回调
func _on_button_toggled(toggle_on, button):
	
	if toggle_on:
		var t_page = get_node("TabView/TabC/%s" % button.name)
		t_page.visible = true
		AnimationManager.instance.animate_fade_in(t_page, 0.2, "tabSwitch")
