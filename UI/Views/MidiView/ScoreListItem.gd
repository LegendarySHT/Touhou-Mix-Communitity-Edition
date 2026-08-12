extends ListItemBase

# 使用玩家uid查找玩家信息？
var player_uid

func setup_score(rank, score, scoreRank, accuracy, pp: float, perfect_ctn: int, great_ctn: int, good_ctn: int, bad_ctn: int, miss_ctn: int):
	get_node("Rank").text = str(rank)
	get_node("Score").text = str(score)
	get_node("ScoreRank").text = str(scoreRank)

	get_node("Acc").text = "%.2f%%" % accuracy
	get_node("PP").text = "%.2f" % pp

	get_node("Count/perfect").text = str(perfect_ctn)
	get_node("Count/great").text = str(great_ctn)
	get_node("Count/good").text = str(good_ctn)
	get_node("Count/bad").text = str(bad_ctn)
	get_node("Count/miss").text = str(miss_ctn)

## 加载玩家头像：avatar_url 为相对路径（如 /avatars/xxx.jpg），空则保持默认
func setup_avatar(avatar_url: String) -> void:
	if avatar_url.is_empty():
		return
	if NetManager.instance == null or not NetManager.instance.is_online:
		return
	var img_node = get_node_or_null("Avator/img")
	if img_node == null:
		return
	var full_url := "%s%s" % [NetManager.instance.server_url, avatar_url]
	HttpImageLoader.load(full_url, self, func(tex: Texture2D) -> void:
		if tex and is_instance_valid(img_node):
			img_node.texture = tex
	)

## 设置中途退出（W 评级）状态：整体半透明以区分正常完成记录
func set_withdraw_state(withdraw: bool) -> void:
	modulate.a = 0.4 if withdraw else 1.0

func setup_player_info(uid):
	player_uid = uid
	# 头像，玩家名
	get_node("Avator/img")
	get_node("Name")

# 展开该玩家的相关信息
func _on_btn_pressed():
	pass
