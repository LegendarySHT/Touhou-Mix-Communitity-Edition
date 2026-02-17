extends VBoxContainer

@onready var ui : UIStateManager = UIStateManager.instance
@onready var se = SortEngine.instance
@onready var ani: AnimationManager = AnimationManager.instance

@onready var sort_button = $Btns/Search
@onready var love_button = $Btns/FavorList

@onready var page_container = $Panel # 页面背景
@onready var page = $Panel/Page # 页面内容

func _ready() -> void:
	# 连接按钮点击事件
	sort_button.toggled.connect(_on_menu_tab_btn_toggled.bind(sort_button))
	love_button.toggled.connect(_on_menu_tab_btn_toggled.bind(love_button))

	_on_menu_tab_btn_toggled(false, sort_button)

	# 按键退出事件
	ui.state_changed.connect(_on_state_changed)

	# 按钮聚焦事件
	sort_button.focus_entered.connect(_on_focus_enter.bind(sort_button))
	love_button.focus_entered.connect(_on_focus_enter.bind(love_button))

func _on_focus_enter(btn: Button):
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	await get_tree().create_timer(0.1).timeout
	if not btn.button_pressed:
		btn.button_pressed = true

func _on_state_changed(old_state: UIStateManager.UIState, _new_state: UIStateManager.UIState) -> void:
	if old_state == UIStateManager.UIState.SORTED_VIEW:
		sort_button.button_pressed = false
		love_button.button_pressed = false

func _on_menu_tab_btn_toggled(toggled_on: bool, btn: Button):
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_parallel(true)

	tween.tween_property(btn, "custom_minimum_size", Vector2(120 + 310 * (1 if toggled_on else 0), 120), 0.45)

	if _is_all_off():
		tween.tween_property(page_container, "custom_minimum_size", Vector2.ZERO, 0.5)
		ani.animate_fade_out(page_container, 0.6, "menu_fade")
	else:
		tween.tween_property(page_container, "custom_minimum_size",Vector2(600, 700), 0.5)
		ani.animate_fade_in(page_container, 0, "menu_fade")

	if toggled_on:
		tween.tween_property(page, "position", Vector2(40, 50) + (Vector2(-605, 0) if btn == love_button else Vector2.ZERO), 0.5)

func _is_all_off() -> bool:
	if sort_button.button_pressed or love_button.button_pressed:
		return false
	return true

# 筛选按钮部分
var sortByStatus: SortEngine.SortStatField = 0 as SortEngine.SortStatField
var sortByData: SortEngine.SortDataField = 0 as SortEngine.SortDataField
var sortDirection: SortEngine.SortDirection = 0 as SortEngine.SortDirection

@onready var sort_btns = $Panel/Page/SortPage/SortButton

var _sort_stat_icon_map = {
	SortEngine.SortStatField.ALL: "res://Resources/icon/Sort/Status/All.png",
	SortEngine.SortStatField.PENDING: "res://Resources/icon/Sort/Status/pending.png",
	SortEngine.SortStatField.APPROVED: "res://Resources/icon/Sort/Status/Approved.png",
	SortEngine.SortStatField.INCLUDED: "res://Resources/icon/Sort/Status/Included.png",
	SortEngine.SortStatField.DEAD: "res://Resources/icon/Sort/Status/Dead.png",
}
func _on_status_pressed() -> void:
	# Midi状态筛选
	sortByStatus=(sortByStatus+1)%5 as SortEngine.SortStatField

	sort_btns.get_node("Status").texture_normal=load(_sort_stat_icon_map[sortByStatus])
	se.set_sort_mode(sortByStatus)

	if ui.current_state!=ui.UIState.SORTED_VIEW:
		ui.change_state(ui.UIState.SORTED_VIEW)

# 数据筛选
var _sort_data_icon_map = {
	SortEngine.SortDataField.DEFAULT: "res://Resources/icon/Sort/Status/All.png",
	SortEngine.SortDataField.DOWNLOAD_COUNT: "res://Resources/icon/Sort/Data/Download.png",
	SortEngine.SortDataField.LOVE_COUNT: "res://Resources/icon/Sort/Data/Favor.png",
	SortEngine.SortDataField.UP_COUNT: "res://Resources/icon/Sort/Data/Up.png",
	SortEngine.SortDataField.TRIAL_COUNT: "res://Resources/icon/Sort/Data/Played.png",
	SortEngine.SortDataField.UPLOADED_DATE: "res://Resources/icon/Sort/Data/CreateTime.png",
}
func _on_data_toggled(toggled_on: bool) -> void:
	if toggled_on:
		sortByData = (sortByData + 1) % 6 as SortEngine.SortDataField

		sort_btns.get_node("Data").texture_normal=load(_sort_data_icon_map[sortByData])
		se.set_sort_mode(se.current_sort_stat_field, sortByData)
		if ui.current_state!=ui.UIState.SORTED_VIEW:
			ui.change_state(ui.UIState.SORTED_VIEW)

func _on_ordering_pressed() -> void:
	sortDirection = (sortDirection + 1) % 2 as SortEngine.SortDirection
	sort_btns.get_node("Ordering").texture_normal=load("res://Resources/icon/Sort/Ordering/Ascent.png" if sortDirection == SortEngine.SortDirection.ASCENDING else "res://Resources/icon/Sort/Ordering/Descent.png")
	se.set_sort_mode(se.current_sort_stat_field, se.current_sort_field, sortDirection)

	if ui.current_state!=ui.UIState.SORTED_VIEW:
		ui.change_state(ui.UIState.SORTED_VIEW)
