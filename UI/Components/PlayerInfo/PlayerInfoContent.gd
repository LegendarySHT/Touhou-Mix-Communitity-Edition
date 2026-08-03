extends TabContainer
class_name PlayerInfoContent

## PlayerInfo 的内容容器，管理 MiniInfo / LogIn / ProfileView / ProfilePage 四个 tab。
## 负责表单交互、个人信息填充等页面内逻辑；
## 状态切换、面板几何动画由 PlayerInfo.gd 处理。

signal login_submitted()
signal expand_toggled()

enum LoginMode { LOGIN, REGISTER }

# Mock 玩家数据（后续替换为真实数据源）
var _player_data := {
	"name": "Anonymous Player",
	"level": 1,
	"pp": 0,
	"rank": 0,
	"total_plays": 0,
	"accuracy": 0.0,
	"max_combo": 0,
	"play_time_hours": 0,
	"level_progress": 0.0,
	"grades": {"SS": 0, "S": 0, "A": 0, "B": 0, "C": 0, "D": 0},
	"recent_scores": [],
}

# MiniInfo（收起状态）
@onready var tip: Control = $MiniInfo/Tip
@onready var tip_label: Label = $MiniInfo/Tip/Label
@onready var avatar: Panel = $MiniInfo/Avatar
@onready var data: VBoxContainer = $MiniInfo/Data
@onready var mini_name: Label = $MiniInfo/Data/name
@onready var mini_level: Label = $MiniInfo/Data/level
@onready var mini_pp: Label = $MiniInfo/Data/pp
@onready var mini_progress: ProgressBar = $MiniInfo/Data/MC/ProgressBar
# LogIn（登录/注册表单）
@onready var login_tab: Button = $C/Skew/LogIn/ModeToggle/LoginTab
@onready var signup_tab: Button = $C/Skew/LogIn/ModeToggle/SignUpTab
@onready var account_edit: LineEdit = $C/Skew/LogIn/AccountLineEdit
@onready var pwd_edit: LineEdit = $C/Skew/LogIn/PwdLineEdit
@onready var confirm_pwd_label: Label = $C/Skew/LogIn/ConfirmPassword
@onready var confirm_pwd_edit: LineEdit = $C/Skew/LogIn/ConfirmPwdLineEdit
@onready var submit_btn: Button = $C/Skew/LogIn/SubmitBtn
@onready var error_msg: Label = $C/Skew/LogIn/ErrorMsg
# ProfileView（个人信息概要，半展开状态）
@onready var profile_name: Label = $ProfileView/Header/NameLevelVBox/NameLabel
@onready var profile_level: Label = $ProfileView/Header/NameLevelVBox/HBox/VBox/HBox/LevelLabel
@onready var profile_pp: Label = $ProfileView/Header/NameLevelVBox/HBox/VBox/HBox/PPLabel
@onready var profile_rank: Label = $ProfileView/Header/NameLevelVBox/HBox/RankLabel
@onready var level_progress: ProgressBar = $ProfileView/ProgressMC/LevelProgressBar
@onready var total_plays_label: Label = $ProfileView/StatsGrid/TotalPlaysLabel
@onready var accuracy_label: Label = $ProfileView/StatsGrid/AccuracyLabel
@onready var max_combo_label: Label = $ProfileView/StatsGrid/MaxComboLabel
@onready var play_time_label: Label = $ProfileView/StatsGrid/PlayTimeLabel
@onready var expand_btn: Button = $ProfileView/ExpandBtn

var _login_mode: LoginMode = LoginMode.LOGIN

func _ready() -> void:
	_set_login_mode(LoginMode.LOGIN)

# ========== 内容可见性（供 PlayerInfo 调用） ==========

## 收起状态切换 MiniInfo 内部可见性
func apply_mini_visibility(show_tip: bool) -> void:
	tip_label.visible = show_tip
	avatar.visible = not show_tip
	data.visible = not show_tip

## ProfileView 详情切换：
## full=false（LOGGED_IN_EXPANDED）→ tab 2 概要页
## full=true （FULL_EXPANDED）      → tab 3 ProfilePage 详情页
func apply_profile_visibility(full: bool) -> void:
	current_tab = 3 if full else 2
	expand_btn.text = "收起详情" if full else "展开详情"

# ========== 登录/注册表单 ==========

func _on_login_tab_pressed() -> void:
	_set_login_mode(LoginMode.LOGIN)

func _on_signup_tab_pressed() -> void:
	_set_login_mode(LoginMode.REGISTER)

func _set_login_mode(mode: LoginMode) -> void:
	_login_mode = mode
	var is_register := mode == LoginMode.REGISTER
	login_tab.button_pressed = not is_register
	signup_tab.button_pressed = is_register
	confirm_pwd_label.visible = is_register
	confirm_pwd_edit.visible = is_register
	submit_btn.text = "注册" if is_register else "登录"
	error_msg.text = ""

func _on_submit_btn_pressed() -> void:
	var account := account_edit.text.strip_edges()
	var pwd := pwd_edit.text
	if account.is_empty() or pwd.is_empty():
		error_msg.text = "帐号和密码不能为空"
		return
	if _login_mode == LoginMode.REGISTER:
		var confirm_pwd := confirm_pwd_edit.text
		if confirm_pwd != pwd:
			error_msg.text = "两次密码不一致"
			return
	# 模拟登录/注册成功（后续替换为真实网络请求）
	_player_data.name = account
	populate_profile()
	populate_mini_info()
	_clear_login_form()
	login_submitted.emit()

func _clear_login_form() -> void:
	account_edit.text = ""
	pwd_edit.text = ""
	confirm_pwd_edit.text = ""
	error_msg.text = ""

# ========== 个人信息页面 ==========

## 从 _player_data 填充 ProfileView 的所有 label
func populate_profile() -> void:
	profile_name.text = _player_data.name
	profile_level.text = "Level %d" % _player_data.level
	profile_pp.text = "%d pp" % _player_data.pp
	if _player_data.rank > 0:
		profile_rank.text = "Global Rank: #%d" % _player_data.rank
	else:
		profile_rank.text = "Unranked"
	level_progress.value = _player_data.level_progress * 100.0
	total_plays_label.text = "Total Plays: %d" % _player_data.total_plays
	accuracy_label.text = "Accuracy: %.2f%%" % _player_data.accuracy
	max_combo_label.text = "Max Combo: %d" % _player_data.max_combo
	play_time_label.text = "Play Time: %dh" % _player_data.play_time_hours

## 从 _player_data 填充 MiniInfo/Data 的 label（收起状态显示）
func populate_mini_info() -> void:
	mini_name.text = _player_data.name
	mini_level.text = "Lv%d" % _player_data.level
	mini_pp.text = "%d pp" % _player_data.pp
	mini_progress.value = _player_data.level_progress * 100.0

func _on_expand_btn_pressed() -> void:
	expand_toggled.emit()

## 更新玩家数据并刷新显示
func update_player_data(player_data: Dictionary) -> void:
	for key in player_data:
		_player_data[key] = player_data[key]
	populate_profile()
	populate_mini_info()
