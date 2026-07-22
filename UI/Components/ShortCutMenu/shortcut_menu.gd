extends VBoxContainer

@onready var ui : UIStateManager = UiStatMGR
@onready var se = SortEngine
@onready var ani: AnimationManager = AniMGR

@onready var sort_button = $Btns/Search
@onready var love_button = $Btns/FavorList

@onready var page_container = $Panel # 页面背景
@onready var page = $Panel/Page # 页面内容

@onready var search_lineedit: LineEdit = $Panel/Page/SortPage/SearchBox/TextEdit

# 收藏夹相关节点
@onready var favor_list_container: VBoxContainer = $Panel/Page/FavorPage/FavorList/VBoxC
@onready var favor_list: ScrollContainer = $Panel/Page/FavorPage/FavorList
@onready var create_list: VBoxContainer = $Panel/Page/FavorPage/CreateList
@onready var add_btn: TextureButton = $Panel/Page/FavorPage/CreateList/AddBtn
@onready var favor_page: VBoxContainer = $Panel/Page/FavorPage

# 收藏夹列表项场景
const FAVOR_ITEM_SCENE := preload("res://UI/Components/ShortCutMenu/favorListItem.tscn")
const ICON_ADD := "res://Resources/icon/add.png"
const ICON_CONFIRM := "res://Resources/icon/comfirm.png"
const FAVOR_LIST_DEFAULT_HEIGHT := 530
const FAVOR_LIST_CREATE_HEIGHT := 400

# 新建收藏夹状态
var _is_creating: bool = false
var _create_edit: LineEdit = null

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

	# 收藏夹相关
	add_btn.pressed.connect(_on_add_btn_pressed)
	EvtBus.favorites_loaded.connect(_refresh_favor_list)
	EvtBus.favorites_updated.connect(_refresh_favor_list)
	EvtBus.favorite_list_created.connect(_refresh_favor_list)
	EvtBus.favorite_list_deleted.connect(_refresh_favor_list)
	EvtBus.favorite_list_renamed.connect(_refresh_favor_list)
	EvtBus.favorite_midi_changed.connect(_refresh_favor_list)

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
		search_lineedit.text = ""
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


func _on_search_query(query: String = "") -> void:
	EvtBus.search_query_changed.emit(query if query else search_lineedit.text)

	if ui.current_state!=ui.UIState.SORTED_VIEW:
		ui.change_state(ui.UIState.SORTED_VIEW)


# ========== 收藏夹相关 ==========

## 刷新收藏夹列表
func _refresh_favor_list(_arg1 = null, _arg2 = null, _arg3 = null) -> void:
	if not FavoriteManager.instance:
		return
	# 清空现有列表项
	for child in favor_list_container.get_children():
		child.queue_free()
	# 重新填充
	for fav in FavoriteManager.instance.favorites:
		var item = FAVOR_ITEM_SCENE.instantiate()
		favor_list_container.add_child(item)
		item.setup(fav, FavorListItem.Mode.BROWSE)
		item.favor_item_clicked.connect(_on_favor_item_clicked)
		item.favor_item_renamed.connect(_on_favor_item_renamed)
		item.favor_item_deleted.connect(_on_favor_item_deleted)


## AddBtn 点击：根据当前状态切换新建/确认
func _on_add_btn_pressed() -> void:
	if _is_creating:
		_confirm_create()
	else:
		_enter_create_mode()


## 进入新建模式：显示文本框，切换图标为 confirm
func _enter_create_mode() -> void:
	_is_creating = true
	# 缩小 FavorList 高度为 LineEdit 腾出空间
	favor_list.custom_minimum_size.y = FAVOR_LIST_CREATE_HEIGHT
	_create_edit = LineEdit.new()
	_create_edit.placeholder_text = "输入收藏夹名称"
	_create_edit.custom_minimum_size = Vector2(400, 60)
	_create_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_create_edit.text_submitted.connect(func(_t): _confirm_create())
	# 插入到 CreateList 内部 AddBtn 上方
	create_list.add_child(_create_edit)
	create_list.move_child(_create_edit, 0)
	# 切换 AddBtn 图标为 confirm
	add_btn.texture_normal = load(ICON_CONFIRM)
	_create_edit.grab_focus()


## 确认创建：读取文本，创建收藏夹，恢复 AddBtn 图标
func _confirm_create() -> void:
	if not _is_creating or not _create_edit:
		return
	var fav_name := _create_edit.text.strip_edges()
	_is_creating = false
	_create_edit.queue_free()
	_create_edit = null
	# 恢复 FavorList 高度
	favor_list.custom_minimum_size.y = FAVOR_LIST_DEFAULT_HEIGHT
	# 切换 AddBtn 图标回 add
	add_btn.texture_normal = load(ICON_ADD)
	# 创建收藏夹
	if not fav_name.is_empty():
		FavoriteManager.instance.create_favorite(fav_name)


## 点击收藏夹项：跳转到 SortedMidiView 浏览
func _on_favor_item_clicked(fav_id: String) -> void:
	if fav_id.is_empty():
		return
	EvtBus.favorite_selected_for_browse.emit(fav_id)
	if ui.current_state != ui.UIState.SORTED_VIEW:
		ui.change_state(ui.UIState.SORTED_VIEW)
	# 关闭 ShortCutMenu
	love_button.button_pressed = false


## 重命名收藏夹
func _on_favor_item_renamed(fav_id: String, new_name: String) -> void:
	FavoriteManager.instance.rename_favorite(fav_id, new_name)


## 删除收藏夹（带确认弹窗）
func _on_favor_item_deleted(fav_id: String) -> void:
	var fav := FavoriteManager.instance.get_favorite(fav_id)
	var fav_name := fav.name if fav else ""
	var popup := PopupWindow.instance
	popup.set_message("确定要删除收藏夹 \"%s\" 吗？" % fav_name)
	await popup.window_close
	if popup.confirm:
		FavoriteManager.instance.delete_favorite(fav_id)
