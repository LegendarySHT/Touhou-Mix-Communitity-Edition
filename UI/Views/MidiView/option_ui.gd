extends VBoxContainer

# 模式设置 (自动/普通 模式)
@onready var mode_btn: OptionButton = $TabView/TabC/Mode/GridC/Mode
# 限制设置 (无限制/FC/AP)
@onready var limit_btn: OptionButton = $TabView/TabC/Mode/GridC/Limit
# 循环设置 （单次/无限）
@onready var repeat_btn: OptionButton = $TabView/TabC/Mode/GridC/Repeat
# 游戏模式 （普通/扫描线）
@onready var gamme_mode_btn: OptionButton = $TabView/TabC/Mode/GridC/GameMode


func _ready():
	# 连接选项卡按钮
	for i in get_node("TabBtn").get_children():
		if i is Button:
			i.toggled.connect(_on_button_toggled.bind(i))
			i.focus_entered.connect(func ():
				if not i.button_pressed:
					i.button_pressed = true
			)
	
	for i in get_node("TabView/TabC/Mode/GridC").get_children():
		i.get_popup().about_to_popup.connect(_on_popup_menu_popup.bind(i.get_popup()))

# 修改popupmenu的弹出位置
func _on_popup_menu_popup(popup_menu: PopupMenu) -> void:
	await get_tree().process_frame
	popup_menu.position.y += 20
	popup_menu.position.x -= 60

## 选项卡切换回调
func _on_button_toggled(toggle_on, button):
	
	if toggle_on:
		var t_page = get_node("TabView/TabC/%s" % button.name)
		if t_page.visible:
			return
		t_page.visible = true
		AnimationManager.instance.animate_fade_in(t_page, 0.2, "tabSwitch")
