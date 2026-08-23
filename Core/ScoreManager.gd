extends Node
class_name ScoreManager

## 成绩管理器：成绩上传、排行榜查询、设备标识管理
## 通过 Main.gd 手动 add_child，使用 ScoreManager.instance 访问

static var instance: ScoreManager = null

## 设备标识文件路径：user://files/device_id.txt
const DEVICE_ID_FILE: String = "user://files/device_id.txt"

## 当前设备标识（首次启动时生成，持久化存储）
var _device_id: String = ""

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	add_to_group("singleton")
	_load_or_create_device_id()
	GLogger.info("ScoreManager initialized (device_id=%s)" % _device_id, "ScoreMGR")


## 加载或生成设备标识
## 首次启动生成 UUIDv4，存入 user://files/device_id.txt
func _load_or_create_device_id() -> void:
	if FileAccess.file_exists(DEVICE_ID_FILE):
		var file := FileAccess.open(DEVICE_ID_FILE, FileAccess.READ)
		if file:
			_device_id = file.get_as_text().strip_edges()
			if not _device_id.is_empty():
				return
	# 生成新设备标识
	_device_id = _generate_uuid_v4()
	# 确保目录存在
	var dir := DirAccess.open("user://files")
	if dir == null:
		DirAccess.make_dir_recursive_absolute("user://files")
	var f := FileAccess.open(DEVICE_ID_FILE, FileAccess.WRITE)
	if f:
		f.store_string(_device_id)
		GLogger.info("Generated new device_id: %s" % _device_id, "ScoreMGR")


## 生成简化版 UUIDv4（不依赖外部库）
func _generate_uuid_v4() -> String:
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in range(16):
		bytes[i] = randi() % 256
	# RFC 4122 版本位：第 6 字节高 4 位为 0100（版本 4）
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	# 变体位：第 8 字节高 2 位为 10
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	# 格式化为 8-4-4-4-12
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


## 保存本地最佳成绩：打歌完成后调用，无论在线与否都写入
## 每首 MIDI 只保留 pp 最高的一条记录；中途退出（W 评级）不计入
func save_local_score(midi: MidiData, snapshot: Dictionary) -> void:
	if midi == null or midi.file_hash.is_empty():
		return
	var rank := str(snapshot.get("rank", "F"))
	if rank == "W":
		return
	if ChartDB == null or not ChartDB.IsOpen():
		GLogger.warning("Local score save skipped: ChartDB not ready", "ScoreMGR")
		return
	var hash := midi.file_hash
	var cur: Dictionary = ChartDB.GetLocalBest(hash)
	if not cur.is_empty() and float(cur.get("pp", 0.0)) >= float(snapshot.get("pp", 0.0)):
		return  # 已有更高或相同 pp，不覆盖
	var record: Dictionary = _extract_payload(midi, snapshot)
	record["timestamp"] = Time.get_unix_time_from_system()
	ChartDB.SaveLocalScore(hash, record)
	GLogger.info("Local score saved: midi=%s pp=%s" % [hash, str(record.get("pp", 0))], "ScoreMGR")


## 读取某 MIDI 的本地最佳成绩（无记录返回空字典）
func get_local_best(midi_hash: String) -> Dictionary:
	if ChartDB == null or not ChartDB.IsOpen():
		return {}
	return ChartDB.GetLocalBest(midi_hash)


## 从 ScoreCalculator.get_snapshot() 和 MidiData 提取上传载荷
## 注意：键名使用 camelCase，与服务端 ASP.NET Core DTO 反序列化默认格式匹配
func _extract_payload(midi: MidiData, snapshot: Dictionary) -> Dictionary:
	var counts: Dictionary = snapshot.get("judge_counts", {})
	var rank := str(snapshot.get("rank", "F"))
	return {
		"midiHash": midi.file_hash,
		"deviceId": _device_id,
		"totalScore": int(snapshot.get("total_score", 0)),
		"maxCombo": int(snapshot.get("max_combo", 0)),
		"accuracy": float(snapshot.get("accuracy", 0.0)),
		"pp": float(snapshot.get("pp", 0.0)),
		"rank": rank,
		"perfectCount": int(counts.get(ScoreCalculator.Judgment.PERFECT, 0)),
		"greatCount": int(counts.get(ScoreCalculator.Judgment.GREAT, 0)),
		"goodCount": int(counts.get(ScoreCalculator.Judgment.GOOD, 0)),
		"badCount": int(counts.get(ScoreCalculator.Judgment.BAD, 0)),
		"missCount": int(counts.get(ScoreCalculator.Judgment.MISS, 0)),
		"earlyCount": int(snapshot.get("early_count", 0)),
		"lateCount": int(snapshot.get("late_count", 0)),
		"totalNotes": int(snapshot.get("total_notes", 0)),
		# cleared: 完成（非 F 且非 W）。W = 中途退出，不算完成
		"cleared": rank != "F" and rank != "W",
		"playDurationMs": int(snapshot.get("play_duration_ms", 0)),
	}


## 上传成绩
## midi: MidiData 对象（需要 file_hash 非空）
## snapshot: ScoreCalculator.get_snapshot() 返回的字典
## 返回 { ok, status, data, error }
## 去重逻辑由服务端处理：同设备/同用户 + 同 MIDI 只保留最高分
func upload_score(midi: MidiData, snapshot: Dictionary) -> Dictionary:
	if midi.file_hash.is_empty():
		return { "ok": false, "status": 0, "data": null, "error": "midi_hash_empty" }
	# 未登录时不提交到匿名账号，由上层提示用户先登录后再重试
	if AuthManager.instance == null or not AuthManager.instance.is_logged_in:
		return { "ok": false, "status": 0, "data": null, "error": "not_logged_in" }
	var token := ""
	# 确保 access token 有效（过期则自动 refresh）
	if await AuthManager.instance.ensure_valid_token():
		token = AuthManager.instance.current_user.access_token
	else:
		return { "ok": false, "status": 0, "data": null, "error": "token_refresh_failed" }
	var body := _extract_payload(midi, snapshot)
	var url := "%s/api/scores" % NetManager.instance.server_url
	return await NetManager.instance._request("POST", url, body, PackedStringArray(), token)


## 获取排行榜
func get_leaderboard(midi_hash: String, limit: int = 20, offset: int = 0) -> Dictionary:
	var url := "%s/api/scores/leaderboard?midi_hash=%s&limit=%d&offset=%d" % [
		NetManager.instance.server_url, midi_hash.uri_encode(), limit, offset
	]
	return await NetManager.instance._request("GET", url, null)


## 获取当前用户在该 MIDI 的最佳成绩（需登录）
func get_my_best(midi_hash: String) -> Dictionary:
	var url := "%s/api/scores/mine?midi_hash=%s" % [
		NetManager.instance.server_url, midi_hash.uri_encode()
	]
	var token := ""
	if AuthManager.instance and AuthManager.instance.is_logged_in:
		token = AuthManager.instance.current_user.access_token
	return await NetManager.instance._request("GET", url, null, PackedStringArray(), token)


## 获取某 MIDI 的聚合统计
func get_stats(midi_hash: String) -> Dictionary:
	var url := "%s/api/scores/stats?midi_hash=%s" % [
		NetManager.instance.server_url, midi_hash.uri_encode()
	]
	return await NetManager.instance._request("GET", url, null)
