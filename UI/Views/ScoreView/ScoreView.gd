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

# 个人信息区
@onready var avator: TextureRect = $LevelingProgress/Panel/TextureRect
@onready var name_label: Label = $LevelingProgress/Data/name
@onready var lvl_label: Label = $LevelingProgress/Data/level
@onready var lvl_exp_progress: ProgressBar = $LevelingProgress/Data/ProgressBar

# 图片
@onready var bg: TextureRect = $BackGround
@onready var chara: TextureRect = $Chara

# 动画相关
@onready var btns: Panel = $Btns
@onready var bottom: Panel = $Bottom
@onready var info: Panel = $LevelingProgress
@onready var score_panel: Panel = $Score

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
	UiStatMGR.state_changed.connect(_on_state_changed)
	animate(false)

	# 监听 PlayerInfoContent 统计刷新信号，成绩上传后自动同步玩家信息
	_connect_stats_refreshed()

	if ThemeMGR:
		ThemeMGR.register_theme_applier(self)
		apply_theme()

## 应用主题色（由 ThemeManager 广播调用 + _ready 首次自调）
func apply_theme() -> void:
	# LevelingProgress — 透明 primary_dark
	if info:
		var sb := info.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			var a = sb.bg_color.a
			var pd := ThemeMGR.get_color("primary_dark")
			sb.bg_color = Color(pd.r, pd.g, pd.b, a)
	# Btns — 透明 primary_light
	if btns:
		var sb := btns.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			var a = sb.bg_color.a
			var pl := ThemeMGR.get_color("primary_light")
			sb.bg_color = Color(pl.r, pl.g, pl.b, a)

func _exit_tree() -> void:
	if ThemeMGR:
		ThemeMGR.unregister_theme_applier(self)
	_disconnect_stats_refreshed()

## 连接 PlayerInfoContent 的 stats_refreshed 信号
func _connect_stats_refreshed() -> void:
	var pic := _get_player_info_content()
	if pic and not pic.stats_refreshed.is_connected(_on_stats_refreshed):
		pic.stats_refreshed.connect(_on_stats_refreshed)

## 断开 PlayerInfoContent 的 stats_refreshed 信号
func _disconnect_stats_refreshed() -> void:
	var pic := _get_player_info_content()
	if pic and pic.stats_refreshed.is_connected(_on_stats_refreshed):
		pic.stats_refreshed.disconnect(_on_stats_refreshed)

## 获取 PlayerInfoContent 节点（可能在不同路径下）
func _get_player_info_content() -> PlayerInfoContent:
	for path in [PathRegistry.PLAYER_INFO_TAB_C_LEGACY, PathRegistry.PLAYER_INFO_TAB_C]:
		var node = get_node_or_null(path)
		if node and node is PlayerInfoContent:
			return node as PlayerInfoContent
	return null

## 统计刷新回调：重新同步玩家信息（头像、名称、等级、进度条）
func _on_stats_refreshed() -> void:
	_update_player_info()

func _on_state_changed(old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	# 退出 SCORE_VIEW 时停止循环动画，节省 CPU
	if old_state == UIStateManager.UIState.SCORE_VIEW and new_state != UIStateManager.UIState.SCORE_VIEW:
		_cleanup()

## 释放视图内部资源（循环动画 Tween），保留节点壳
func _cleanup() -> void:
	_kill_loop_ani()

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

	# 确保统计刷新信号已连接（_ready 时可能 PlayerInfoContent 尚未就绪）
	_connect_stats_refreshed()
	# 同步玩家信息（头像、名称、等级、进度条）
	_update_player_info()

## 从 PlayerInfoContent 同步玩家信息（头像、名称、等级、进度条）
## 在 set_display 后调用，确保结算界面显示最新玩家状态
## 也在 stats_refreshed 信号回调中调用，成绩上传后自动刷新
func _update_player_info() -> void:
	var pic := _get_player_info_content()
	if pic == null:
		return
	# 头像
	avator.texture = pic.mini_avatar_rect.texture
	# 名称
	var player_data: Dictionary = pic.get_player_data()
	name_label.text = player_data.display_name if not player_data.display_name.is_empty() else player_data.name
	# 等级 = floor(sqrt(pp))
	var pp_val = player_data.pp
	var lvl = pic.calc_level(pp_val)
	lvl_label.text = "Lv%d" % lvl
	# 升级进度 = (pp - level²) / ((level+1)² - level²)
	lvl_exp_progress.value = pic.calc_level_progress(pp_val, lvl) * 100.0

func _on_like_btn_pressed():
	pass

func _on_dislike_btn_pressed():
	pass

func _on_love_btn_pressed():
	pass

############################# 动画 ###############################
@onready var ani: AnimationManager = AniMGR
var _loop_ani_chara: Tween = null
var _loop_ani_rank: Tween = null

func _kill_loop_ani():
	if _loop_ani_chara:
		_loop_ani_chara.kill()
		_loop_ani_chara = null
	if _loop_ani_rank:
		_loop_ani_rank.kill()
		_loop_ani_rank = null

func _play_loop_ani():
	_kill_loop_ani()
	_loop_ani_chara = AniMGR.create_managed_tween(self, "score_loop_chara")
	_loop_ani_rank = AniMGR.create_managed_tween(self, "score_loop_rank")

	_loop_ani_chara.set_loops()
	_loop_ani_rank.set_loops()

	_loop_ani_rank.tween_property(rank, "offset_transform_scale", Vector2.ONE*0.99, 1)
	_loop_ani_rank.tween_property(rank, "offset_transform_scale", Vector2.ONE*1.01, 1)

	_loop_ani_chara.tween_property(chara, "position:y", chara.position.y + 10, 1.5)
	_loop_ani_chara.tween_property(chara, "position:y", chara.position.y - 10, 1.5)

func animate(ani_in: bool = true):
	# 窗口大小
	var wh = size.y
	var ww = size.x

	# 外围组件
	if ani_in:
		ani.animate_scale(bg, Vector2.ONE, 0.5, "sv_bg")
		ani.animate_offset_back(info, 0.5, "sv_info")

		ani.animate_offset_back(btns, 0.8, "sv_btns")
		ani.animate_offset_back(chara, 0.8, "sv_chara")
		ani.animate_offset_back(bottom, 0.8, "sv_bottom")
	else:
		ani.animate_scale(bg, Vector2.ZERO, 0.25, "sv_bg")
		ani.animate_offset_to(info, Vector2(- info.size.x, 0), 0.25, "sv_info")

		ani.animate_offset_to(btns, Vector2(btns.size.x + 100, 0), 0.5, "sv_btns")
		ani.animate_offset_to(chara, Vector2(0, wh), 0.5, "sv_chara")
		ani.animate_offset_to(bottom, Vector2(0, wh), 0.5, "sv_bottom")
	
	await get_tree().create_timer(0.05).timeout
	# 数值组件
	if ani_in:
		ani.animate_offset_back(rank, 0.8, "sv_rank")

		ani.animate_fade_in(score_panel, 1, "sv_score_fade")
		ani.animate_offset_back(score, 0.5, "sv_score")
		ani.animate_offset_back(pp, 0.8, "sv_pp")

		ani.animate_offset_back(accuracy, 1.5, "sv_acc")
	else:
		ani.animate_offset_to(rank, Vector2(0, wh), 0.5, "sv_rank")

		ani.animate_fade_out(score_panel, 1, "sv_score_fade")
		ani.animate_offset_to(score, Vector2(-ww, 0), 0.5, "sv_score")
		ani.animate_offset_to(pp, Vector2(-ww, 0), 0.8, "sv_pp")

		ani.animate_offset_to(accuracy, Vector2(0, wh), 1.5, "sv_acc")

	await get_tree().create_timer(0.8).timeout
	_play_loop_ani()
