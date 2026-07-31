extends Node
class_name NetManager

## 在线管理器：HTTP 请求封装、服务端连接管理
## 通过 Main.gd 手动 add_child，使用 NetManager.instance 访问

static var instance: NetManager = null

## 服务器地址（从 ConfigManager [General] server_address 读取）
var server_url: String = ""

## 当前是否在线（服务端可达）
var is_online: bool = false

## 请求超时（秒）
const REQUEST_TIMEOUT: float = 10.0

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	add_to_group("singleton")
	_load_server_url()
	GLogger.info("NetManager initialized, server_url=%s" % server_url, "NetMGR")

## 从配置加载服务器地址
func _load_server_url() -> void:
	var addr = ConfigManager.instance.get_string("General", "server_address", "thmix.org")
	# 若地址不含 http 前缀，默认补 http://localhost:5000（开发期）
	if not addr.begins_with("http"):
		server_url = "http://localhost:5000"
	else:
		server_url = addr

## 健康检查：GET /api/health
## 返回 { ok, status, data, error }
func check_health() -> Dictionary:
	var url = "%s/api/health" % server_url
	return await _request("GET", url, {})

## 通用请求方法
## method: "GET"/"POST"/"PATCH"/"DELETE"
## url: 完整 URL
## body: Dictionary（自动 JSON 序列化）或 null
## headers: 额外请求头
## auth_token: 可选 Bearer token
## 返回：{ "ok": bool, "status": int, "data": Variant, "error": String }
func _request(method: String, url: String, body: Variant, headers: PackedStringArray = PackedStringArray(), auth_token: String = "") -> Dictionary:
	var http = HTTPRequest.new()
	add_child(http)
	http.timeout = REQUEST_TIMEOUT

	var all_headers = headers.duplicate()
	all_headers.append("Content-Type: application/json")
	if not auth_token.is_empty():
		all_headers.append("Authorization: Bearer %s" % auth_token)

	var body_str = ""
	if body is Dictionary and not body.is_empty():
		body_str = JSON.stringify(body)

	EvtBus.online_request_started.emit(url)

	var err = http.request(url, all_headers, _method_to_http_client(method), body_str)
	if err != OK:
		EvtBus.online_request_finished.emit(url, false)
		http.queue_free()
		return { "ok": false, "status": 0, "data": null, "error": "request_failed: %d" % err }

	var resp = await http.request_completed
	var result_code = resp[0]
	var response_code = resp[1]
	var response_body = resp[3]

	http.queue_free()

	var data: Variant = null
	if response_body is PackedByteArray and response_body.size() > 0:
		var text = response_body.get_string_from_utf8()
		data = JSON.parse_string(text)

	var ok = result_code == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	EvtBus.online_request_finished.emit(url, ok)
	return {
		"ok": ok,
		"status": response_code,
		"data": data,
		"error": "" if ok else "HTTP %d (result=%d)" % [response_code, result_code]
	}

func _method_to_http_client(method: String) -> int:
	match method:
		"GET": return HTTPClient.METHOD_GET
		"POST": return HTTPClient.METHOD_POST
		"PATCH": return HTTPClient.METHOD_PATCH
		"DELETE": return HTTPClient.METHOD_DELETE
		_: return HTTPClient.METHOD_GET

## 测试连接并更新 is_online 状态
func test_connection() -> bool:
	var result = await check_health()
	var was_online = is_online
	is_online = result.get("ok", false)
	if is_online != was_online:
		EvtBus.online_status_changed.emit(is_online, result.get("error", ""))
	GLogger.info("Connection test: %s (%s)" % ["online" if is_online else "offline", result.get("error", "ok")], "NetMGR")
	return is_online
