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

## 计算长条主体高度（像素）
## @param duration_ms 长条持续时间（毫秒）
## @param speed_px_per_ms 基础下落速度（像素/毫秒）
## @param head_tail_total_px 头尾总高度（像素）
## @return 长条主体高度（像素）
func compute_long_body_height(duration_ms: float, speed_px_per_ms: float, head_tail_total_px: float) -> float:
	return max(0.0, speed_px_per_ms * max(0.0, duration_ms) - max(0.0, head_tail_total_px))
