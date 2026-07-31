## 在线功能测试临时视图（PopupPanel 实现）
## 通过 SettingList._popup_online_test 弹出，后续替换为正式 LoginView
extends PopupPanel

class_name OnlineTestView

var _status_label: Label
var _username_edit: LineEdit
var _password_edit: LineEdit

func _ready() -> void:
	# 关闭时自动释放
	popup_hide.connect(queue_free)
	_build_ui()

func _build_ui() -> void:
	size = Vector2(420, 480)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "在线功能测试"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.text = "状态: 未知"
	vbox.add_child(_status_label)

	var user_label := Label.new()
	user_label.text = "用户名:"
	vbox.add_child(user_label)
	_username_edit = LineEdit.new()
	_username_edit.placeholder_text = "用户名"
	vbox.add_child(_username_edit)

	var pass_label := Label.new()
	pass_label.text = "密码:"
	vbox.add_child(pass_label)
	_password_edit = LineEdit.new()
	_password_edit.placeholder_text = "密码（至少6位）"
	_password_edit.secret = true
	vbox.add_child(_password_edit)

	var btn_row1 := HBoxContainer.new()
	vbox.add_child(btn_row1)

	var btn_test := Button.new()
	btn_test.text = "测试连接"
	btn_test.pressed.connect(_on_test_connection)
	btn_row1.add_child(btn_test)

	var btn_register := Button.new()
	btn_register.text = "注册"
	btn_register.pressed.connect(_on_register)
	btn_row1.add_child(btn_register)

	var btn_login := Button.new()
	btn_login.text = "登录"
	btn_login.pressed.connect(_on_login)
	btn_row1.add_child(btn_login)

	var btn_row2 := HBoxContainer.new()
	vbox.add_child(btn_row2)

	var btn_verify := Button.new()
	btn_verify.text = "验证token"
	btn_verify.pressed.connect(_on_verify_token)
	btn_row2.add_child(btn_verify)

	var btn_logout := Button.new()
	btn_logout.text = "登出"
	btn_logout.pressed.connect(_on_logout)
	btn_row2.add_child(btn_logout)

	var btn_close := Button.new()
	btn_close.text = "关闭"
	btn_close.pressed.connect(hide)
	vbox.add_child(btn_close)

	EvtBus.online_status_changed.connect(_on_status_changed)
	EvtBus.auth_changed.connect(_on_auth_changed)
	_update_status_label()

func _update_status_label() -> void:
	var online_str := "未知"
	if NetManager.instance != null:
		online_str = "已连接" if NetManager.instance.is_online else "未连接"
	var login_str := "未登录"
	if AuthManager.instance != null and AuthManager.instance.is_logged_in:
		var username := str(AuthManager.instance.current_user.get("username", ""))
		login_str = "已登录: %s" % username
	_status_label.text = "状态: %s | %s" % [online_str, login_str]

func _on_status_changed(_online: bool, _message: String) -> void:
	_update_status_label()

func _on_auth_changed(_user_data: Variant) -> void:
	_update_status_label()

func _on_test_connection() -> void:
	if NetManager.instance == null:
		await _show_msg("NetManager 未初始化")
		return
	var online := await NetManager.instance.test_connection()
	await _show_msg("连接测试: %s" % ("成功" if online else "失败"))

func _on_register() -> void:
	if AuthManager.instance == null:
		await _show_msg("AuthManager 未初始化")
		return
	var username := _username_edit.text.strip_edges()
	var password := _password_edit.text
	if username.is_empty() or password.is_empty():
		await _show_msg("用户名和密码不能为空")
		return
	var result: Dictionary = await AuthManager.instance.register(username, password)
	if result.ok:
		await _show_msg("注册成功，请登录")
	else:
		await _show_msg("注册失败: %s" % str(result.get("error", "")))

func _on_login() -> void:
	if AuthManager.instance == null:
		await _show_msg("AuthManager 未初始化")
		return
	var username := _username_edit.text.strip_edges()
	var password := _password_edit.text
	if username.is_empty() or password.is_empty():
		await _show_msg("用户名和密码不能为空")
		return
	var result: Dictionary = await AuthManager.instance.login(username, password)
	if result.ok:
		await _show_msg("登录成功")
	else:
		await _show_msg("登录失败: %s" % str(result.get("error", "")))

func _on_verify_token() -> void:
	if AuthManager.instance == null:
		await _show_msg("AuthManager 未初始化")
		return
	if not AuthManager.instance.is_logged_in:
		await _show_msg("未登录，无 token 可验证")
		return
	var valid := await AuthManager.instance.verify_token()
	await _show_msg("Token %s" % ("有效" if valid else "无效（已登出）"))

func _on_logout() -> void:
	if AuthManager.instance == null:
		await _show_msg("AuthManager 未初始化")
		return
	AuthManager.instance.logout()
	await _show_msg("已登出")

func _show_msg(msg: String) -> void:
	var popup = PopupWindow.instance
	if popup and popup.has_method("show_message"):
		await popup.show_message(msg, false)
	else:
		GLogger.info("[OnlineTest] %s" % msg, "OnlineTest")
