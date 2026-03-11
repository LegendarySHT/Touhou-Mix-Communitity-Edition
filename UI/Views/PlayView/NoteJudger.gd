## 音符触摸判定查找器
## 提供四种独立的触摸判定模式，从活跃音符列表中找到最适合被判定的音符
## 无状态纯函数，可安全被 FlowArea 持有并反复调用
class_name NoteJudger
extends RefCounted

## 四种触摸判定模式，索引与 SettingList "touch_judging_criteria" 的选项顺序一一对应
enum JudgeMode {
	## 最临近：以点击点为圆心、半径 = note_judge_width 的圆内，选欧式距离最小的音符
	NEAREST = 0,
	## 最佳时机：矩形判定区域（宽 = note_judge_width）内，选 |note_y - click_y| 最小的音符
	BEST_TIMING = 1,
	## 距判定线最近：矩形判定区域内，选 |note_y - judge_line_y| 最小的音符
	NEAREST_JUDGE = 2,
	## 最佳时机(先现先判)：矩形判定区域内，选 note_y 最大（最靠近底部）的音符
	BEST_TIMING_FIFO = 3,
}

## 从活跃音符列表中找到最适合被判定的音符
## [param click_pos] 点击 / 触摸位置（屏幕坐标）
## [param active_notes] FlowArea.active_notes，元素为 FlowArea.Note 对象
## [param judge_line_y] 判定线的屏幕 Y 坐标（供 NEAREST_JUDGE 模式使用）
## [param note_judge_width] 判定宽度：NEAREST 模式为圆半径；其他模式为矩形全宽（半宽 = note_judge_width / 2）
## [param mode] JudgeMode 枚举值（int）
## 返回最优 FlowArea.Note 对象；若无满足条件的音符则返回 null
func find_best_note(click_pos: Vector2, active_notes: Array, judge_line_y: float,
		note_judge_width: float, mode: int) -> Object:
	var best_note: Object = null
	var best_score: float = INF

	for note in active_notes:
		if note.is_held:
			continue

		var center: Vector2 = _get_note_center(note)

		match mode:
			JudgeMode.NEAREST:
				# 圆形判定区域：半径 = note_judge_width
				var dist: float = click_pos.distance_to(center)
				if dist <= note_judge_width and dist < best_score:
					best_score = dist
					best_note = note

			JudgeMode.BEST_TIMING:
				# 矩形判定区域（半宽 = note_judge_width / 2），选 |note_y - click_y| 最小的音符
				if abs(center.x - click_pos.x) > note_judge_width * 0.5:
					continue
				var diff: float = abs(center.y - click_pos.y)
				if diff < best_score:
					best_score = diff
					best_note = note

			JudgeMode.NEAREST_JUDGE:
				# 矩形判定区域，选 |note_y - judge_line_y| 最小的音符
				if abs(center.x - click_pos.x) > note_judge_width * 0.5:
					continue
				var diff: float = abs(center.y - judge_line_y)
				if diff < best_score:
					best_score = diff
					best_note = note

			JudgeMode.BEST_TIMING_FIFO:
				# 矩形判定区域，选 note_y 最大（最靠近底部）的音符
				# 最大化 center.y 等价于最小化 -center.y
				if abs(center.x - click_pos.x) > note_judge_width * 0.5:
					continue
				var score: float = -center.y
				if score < best_score:
					best_score = score
					best_note = note

	return best_note

## 获取音符的代表中心点（屏幕坐标）
## Long 音符（type == 2）使用 VBoxC/head 节点中心 Y，与判定线距离比较更准确
## 其他音符使用 rect 自身中心点
func _get_note_center(note: Object) -> Vector2:
	var rect: Control = note.rect as Control
	var center_x: float = rect.position.x + rect.size.x * 0.5
	var center_y: float

	# NoteType.Long == 2（不直接引用 FlowArea.NoteType 以避免循环依赖）
	if note.type == 2:
		var head: Control = rect.get_node("VBoxC/head") as Control
		center_y = head.global_position.y + head.size.y * 0.5
	else:
		center_y = rect.position.y + rect.size.y * 0.5

	return Vector2(center_x, center_y)
