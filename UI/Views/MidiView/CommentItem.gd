extends ListItemBase

## 单条评论条目：展示头像、用户名、时间、内容与点赞数
## 高度随内容自适应，配合 CommentList（BaseScrollList）使用

## 填充评论数据
## comment: 后端返回的评论字典（username/time/content/like_count/avatar_url）
func setup_comment(comment: Dictionary) -> void:
	var name_node := get_node_or_null("HBox/VBox/Head/Name")
	if name_node:
		name_node.text = str(comment.get("username", "Anonymous"))

	var time_node := get_node_or_null("HBox/VBox/Head/Time")
	if time_node:
		time_node.text = str(comment.get("time", ""))

	var content_node := get_node_or_null("HBox/VBox/Content")
	if content_node:
		content_node.text = str(comment.get("content", ""))

	var like_node := get_node_or_null("HBox/VBox/Foot/Like")
	if like_node:
		like_node.text = str(comment.get("like_count", 0))

	var avatar_url := str(comment.get("avatar_url", ""))
	setup_avatar(avatar_url)

## 单条评论点赞（占位）
## TODO: 后端评论接口未实现 —— 实装后调用评论点赞 API，成功后刷新按钮状态/计数
## 当前仅靠按钮 toggle_mode 维持本地视觉切换，无网络交互
func _on_like_pressed() -> void:
	pass

## 加载头像：avatar_url 为相对路径（如 /avatars/xxx.jpg），空则保持默认占位
func setup_avatar(avatar_url: String) -> void:
	if avatar_url.is_empty():
		return
	if NetManager.instance == null or not NetManager.instance.is_online:
		return
	var img_node := get_node_or_null("HBox/Avator/img")
	if img_node == null:
		return
	var full_url := "%s%s" % [NetManager.instance.server_url, avatar_url]
	HttpImageLoader.load(full_url, self, func(tex: Texture2D) -> void:
		if tex and is_instance_valid(img_node):
			img_node.texture = tex
	)
