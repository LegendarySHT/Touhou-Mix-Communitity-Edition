## 音符触摸判定查找器
## 提供四种独立的触摸判定模式，从活跃音符索引列表中找到最适合被判定的音符
## 无状态纯函数，可安全被 FlowArea 持有并反复调用
class_name NoteJudger
extends RefCounted

## 四种触摸判定模式，索引与 SettingList "touch_judging_criteria" 的选项顺序一一对应
enum JudgeMode {
	## 最临近：水平矩形范围内，选欧式距离最小的音符
	NEAREST = 0,
	## 最佳时机：水平矩形范围内，选 |note_y - click_y| 最小的音符
	BEST_TIMING = 1,
	## 距判定线最近：水平矩形范围内，选 |note_y - judge_line_y| 最小的音符
	NEAREST_JUDGE = 2,
	## 最佳时机(先现先判)：水平矩形范围内，选 note_y 最大（最靠近底部/最早到达）的音符
	BEST_TIMING_FIFO = 3,
}

## 平行数组宿主（FlowArea 注入）：判定读取 _rt_cx/_rt_cy/_rt_flags，无需对象
var flow_area: Object = null

## 从活跃音符索引列表中找到最适合被判定的音符
## 所有模式统一使用矩形半宽水平过滤，垂直方向不限（全屏判定范围）
## [param click_pos] 点击 / 触摸位置（屏幕坐标）
## [param active_indices] FlowArea 的候选 seq 索引数组
## [param judge_line_y] 判定线的屏幕 Y 坐标（供 NEAREST_JUDGE 模式使用）
## [param note_judge_width] 判定宽度：矩形全宽（半宽 = note_judge_width / 2）
## [param mode] JudgeMode 枚举值（int）
## 返回最优 seq 索引；若无满足条件的音符则返回 -1
func find_best_note_index(click_pos: Vector2, active_indices: Array, judge_line_y: float,
		note_judge_width: float, mode: int) -> int:
	var best_index: int = -1
	var best_score: float = INF
	var half_width: float = note_judge_width * 0.5
	var rt_cx: PackedFloat32Array = flow_area._rt_cx
	var rt_cy: PackedFloat32Array = flow_area._rt_cy
	var rt_flags: PackedByteArray = flow_area._rt_flags

	for i in active_indices:
		if rt_flags[i] & (flow_area.F_HELD | flow_area.F_JUDGED | flow_area.F_REMOVED):
			continue

		var center: Vector2 = Vector2(rt_cx[i], rt_cy[i])

		# 统一水平过滤：所有模式使用相同的矩形半宽
		if abs(center.x - click_pos.x) > half_width:
			continue

		match mode:
			JudgeMode.NEAREST:
				# 欧式距离最小的音符（无垂直限制，全屏范围内选最近）
				var dist: float = click_pos.distance_to(center)
				if dist < best_score:
					best_score = dist
					best_index = i

			JudgeMode.BEST_TIMING:
				# 选 |note_y - click_y| 最小的音符（离点击位置垂直最近）
				var diff: float = abs(center.y - click_pos.y)
				if diff < best_score:
					best_score = diff
					best_index = i

			JudgeMode.NEAREST_JUDGE:
				# 选 |note_y - judge_line_y| 最小的音符（离判定线最近）
				var diff: float = abs(center.y - judge_line_y)
				if diff < best_score:
					best_score = diff
					best_index = i

			JudgeMode.BEST_TIMING_FIFO:
				# 选 note_y 最大（最靠近底部/最早到达）的音符，防止跳过早期音符
				var score: float = -center.y
				if score < best_score:
					best_score = score
					best_index = i

	return best_index
