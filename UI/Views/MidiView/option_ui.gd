extends VBoxContainer

# 模式设置 (自动/普通 模式)
@onready var mode_btn: OptionButton = $TabView/TabC/Mode/GridC/Mode
# 限制设置 (无限制/FC/AP)
@onready var limit_btn: OptionButton = $TabView/TabC/Mode/GridC/Limit
# 循环设置 （单次/无限）
@onready var repeat_btn: OptionButton = $TabView/TabC/Mode/GridC/Repeat
# 游戏模式 （普通/扫描线）
@onready var gamme_mode_btn: OptionButton = $TabView/TabC/Mode/GridC/GameMode

const MODE_NORMAL_ID: int = 0
const MODE_AUTO_ID: int = 1

var _is_syncing_mode_ui: bool = false


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

	if not mode_btn.item_selected.is_connected(_on_mode_selected):
		mode_btn.item_selected.connect(_on_mode_selected)

	_sync_mode_from_config()

func _sync_mode_from_config() -> void:
	var is_auto := ConfigManager.instance.get_int("Playback", "auto_mode", 0) == 1
	var target_id := MODE_AUTO_ID if is_auto else MODE_NORMAL_ID
	var target_index := mode_btn.get_item_index(target_id)

	if target_index < 0:
		target_index = 0

	_is_syncing_mode_ui = true
	mode_btn.select(target_index)
	_is_syncing_mode_ui = false

func _on_mode_selected(index: int) -> void:
	if _is_syncing_mode_ui:
		return

	var selected_id := mode_btn.get_item_id(index)
	var is_auto := selected_id == MODE_AUTO_ID
	var value := 1 if is_auto else 0

	ConfigManager.instance.set_value_and_notify("Playback", "auto_mode", value)
	var save_ok := ConfigManager.instance.save_config(ConfigManager.USER_CONFIG_PATH)
	if not save_ok:
		GameLogger.instance.warning("Failed to persist Playback.auto_mode to user config", "OptionUI")
	else:
		GameLogger.instance.info("Playback.auto_mode set to %d" % value, "OptionUI")

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
