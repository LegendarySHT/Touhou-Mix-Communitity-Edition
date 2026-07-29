extends VBoxContainer

class_name DelayAdjust

## 校准完成信号（连续 N 个稳定样本后触发），由 PopupWindow 监听并 hide()
signal finish_requested

@onready var _delay_indicator: Panel = $DelayIndicator
@onready var _center_line: PanelContainer = $DelayIndicator/CenterLine
@onready var _adjust_line: PanelContainer = $DelayIndicator/AdjustLine
@onready var _delay_value: Label = $HBoxC/Value
# 主题管理器通过 PopupWindow.delay_btn getter 转发访问
@onready var delay_btn: Button = $Button

# ===== 延迟校准状态 =====
## 校准是否进行中
var _calib_active: bool = false
## 已采集的延迟样本（单位：ms，正=音频延迟需正向补偿，负=负向补偿）
var _calib_samples: Array[float] = []
## AdjustLine 循环动画 Tween 引用
var _adjust_line_tween: Tween = null
## 连续稳定样本计数（与前一个样本差值 ≤ _STABLE_MAX_DIFF 的连续次数）
var _stable_count: int = 0
## 上一个样本值（用于差值计算）
var _last_sample: float = NAN

## AdjustLine 单向运动范围（绝对值，单位：像素，1 像素 = 1 ms）
const _ADJUST_LINE_RANGE: float = 310.0
## AdjustLine 单程时间
const _ADJUST_LINE_DURATION: float = 1.0
## 进入稳定状态所需连续稳定次数（3个连续样本 = _stable_count >= 2 时开始移动 CenterLine）
const _STABLE_START_THRESHOLD: int = 2
## 校准完成所需连续稳定次数（8个连续样本 = _stable_count >= 7 时完成）
const _CALIB_DONE_STABLE: int = 7
## 样本间允许的最大差值（ms），超过则视为不稳定
const _STABLE_MAX_DIFF: float = 50.0

func _ready() -> void:
	delay_btn.pressed.connect(_on_delay_btn_pressed)

# 启动校准：重置数据 + 启动 AdjustLine 单向循环动画
func start_calibration(current_delay: int = 0) -> void:
	_calib_active = true
	_calib_samples.clear()
	_stable_count = 0
	_last_sample = NAN

	_delay_value.text = str(current_delay)
	_update_center_line(float(_delay_value.text))
	# 启动 AdjustLine 单向循环动画
	# AdjustLine 本身不可见，仅作为位置跟踪器，点击时在当前位置生成残影
	_adjust_line.offset_transform_position = Vector2(_ADJUST_LINE_RANGE, 0)
	if _adjust_line_tween and _adjust_line_tween.is_valid():
		_adjust_line_tween.kill()
	_adjust_line_tween = AniMGR.create_sequence("popup_adjust_line_loop")
	_adjust_line_tween.set_loops()
	_adjust_line_tween.set_trans(Tween.TRANS_LINEAR)

	# 三个轻拍音一个重拍音
	_adjust_line_tween.tween_callback(func(): _adjust_line.offset_transform_position = Vector2(_ADJUST_LINE_RANGE, 0))
	_adjust_line_tween.tween_property(_adjust_line, "offset_transform_position:x", _ADJUST_LINE_RANGE / 2, _ADJUST_LINE_DURATION / 4)
	_adjust_line_tween.tween_callback(func(): _play_beat_sound())
	_adjust_line_tween.tween_property(_adjust_line, "offset_transform_position:x", 0, _ADJUST_LINE_DURATION / 4)
	_adjust_line_tween.tween_callback(func(): _play_beat_sound(true))
	_adjust_line_tween.tween_property(_adjust_line, "offset_transform_position:x", -_ADJUST_LINE_RANGE / 2, _ADJUST_LINE_DURATION / 4)
	_adjust_line_tween.tween_callback(func(): _play_beat_sound())
	_adjust_line_tween.tween_property(_adjust_line, "offset_transform_position:x", -_ADJUST_LINE_RANGE, _ADJUST_LINE_DURATION / 4)
	_adjust_line_tween.tween_callback(func(): _play_beat_sound())

# 停止校准：终止动画
func stop_calibration() -> void:
	if not _calib_active:
		return
	_calib_active = false
	if _adjust_line_tween and _adjust_line_tween.is_valid():
		_adjust_line_tween.kill()
	_adjust_line_tween = null

## 占位函数：AdjustLine 经过 0 时调用，正常应播放节拍音
## TODO: 接入实际音频播放
func _play_beat_sound(hard: bool = false) -> void:
	# 重音
	if hard:
		pass
	else:
		pass

## 获取当前延迟值（用于 PopupWindow.show_delay_adjust 返回）
func get_delay_value() -> int:
	return int(_delay_value.text)

# 点击校准按钮：记录当前 AdjustLine 位置作为延迟样本
func _on_delay_btn_pressed() -> void:
	if not _calib_active:
		return
	var click_x: float = _adjust_line.offset_transform_position.x
	# 生成 AdjustLine 残影并播放淡出动画（视觉反馈）
	_spawn_adjust_line_ghost(click_x)
	# 记录样本：左（负 x）= 正延迟，右（正 x）= 负延迟 → 取反
	var delay: float = -click_x
	_calib_samples.append(delay)
	# 稳定性检测：与前一个样本的差值 ≤ 50ms → 计数器 +1，否则归零
	if not is_nan(_last_sample):
		if abs(delay - _last_sample) <= _STABLE_MAX_DIFF:
			_stable_count += 1
		else:
			_stable_count = 0
	_last_sample = delay
	# 进入稳定状态（连续3个样本稳定，即 _stable_count >= 2）→ 开始更新 CenterLine 和 LineEdit
	if _stable_count >= _STABLE_START_THRESHOLD:
		var avg: float = _compute_stable_average()
		_set_delay_value(avg)
	# 连续8个样本稳定（_stable_count >= 7）→ 校准完成
	if _stable_count >= _CALIB_DONE_STABLE:
		_finish_calibration()

# 在指定位置生成 AdjustLine 残影（点击瞬间的视觉反馈，1秒淡出）
func _spawn_adjust_line_ghost(pos_x: float) -> void:
	var ghost: PanelContainer = _adjust_line.duplicate()
	ghost.visible = true
	ghost.offset_transform_position = Vector2(pos_x, 0)
	_delay_indicator.add_child(ghost)
	var ghost_tween := AniMGR.animate_fade_out(ghost, 1.0, "popup_adjust_ghost_%d" % Time.get_ticks_msec())
	ghost_tween.finished.connect(func() -> void:
		if is_instance_valid(ghost):
			ghost.queue_free()
	)

# 计算当前稳定窗口内样本的平均值（窗口 = _stable_count + 1 个连续稳定样本）
func _compute_stable_average() -> float:
	var window_size: int = _stable_count + 1
	var start: int = maxi(0, _calib_samples.size() - window_size)
	var sum: float = 0.0
	for i in range(start, _calib_samples.size()):
		sum += _calib_samples[i]
	return sum / float(_calib_samples.size() - start)

# 更新 CenterLine 位置（中间=0，左=正延迟，右=负延迟，1像素=1ms）
func _update_center_line(delay_ms: float) -> void:
	_center_line.offset_transform_position = Vector2(-delay_ms, 0)

# 统一设置延迟值：更新 Label 和 CenterLine
func _set_delay_value(delay_ms: float) -> void:
	_delay_value.text = str(roundi(delay_ms))
	_update_center_line(delay_ms)

# 手动拖动 DelayIndicator：在面板范围内点击/拖动 → CenterLine 移动到手指位置并更新延迟
# 注意：TabContainer 切换到本页时本节点 visible=true；PopupWindow hide() 不改子节点 visible，
# 因此用 is_visible_in_tree() 综合判断窗口实际可见性
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	# 忽略松开事件
	if event is InputEventScreenTouch and not event.pressed:
		return
	var rect := _delay_indicator.get_global_rect()
	if not rect.has_point(event.position):
		return
	# 计算手指相对于 DelayIndicator 中心的 x 偏移（1 像素 = 1 ms）
	var local_x: float = event.position.x - rect.get_center().x
	# 限制在面板范围内
	local_x = clampf(local_x, -rect.size.x / 2.0, rect.size.x / 2.0)
	# 左 = 正延迟，右 = 负延迟 → 取反
	_set_delay_value(-local_x)

# 校准完成：停止动画并请求 PopupWindow 隐藏
func _finish_calibration() -> void:
	stop_calibration()
	finish_requested.emit()
