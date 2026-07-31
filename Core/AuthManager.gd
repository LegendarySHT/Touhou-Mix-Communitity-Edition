extends Node
class_name AuthManager

## 认证管理器：登录态、token 持久化、带认证的请求
## 通过 Main.gd 手动 add_child，使用 AuthManager.instance 访问

static var instance: AuthManager = null

## Token 文件路径：user://files/auth.json
const TOKEN_FILE: String = "user://files/auth.json"

## 当前用户数据（null 表示未登录）
## 结构：{ "username": "...", "access_token": "...", "refresh_token": "...", "expires_at": int }
var current_user: Variant = null

## 是否已登录
var is_logged_in: bool:
	get:
		return current_user != null and not current_user.get("access_token", "").is_empty()

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	add_to_group("singleton")
	_load_session()
	GLogger.info("AuthManager initialized, logged_in=%s" % is_logged_in, "AuthMGR")

## 从本地加载已保存的会话
func _load_session() -> void:
	var data = ConfigManager.instance.load_json_file(TOKEN_FILE)
	if data.is_empty():
		return
	# 简单过期检查（expires_at 是 unix 时间戳）
	var expires_at = data.get("expires_at", 0)
	if expires_at > 0 and Time.get_unix_time_from_system() > expires_at:
		# access token 过期，本期简单丢弃（不实现 refresh）
		_clear_session()
		return
	current_user = data
	EvtBus.auth_changed.emit(current_user)

## 保存会话到本地
func _save_session(data: Dictionary) -> void:
	current_user = data
	ConfigManager.instance.save_json_file(TOKEN_FILE, data, true)
	EvtBus.auth_changed.emit(current_user)

## 清除本地会话
func _clear_session() -> void:
	current_user = null
	if FileAccess.file_exists(TOKEN_FILE):
		DirAccess.remove_absolute(TOKEN_FILE)
	EvtBus.auth_changed.emit(null)

## 注册
## 返回 { "ok": bool, "error": String }
func register(username: String, password: String) -> Dictionary:
	var result = await NetManager.instance._request(
		"POST",
		"%s/api/auth/register" % NetManager.instance.server_url,
		{ "username": username, "password": password }
	)
	if not result.ok:
		return { "ok": false, "error": result.error }
	return { "ok": true, "error": "" }

## 登录
## 成功后自动保存 token
func login(username: String, password: String) -> Dictionary:
	var result = await NetManager.instance._request(
		"POST",
		"%s/api/auth/login" % NetManager.instance.server_url,
		{ "username": username, "password": password }
	)
	if not result.ok:
		return { "ok": false, "error": result.error }
	var data = result.data
	if data == null or not data is Dictionary:
		return { "ok": false, "error": "invalid_response" }
	var session = {
		"username": data.get("username", username),
		"access_token": data.get("accessToken", ""),
		"refresh_token": data.get("refreshToken", ""),
		"expires_at": data.get("expiresAt", 0),
		"refresh_expires_at": data.get("refreshExpiresAt", 0),
		"role": data.get("role", "user")
	}
	_save_session(session)
	GLogger.info("Login successful: %s" % username, "AuthMGR")
	return { "ok": true, "error": "" }

## 登出
func logout() -> void:
	_clear_session()
	GLogger.info("Logged out", "AuthMGR")

## 带认证的请求（封装 NetManager._request，自动附加 token）
func authed_request(method: String, path: String, body: Variant = null) -> Dictionary:
	if not is_logged_in:
		return { "ok": false, "status": 0, "data": null, "error": "not_logged_in" }
	var url = "%s%s" % [NetManager.instance.server_url, path]
	return await NetManager.instance._request(
		method, url, body, PackedStringArray(), current_user.access_token
	)

## 验证当前 token 是否有效：GET /api/auth/me
func verify_token() -> bool:
	if not is_logged_in:
		return false
	var result = await authed_request("GET", "/api/auth/me")
	var valid = result.ok
	if not valid:
		# token 失效，清除会话
		_clear_session()
	return valid
