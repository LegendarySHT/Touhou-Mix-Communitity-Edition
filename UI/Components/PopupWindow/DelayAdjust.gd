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

## AdjustLine 单向运动范围（绝对值，单位：像素）
const _ADJUST_LINE_RANGE: float = 310
## 单段时间（每拍 0.5s，4 拍循环 = 3 轻 + 1 重 = 2.0s）
const _BEAT_SEGMENT_SEC: float = 0.5
## 动画速度 = RANGE/2 ÷ SEGMENT = 155/0.5 = 310px/s，用于 px↔ms 互转
const _ANIM_SPEED: float = _ADJUST_LINE_RANGE * 0.5 / _BEAT_SEGMENT_SEC
## 延迟显示范围（±ms），超过此范围的延迟值会被 clamp 到边界
const _MAX_DELAY_MS: float = 300.0
## 进入稳定状态所需连续稳定次数（3个连续样本 = _stable_count >= 2 时开始移动 CenterLine 和 LineEdit）
const _STABLE_START_THRESHOLD: int = 2
## 校准完成所需连续稳定次数（8个连续样本 = _stable_count >= 7 时完成）
const _CALIB_DONE_STABLE: int = 7
## 样本间允许的最大差值（ms），超过则视为不稳定
const _STABLE_MAX_DIFF: float = 50.0

# ===== 节拍音配置（GM 鼓组，channel 9）=====
# 重拍：Closed Hi-Hat（清脆响亮，穿透力强）；轻拍：Side Stick（军鼓击边，短促轻巧）
const _BEAT_CHANNEL: int = 9           # GM 标准鼓组通道
const _BEAT_TRACK: int = 0
const _BEAT_HARD_PITCH: int = 42       # Closed Hi-Hat（重拍，清脆响亮）
const _BEAT_HARD_VEL: int = 115
const _BEAT_SOFT_PITCH: int = 37       # Side Stick（轻拍，军鼓击边短促）
const _BEAT_SOFT_VEL: int = 60
const _BEAT_DURATION_SEC: float = 0.12 # 单拍发声时长（note_off 延迟，避免叠音）
# 待清理的 note_off entry 列表（stop_calibration 时强制停音）
# 每个 entry = {pitch, done, mp}，done 标志防止 SceneTreeTimer 自然超时重复触发 note_off
var _beat_off_timers: Array = []
# 校准前保存的 MidiPlaybackManager 音量（dB），stop_calibration 时恢复
# 避免校准期间修改的全局音量污染后续 PlayView 播放
var _saved_volume_db: float = NAN

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

	# 确保 SoundFont 已加载到后端合成器（trigger_note_on 依赖 SoundFont）
	# 设置页打开 DelayAdjust 时未调用 play()，SoundFont 可能尚未懒加载到 synth
	var mp = MidiPlaybackManager.instance
	if mp:
		mp.ensure_soundfont_loaded()
		_saved_volume_db = mp.midi_player_config.get("volume_db", -20.0)
		var midi_vol = ConfigManager.instance.get_int("Gameplay", "default_midi_volume", 50)
		mp.set_volume_db(linear_to_db(clamp(midi_vol, 0, 100) / 100.0))
	# 启动 AdjustLine 单向循环动画
	# AdjustLine 本身不可见，仅作为位置跟踪器，点击时在当前位置生成残影
	if _adjust_line_tween and _adjust_line_tween.is_valid():
		_adjust_line_tween.kill()
	_adjust_line_tween = AniMGR.create_sequence("popup_adjust_line_loop")
	_adjust_line_tween.set_loops()
	_adjust_line.offset_transform_position.x = 0
	_adjust_line_tween.set_trans(Tween.TRANS_LINEAR)

	# 4 拍循环：轻-轻-轻-重
	_adjust_line_tween.tween_property(_adjust_line, "offset_transform_position:x", -_ADJUST_LINE_RANGE / 2, _BEAT_SEGMENT_SEC)
	_adjust_line_tween.tween_callback(func(): _play_beat_sound(false))
	_adjust_line_tween.tween_property(_adjust_line, "offset_transform_position:x", - _ADJUST_LINE_RANGE, _BEAT_SEGMENT_SEC)
	_adjust_line_tween.tween_callback(func(): _play_beat_sound(false))
	_adjust_line_tween.tween_callback(func(): _adjust_line.offset_transform_position.x = _ADJUST_LINE_RANGE)
	_adjust_line_tween.tween_property(_adjust_line, "offset_transform_position:x", _ADJUST_LINE_RANGE / 2, _BEAT_SEGMENT_SEC)
	_adjust_line_tween.tween_callback(func(): _play_beat_sound(false))
	_adjust_line_tween.tween_property(_adjust_line, "offset_transform_position:x", 0, _BEAT_SEGMENT_SEC)
	_adjust_line_tween.tween_callback(func(): _on_hard_beat_triggered())
	
# 停止校准：终止动画 + 停止所有节拍音 + 恢复音量
func stop_calibration() -> void:
	if not _calib_active:
		return
	_calib_active = false
	if _adjust_line_tween and _adjust_line_tween.is_valid():
		_adjust_line_tween.kill()
		_adjust_line_tween = null
	_stop_all_beat_sounds()
	# 恢复校准前的全局音量，避免污染后续 PlayView 播放
	if not is_nan(_saved_volume_db):
		var mp = MidiPlaybackManager.instance
		if mp:
			mp.set_volume_db(_saved_volume_db)
		_saved_volume_db = NAN

# 停止所有节拍音：对每个未完成的 entry 直接触发 note_off 并标记 done
# done 标志防止 SceneTreeTimer 自然超时时重复触发 note_off（会导致 _manualActiveVoiceCount 变负）
func _stop_all_beat_sounds() -> void:
	for entry in _beat_off_timers:
		if entry["done"]:
			continue
		entry["done"] = true
		if is_instance_valid(entry["mp"]) and entry["mp"].midi_player:
			entry["mp"].midi_player.call("trigger_note_off", entry["pitch"], 0, _BEAT_CHANNEL, _BEAT_TRACK)
	_beat_off_timers.clear()

## 播放节拍音：通过 MidiPlaybackManager 实时合成 GM 鼓组
## 与 PlayView 演奏模式音符走同一音频路径（trigger_note_on），确保延迟特性一致
func _play_beat_sound(hard: bool = false) -> void:
	var mp = MidiPlaybackManager.instance
	if not mp or not mp.midi_player:
		return
	var pitch: int = _BEAT_HARD_PITCH if hard else _BEAT_SOFT_PITCH
	var vel: int = _BEAT_HARD_VEL if hard else _BEAT_SOFT_VEL
	mp.midi_player.call("trigger_note_on", pitch, vel, _BEAT_CHANNEL, _BEAT_TRACK)
	# 延迟 note_off，避免叠音；用 SceneTreeTimer 不依赖本节点生命周期
	var timer := get_tree().create_timer(_BEAT_DURATION_SEC)
	# entry 持有 pitch/done/mp，done 标志防止自然超时与 _stop_all_beat_sounds 重复触发
	var entry := {"pitch": pitch, "done": false, "mp": mp}
	_beat_off_timers.append(entry)
	timer.timeout.connect(func() -> void:
		if entry["done"]:
			return
		entry["done"] = true
		_beat_off_timers.erase(entry)
		if is_instance_valid(mp) and mp.midi_player:
			mp.midi_player.call("trigger_note_off", pitch, 0, _BEAT_CHANNEL, _BEAT_TRACK)
	)

## 获取当前延迟值（用于 PopupWindow.show_delay_adjust 返回）
func get_delay_value() -> int:
	return int(_delay_value.text)

# 重拍触发：播放重拍音（用户应在此刻点击）
# 重拍在 AdjustLine 中心(0) 触发，点击时用 AdjustLine 位置算延迟，与动画完全同步
func _on_hard_beat_triggered() -> void:
	_play_beat_sound(true)

# 点击校准按钮：用 AdjustLine 当前位置换算延迟，px → ms 由 _ANIM_SPEED 转换
func _on_delay_btn_pressed() -> void:
	if not _calib_active:
		return
	var click_x: float = _adjust_line.offset_transform_position.x
	# 生成残影：直接用 AdjustLine 当前位置，残影直观反映点击时刻 AdjustLine 的位置
	_spawn_adjust_line_ghost(click_x)
	# px → ms：除以速度 _ANIM_SPEED 乘 1000，取反使 x<0→正值
	var delay: float = -click_x / _ANIM_SPEED * 1000.0
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

# 更新 CenterLine 位置（坐标映射与 _on_delay_btn_pressed 互逆）
# clamp 到 ±_MAX_DELAY_MS 避免越出 DelayIndicator 容器边界
func _update_center_line(delay_ms: float) -> void:
	var clamped: float = clampf(delay_ms, -_MAX_DELAY_MS, _MAX_DELAY_MS)
	# ms → px：乘 _ANIM_SPEED 除 1000，与 _on_delay_btn_pressed 互逆
	_center_line.offset_transform_position = Vector2(-clamped * _ANIM_SPEED / 1000.0, 0)

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
	# 计算手指相对于 DelayIndicator 中心的 x 偏移（px），下转 ms）
	var local_x: float = event.position.x - rect.get_center().x
	# px → ms：除以 _ANIM_SPEED 乘 1000，取反使左侧→正延迟
	var delay: float = -local_x / _ANIM_SPEED * 1000.0
	delay = clampf(delay, -_MAX_DELAY_MS, _MAX_DELAY_MS)
	_set_delay_value(delay)

# 校准完成：停止动画并请求 PopupWindow 隐藏
func _finish_calibration() -> void:
	stop_calibration()
	finish_requested.emit()
