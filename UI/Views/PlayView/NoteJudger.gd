## 音符触摸判定查找器
## 提供四种独立的触摸判定模式，从活跃音符列表中找到最适合被判定的音符
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

## 从活跃音符列表中找到最适合被判定的音符
## 所有模式统一使用矩形半宽水平过滤，垂直方向不限（全屏判定范围）
## [param click_pos] 点击 / 触摸位置（屏幕坐标）
## [param active_notes] FlowArea.active_notes，元素为 FlowArea.Note 对象
## [param judge_line_y] 判定线的屏幕 Y 坐标（供 NEAREST_JUDGE 模式使用）
## [param note_judge_width] 判定宽度：矩形全宽（半宽 = note_judge_width / 2）
## [param mode] JudgeMode 枚举值（int）
## 返回最优 FlowArea.Note 对象；若无满足条件的音符则返回 null
func find_best_note(click_pos: Vector2, active_notes: Array, judge_line_y: float,
		note_judge_width: float, mode: int) -> Object:
	var best_note: Object = null
	var best_score: float = INF
	var half_width: float = note_judge_width * 0.5

	for note in active_notes:
		if note.is_held or note.is_judged or note.rect == null:
			continue

		var center: Vector2 = _get_note_center(note)

		# 统一水平过滤：所有模式使用相同的矩形半宽
		if abs(center.x - click_pos.x) > half_width:
			continue

		match mode:
			JudgeMode.NEAREST:
				# 欧式距离最小的音符（无垂直限制，全屏范围内选最近）
				var dist: float = click_pos.distance_to(center)
				if dist < best_score:
					best_score = dist
					best_note = note

			JudgeMode.BEST_TIMING:
				# 选 |note_y - click_y| 最小的音符（离点击位置垂直最近）
				var diff: float = abs(center.y - click_pos.y)
				if diff < best_score:
					best_score = diff
					best_note = note

			JudgeMode.NEAREST_JUDGE:
				# 选 |note_y - judge_line_y| 最小的音符（离判定线最近）
				var diff: float = abs(center.y - judge_line_y)
				if diff < best_score:
					best_score = diff
					best_note = note

			JudgeMode.BEST_TIMING_FIFO:
				# 选 note_y 最大（最靠近底部/最早到达）的音符，防止跳过早期音符
				# 最大化 center.y 等价于最小化 -center.y
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
	var center_x: float = rect.global_position.x + rect.size.x * 0.5 #全局坐标包含offset_transform
	var center_y: float

	# NoteType.Long == 2（不直接引用 FlowArea.NoteType 以避免循环依赖）
	if note.type == 2:
		var head: Control = rect.get_node("VBoxC/head") as Control
		center_y = head.global_position.y + head.size.y * 0.5
	else:
		center_y = rect.global_position.y + rect.size.y * 0.5

	return Vector2(center_x, center_y)
