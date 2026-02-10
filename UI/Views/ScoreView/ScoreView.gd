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
	var accuracy: float = 0
	var performance_point: float = 0
	var max_combo: int = 0
	var total_notes: int = 0

	var score: int = 0:
		set(v):
			score = v
			_update_result()
	var perfect_count: int = 0:
		set(v):
			perfect_count = v
			_update_result()	
	var great_count: int = 0:
		set(v):
			great_count = v
			_update_result()
	var good_count: int = 0:
		set(v):
			good_count = v
			_update_result()
	var bad_count: int = 0:
		set(v):
			bad_count = v
			_update_result()
	var miss_count: int = 0:
		set(v):
			miss_count = v
			_update_result()

	var early_count: int = 0
	var late_count: int = 0

	func _update_result():
		accuracy = (perfect_count + (2.0/3) * great_count + (1.0/3) * good_count)/(perfect_count + great_count + good_count + bad_count + miss_count)
		performance_point = log(1 + score) * pow(accuracy, 2)

	func get_rank() -> String:
		if accuracy == 1:
			return "Ω"
		elif accuracy > 0.9999:
			return "SSS"
		elif accuracy > 0.999:
			return "SS"
		elif accuracy > 0.99:
			return "S"
		elif accuracy > 0.6:
			var l:int = int(accuracy*100-60)
			@warning_ignore("integer_division")
			return char(ord("D") - l/10)+("+" if l%10>4 else "")
		else:
			return "F"

	func get_formated_score() -> String:
		var str_num = str(score)
		var regex = RegEx.new()
		regex.compile("(\\d)(?=(\\d{3})+(?!\\d))")
		# 替换匹配的部分
		var result = regex.sub(str_num, "$1,", true)
		# 反转字符串，从后向前每三位加逗号
		return result

	func get_accuracy() -> String:
		return "%0.2f%%" % (accuracy*100)
	
	func get_pp() -> String:
		return "%0.2fpp" % performance_point

func _ready() -> void:
	get_window().size_changed.connect(func():
		c.size.x = get_viewport().get_visible_rect().size.x
	)

	await get_tree().create_timer(2).timeout
	ani_out()
	await get_tree().create_timer(3).timeout
	ani_in()

func set_display(result: ScoreData):
	data_area.get_node("PerfectCtn").text = str(result.perfect_count)
	data_area.get_node("GreatCtn").text = str(result.great_count)
	data_area.get_node("GoodCtn").text = str(result.good_count)
	data_area.get_node("BadCtn").text = str(result.bad_count)
	data_area.get_node("MissCtn").text = str(result.miss_count)

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

func _on_retry_btn_pressed():
	UIStateManager.instance.change_state(UIStateManager.UIState.PLAY_VIEW, false)
	await get_tree().create_timer(1).timeout
	get_node("/root/Main/PlayView").retry_btn.pressed.emit()

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
