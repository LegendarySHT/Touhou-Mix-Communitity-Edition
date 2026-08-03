extends TabContainer
class_name PlayerInfoContent

## PlayerInfo 的内容容器，管理 MiniInfo / LogIn / ProfileView / ProfilePage 四个 tab。
## 负责表单交互、个人信息填充等页面内逻辑；
## 状态切换、面板几何动画由 PlayerInfo.gd 处理。

signal login_submitted()
signal logout_submitted()
signal expand_toggled()

enum LoginMode { LOGIN, REGISTER }

# 玩家数据（登录后从 AuthManager.current_user 填充）
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
@onready var logout_btn: Button = $ProfileView/LogoutBtn

var _login_mode: LoginMode = LoginMode.LOGIN
## 提交进行中（防止重复点击）
var _submitting: bool = false

func _ready() -> void:
	_set_login_mode(LoginMode.LOGIN)
	# 监听认证状态变化，自动同步显示
	if not EvtBus.auth_changed.is_connected(_on_auth_changed):
		EvtBus.auth_changed.connect(_on_auth_changed)
	# 启动时若已登录（从本地恢复会话），立即填充
	_sync_from_auth()

## 认证状态变化回调
func _on_auth_changed(user_data: Variant) -> void:
	_sync_from_auth()

## 从 AuthManager 同步登录态到本地显示
func _sync_from_auth() -> void:
	if AuthManager.instance != null and AuthManager.instance.is_logged_in:
		var username := str(AuthManager.instance.current_user.get("username", ""))
		if not username.is_empty():
			_player_data.name = username
			populate_profile()
			populate_mini_info()
	else:
		_player_data.name = "Anonymous Player"
		populate_profile()
		populate_mini_info()

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
	if _submitting:
		return
	if AuthManager.instance == null:
		error_msg.text = "认证服务未就绪"
		return
	if NetManager.instance == null or not NetManager.instance.is_online:
		error_msg.text = "未连接服务器"
		return
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

	_submitting = true
	submit_btn.disabled = true
	error_msg.text = "处理中..."

	var ok := false
	var err_msg := ""
	if _login_mode == LoginMode.REGISTER:
		var result: Dictionary = await AuthManager.instance.register(account, pwd)
		ok = result.ok
		err_msg = str(result.get("error", ""))
		if ok:
			# 注册成功后自动登录
			var login_result: Dictionary = await AuthManager.instance.login(account, pwd)
			ok = login_result.ok
			err_msg = str(login_result.get("error", ""))
	else:
		var result: Dictionary = await AuthManager.instance.login(account, pwd)
		ok = result.ok
		err_msg = str(result.get("error", ""))

	_submitting = false
	submit_btn.disabled = false

	if ok:
		_clear_login_form()
		login_submitted.emit()
	else:
		error_msg.text = _format_error(err_msg)

## 登出按钮
func _on_logout_btn_pressed() -> void:
	if AuthManager.instance == null:
		return
	AuthManager.instance.logout()
	logout_submitted.emit()

## 将服务端错误码转为中文提示
func _format_error(err: String) -> String:
	match err:
		"username_taken":
			return "用户名已被占用"
		"invalid_credentials":
			return "用户名或密码错误"
		"network_error", "timeout":
			return "网络错误，请重试"
		_:
			return "操作失败: %s" % err if not err.is_empty() else "操作失败"

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
