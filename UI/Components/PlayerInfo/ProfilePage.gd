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

# ========== 主题色引用节点（每个共享 StyleBox 取一个代表节点） ==========
@onready var _info_panel: PanelContainer = $PC/PageContent/Profile/Main/PC/Displayer/Info
@onready var _header_panel: PanelContainer = $PC/PageContent/Profile/Main/Header
@onready var _play_panel: PanelContainer = $PC/PageContent/Profile/Data/VBox/Play
@onready var _rank_total: PanelContainer = $PC/PageContent/Profile/Data/VBox/Desc/Rank/RankTotal
@onready var _navi_panel: PanelContainer = $Navi
@onready var _history_pc: PanelContainer = $PC/PageContent/History/PC
@onready var _edit_confirm_btn: Button = $PC/PageContent/Edit/HBox/ProfileEdit/Nickname/ConfirmBtn

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
	_sync_navi_selection(page_content.current_tab)
	_sync_topbtn_z_index(recent_play_btn)
	if ThemeMGR:
		ThemeMGR.register_theme_applier(self)
		apply_theme()

func _exit_tree() -> void:
	if ThemeMGR:
		ThemeMGR.unregister_theme_applier(self)

# ========== 主题色应用 ==========

## 规则：亮蓝 bg → primary_light，暗蓝 bg → primary_dark，中等蓝 bg → primary
## 暗蓝边框 → primary_dark.darkened()，亮蓝边框 → primary_light
## 近黑 bg 保持不动，只替换蓝色边框
func apply_theme() -> void:
	var pl := ThemeMGR.get_color("primary_light")
	var p := ThemeMGR.get_color("primary")
	var pd := ThemeMGR.get_color("primary_dark")
	var pd_darker := pd.darkened(0.2)

	# Profile 页面面板
	_set_panel(_info_panel, pl, pd_darker)      # Info: 亮蓝 bg, 暗蓝 border
	_set_panel(_header_panel, pd, pl)            # Header: 暗蓝 bg, 亮蓝 border
	_set_panel(_play_panel, pd, pl)              # Play + Desc Label（共享）: 暗蓝 bg, 亮蓝 border
	_set_panel(_rank_total, pl, pd_darker)       # RankTotal: 亮蓝 bg, 暗蓝 border
	# Navi 面板
	_set_panel(_navi_panel, pl, pd_darker)       # Navi: 亮蓝 bg, 暗蓝 border
	# History 顶部面板（近黑 bg 保持，只改暗蓝边框）
	_set_panel_border(_history_pc, pd_darker)
	# Navi 按钮（normal/pressed/hover/focus 共享 StyleBox，改 navi_profile_btn 即同步全部）
	# pressed 与 InfoPanelBtn 按下态同色（primary_dark），视觉上融入 PlayerInfo 面板背景
	_set_btn(navi_profile_btn, "normal", pl, pd_darker)
	_set_btn(navi_profile_btn, "pressed", pd, pd_darker)
	_set_btn(navi_profile_btn, "hover", p, pd_darker)
	_set_btn(navi_profile_btn, "focus", p, pd_darker)
	# History TopBtns（近黑 bg 保持，只改蓝色边框）
	_set_btn_border(recent_play_btn, "pressed", pl)
	_set_btn_border(recent_play_btn, "hover", pl)
	# MostPlay hover 用单独 StyleBox（665dv，近黑 bg），只改边框
	_set_btn_border(most_play_btn, "hover", pl)
	# Edit 页面 ConfirmBtn / UploadBtn（共享 StyleBox）
	_set_btn(_edit_confirm_btn, "normal", pl, pl)
	_set_btn(_edit_confirm_btn, "pressed", pd, pl)
	_set_btn(_edit_confirm_btn, "hover", p, pl)

## 设置面板 bg + border
func _set_panel(node: Control, bg: Color, border: Color) -> void:
	if not node:
		return
	var sb := node.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		sb.bg_color = bg
		sb.border_color = border

## 仅设置面板 border（保留原 bg）
func _set_panel_border(node: Control, border: Color) -> void:
	if not node:
		return
	var sb := node.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		sb.border_color = border

## 设置按钮某状态的 bg + border
func _set_btn(btn: Button, state: String, bg: Color, border: Color) -> void:
	if not btn:
		return
	var sb := btn.get_theme_stylebox(state)
	if sb is StyleBoxFlat:
		sb.bg_color = bg
		sb.border_color = border

## 仅设置按钮某状态的 border（保留原 bg 和 border alpha）
func _set_btn_border(btn: Button, state: String, border: Color) -> void:
	if not btn:
		return
	var sb := btn.get_theme_stylebox(state)
	if sb is StyleBoxFlat:
		var a = sb.border_color.a
		sb.border_color = Color(border.r, border.g, border.b, a)

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
