extends RefCounted
class_name NoteFallCalculator

## 计算音符下落速度（像素/毫秒）
## @param distance_px 下落距离（像素）
## @param fall_time_seconds 下落时间（秒）
## @return 速度（像素/毫秒）
func compute_speed_px_per_ms(distance_px: float, fall_time_seconds: float) -> float:
	var safe_time_ms = max(1.0, fall_time_seconds * 1000.0)
	return max(0.0001, distance_px) / safe_time_ms

## 根据距离与速度计算时长（秒）
## @param distance_px 距离（像素）
## @param speed_px_per_ms 速度（像素/毫秒）
## @return 时长（秒）
func compute_duration_seconds(distance_px: float, speed_px_per_ms: float) -> float:
	var safe_speed = max(0.0001, speed_px_per_ms)
	return max(0.0, distance_px) / safe_speed / 1000.0

## 计算判定线后下落时长（秒）
## @param distance_px 判定线后下落距离（像素）
## @param base_speed_px_per_ms 判定线前基础速度（像素/毫秒）
## @param after_speed_multiplier 判定线后速度倍率
## @return 时长（秒）
func compute_after_line_duration_seconds(distance_px: float, base_speed_px_per_ms: float, after_speed_multiplier: float) -> float:
	var safe_multiplier = max(0.01, after_speed_multiplier)
	var after_speed = max(0.0001, base_speed_px_per_ms) * safe_multiplier
	return compute_duration_seconds(distance_px, after_speed)

## 评估缓动曲线在指定进度的归一化位移（0~1）
## @param progress 归一化时间进度（0~1）
## @param trans Tween.TRANS_* 常量
## @param ease_ Tween.EASE_* 常量
## @return 归一化位移（0~1）
func evaluate_curve_progress(progress: float, trans: int, ease_: int) -> float:
	var safe_progress = clamp(progress, 0.0, 1.0)
	if trans == Tween.TRANS_LINEAR:
		return safe_progress
	var value = Tween.interpolate_value(0.0, 1.0, safe_progress, 1.0, trans, ease_)
	return clamp(float(value), 0.0, 1.0)

## 在指定缓动曲线下，计算保证“头部在开始时刻到线、尾部在持续时长后到线”的长条总高度（含头尾）
## @param pre_line_distance_px 普通音符从生成点到判定线的距离（像素）
## @param pre_line_fall_time_seconds 普通音符下落到判定线所需时间（秒）
## @param hold_duration_ms 长条持续时间（毫秒）
## @param trans Tween.TRANS_* 常量
## @param ease_ Tween.EASE_* 常量
## @param fallback_speed_px_per_ms 兜底线性速度（像素/毫秒）
## @return 长条总高度（像素，包含头尾）
func compute_long_total_height_with_easing(
	pre_line_distance_px: float,
	pre_line_fall_time_seconds: float,
	hold_duration_ms: float,
	trans: int,
	ease_: int,
	fallback_speed_px_per_ms: float,
	reference_offset_px: float = 0.0
) -> float:
	var safe_distance = max(0.0001, pre_line_distance_px)
	var safe_pre_time = max(0.001, pre_line_fall_time_seconds)
	var safe_hold_ms = max(0.0, hold_duration_ms)
	var safe_offset = max(0.0, reference_offset_px)

	if safe_hold_ms <= 0.0:
		return 0.0

	var hold_seconds = safe_hold_ms / 1000.0
	var alpha = safe_pre_time / (safe_pre_time + hold_seconds)
	var eased_alpha = evaluate_curve_progress(alpha, trans, ease_)

	if eased_alpha <= 0.0001:
		return max(0.0, max(0.0001, fallback_speed_px_per_ms) * safe_hold_ms + safe_offset)

	return max(0.0, (safe_distance + safe_offset) / eased_alpha - safe_distance)

## 计算长条主体高度（像素）
## @param duration_ms 长条持续时间（毫秒）
## @param speed_px_per_ms 基础下落速度（像素/毫秒）
## @param head_tail_total_px 头尾总高度（像素）
## @return 长条主体高度（像素）
func compute_long_body_height(duration_ms: float, speed_px_per_ms: float, head_tail_total_px: float) -> float:
	return max(0.0, speed_px_per_ms * max(0.0, duration_ms) - max(0.0, head_tail_total_px))
