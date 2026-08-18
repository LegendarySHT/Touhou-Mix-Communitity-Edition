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

## FailMessage 显示前的标签页索引（隐藏时恢复，见 _hide_message）
var _fail_prev_tab: int = -1

## 待显示的提示信息：排行榜标签页未激活时先缓存，切回时经 FailMessage 展示
var _pending_message: String = ""

## 「在线模式已开启但尚未连上服务器」的等待标记
## 连接成功（online_status_changed 为 true）后据此自动刷新排行榜
var _waiting_online: bool = false

func _ready() -> void:
	super._ready()
	EvtBus.online_status_changed.connect(_on_online_status_changed)

## 可见性变化：排行榜标签页切回时把缓存的消息经 FailMessage 展示
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree() \
			and not _pending_message.is_empty():
		_apply_message()

## 在线状态变化：初次连接成功（或重连成功）时，若正停在「在线模式未开启」提示上则自动刷新
func _on_online_status_changed(online: bool, _message: String) -> void:
	if not online or not _waiting_online or _current_midi == null:
		return
	if not is_visible_in_tree():
		return
	load_scores(_current_midi)

## 加载排行榜数据
## midi: 要查询的 MidiData（使用 file_hash 作为 key）
func load_scores(midi: MidiData) -> void:
	_current_midi = midi
	_request_version += 1
	var request_version := _request_version
	_hide_message()
	clear_items()
	_loading = false
	_waiting_online = false

	# 在线模式关闭：显示本地最佳成绩（离线排行榜），无论服务器是否可达
	if NetManager.instance == null or NetManager.instance.connect_state == NetManager.ConnectState.OFFLINE_MODE:
		_show_local_best(midi)
		return

	# 在线模式开启但未连接上服务器：不显示离线成绩，保留原有提示
	if not NetManager.instance.is_online:
		_waiting_online = true
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

## 显示本地最佳成绩（单条，离线排行榜）
## 未登录/在线模式关闭时使用，仅展示本机每首 pp 最高的记录
func _show_local_best(midi: MidiData) -> void:
	if midi == null or midi.file_hash.is_empty():
		_show_message("无法获取 MIDI 信息")
		return
	if ScoreManager.instance == null:
		_show_message("成绩服务未就绪")
		return
	var local := ScoreManager.instance.get_local_best(midi.file_hash)
	if local.is_empty():
		_show_message("暂无本地成绩")
		return
	_hide_message()
	clear_items()
	var node := create_and_add_item("local_best", "score")
	# 本地最佳固定排名第 1
	node.setup_score(
		1,
		int(local.get("totalScore", 0)),
		str(local.get("rank", "F")),
		float(local.get("accuracy", 0.0)) * 100.0,
		float(local.get("pp", 0.0)),
		int(local.get("perfectCount", 0)),
		int(local.get("greatCount", 0)),
		int(local.get("goodCount", 0)),
		int(local.get("badCount", 0)),
		int(local.get("missCount", 0))
	)
	var name_label := node.get_node_or_null("Name")
	if name_label:
		name_label.text = "Offline Score"
	# 本地成绩无头像，保持默认头像占位

## 显示提示信息（经 TabView 下 FailMessage 节点，作为独立页展示）
## 排行榜标签页未激活时仅缓存，切回时再展示，避免抢占其它标签页
func _show_message(msg: String) -> void:
	clear_items()
	_pending_message = msg
	if is_visible_in_tree():
		_apply_message()

## 把待显示消息写入 FailMessage（显示时 TabContainer 会切到该页）
func _apply_message() -> void:
	var fail := get_node_or_null("../../FailMessage") as Label
	if fail == null:
		return
	if not fail.visible:
		var tab_view := get_parent().get_parent()
		if tab_view is TabContainer:
			_fail_prev_tab = tab_view.current_tab
	fail.text = _pending_message
	fail.visible = true

## 隐藏 FailMessage 并恢复到显示前的标签页
## 仅当排行榜标签页可见且 FailMessage 由本列表显示时操作，避免干预其它标签页
func _hide_message() -> void:
	_pending_message = ""
	if not is_visible_in_tree():
		return
	if _fail_prev_tab < 0:
		return  # FailMessage 非本列表显示，不干预
	var fail := get_node_or_null("../../FailMessage") as Label
	if fail == null or not fail.visible:
		_fail_prev_tab = -1
		return
	fail.visible = false
	var tab_view := get_parent().get_parent()
	if tab_view is TabContainer:
		tab_view.current_tab = _fail_prev_tab
	_fail_prev_tab = -1
