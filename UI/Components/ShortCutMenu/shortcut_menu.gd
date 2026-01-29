extends VBoxContainer

@onready var UI: UIStateManager = UIStateManager.instance

@onready var sort_button = $Btns/Search
@onready var favor_button = $Btns/FavorList

@onready var page_container = $Panel
@onready var page = $Panel/Page

func _ready() -> void:
	# 连接按钮点击事件
	sort_button.toggled.connect(_on_menu_tab_btn_toggled.bind(sort_button))
	favor_button.toggled.connect(_on_menu_tab_btn_toggled.bind(favor_button))

	_on_menu_tab_btn_toggled(false, sort_button)

	# 按键退出事件
	UI.state_changed.connect(_on_state_changed)

	# 按钮聚焦事件
	sort_button.focus_entered.connect(_on_focus_enter.bind(sort_button))
	favor_button.focus_entered.connect(_on_focus_enter.bind(favor_button))

	sort_button.focus_exited.connect(_on_focus_exit.bind(sort_button))
	favor_button.focus_exited.connect(_on_focus_exit.bind(favor_button))

func _on_focus_enter(btn: Button):
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	await get_tree().create_timer(0.1).timeout
	if not btn.button_pressed:
		btn.button_pressed = true

func _on_focus_exit(btn: Button):
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	if UI.current_state == UIStateManager.UIState.SORTED_VIEW:
		return
	await get_tree().create_timer(0.1).timeout
	var fn = get_viewport().gui_get_focus_owner()
	var node = get_node("Panel/Page")

	if (btn == sort_button and node.get_node("SortPage").is_ancestor_of(fn)) or (btn == favor_button and node.get_node("FavorPage").is_ancestor_of(fn)):
		return
	btn.button_pressed = false

func _on_state_changed(old_state: UIStateManager.UIState, _new_state: UIStateManager.UIState) -> void:
	if old_state == UIStateManager.UIState.SORTED_VIEW:
		sort_button.button_pressed = false
		favor_button.button_pressed = false

func _on_menu_tab_btn_toggled(toggled_on: bool, btn: Button):
	# print("按钮切换：%s %s" % [btn.name, toggled_on])
	var expa = 1 if toggled_on else 0
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_parallel(true)

	tween.tween_property(btn, "custom_minimum_size", Vector2(120 + 310 * expa, 120), 0.45)

	var aniMgr: AnimationManager = AnimationManager.instance
	if _is_all_off():
		tween.tween_property(page_container, "custom_minimum_size", Vector2(0, 0), 0.5)
		aniMgr.animate_fade_out(page_container, 0.6, "menu_fade")

		if UI.current_state == UI.UIState.SORTED_VIEW:
			UI.change_state(UI.previous_state)
	else:
		tween.tween_property(page_container, "custom_minimum_size",Vector2(600, 700), 0.5)
		aniMgr.animate_fade_in(page_container, 0, "menu_fade")

	if toggled_on:
		if btn == sort_button:
			tween.tween_property(page, "position", Vector2(40, 50), 0.5)
		else:
			tween.tween_property(page, "position", Vector2(-565, 50), 0.5)

func _is_all_off() -> bool:
	if sort_button.button_pressed or favor_button.button_pressed:
		return false
	else:
		return true

# 筛选按钮部分
var SortByStatus: int = 0
var SortByData: int = 0
var Ascending: bool = false

@onready var sort_btns = $Panel/Page/SortPage/SortButton

func _on_status_pressed() -> void:
	# Midi状态筛选
	var SE = SortEngine.instance
	SortByStatus=(SortByStatus+1)%5
	match SortByStatus:
		0: # 取消筛选（显示全部）
			sort_btns.get_node("Status").texture_normal=load("res://Resources/icon/Sort/Status/All.png")
			SE.set_sort_mode(SE.SortStatField.ALL)
		1: # 筛选pending状态
			sort_btns.get_node("Status").texture_normal=load("res://Resources/icon/Sort/Status/pending.png")
			SE.set_sort_mode(SE.SortStatField.PENDING)
		2: # 筛选approved状态
			sort_btns.get_node("Status").texture_normal=load("res://Resources/icon/Sort/Status/Approved.png")
			SE.set_sort_mode(SE.SortStatField.APPROVED)
		3: # 筛选included状态
			sort_btns.get_node("Status").texture_normal=load("res://Resources/icon/Sort/Status/Included.png")
			SE.set_sort_mode(SE.SortStatField.INCLUDED)
		4: # 筛选dead状态
			sort_btns.get_node("Status").texture_normal=load("res://Resources/icon/Sort/Status/Dead.png")
			SE.set_sort_mode(SE.SortStatField.DEAD)

	if UI.current_state!=UI.UIState.SORTED_VIEW:
		UI.change_state(UI.UIState.SORTED_VIEW)

# 数据筛选
func _on_data_toggled(toggled_on: bool) -> void:
	# create_tween().tween_property(get_node("SelectData"),"self_modulate",Color(1, 1, 1,(1 if toggled_on else 0) * 0.87),0.25).set_trans(Tween.TRANS_SINE)
	var SE = SortEngine.instance
	if toggled_on:
		print("按数据筛选")
		SortByData = (SortByData + 1) % 6
		match SortByData:
			0: # 取消筛选（显示全部）
				sort_btns.get_node("Data").texture_normal=load("res://Resources/icon/Sort/Status/All.png")
				# create_tween().tween_property(get_node("SelectData"),"self_modulate",Color(1, 1, 1, 0),0.25).set_trans(Tween.TRANS_SINE)
				SE.set_sort_mode(SE.current_sort_stat_field, SE.SortDataField.DEFAULT)
			1: # 筛选下载数
				sort_btns.get_node("Data").texture_normal=load("res://Resources/icon/Sort/Data/Download.png")
				SE.set_sort_mode(SE.current_sort_stat_field, SE.SortDataField.DOWNLOAD_COUNT)
			2: # 筛选收藏数
				sort_btns.get_node("Data").texture_normal=load("res://Resources/icon/Sort/Data/Favor.png")
				SE.set_sort_mode(SE.current_sort_stat_field, SE.SortDataField.LOVE_COUNT)
			3: # 筛选点赞数
				sort_btns.get_node("Data").texture_normal=load("res://Resources/icon/Sort/Data/Up.png")
				SE.set_sort_mode(SE.current_sort_stat_field, SE.SortDataField.UP_COUNT)
			4: # 筛选游玩数
				sort_btns.get_node("Data").texture_normal=load("res://Resources/icon/Sort/Data/Played.png")
				SE.set_sort_mode(SE.current_sort_stat_field, SE.SortDataField.TRIAL_COUNT)
			5: # 筛选上传时间
				sort_btns.get_node("Data").texture_normal=load("res://Resources/icon/Sort/Data/CreateTime.png")
				SE.set_sort_mode(SE.current_sort_stat_field, SE.SortDataField.UPLOADED_DATE)
		
		if UI.current_state!=UI.UIState.SORTED_VIEW:
			UI.change_state(UI.UIState.SORTED_VIEW)

func _on_ordering_pressed() -> void:
	Ascending = not Ascending
	var SE = SortEngine.instance
	if Ascending:
		print("筛选：升序")
		sort_btns.get_node("Ordering").texture_normal=load("res://Resources/icon/Sort/Ordering/Ascent.png")
		SE.set_sort_mode(SE.current_sort_stat_field, SE.current_sort_field, SE.SortDirection.ASCENDING)
	else:
		print("筛选：降序")
		sort_btns.get_node("Ordering").texture_normal=load("res://Resources/icon/Sort/Ordering/Descent.png")
		SE.set_sort_mode(SE.current_sort_stat_field, SE.current_sort_field, SE.SortDirection.DESCENDING)

	if UI.current_state!=UI.UIState.SORTED_VIEW:
		UI.change_state(UI.UIState.SORTED_VIEW)
