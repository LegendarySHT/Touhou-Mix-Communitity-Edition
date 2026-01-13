## 分数计算器
## 负责游戏中的打分、等级判定等逻辑
extends Node

class_name ScoreCalculator

## 评级定义
const GRADE_PERFECT = "S"     # Perfect: 1.0
const GRADE_EXCELLENT = "A"   # 95-99%
const GRADE_GOOD = "B"        # 85-94%
const GRADE_OK = "C"          # 70-84%
const GRADE_POOR = "D"        # 50-69%
const GRADE_FAIL = "F"        # < 50%

## 判定等级定义
enum JudgeGrade {
	PERFECT = 0,   # 完美 (±50ms)
	GOOD = 1,      # 好 (±100ms)
	OK = 2,        # 可以 (±150ms)
	MISS = 3       # 失误 (超过±150ms)
}

## 当前分数
var current_score: int = 0

## 判定统计
var judge_counts: Dictionary = {
	"perfect": 0,
	"good": 0,
	"ok": 0,
	"miss": 0
}

## 连击数
var combo: int = 0
var max_combo: int = 0

## 分数改变信号
signal score_changed(new_score: int)
signal combo_changed(new_combo: int)
signal judge_recorded(judge_grade: JudgeGrade)

func _ready() -> void:
	add_to_group("game_logic")

## 记录判定
func record_judge(judge_grade: JudgeGrade) -> void:
	var points = 0
	
	match judge_grade:
		JudgeGrade.PERFECT:
			points = 1000
			judge_counts["perfect"] += 1
			combo += 1
		
		JudgeGrade.GOOD:
			points = 800
			judge_counts["good"] += 1
			combo += 1
		
		JudgeGrade.OK:
			points = 500
			judge_counts["ok"] += 1
			combo += 1
		
		JudgeGrade.MISS:
			points = 0
			judge_counts["miss"] += 1
			combo = 0
	
	# 更新连击数
	if combo > max_combo:
		max_combo = combo
	
	# 计算分数（考虑连击加成）
	var combo_bonus = max(0, combo - 1) * 10
	current_score += points + combo_bonus
	
	score_changed.emit(current_score)
	combo_changed.emit(combo)
	judge_recorded.emit(judge_grade)

## 计算最终等级
func calculate_grade() -> String:
	var total = judge_counts["perfect"] + judge_counts["good"] + \
				judge_counts["ok"] + judge_counts["miss"]
	
	if total == 0:
		return GRADE_FAIL
	
	var accuracy = float(judge_counts["perfect"] + judge_counts["good"]) / total
	
	if accuracy >= 0.95:
		return GRADE_EXCELLENT
	elif accuracy >= 0.85:
		return GRADE_GOOD
	elif accuracy >= 0.70:
		return GRADE_OK
	elif accuracy >= 0.50:
		return GRADE_POOR
	else:
		return GRADE_FAIL

## 计算准确率（百分比）
func calculate_accuracy() -> float:
	var total = judge_counts["perfect"] + judge_counts["good"] + \
				judge_counts["ok"] + judge_counts["miss"]
	
	if total == 0:
		return 0.0
	
	var accurate = judge_counts["perfect"] + judge_counts["good"]
	return float(accurate) / total * 100.0

## 获取完整分数数据
func get_score_data() -> Dictionary:
	return {
		"total_score": current_score,
		"accuracy": calculate_accuracy(),
		"grade": calculate_grade(),
		"max_combo": max_combo,
		"perfect_count": judge_counts["perfect"],
		"good_count": judge_counts["good"],
		"ok_count": judge_counts["ok"],
		"miss_count": judge_counts["miss"]
	}

## 重置分数
func reset() -> void:
	current_score = 0
	combo = 0
	max_combo = 0
	judge_counts = {
		"perfect": 0,
		"good": 0,
		"ok": 0,
		"miss": 0
	}

## 获取当前分数
func get_current_score() -> int:
	return current_score

## 获取当前连击
func get_current_combo() -> int:
	return combo

## 获取最大连击
func get_max_combo() -> int:
	return max_combo
