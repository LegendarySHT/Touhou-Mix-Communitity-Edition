## 动画管理器
## 统一管理项目中的动画和Tween，避免重复创建和内存泄漏
extends Node

class_name AnimationManager

## 单例实例
static var instance: AnimationManager

## 预定义的动画时长
const DURATION_QUICK = 0.2
const DURATION_NORMAL = 0.3
const DURATION_SLOW = 0.5

## 预定义的缓动方式
const EASING_STANDARD = Tween.EASE_OUT
const EASING_SMOOTH = Tween.EASE_IN_OUT
const EASING_SHARP = Tween.EASE_IN

## 所有活跃Tween的集合（用于统一管理）
var active_tweens: Dictionary[String, Tween] = {}

## Tween计数器（为每个Tween生成唯一ID）
var tween_counter: int = 0

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
	add_to_group("singleton")

## 创建位置动画
func animate_position(target: Node, to_pos: Vector2, duration: float = DURATION_NORMAL, 
					  tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "position", to_pos, duration)
	return tween

## 列表项水平滑动动画
func animate_list_item_horizontal(target: Node, excluded_index: int, horizon_delta: int, tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)

	var time=0.15
	tween.set_parallel(true)
	for i in range(excluded_index-4 if excluded_index-4>=0 else 0,excluded_index+5 if excluded_index+5<target.get_node("VBox").get_child_count() else target.get_node("VBox").get_child_count()):
		if i != excluded_index:
			var tag = target.get_node("VBox").get_child(i)
			time = time + 0.15 if time < 0.3 else 0.3
			tween.tween_property(tag,"theme_override_constants/margin_left",horizon_delta,time)

	return tween

## 创建透明度动画
func animate_modulate(target: Node, to_color: Color, duration: float = DURATION_NORMAL,
					  tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "modulate", to_color, duration)
	return tween

## 创建缩放动画
func animate_scale(target: Node, to_scale: Vector2, duration: float = DURATION_NORMAL,
				   tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "scale", to_scale, duration)
	return tween

## 创建旋转动画
func animate_rotation(target: Node, to_rotation: float, duration: float = DURATION_NORMAL,
					  tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "rotation", to_rotation, duration)
	return tween

## 创建大小动画（仅Control节点）
func animate_size(target: Control, to_size: Vector2, duration: float = DURATION_NORMAL,
				  tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "size", to_size, duration)
	return tween

## 创建淡入效果
func animate_fade_in(target: Node, duration: float = DURATION_NORMAL,
					 tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	target.modulate.a = 0.0
	tween.tween_property(target, "modulate:a", 1.0, duration)
	return tween

## 创建淡出效果
func animate_fade_out(target: Node, duration: float = DURATION_NORMAL,
					  tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "modulate:a", 0.0, duration)
	return tween

## 创建菜单展开动画
func animate_menu_expand(target: Control, target_height: float, 
						duration: float = DURATION_NORMAL,
						tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_SMOOTH)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(target, "custom_minimum_size:y", target_height, duration)
	return tween

## 创建菜单收起动画
func animate_menu_collapse(target: Control, duration: float = DURATION_NORMAL,
						   tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_SMOOTH)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(target, "custom_minimum_size:y", 0, duration)
	return tween

## 创建弹跳动画
func animate_bounce(target: Node, from_pos: Vector2, to_pos: Vector2,
					duration: float = DURATION_NORMAL,
					tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BOUNCE)
	target.position = from_pos
	tween.tween_property(target, "position", to_pos, duration)
	return tween

## 创建脉冲效果
func animate_pulse(target: Node, min_scale: float = 0.9, max_scale: float = 1.0,
				   duration: float = DURATION_QUICK,
				   tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "scale", Vector2(max_scale, max_scale), duration / 2.0)
	tween.tween_property(target, "scale", Vector2(min_scale, min_scale), duration / 2.0)
	return tween

## 延迟执行回调
func delay_call(callback: Callable, delay: float, tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.tween_callback(callback)
	if delay > 0:
		tween.set_delay(delay)
	return tween

## 创建序列动画（多个动画依次执行）
func create_sequence(tween_id: String = "") -> Tween:
	return _create_tween(tween_id)

## 获取或创建Tween（使用tween_id来保存和重用）
func _create_tween(tween_id: String = "") -> Tween:
	# 如果提供了ID且已存在，则杀死旧Tween
	if not tween_id.is_empty() and active_tweens.has(tween_id):
		active_tweens[tween_id].kill()
	
	# 生成唯一ID（如果未提供）
	if tween_id.is_empty():
		tween_id = "tween_%d" % tween_counter
		tween_counter += 1
	
	# 创建新Tween
	var tween = create_tween()
	active_tweens[tween_id] = tween
	
	# 连接Tween完成信号以清理
	tween.finished.connect(func() -> void:
		active_tweens.erase(tween_id)
	)
	
	return tween

## 停止特定ID的Tween
func stop_tween(tween_id: String) -> void:
	if active_tweens.has(tween_id):
		active_tweens[tween_id].kill()
		active_tweens.erase(tween_id)

## 停止所有Tween
func stop_all_tweens() -> void:
	for tween in active_tweens.values():
		if tween and tween.is_valid():
			tween.kill()
	active_tweens.clear()

## 暂停特定ID的Tween
func pause_tween(tween_id: String) -> void:
	if active_tweens.has(tween_id):
		active_tweens[tween_id].pause()

## 恢复特定ID的Tween
func resume_tween(tween_id: String) -> void:
	if active_tweens.has(tween_id):
		active_tweens[tween_id].play()

## 获取活跃Tween数量
func get_active_tween_count() -> int:
	return active_tweens.size()

## 销毁时清理所有Tween
func _exit_tree() -> void:
	stop_all_tweens()
