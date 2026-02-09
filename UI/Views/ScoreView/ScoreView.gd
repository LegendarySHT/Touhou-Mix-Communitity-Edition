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
	var score: String = "0"
	var accuracy: String = "00.00%"
	var performance_point: String = "00.00pp"
	var max_combo: String = "0"
	var total_notes: String = "0"

	var perfect_count: String = "0"
	var great_count: String = "0"
	var good_count: String = "0"
	var bad_count: String = "0"
	var miss_count: String = "0"

	var early_count: String = "0"
	var late_count: String = "0"

	func _init(Score, Accuracy, PerformancePoint, MaxCombo, TotalNotes, PerfectCtn, GreatCtn, GoodCtn, BadCtn, MissCtn, EarlyCtn, LateCtn) -> void:
		score = str(Score)
		accuracy = "%0.2f%" % Accuracy
		performance_point = "%0.2fpp" % PerformancePoint
		max_combo = str(MaxCombo)
		total_notes = str(TotalNotes)

		perfect_count = str(PerfectCtn)
		great_count = str(GreatCtn)
		good_count = str(GoodCtn)
		bad_count = str(BadCtn)
		miss_count = str(MissCtn)

		early_count = str(EarlyCtn)
		late_count = str(LateCtn)

func _ready() -> void:
	get_window().size_changed.connect(func():
		c.size.x = get_viewport().get_visible_rect().size.x
	)

	await get_tree().create_timer(2).timeout
	ani_out()
	await get_tree().create_timer(3).timeout
	ani_in()

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

	var nd = get_node("Btns")
	ani.animate_position(nd, Vector2(nd.position.x, wh), 0.5, "sv_btns")

	nd = get_node("LevelingProgress")
	ani.animate_position(nd, Vector2(-100-nd.size.x, 0), 0.25, "sv_info")
	
	nd = get_node("Chara")
	ani.animate_position(nd, Vector2(nd.position.x, wh), 0.5, "sv_chara")

	nd = get_node("Bottom")
	ani.animate_position(nd, Vector2(nd.position.x, wh + 100), 0.5, "sv_bottom")
	
	await get_tree().create_timer(0.05).timeout
	nd = get_node("Rank")
	ani.animate_position(nd, Vector2(nd.position.x, wh), 0.5, "sv_rank")

	nd = get_node("Score")
	ani.animate_position(nd, Vector2(-ww, nd.position.y), 1, "sv_score")
	ani.animate_fade_out(nd, 1, "sv_score_fade")
	
	await get_tree().create_timer(0.05).timeout
	nd = get_node("Accuracy")
	ani.animate_position(nd, Vector2(nd.position.x, wh), 0.5, "sv_acc")

	nd = get_node("LT_Btn")
	ani.animate_position(nd, Vector2(-nd.size.x - 100, nd.position.y), 0.5, "sv_lt")

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

	var nd = get_node("Btns")
	ani.animate_position(nd, Vector2(nd.position.x, 0), 0.5, "sv_btns")

	nd = get_node("LevelingProgress")
	ani.animate_position(nd, Vector2.ZERO, 0.25, "sv_info")
	
	charaNode = get_node("Chara")
	ani.animate_position(charaNode, Vector2(charaNode.position.x, 150), 0.5, "sv_chara")

	nd = get_node("Bottom")
	ani.animate_position(nd, Vector2(nd.position.x, 680), 0.5, "sv_bottom")
	
	await get_tree().create_timer(0.05).timeout
	rankNode = get_node("Rank")
	ani.animate_position(rankNode, Vector2(rankNode.position.x, 400), 0.5, "sv_rank")

	nd = get_node("Score")
	ani.animate_position(nd, Vector2(0, nd.position.y), 1, "sv_score")
	ani.animate_fade_in(nd, 1, "sv_score_fade")
	
	await get_tree().create_timer(0.05).timeout
	nd = get_node("Accuracy")
	ani.animate_position(nd, Vector2(nd.position.x, 427), 0.5, "sv_acc")

	nd = get_node("LT_Btn")
	ani.animate_position(nd, Vector2(26, nd.position.y), 0.5, "sv_lt")

	await get_tree().create_timer(0.6).timeout
	_kill_loop_ani()
	
	_loop_ani_chara = create_tween()
	_loop_ani_rank = create_tween()

	_loop_ani_chara.set_loops()
	_loop_ani_rank.set_loops()

	_loop_ani_rank.tween_property(rankNode, "scale", Vector2.ONE*1.01, 1)
	_loop_ani_rank.tween_property(rankNode, "scale", Vector2.ONE*0.99, 1)

	_loop_ani_chara.tween_property(charaNode, "position:y", charaNode.position.y + 10, 1.5)
	_loop_ani_chara.tween_property(charaNode, "position:y", charaNode.position.y - 10, 1.5)
