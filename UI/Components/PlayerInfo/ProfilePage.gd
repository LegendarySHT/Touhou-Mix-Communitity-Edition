extends VBoxContainer

# ========== PageContent（Profile / History / Edit） ==========
@onready var page_content: TabContainer = $PC/PageContent
@onready var navi_profile_btn: Button = $Navi/Btns/Profile
@onready var navi_history_btn: Button = $Navi/Btns/History
@onready var navi_edit_btn: Button = $Navi/Btns/Edit

# ========== History 页面 List 切换 ==========
@onready var history_list: TabContainer = $PC/PageContent/History/List
@onready var recent_play_btn: Button = $PC/PageContent/History/PC/TopBar/TopBtns/RecentPlay
@onready var best_play_btn: Button = $PC/PageContent/History/PC/TopBar/TopBtns/BestPlay
@onready var most_play_btn: Button = $PC/PageContent/History/PC/TopBar/TopBtns/MostPlay

# PageContent tab 索引
const TAB_PROFILE := 0
const TAB_HISTORY := 1
const TAB_EDIT := 2
# History/List tab 索引
const LIST_RECENT := 0
const LIST_BEST := 1
const LIST_MOST := 2

func _ready() -> void:
	navi_profile_btn.pressed.connect(_on_navi_profile_pressed)
	navi_history_btn.pressed.connect(_on_navi_history_pressed)
	navi_edit_btn.pressed.connect(_on_navi_edit_pressed)
	recent_play_btn.pressed.connect(_on_recent_play_pressed)
	best_play_btn.pressed.connect(_on_best_play_pressed)
	most_play_btn.pressed.connect(_on_most_play_pressed)
	# 同步 Navi 初始选中状态（PageContent 默认显示 History）
	_sync_navi_selection(page_content.current_tab)
	# 同步 History TopBtns 初始 z_index（RecentPlay 默认 pressed）
	_sync_topbtn_z_index(recent_play_btn)

# ========== Navi → PageContent 切换 ==========

func _on_navi_profile_pressed() -> void:
	page_content.current_tab = TAB_PROFILE

func _on_navi_history_pressed() -> void:
	page_content.current_tab = TAB_HISTORY

func _on_navi_edit_pressed() -> void:
	page_content.current_tab = TAB_EDIT

func _sync_navi_selection(tab_idx: int) -> void:
	navi_profile_btn.button_pressed = (tab_idx == TAB_PROFILE)
	navi_history_btn.button_pressed = (tab_idx == TAB_HISTORY)
	navi_edit_btn.button_pressed = (tab_idx == TAB_EDIT)

# ========== History TopBar → List 切换 + z_index ==========

func _on_recent_play_pressed() -> void:
	_switch_history_list(LIST_RECENT, recent_play_btn)

func _on_best_play_pressed() -> void:
	_switch_history_list(LIST_BEST, best_play_btn)

func _on_most_play_pressed() -> void:
	_switch_history_list(LIST_MOST, most_play_btn)

## 切换 History/List 的 tab，并把激活按钮 z_index 抬到 1，其余压回 0
## 避免相邻按钮 stylebox 超边界部分被遮挡
func _switch_history_list(tab_idx: int, active_btn: Button) -> void:
	if tab_idx < history_list.get_tab_count():
		history_list.current_tab = tab_idx
	_sync_topbtn_z_index(active_btn)

func _sync_topbtn_z_index(active_btn: Button) -> void:
	recent_play_btn.z_index = 1 if recent_play_btn == active_btn else 0
	best_play_btn.z_index = 1 if best_play_btn == active_btn else 0
	most_play_btn.z_index = 1 if most_play_btn == active_btn else 0

# ========== Edit 页面保存按钮（占位） ==========

func _on_upload_avatar_btn_pressed() -> void:
	pass # Replace with function body.


func _on_save_nickname_btn_pressed() -> void:
	pass # Replace with function body.


func _on_save_desc_btn_pressed() -> void:
	pass # Replace with function body.


func _on_save_pwd_btn_pressed() -> void:
	pass # Replace with function body.
