extends BaseScrollList

class_name ScoreList

## 排行榜单次加载条数
const LOAD_LIMIT := 50

## 当前关联的 MIDI（用于刷新）
var _current_midi: MidiData = null

## 加载中标记
var _loading: bool = false

## 请求版本号：快速切换 MIDI 时丢弃过期响应
var _request_version: int = 0

## 提示信息 Label（无数据/加载中/错误时显示在列表中央）
var _message_label: Label = null

## 加载排行榜数据
## midi: 要查询的 MidiData（使用 file_hash 作为 key）
func load_scores(midi: MidiData) -> void:
	_current_midi = midi
	_request_version += 1
	var request_version := _request_version
	_hide_message()
	clear_items()

	# 在线模式关闭或未连接时，不加载
	if NetManager.instance == null or not NetManager.instance.is_online:
		_show_message("在线模式未开启")
		return

	if midi == null or midi.file_hash.is_empty():
		_show_message("无法获取 MIDI 信息")
		return

	if ScoreManager.instance == null:
		_show_message("成绩服务未就绪")
		return

	_loading = true
	_show_message("加载中...")

	var result = await ScoreManager.instance.get_leaderboard(midi.file_hash, LOAD_LIMIT, 0)
	if request_version != _request_version:
		return  # 已有更新的请求，丢弃过期响应
	_loading = false

	if not result.get("ok", false):
		_show_message("加载失败")
		return

	var data = result.get("data")
	if data == null or not data is Dictionary:
		_show_message("数据格式错误")
		return

	var scores = data.get("scores", [])
	if scores.is_empty():
		_show_message("暂无成绩记录")
		return

	_hide_message()
	clear_items()
	for i in range(scores.size()):
		var s = scores[i]
		var node = create_and_add_item(str(s.get("id", i)), "score")
		var rank_pos := i + 1  # 排名从 1 开始
		var accuracy_pct := float(s.get("accuracy", 0.0)) * 100.0
		var rank_str := str(s.get("rank", "F"))
		node.setup_score(
			rank_pos,
			int(s.get("totalScore", 0)),
			rank_str,
			accuracy_pct,
			float(s.get("pp", 0.0)),
			int(s.get("perfectCount", 0)),
			int(s.get("greatCount", 0)),
			int(s.get("goodCount", 0)),
			int(s.get("badCount", 0)),
			int(s.get("missCount", 0))
		)
		# W 评级（中途退出）：整体半透明
		node.set_withdraw_state(rank_str == "W")
		# 填充玩家名
		var username = s.get("username")
		var name_label = node.get_node_or_null("Name")
		if name_label:
			name_label.text = username if username != null and not str(username).is_empty() else "Anonymous"
		# 加载玩家头像（服务端返回 avatarUrl，可能为 null）
		var avatar_url = s.get("avatarUrl")
		var avatar_url_str := str(avatar_url) if avatar_url != null else ""
		node.setup_avatar(avatar_url_str)

## 在列表区域中央显示提示文字
func _show_message(msg: String) -> void:
	clear_items()
	if _message_label == null:
		_message_label = Label.new()
		_message_label.name = "MessageLabel"
		_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_message_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_message_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		container.add_child(_message_label)
	_message_label.text = msg
	_message_label.visible = true

## 隐藏并移除提示 Label
func _hide_message() -> void:
	if _message_label != null:
		_message_label.queue_free()
		_message_label = null
