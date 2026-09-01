## 音符触摸判定查找器
## 从活跃音符索引列表中找到最适合被判定的音符
## 无状态纯函数，可安全被 FlowArea 持有并反复调用
class_name NoteJudger
extends RefCounted

## 平行数组宿主（FlowArea 注入）：判定读取 _rt_cx/_rt_cy/_rt_flags/_st_start 与时间窗，无需对象
var flow_area: Object = null

## 从活跃音符索引列表中找到最适合被判定的音符
## 判定策略固定为"先现先判"：水平矩形范围内，选 note_y 最大（最靠近底部/最早到达）的音符
## [param click_pos] 点击 / 触摸位置（屏幕坐标）
## [param active_indices] FlowArea 的候选 seq 索引数组
## [param note_judge_width] 判定宽度：矩形全宽（半宽 = note_judge_width / 2）
## 返回最优 seq 索引；若无满足条件的音符则返回 -1
func find_best_note_index(click_pos: Vector2, active_indices: Array, note_judge_width: float) -> int:
	var best_index: int = -1
	var best_score: float = INF
	var half_width: float = note_judge_width * 0.5
	var rt_cx: PackedFloat32Array = flow_area._rt_cx
	var rt_cy: PackedFloat32Array = flow_area._rt_cy
	var rt_flags: PackedByteArray = flow_area._rt_flags
	var st_start: PackedFloat32Array = flow_area._st_start
	var window_ms: float = flow_area.judge_window_ms
	var current_time: float = flow_area._synced_current_time

	for i in active_indices:
		if rt_flags[i] & (flow_area.F_HELD | flow_area.F_JUDGED | flow_area.F_REMOVED):
			continue

		var center: Vector2 = Vector2(rt_cx[i], rt_cy[i])

		# 统一水平过滤：矩形半宽
		if abs(center.x - click_pos.x) > half_width:
			continue

		# 判定有效区（时间窗）：音符起始时间比当前播放时间早超过 window_ms 则跳过，
		# 防止点击提前判定到过远的音符；已过线音符差值为负，天然不受影响，无需特殊处理
		if window_ms > 0.0 and (st_start[i] - current_time) > window_ms:
			continue

		# 先现先判：选 note_y 最大（最靠近底部/最早到达）的音符，防止跳过早期音符
		var score: float = -center.y
		if score < best_score:
			best_score = score
			best_index = i

	return best_index