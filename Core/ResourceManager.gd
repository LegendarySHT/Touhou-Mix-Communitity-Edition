extends Node
class_name ResourceManager

## 资源下载管理器：管理 MIDI 等资源的下载、状态追踪
## 通过 project.godot autoload 注册为单例 ResMGR

## 下载状态枚举
enum DownloadState { NOT_DOWNLOADED, DOWNLOADING, DOWNLOADED, FAILED }

static var instance: ResourceManager

## 下载状态缓存 {hash: DownloadState}
var _download_states: Dictionary = {}

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	# 初始化本地已下载状态
	_refresh_local_states()

## 刷新本地下载状态：扫描 FileSystemManager._hash_to_folder
func _refresh_local_states() -> void:
	_download_states.clear()
	if FileSystemManager.instance == null:
		return
	for hash_key in FileSystemManager.instance._hash_to_folder:
		_download_states[hash_key] = DownloadState.DOWNLOADED

# ========== MIDI 资源 API ==========

## 获取 MIDI 列表（分页+搜索）
## 返回 {ok, data: {charts: [], total: int}}
func get_chart_list(page: int = 1, limit: int = 20, search: String = "") -> Dictionary:
	if NetManager.instance == null or not NetManager.instance.is_online:
		return {"ok": false, "error": "offline"}
	var url := "%s/api/charts?page=%d&limit=%d&search=%s" % [
		NetManager.instance.server_url, page, limit, search.uri_encode()
	]
	return await NetManager.instance._request("GET", url, null)

## 下载 MIDI 到本地
## 返回 {"ok": bool, "error": String}
func download_chart(hash: String) -> Dictionary:
	if NetManager.instance == null or not NetManager.instance.is_online:
		return {"ok": false, "error": "offline"}
	if hash.is_empty():
		return {"ok": false, "error": "hash_empty"}
	
	_download_states[hash] = DownloadState.DOWNLOADING
	
	# 1. 获取元数据
	var meta_url := "%s/api/charts/%s" % [NetManager.instance.server_url, hash]
	var meta_result := await NetManager.instance._request("GET", meta_url, null)
	if not meta_result.get("ok", false):
		_download_states[hash] = DownloadState.FAILED
		return {"ok": false, "error": "metadata_fetch_failed: %s" % str(meta_result.get("error", ""))}
	
	var chart_data: Dictionary = meta_result.data
	
	# 2. 构建本地文件夹路径
	var song_name := str(chart_data.get("songName", "unknown"))
	var difficulty := str(chart_data.get("difficulty", "Normal"))
	# 清理文件名中的非法字符
	song_name = _sanitize_folder_name(song_name)
	difficulty = _sanitize_folder_name(difficulty)
	var folder_name := "%s_%s_%s" % [hash, song_name, difficulty]
	var chart_dir := FileSystemManager.CHARTS_DIR.path_join(folder_name)
	
	# 确保目录存在
	DirAccess.make_dir_recursive_absolute(chart_dir)
	
	# 3. 下载 MIDI 文件
	var midi_url := "%s/api/charts/%s/file" % [NetManager.instance.server_url, hash]
	var midi_path := chart_dir.path_join("%s.mid" % hash)
	var midi_result := await _download_file(midi_url, midi_path)
	if not midi_result.get("ok", false):
		_download_states[hash] = DownloadState.FAILED
		return {"ok": false, "error": "midi_download_failed: %s" % str(midi_result.get("error", ""))}
	
	# 4. 下载封面（如有）
	var has_cover := bool(chart_data.get("hasCover", false))
	if has_cover:
		var cover_url := "%s/api/charts/%s/cover" % [NetManager.instance.server_url, hash]
		# 尝试 jpg 和 png 两种扩展名
		var cover_path := chart_dir.path_join("%s-cover.jpg" % hash)
		var cover_result := await _download_file(cover_url, cover_path)
		if not cover_result.get("ok", false):
			# 封面下载失败不阻塞整体流程
			GLogger.warning("Cover download failed for %s: %s" % [hash, str(cover_result.get("error", ""))], "ResMGR")
	
	# 5. 写入元数据 JSON（格式需匹配 MidiData.from_json 期望）
	var json_data := _build_local_json(chart_data)
	var json_path := chart_dir.path_join("%s.json" % hash)
	var json_content := JSON.stringify(json_data)
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f == null:
		_download_states[hash] = DownloadState.FAILED
		return {"ok": false, "error": "json_write_failed"}
	f.store_string(json_content)
	f.close()
	
	# 6. 刷新 FileSystemManager 索引
	if FileSystemManager.instance:
		await FileSystemManager.instance.rescan_resources()
	
	_download_states[hash] = DownloadState.DOWNLOADED
	GLogger.info("Chart downloaded: %s" % hash, "ResMGR")
	return {"ok": true}

## 构建本地 JSON 元数据（匹配 MidiData.from_json 格式）
func _build_local_json(chart_data: Dictionary) -> Dictionary:
	return {
		"_id": str(chart_data.get("hash", "")),
		"name": str(chart_data.get("title", "")),
		"desc": str(chart_data.get("description", "")),
		"status": str(chart_data.get("status", "APPROVED")),
		"artistName": str(chart_data.get("artistName", "")),
		"uploaderName": str(chart_data.get("uploaderName", "")),
		"author": str(chart_data.get("authorName", "")),
		"uploadedDate": str(chart_data.get("uploadedAt", "")),
		"hash": str(chart_data.get("hash", "")),
		"song": {
			"id": str(chart_data.get("songId", "")),
			"name": str(chart_data.get("songName", ""))
		},
		"album": {
			"id": str(chart_data.get("albumId", "")),
			"name": str(chart_data.get("albumName", ""))
		}
	}

## 下载二进制文件到本地路径
func _download_file(url: String, save_path: String) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	# 文件下载可能较大，设置较长超时
	http.timeout = 60.0
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "request_failed: %d" % err}
	var resp = await http.request_completed
	http.queue_free()
	var result_code = resp[0]
	var response_code = resp[1]
	var response_body = resp[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "download_failed: result=%d" % result_code}
	if response_code != 200:
		return {"ok": false, "error": "http_%d" % response_code}
	if not response_body is PackedByteArray or response_body.size() == 0:
		return {"ok": false, "error": "empty_response"}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "file_open_failed: %s" % save_path}
	f.store_buffer(response_body)
	f.close()
	return {"ok": true}

## 清理文件夹名中的非法字符
func _sanitize_folder_name(str: String) -> String:
	var illegal := ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]
	var result := str
	for c in illegal:
		result = result.replace(c, "_")
	return result

## 检查 MIDI 是否已下载
func is_chart_downloaded(chart_hash: String) -> bool:
	return get_download_state(chart_hash) == DownloadState.DOWNLOADED

## 获取下载状态
func get_download_state(chart_hash: String) -> DownloadState:
	if _download_states.has(chart_hash):
		return _download_states[chart_hash]
	# 检查 FileSystemManager 是否有该 hash
	if FileSystemManager.instance and FileSystemManager.instance._hash_to_folder.has(chart_hash):
		_download_states[chart_hash] = DownloadState.DOWNLOADED
		return DownloadState.DOWNLOADED
	return DownloadState.NOT_DOWNLOADED

# ========== 预留接口（未来实现） ==========

## 下载人声音频（预留接口）
func download_vocal(target_hash: String) -> Dictionary:
	return {"ok": false, "error": "not_implemented"}

## 下载 SF2 音源（预留接口）
func download_soundfont(id: String) -> Dictionary:
	return {"ok": false, "error": "not_implemented"}

## 下载皮肤包（预留接口）
func download_skin(id: String) -> Dictionary:
	return {"ok": false, "error": "not_implemented"}
