extends Control

class_name ScoreView

# 数据区
@onready var flags_area: GridContainer = $Bottom/skew/C/Flags/GridC
@onready var data_area: GridContainer = $Bottom/skew/C/Data/GridC
@onready var c: Control = $Bottom/skew/C

@onready var rank: Label = $Rank
@onready var accuracy: Label = $Accuracy
@onready var score: Label = $Score/score
@onready var pp: Label = $Score/score/pp

# 角色
@onready var chara: TextureRect = $Chara

# 个人信息区
@onready var avator: TextureRect = $LevelingProgress/Panel/TextureRect
@onready var name_label: Label = $LevelingProgress/Data/name
@onready var lvl_label: Label = $LevelingProgress/Data/level
@onready var lvl_exp_progress: ProgressBar = $LevelingProgress/Data/ProgressBar

class ScoreData:
	## 由 ScoreCalculator 填充的最终数据（纯数据容器，不含计算逻辑）
	var accuracy: float = 1.0
	var performance_point: float = 0.0
	var max_combo: int = 0
	var total_notes: int = 0
	var score: int = 0
	var count: Dictionary = {
		"Perfect": 0,
		"Great": 0,
		"Good": 0,
		"Bad": 0,
		"Miss": 0
	}
	var early_count: int = 0
	var late_count: int = 0

	## 评级 - 委托 ScoreCalculator（唯一计分真源）
	func get_rank() -> String:
		if ScoreCalculator.instance:
			return ScoreCalculator.instance.get_rank()
		# 回退：使用本地 accuracy 按阈值查找
		for threshold in ScoreCalculator.RANK_THRESHOLDS:
			if accuracy >= threshold[0]:
				return threshold[1]
		return "F"

	func get_formated_score() -> String:
		var str_num = str(score)
		var regex = RegEx.new()
		regex.compile("(\\d)(?=(\\d{3})+(?!\\d))")
		return regex.sub(str_num, "$1,", true)

	func get_accuracy() -> String:
		return "%0.2f%%" % (accuracy * 100)

	func get_pp() -> String:
		return "%0.2fpp" % performance_point

func _ready() -> void:
	get_window().size_changed.connect(func():
		c.size.x = get_viewport().get_visible_rect().size.x
	)

	ani_out()

func set_display(result: ScoreData):
	data_area.get_node("PerfectCtn").text = str(result.count.Perfect)
	data_area.get_node("GreatCtn").text = str(result.count.Great)
	data_area.get_node("GoodCtn").text = str(result.count.Good)
	data_area.get_node("BadCtn").text = str(result.count.Bad)
	data_area.get_node("MissCtn").text = str(result.count.Miss)

	data_area.get_node("EarlyCtn").text = str(result.early_count)
	data_area.get_node("LateCtn").text = str(result.late_count)
	data_area.get_node("MaxCombo").text = "%d/%d" % [result.max_combo, result.total_notes]

	rank.text = result.get_rank()
	accuracy.text = result.get_accuracy()
	score.text = result.get_formated_score()
	pp.text = result.get_pp()

func _on_like_btn_pressed():
	pass

func _on_dislike_btn_pressed():
	pass

func _on_love_btn_pressed():
	pass

############################# 动画 ###############################
@onready var ani: AnimationManager = AnimationManager.instance
var _loop_ani_chara: Tween = null
var _loop_ani_rank: Tween = null

func ani_out():
	var wh = get_viewport().get_visible_rect().size.y
	var ww = get_viewport().get_visible_rect().size.x

	var nd = get_node("BackGround")
	ani.animate_scale(nd, Vector2.ZERO, 0.25, "sv_bg")

	nd = get_node("Btns")
	ani.animate_position(nd, Vector2(nd.position.x, wh), 0.5, "sv_btns")

	nd = get_node("LevelingProgress")
	ani.animate_position(nd, Vector2(-100-nd.size.x, 0), 0.25, "sv_info")
	
	nd = get_node("Chara")
	ani.animate_position(nd, Vector2(nd.position.x, wh), 0.5, "sv_chara")

	nd = get_node("Bottom")
	ani.animate_position(nd, Vector2(nd.position.x, wh + 100), 0.5, "sv_bottom")
	
	await get_tree().create_timer(0.05).timeout
	if UiStatMGR.instance.transition_version != AniMGR.instance._current_transition_version:
		return
	nd = get_node("Rank")
	ani.animate_position(nd, Vector2(nd.position.x, wh), 0.5, "sv_rank")

	nd = get_node("Score")
	ani.animate_position(nd, Vector2(-ww, nd.position.y), 1, "sv_score")
	ani.animate_fade_out(nd, 1, "sv_score_fade")
	
	await get_tree().create_timer(0.05).timeout
	if UiStatMGR.instance.transition_version != AniMGR.instance._current_transition_version:
		return
	nd = get_node("Accuracy")
	ani.animate_position(nd, Vector2(nd.position.x, wh), 0.5, "sv_acc")

	_kill_loop_ani()

func _kill_loop_ani():
	if _loop_ani_chara:
		_loop_ani_chara.kill()
		_loop_ani_chara = null
	if _loop_ani_rank:
		_loop_ani_rank.kill()
		_loop_ani_rank = null

func ani_in():
	var charaNode = null
	var rankNode = null

	var nd = get_node("BackGround")
	ani.animate_scale(nd, Vector2.ONE, 0.5, "sv_bg")

	nd = get_node("Btns")
	ani.animate_position(nd, Vector2(nd.position.x, 0), 0.8, "sv_btns")

	nd = get_node("LevelingProgress")
	ani.animate_position(nd, Vector2.ZERO, 0.5, "sv_info")
	
	charaNode = get_node("Chara")
	ani.animate_position(charaNode, Vector2(charaNode.position.x, 150), 0.8, "sv_chara")

	nd = get_node("Bottom")
	ani.animate_position(nd, Vector2(nd.position.x, 680), 0.8, "sv_bottom")
	
	await get_tree().create_timer(0.05).timeout
	rankNode = get_node("Rank")
	ani.animate_position(rankNode, Vector2(rankNode.position.x, 400), 0.8, "sv_rank")

	nd = get_node("Score")
	ani.animate_position(nd, Vector2(0, nd.position.y), 1.25, "sv_score")
	ani.animate_fade_in(nd, 1, "sv_score_fade")
	
	await get_tree().create_timer(0.05).timeout
	nd = get_node("Accuracy")
	ani.animate_position(nd, Vector2(nd.position.x, 427), 0.8, "sv_acc")

	await get_tree().create_timer(0.8).timeout
	_kill_loop_ani()
	
	_loop_ani_chara = create_tween()
	_loop_ani_rank = create_tween()

	_loop_ani_chara.set_loops()
	_loop_ani_rank.set_loops()

	_loop_ani_rank.tween_property(rankNode, "scale", Vector2.ONE*1.01, 1)
	_loop_ani_rank.tween_property(rankNode, "scale", Vector2.ONE*0.99, 1)

	_loop_ani_chara.tween_property(charaNode, "position:y", charaNode.position.y + 10, 1.5)
	_loop_ani_chara.tween_property(charaNode, "position:y", charaNode.position.y - 10, 1.5)
