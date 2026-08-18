extends VBoxContainer

## 评论区：展示谱面评论列表 + 推荐/喜欢/不喜欢 + 发表评论
## 后端评论接口未就绪，_request_* / _submit_* 系列以占位符实现（见各函数内 TODO 注释）
## 评论列表使用 CommentList（BaseScrollList，列表项 commentItem.tscn）

## 评论列表（BaseScrollList）
@onready var comments_list: BaseScrollList = $Comments

## 评论输入框
@onready var input: LineEdit = $Bottom/LineEdit

## 当前关联的 MIDI（用于刷新/发表评论/推荐）
var _current_midi: MidiData = null

## 请求版本号：快速切换 MIDI 时丢弃过期响应
var _request_version: int = 0

## FailMessage 显示前的标签页索引（隐藏时恢复，见 _hide_fail_message）
var _fail_prev_tab: int = -1

## 由 MidiView 在 midi 选中变化/重新进入视图时调用
func load_comments(midi: MidiData) -> void:
	_current_midi = midi
	_request_version += 1
	var version := _request_version
	comments_list.clear_items()
	# 仅当评论区为当前激活标签时才操作 FailMessage，避免抢占排行榜等其它标签页的提示
	if is_visible_in_tree():
		_hide_fail_message()

	if midi == null or midi.file_hash.is_empty():
		return

	_request_comments(midi, version)

## 拉取评论列表（后端占位）
## TODO: 后端评论接口未实现 —— 实装后改为异步请求评论列表，完成后校验 version 再渲染
func _request_comments(midi: MidiData, version: int) -> void:
	# 占位：后端接口未就绪，直接以空列表返回
	_finish_fetch_comments(version, [])

## 渲染评论列表：失败/空列表时在 FailMessage 显示提示
func _finish_fetch_comments(version: int, comments: Array) -> void:
	if version != _request_version:
		return  # 已有更新的请求，丢弃过期响应
	comments_list.clear_items()
	if comments.is_empty():
		if is_visible_in_tree():
			_show_fail_message("评论区暂未开放")
		return
	if is_visible_in_tree():
		_hide_fail_message()
	for i in range(comments.size()):
		var comment: Dictionary = comments[i]
		var node := comments_list.create_and_add_item(str(i), "comment")
		node.setup_comment(comment)

## 发表评论（发送按钮 pressed / 输入框回车 text_submitted 均连接到此）
func _on_send_pressed(_text: String = "") -> void:
	var content := input.text.strip_edges() if input else ""
	if content.is_empty():
		_show_fail_message("评论内容不能为空")
		return
	if _current_midi == null:
		_show_fail_message("请先选择歌曲")
		return
	if not _is_online_ready():
		return
	_submit_comment(content)

## 提交评论到后端（后端占位）
## TODO: 后端评论接口未实现 —— 实装后调用评论 API 提交，成功后把新评论插入列表顶部并清空输入框
func _submit_comment(content: String) -> void:
	# 占位：接口未就绪，仅提示
	_show_fail_message("评论功能暂未开放")

## 推荐按钮（顶栏 Like 图标）
func _on_like_pressed() -> void:
	_submit_recommendation("like")

## 喜欢按钮（顶栏 Love 图标）
func _on_love_pressed() -> void:
	_submit_recommendation("love")

## 不喜欢按钮（顶栏 Dislike 图标）
func _on_dislike_pressed() -> void:
	_submit_recommendation("dislike")

## 提交推荐/喜欢/不喜欢（后端占位）
## TODO: 后端接口未实现 —— 实装后调用推荐 API 提交并更新按钮状态
func _submit_recommendation(kind: String) -> void:
	if _current_midi == null:
		_show_fail_message("请先选择歌曲")
		return
	if not _is_online_ready():
		return
	# 占位：接口未就绪，仅提示
	_show_fail_message("推荐功能暂未开放")

## 在线功能可用性检查（在线模式开启且已连接服务器）
func _is_online_ready() -> bool:
	if NetManager.instance == null or NetManager.instance.connect_state == NetManager.ConnectState.OFFLINE_MODE:
		_show_fail_message("在线功能未启用")
		return false
	if not NetManager.instance.is_online:
		_show_fail_message("在线模式未开启")
		return false
	return true

## 显示 TabView 级别的提示：FailMessage 节点位于 TabView 下，作为独立页展示
## 显示时 TabContainer 会把 current_tab 切到 FailMessage，隐藏时容器自动切到"下一可用"标签
func _show_fail_message(msg: String) -> void:
	var fail := get_node_or_null("../FailMessage") as Label
	if fail == null:
		return
	if not fail.visible:
		var tab_view := get_parent()
		if tab_view is TabContainer:
			_fail_prev_tab = tab_view.current_tab
	fail.text = msg
	fail.visible = true

## 隐藏 FailMessage 并恢复到显示前的标签页
## 仅当 FailMessage 由本评论区显示时操作，避免干预排行榜等其它标签页
func _hide_fail_message() -> void:
	var fail := get_node_or_null("../FailMessage") as Label
	if fail == null or not fail.visible:
		return
	if _fail_prev_tab < 0:
		return  # FailMessage 非本评论区显示，不干预
	fail.visible = false
	var tab_view := get_parent()
	if tab_view is TabContainer:
		tab_view.current_tab = _fail_prev_tab
	_fail_prev_tab = -1
