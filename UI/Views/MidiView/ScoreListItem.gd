extends ListItemBase

# 使用玩家uid查找玩家信息？
var player_uid

func _ready() -> void:
	# ScoreNode 本身即 Button（原 Panel + 子 Button 已合并）
	self.pressed.connect(_on_btn_pressed)

func setup_score(rank, score, scoreRank, accuracy, pp: float, perfect_ctn: int, great_ctn: int, good_ctn: int, bad_ctn: int, miss_ctn: int):
	get_node("Rank").text = str(rank)
	get_node("Score").text = str(score)
	get_node("ScoreRank").text = str(scoreRank)

	get_node("Acc").text = str(accuracy)
	get_node("PP").text = str(pp)

	get_node("Count/perfect").text = str(perfect_ctn)
	get_node("Count/great").text = str(great_ctn)
	get_node("Count/good").text = str(good_ctn)
	get_node("Count/bad").text = str(bad_ctn)
	get_node("Count/miss").text = str(miss_ctn)

func setup_player_info(uid):
	player_uid = uid
	# 头像，玩家名
	get_node("Avator/img")
	get_node("Name")

# 展开该玩家的相关信息
func _on_btn_pressed():
	pass
