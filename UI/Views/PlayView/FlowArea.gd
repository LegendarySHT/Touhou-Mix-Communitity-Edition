extends Panel

class_name FlowArea

# 判定线
@onready var jl: HSeparator = $JudgeLine
@onready var ui: UIStateManager = UIStateManager.instance
@onready var canvas: CanvasLayer = $SVP

########## 配置参数 #############
var auto_mode: bool = false
var judge_mode: int = NoteJudger.JudgeMode.BEST_TIMING_FIFO  # 从 Judge/touch_judging_criteria 配置初始化
var note_judge_width: int = 100  # 统一判定宽度，从 Judge/block_judging_width 配置读取
var note_visual_width: int = 200  # 从 Appearance/block_size 配置读取
var note_judger: NoteJudger = NoteJudger.new()

# 音符下落动画
var trans_before_line: int = Tween.TRANS_LINEAR as int
var ease_before_line: int = Tween.EASE_IN_OUT as int
var trans_after_line: int = Tween.TRANS_LINEAR as int
var ease_after_line: int = Tween.EASE_OUT as int

var note_color_short: Color = Color.DEEP_PINK
var note_color_slide: Color = Color.CYAN
var note_color_long: Color = Color.DARK_ORANGE

# 判定参数（毫秒）- 与 ScoreCalculator.JUDGE_WINDOWS（秒）对应
var judge_windows: Dictionary = {
	"perfect": 50,    # < 0.05s
	"great": 150,     # < 0.15s
	"good": 200,      # < 0.20s
	"bad": 500        # < 0.50s
}

# 音符生成提前量（毫秒） - 确保音符在到达判定线前有足够时间显示 - 调下落速度也是用它（
var note_generation_lead_time: float = 1000.0

# 下落参数
var _note_fall_time_seconds: float = 1.0
var _note_fall_speed_after_judge_multiplier: float = 1.0
# 音符特效缩放
var particle_scale: float = 0.8
###################################

## note_judged(result: String, offset: String, block_type: int, timing_sec: float, signed_offset_sec: float)
## block_type: KeySequenceManager.BlockType 值 (0=INSTANT,1=SHORT,2=LONG)
## timing_sec: 偏差绝对值(秒)  signed_offset_sec: 带符号偏差(秒)
signal note_judged(result: String, offset: String, block_type: int, timing_sec: float, signed_offset_sec: float)
## long_holding(long_instance_id: int) - 长条持续加分 tick
signal long_holding(long_instance_id: int)

# 音符相关
var lane_width: float = 0
var active_notes: Array = []  # 存储活跃的音符

@onready var nt_b = load("res://UI/Views/PlayView/note_block.tscn").instantiate()
@onready var nt_s = load("res://UI/Views/PlayView/note_slide.tscn").instantiate()
@onready var nt_l = load("res://UI/Views/PlayView/note_long.tscn").instantiate()
@onready var particle = load("res://UI/Views/PlayView/particleSquare.tscn").instantiate()

# 粒子对象池：预创建固定数量实例并复用，避免每次按键 duplicate()+queue_free()
const _PARTICLE_POOL_SIZE = 12
var _particle_pool: Array = []
var _note_fall_calculator: NoteFallCalculator = NoteFallCalculator.new()

var parent_node: Node = null

# 【方案C】从PlayView同步的当前播放时间（毫秒）
## 这个时间来自 MidiPlaybackManager.get_position_ms()，已包含缓冲补偿
## 用于确保note判定与MIDI播放位置完全同步
var _synced_current_time: float = 0.0

# 修改为从PlayView传入的音符列表
var notes_list: Array[Note] = []  # 移除测试用的音符
var note_idx: int = 0

# 多点触控支持
var touch_positions: Dictionary = {}  # 存储每个触摸点的位置
var active_holds: Dictionary = {}     # 存储正在按住长条音符的触摸点ID和对应的音符

var pressed_keys: Dictionary = {}

enum NoteType {
	Block = 0,
	Slide,
	Long
}

class Note:
	var rect: Node
	var start_time: float    		# 生成note时的时间
	var duration: float
	var type: NoteType
	var lane: int            		# 轨道索引
	var tween: Tween
	var held_by_touch_id: int = -1  # 按住该音符的触摸点ID
	var game_sequence_ref: Object = null  # 新增：指向对应的GameSequence（演奏模式触发使用）

	# 用于滑键
	var can_judge: bool = false
	
	# 防止重复判定标志
	var is_judged: bool = false  # 已被判定过，防止同一note重复记录combo

	# 用于长条
	var is_held: bool = false    	# 是否被按住
	var cooldown: float = 0      	# 长按时的触发计时器
	var long_instance_id: int = -1  # 同一长条的唯一 ID（用于 ScoreCalculator 衰减链）
	var long_head_height: float = 0.0
	var long_tail_height: float = 0.0
	
	static var _next_long_id: int = 0
	static func _gen_long_id() -> int:
		_next_long_id += 1
		return _next_long_id
	
	func _init(tp: NoteType, st: float, dur: float, l: int):
		start_time = st
		duration = dur
		type = tp
		lane = l
	
	func set_rect(rt: Node):
		if rect :
			rect.queue_free()
		rect = rt

func init_flow_area():
	# 保存 notes_list，因为 clear_flow_area() 会清空它
	var saved_notes = notes_list.duplicate()
	clear_flow_area()
	notes_list = saved_notes
	note_idx = 0

	if EventBus.instance and not EventBus.instance.config_changed.is_connected(_on_config_changed):
		EventBus.instance.config_changed.connect(_on_config_changed)
	
	# 从配置读取判定模式和判定宽度
	judge_mode = ConfigManager.instance.get_int("Judge", "touch_judging_criteria", NoteJudger.JudgeMode.BEST_TIMING_FIFO)
	note_judge_width = ConfigManager.instance.get_int("Judge", "block_judging_width", 100)
	note_visual_width = ConfigManager.instance.get_int("Appearance", "block_size", note_visual_width)
	_apply_note_fall_config_from_settings()
	var lc = parent_node.get_lane_count()
	# 初始化轨道步长（考虑左右安全区，效果对齐 Unity 的中心点分布）
	var safe_width: float = max(1.0, get_viewport().get_visible_rect().size.x - 2.0 * float(parent_node.lane_padding))
	if lc <= 1:
		lane_width = safe_width
	else:
		lane_width = (safe_width - float(note_visual_width)) / float(lc - 1)
	
	# 设置判定线位置
	jl.position.y = get_viewport().get_visible_rect().size.y - parent_node.judge_line_offset_y
	
	# 配置初始化
	set_particle_scale(particle_scale)
	_init_particle_pool()
	set_note_color(NoteType.Block, note_color_short)
	set_note_color(NoteType.Slide, note_color_slide)
	set_note_color(NoteType.Long, note_color_long)

	set_note_width(note_visual_width)

	# 预计算下落距离和速度
	_note_fall_distance = jl.position.y + _note_max_size_y
	_note_fall_speed = _note_fall_calculator.compute_speed_px_per_ms(_note_fall_distance, _note_fall_time_seconds)

func _apply_note_fall_config_from_settings() -> void:
	var note_fall_time = ConfigManager.instance.get_float("Generator", "note_fall_time", 1.5)
	note_generation_lead_time = max(1.0, note_fall_time * 1000.0)

	var note_fall_mode = ConfigManager.instance.get_int("Generator", "note_fall_mode", 0)
	var note_fall_speed_after_judge_multiplier = ConfigManager.instance.get_float("Generator", "note_fall_speed_after_judge_multiplier", -1.0)
	if note_fall_speed_after_judge_multiplier <= 0.0:
		note_fall_speed_after_judge_multiplier = ConfigManager.instance.get_float("Appearance", "grace_time", 1.0)

	match note_fall_mode:
		0:
			var uniform_config = EasingMapper.get_preset_config(0)
			trans_before_line = EasingMapper.string_to_trans(uniform_config["before_func"])
			ease_before_line = EasingMapper.string_to_ease(uniform_config["before_phase"])
			trans_after_line = EasingMapper.string_to_trans(uniform_config["after_func"])
			ease_after_line = EasingMapper.string_to_ease(uniform_config["after_phase"])
		1:
			var accelerate_config = EasingMapper.get_preset_config(1)
			trans_before_line = EasingMapper.string_to_trans(accelerate_config["before_func"])
			ease_before_line = EasingMapper.string_to_ease(accelerate_config["before_phase"])
			trans_after_line = EasingMapper.string_to_trans(accelerate_config["after_func"])
			ease_after_line = EasingMapper.string_to_ease(accelerate_config["after_phase"])
		2:
			var before_func = ConfigManager.instance.get_string("Generator", "note_fall_easing_before_func", "LINEAR")
			var before_phase = ConfigManager.instance.get_string("Generator", "note_fall_easing_before_phase", "IN")
			var after_func = ConfigManager.instance.get_string("Generator", "note_fall_easing_after_func", "LINEAR")
			var after_phase = ConfigManager.instance.get_string("Generator", "note_fall_easing_after_phase", "IN")

			trans_before_line = EasingMapper.string_to_trans(before_func)
			ease_before_line = EasingMapper.string_to_ease(before_phase)
			trans_after_line = EasingMapper.string_to_trans(after_func)
			ease_after_line = EasingMapper.string_to_ease(after_phase)
		_:
			var fallback_config = EasingMapper.get_preset_config(0)
			trans_before_line = EasingMapper.string_to_trans(fallback_config["before_func"])
			ease_before_line = EasingMapper.string_to_ease(fallback_config["before_phase"])
			trans_after_line = EasingMapper.string_to_trans(fallback_config["after_func"])
			ease_after_line = EasingMapper.string_to_ease(fallback_config["after_phase"])

	_note_fall_time_seconds = note_fall_time
	_note_fall_speed_after_judge_multiplier = max(0.01, note_fall_speed_after_judge_multiplier)

func _on_config_changed(key: String, section: String, value: Variant) -> void:
	if section != "Generator":
		return

	if key in [
		"note_fall_time",
		"note_fall_mode",
		"note_fall_speed_after_judge_multiplier",
		"note_fall_easing_before_func",
		"note_fall_easing_before_phase",
		"note_fall_easing_after_func",
		"note_fall_easing_after_phase"
	]:
		_apply_note_fall_config_from_settings()
		_note_fall_distance = jl.position.y + _note_max_size_y
		_note_fall_speed = _note_fall_calculator.compute_speed_px_per_ms(_note_fall_distance, _note_fall_time_seconds)
		GameLogger.instance.info("Note fall config hot-reloaded: [%s] %s=%s" % [section, key, str(value)], "FlowArea")

# 修改音符颜色
func set_note_color(type: NoteType, cl: Color):
	match type:
		NoteType.Block:
			nt_b.get_node("core").modulate = cl
		NoteType.Slide:
			nt_s.get_node("core").modulate = cl
		NoteType.Long:
			for i in nt_l.get_node("VBoxC").get_children():
				i.get_node("core").modulate = cl

# 修改音符皮肤 数组顺序[短块图片，短块上色区图片，滑块。。。，长条（从头到尾）]
func set_note_texture(texture_array: Array):
	nt_b.texture = texture_array[0]
	nt_b.get_node("core").texture = texture_array[1]
	
	nt_s.texture = texture_array[2]
	nt_s.get_node("core").texture = texture_array[3]
	
	nt_l.get_node("VBoxC/head").texture = texture_array[4]
	nt_l.get_node("VBoxC/head/core").texture = texture_array[5]
	nt_l.get_node("VBoxC/body").texture = texture_array[6]
	nt_l.get_node("VBoxC/body/core").texture = texture_array[7]
	nt_l.get_node("VBoxC/tail").texture = texture_array[8]
	nt_l.get_node("VBoxC/tail/core").texture = texture_array[9]

# 修改音符宽度
func set_note_width(wid: float):
	for nt in [nt_b, nt_s, nt_l]:
		nt.size.x = wid
		if nt == nt_l:
			nt.get_node("VBoxC").size.x = wid
			var hd = nt.get_node("VBoxC/head")
			_note_max_size_y = _note_max_size_y if _note_max_size_y > hd.size.y else hd.size.y
		else:
			_note_max_size_y = _note_max_size_y if _note_max_size_y > nt.size.y else nt.size.y

# 修改特效大小
func set_particle_scale(scl: float):
	particle.set_particle_scale(scl)

func clear_flow_area():
	if notes_list:
		notes_list.clear()

	for note in active_notes.duplicate():
		if note.tween:
			note.tween.kill()
		if note.rect:
			note.rect.visible = false
			note.rect.queue_free()
			note.rect = null

	active_notes.clear()
	active_holds.clear()
	touch_positions.clear()
	pressed_keys.clear()
	note_idx = 0


var _note_max_size_y: float = 0
var _note_fall_speed: float = 0
var _note_fall_distance: float = 0

func _create_note(tp: NoteType, x: float, lane_idx: int = -1) -> Node:
	var cl: Color = parent_node.get_lane_color(lane_idx)
	
	var note_rect: Node = null
	match tp:
		NoteType.Block:
			note_rect = nt_b.duplicate()
			if lane_idx != -1:
				note_rect.get_node("core").modulate = cl
		NoteType.Slide:
			note_rect = nt_s.duplicate()
			if lane_idx != -1:
				note_rect.get_node("core").modulate = cl
		NoteType.Long:
			note_rect = nt_l.duplicate()
			if lane_idx != -1:
				for i in note_rect.get_node("VBoxC").get_children():
					i.get_node("core").modulate = cl
	
	note_rect.position = Vector2(x, -note_rect.size.y)
	canvas.add_child(note_rect)

	return note_rect

func _spawn_note(note_index: int) -> void:
	if note_index >= notes_list.size():
		return
	
	var nt = notes_list[note_index]

	# 计算音符位置
	var start_x = parent_node.lane_area.get_lane_by_idx(nt.lane).position.x + 10
	
	var rect = _create_note(nt.type, start_x, nt.lane)
	nt.set_rect(rect)

	# 计算下落位置
	var note_half = rect.size.y/2
	if nt.type == NoteType.Long:
		await get_tree().process_frame
		nt.long_tail_height = nt.rect.get_node("VBoxC/tail").size.y
		nt.long_head_height = nt.rect.get_node("VBoxC/head").size.y
		note_half = nt.long_tail_height / 2.0
	
	var target_pos_y = jl.position.y - note_half
	nt.rect.position.y = target_pos_y - _note_fall_distance # 因为音符需要匀速所以动态起点

	if nt.type == NoteType.Long:
		active_notes.append(nt)
		nt.tween = null
		_update_long_note_fall(nt, _synced_current_time)
		return

	var fall_time = _note_fall_calculator.compute_duration_seconds(target_pos_y - nt.rect.position.y, _note_fall_speed)

	# 使用Tween创建下落动画
	var tween = create_tween()

	tween.tween_property(rect, "position:y", target_pos_y, fall_time).set_trans(trans_before_line).set_ease(ease_before_line)
	active_notes.append(nt)
	nt.tween = tween

	tween.finished.connect(func():
		if nt.type == NoteType.Slide:
			_check_slide_stat(nt)

		if auto_mode and nt.type != NoteType.Long:
			_auto_click(nt)

		var t = create_tween()
		var window_y = get_viewport().get_visible_rect().size.y
		var after_line_distance = max(1.0, window_y - target_pos_y)
		var after_line_time = _note_fall_calculator.compute_after_line_duration_seconds(after_line_distance, _note_fall_speed, _note_fall_speed_after_judge_multiplier)
		t.tween_property(rect, "position:y", window_y , after_line_time).set_trans(trans_after_line).set_ease(ease_after_line)

		# 创建Note对象并添加到活跃列表	
		nt.tween = t

		# 动画结束后回收音符
		t.finished.connect(func():
			if nt.rect:
				_remove_note(nt)
				# 只有在音符播放完毕但未被击打时才判定为Miss
				note_judged.emit("Miss", "", nt.type, 1.0, 0.0)
		)
	)

func _compute_center_y_by_judge_time(judge_time_ms: float, current_time_ms: float, half_height: float) -> float:
	var pre_ms = max(1.0, _note_fall_time_seconds * 1000.0)
	var spawn_time_ms = judge_time_ms - pre_ms

	if current_time_ms <= judge_time_ms:
		var progress = clamp((current_time_ms - spawn_time_ms) / pre_ms, 0.0, 1.0)
		var eased = _note_fall_calculator.evaluate_curve_progress(progress, trans_before_line, ease_before_line)
		return jl.position.y - _note_fall_distance + eased * _note_fall_distance

	var window_y = get_viewport().get_visible_rect().size.y
	var after_distance = max(1.0, window_y - jl.position.y + half_height)
	var after_time_ms = max(
		1.0,
		_note_fall_calculator.compute_after_line_duration_seconds(after_distance, _note_fall_speed, _note_fall_speed_after_judge_multiplier) * 1000.0
	)
	var after_progress = clamp((current_time_ms - judge_time_ms) / after_time_ms, 0.0, 1.0)
	var eased_after = _note_fall_calculator.evaluate_curve_progress(after_progress, trans_after_line, ease_after_line)
	return jl.position.y + eased_after * after_distance

func _update_long_note_fall(note: Note, current_time_ms: float) -> void:
	if not note.rect:
		return

	var box := note.rect.get_node("VBoxC") as Control
	var head := box.get_node("head") as Control
	var tail := box.get_node("tail") as Control
	var body := box.get_node("body") as Control

	if note.long_head_height <= 0.0:
		note.long_head_height = head.size.y
	if note.long_tail_height <= 0.0:
		note.long_tail_height = tail.size.y

	var head_half = note.long_head_height * 0.5
	var tail_half = note.long_tail_height * 0.5

	var head_center = _compute_center_y_by_judge_time(note.start_time, current_time_ms, head_half)
	var tail_center = _compute_center_y_by_judge_time(note.start_time + max(0.0, note.duration), current_time_ms, tail_half)

	var tail_top = tail_center - tail_half
	var tail_bottom = tail_center + tail_half
	var head_top = head_center - head_half

	body.custom_minimum_size.y = max(0.0, head_top - tail_bottom)
	note.rect.position.y = tail_top

	if not note.is_judged:
		var window_y = get_viewport().get_visible_rect().size.y
		if tail_top > window_y:
			_remove_note(note)
			note_judged.emit("Miss", "", note.type, 1.0, 0.0)

var _auto_hold_idx: int = 0
func _auto_click(note: Note):
	if not note.rect:
		return
	if parent_node.play_mode and note.game_sequence_ref:
		_trigger_midi_notes_from_sequence(note.game_sequence_ref)
	if note.type == NoteType.Long:
		_judge_note(note)
		_hold_long_note(_auto_hold_idx + 666, note)
		_auto_hold_idx += 1
	else:
		_judge_note(note)

# 因为在for循环遍历时erase会导致漏元素，所以推迟元素的移除
func _delay_free(list, item_to_free):
	list.erase(item_to_free)

func _remove_note(note: Note) -> void:
	if note.rect:
		note.rect.visible = false
		note.rect.queue_free()
		call_deferred("_delay_free", active_notes, note)
	
	if note.tween:
		note.tween.kill()
	
	# 如果是被按住的长条音符，清理触摸点
	if note.is_held and note.held_by_touch_id in active_holds:
		call_deferred("_delay_free", active_holds, note.held_by_touch_id)

func _gui_input(event: InputEvent) -> void:
	if parent_node.is_pause:
		accept_event()
		return

	var event_time_ms := _get_realtime_position_ms()
	if event is InputEventScreenTouch:
		if event.pressed:
			# 手指按下
			touch_positions[event.index] = event.position
			_handle_press(event.index, event.position, event_time_ms)
		else:
			# 手指松开
			if event.index in touch_positions:
				touch_positions.erase(event.index)
			_handle_release(event.index)
	
	# 处理触摸拖动
	elif event is InputEventScreenDrag:
		touch_positions[event.index] = event.position
		_handle_touch_drag(event.index, event.position)
	# 桌面端鼠标点击/松开（复用触摸逻辑）
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_press(-1, event.position, event_time_ms)
		else:
			_handle_release(-1)
	# 桌面端鼠标拖动（用于长条跟随）
	elif event is InputEventMouseMotion:
		if -1 in active_holds:
			_handle_touch_drag(-1, event.position)

	if (event is InputEventScreenTouch or event is InputEventScreenDrag) and event.index in touch_positions:
		_check_slides_at_touch_pos(event.index, touch_positions[event.index], event_time_ms)
	elif event is InputEventMouseMotion and -1 in active_holds:
		_check_slides_at_touch_pos(-1, event.position, event_time_ms)

func _input(event: InputEvent) -> void:

	if ui.current_state == ui.UIState.PLAY_VIEW and event is InputEventKey:
		accept_event()
		if event.is_echo():
			return

		if parent_node.key_map and event.keycode in parent_node.key_map:
			if parent_node.is_pause:
				accept_event()
				return

			if event.pressed:
				var idx = parent_node.key_map.find(event.keycode)
				var event_time_ms := _get_realtime_position_ms()
				pressed_keys[event.keycode] = idx
				# 使用统一的判定函数，支持所有音符类型
				var bn = judge_note_at_lane(idx, idx, event_time_ms)
				if bn:
					if bn.type == NoteType.Long:
						_hold_long_note(event.keycode, bn)
				else:
					parent_node.lane_area.light_lane(idx)
			else:
				pressed_keys.erase(event.keycode)
				_handle_release(event.keycode)
		elif event.keycode == KEY_ESCAPE and event.pressed:
			parent_node.show_or_hide_menu()

# 处理触摸按下
func _handle_press(touch_id: int, pos: Vector2, input_time_ms: float = -1.0) -> void:
	var note = note_judger.find_best_note(pos, active_notes, jl.position.y, note_judge_width, judge_mode)
	if note == null:
		return
	if parent_node.play_mode and note.game_sequence_ref:
		_trigger_midi_notes_from_sequence(note.game_sequence_ref)
	_judge_note(note, true, input_time_ms)
	if note.type == NoteType.Long:
		_hold_long_note(touch_id, note)

# 处理触摸松开 释放长条音符
func _handle_release(touch_id: int) -> void:
	if touch_id not in active_holds:
		return
	
	var note = active_holds[touch_id]
	note.is_held = false
	
	# 如果VBoxC没有完全移动完毕，提前判定
	# if note.rect.size.y > note.rect.get_node("VBoxC").size.y * 0.2:
		# 判定为Good（提前释放）
		# note_judged.emit("Good", "提前释放")
	
	# 移除音符
	_remove_note(note)
	active_holds.erase(touch_id)

# 处理触摸拖动
func _handle_touch_drag(touch_id: int, pos: Vector2) -> void:
	if touch_id not in active_holds:
		return

	var note = active_holds[touch_id]
	if not note.is_held or note.held_by_touch_id != touch_id:
		return

	# 只更新x位置，y位置保持与判定线对齐
	note.rect.position.x = clamp(
		pos.x - note.rect.size.x / 2,
		float(parent_node.lane_padding),
		size.x - float(parent_node.lane_padding) - note.rect.size.x
	)

# 按住长条音符
# 注意：调用方负责在调用此函数之前已通过 _judge_note() 完成判定
func _hold_long_note(touch_id: int, note: Note) -> void:
	note.is_held = true
	note.held_by_touch_id = touch_id
	# 为新长条分配唯一实例 ID（用于 ScoreCalculator 独立衰减链）
	if note.long_instance_id < 0:
		note.long_instance_id = Note._gen_long_id()
	active_holds[touch_id] = note

# 检查slide音符是否在手指范围内（用于自动判定接近判定线的slide）
func _check_slides_at_touch_pos(touch_id: int, pos: Vector2, input_time_ms: float = -1.0) -> void:
	var judge_time_ms := input_time_ms
	if judge_time_ms < 0.0:
		judge_time_ms = _get_realtime_position_ms()

	for note in active_notes.filter(func (n):
			if n.type == NoteType.Slide:
				return true
			return false
			):
		var rect = note.rect as Control

		# 如果slide音符在触摸点范围内
		var note_x = rect.position.x + rect.size.x / 2
		var distance_to_touch = abs(pos.x - note_x)

		if note.can_judge and note.held_by_touch_id == touch_id and distance_to_touch > note_judge_width:
			if abs(judge_time_ms - note.start_time) < 100:
				_judge_note(note, true, judge_time_ms)
				# 判定后立即设置标志，防止重复判定
				note.can_judge = false
			else:
				note.can_judge = false

		if distance_to_touch < note_judge_width and not note.can_judge:
			note.can_judge = true
			note.held_by_touch_id = touch_id
			# return

func _check_slide_stat(note: Note):
	if note.lane in pressed_keys.values():
		_judge_note(note)
		return

	if note.can_judge:
		_judge_note(note)

## 获取音符的代表 Y 坐标（屏幕坐标）
## Long 音符使用 VBoxC/head 中心 Y，其他使用 rect 中心 Y
func _get_note_center_y(note: Note) -> float:
	if note.type == NoteType.Long:
		var head := note.rect.get_node("VBoxC/head") as Control
		return head.global_position.y + head.size.y * 0.5
	return note.rect.position.y + note.rect.size.y * 0.5

## 键盘模式专用：在指定轨道范围内查找最合适的音符并完成判定
## 触摸模式请使用 _handle_press()（通过 NoteJudger 实现）
func judge_note_at_lane(lane_l: int, lane_r: int, input_time_ms: float = -1.0) -> Note:
	var best_note: Note = null
	var best_score: float = INF

	for note in active_notes:
		if note.lane < lane_l or note.lane > lane_r or note.is_held:
			continue

		var note_y: float = _get_note_center_y(note)

		match judge_mode:
			NoteJudger.JudgeMode.NEAREST, NoteJudger.JudgeMode.BEST_TIMING, NoteJudger.JudgeMode.NEAREST_JUDGE:
				# 键盘模式无点击位置，以判定线 Y 为参考选最近音符
				var diff: float = abs(jl.position.y - note_y)
				if diff < best_score:
					best_score = diff
					best_note = note
			NoteJudger.JudgeMode.BEST_TIMING_FIFO:
				# 先现先判：选最靠近底部（note_y 最大）的音符
				var score: float = -note_y
				if score < best_score:
					best_score = score
					best_note = note

	if best_note:
		if parent_node.play_mode and best_note.game_sequence_ref:
			_trigger_midi_notes_from_sequence(best_note.game_sequence_ref)
		_judge_note(best_note, true, input_time_ms)
		return best_note
	return null

## 新增：从GameSequence触发MIDI音符（演奏模式）
func _trigger_midi_notes_from_sequence(game_seq: Object) -> void:
	# game_seq 是 KeySequenceManager.GameSequence 对象
	if not game_seq or game_seq.original_notes.is_empty():
		return
	
	var midi_player = MidiPlaybackManager.instance.midi_player
	if not midi_player:
		return
	
	# 触发原始notes中的所有MIDI音符
	for note in game_seq.original_notes:
		if note is MidiParser.Note and note.event:
			var evt = note.event
			
			# 触发note_on
			if midi_player.has_method("trigger_note_on"):
				midi_player.trigger_note_on(evt.pitch, evt.velocity, evt.channel)
			elif midi_player.has_method("note_on"):
				midi_player.note_on(evt.channel, evt.pitch, evt.velocity)

			# 非阻塞调度 note_off（避免循环内 await 导致后续音符串行延后）
			var delay_seconds = (game_seq.duration_ms / 1000.0) if game_seq.duration_ms > 0 else 0.1
			_schedule_note_off(midi_player, evt.pitch, evt.velocity, evt.channel, delay_seconds)

func _schedule_note_off(midi_player: Object, pitch: int, velocity: int, channel: int, delay_seconds: float) -> void:
	var timer = get_tree().create_timer(max(delay_seconds, 0.01))
	timer.timeout.connect(func():
		if not is_instance_valid(midi_player):
			return
		if midi_player.has_method("trigger_note_off"):
			midi_player.trigger_note_off(pitch, velocity, channel)
		elif midi_player.has_method("note_off"):
			midi_player.note_off(channel, pitch)
	)

func _trigger_touch_vibration() -> void:
	if not Input.has_method("vibrate_handheld"):
		return
	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		return
	if ConfigManager.instance.get_int("Playback", "vibrate_on_touch", 1) != 1:
		return
	var duration_ms = max(1.0, ConfigManager.instance.get_int("Playback", "vibration_duration", 20))
	Input.vibrate_handheld(duration_ms, 0.5)

func _init_particle_pool() -> void:
	if not _particle_pool.is_empty():
		# 重新初始化时同步比例（重试场景）
		for ptc in _particle_pool:
			ptc.set_particle_scale(particle_scale)
		return
	for _i in _PARTICLE_POOL_SIZE:
		var ptc = particle.duplicate()
		canvas.add_child(ptc)
		ptc.visible = false
		ptc.particle_done.connect(_on_particle_done.bind(ptc))
		_particle_pool.append(ptc)

func _on_particle_done(ptc: Node2D) -> void:
	ptc.visible = false
	_particle_pool.append(ptc)

func _get_particle_from_pool() -> Node2D:
	if _particle_pool.is_empty():
		# 池耗尽时回退创建（密集谱面极端情况）
		var ptc := particle.duplicate() as Node2D
		canvas.add_child(ptc)
		ptc.particle_done.connect(_on_particle_done.bind(ptc))
		return ptc
	return _particle_pool.pop_back()

func _generate_particle(type: String, pos: Vector2) -> void:
	var ptc := _get_particle_from_pool()
	ptc.position = pos
	ptc.visible = true
	ptc.play(type)
	
## 【方案C】同步当前播放时间（毫秒）
## 由 PlayView._process() 每帧调用，确保 FlowArea 的时间与 MIDI 播放位置完全同步
func set_current_time(time_ms: float) -> void:
	_synced_current_time = time_ms

func _get_realtime_position_ms() -> float:
	var playback_mgr = MidiPlaybackManager.instance
	if playback_mgr:
		return playback_mgr.get_position_ms()
	return _synced_current_time

func _judge_note(judge_note: Note, trigger_vibration: bool = false, input_time_ms: float = -1.0):
	# 防止重复判定：如果该note已被判定过，直接返回
	if judge_note.is_judged:
		return

	var judge_time_ms := input_time_ms if input_time_ms >= 0.0 else _get_realtime_position_ms()
	var time_diff = judge_note.start_time - judge_time_ms  # 毫秒，优先使用事件时刻的实时播放位置
	var abs_diff = abs(time_diff)
	var result: String = "Bad"

	if abs_diff <= judge_windows["perfect"]:
		result = "Perfect"
	elif abs_diff <= judge_windows["great"]:
		result = "Great"
	elif abs_diff <= judge_windows["good"]:
		result = "Good"
	elif abs_diff <= judge_windows["bad"]:
		result = "Bad"

	# 转换为秒，传递给 ScoreCalculator 所需的数据
	var timing_sec: float = abs_diff / 1000.0
	var signed_offset_sec: float = time_diff / 1000.0
	# 将 NoteType 映射到 BlockType (值相同: Block=0→INSTANT, Slide=1→SHORT, Long=2→LONG)
	var block_type: int = judge_note.type

	# 标记该note已被判定，防止重复
	judge_note.is_judged = true
	
	note_judged.emit(result, "%s%.1f ms" % ["+" if time_diff>=0 else "", time_diff],
		block_type, timing_sec, signed_offset_sec)
	if trigger_vibration:
		_trigger_touch_vibration()
	if judge_note.type != NoteType.Long:
		_remove_note(judge_note)

	# 特效
	var light_color = note_color_short if judge_note.type == NoteType.Block else (note_color_slide if judge_note.type == NoteType.Slide else note_color_long)
	get_parent().lane_area.light_lane(judge_note.lane, light_color)
	
	if judge_note.type != NoteType.Long:
		_generate_particle(result, judge_note.rect.position + judge_note.rect.size/2)

var _is_pause: bool = false
func _process(delta: float) -> void:
	if not parent_node:
		return

	# 暂停处理
	if parent_node.is_pause and not _is_pause:
		for i in active_notes:
			if i.tween:
				i.tween.pause()
		_is_pause = true
	elif not parent_node.is_pause and _is_pause:
		for i in active_notes:
			if i.tween:
				i.tween.play()
		_is_pause = false

	if _is_pause:
		return

	# 生成音符
	while note_idx < notes_list.size() and notes_list[note_idx].start_time < parent_node.current_time + note_generation_lead_time:
		_spawn_note(note_idx)
		note_idx += 1

	for note in active_notes:
		if note.type == NoteType.Long and not note.is_held:
			_update_long_note_fall(note, _synced_current_time)
	
	# 自动按长条
	if auto_mode:
		for long in active_notes.filter(func(nt):
			if nt.type == NoteType.Long and not nt.is_held:
				var head = nt.rect.get_node("VBoxC/head")
				return abs(head.global_position.y + head.size.y/2 - jl.position.y) < 12
			return false):
			_auto_click(long)

	# 更新长条音符的按住进度和显示
	for touch_id in active_holds:
		var note = active_holds[touch_id]
		if note.is_held:
			# 更新进度
			var vbox = note.rect.get_node("VBoxC")
			var n_half = vbox.get_node("head").size.y / 2
			var h = jl.position.y - vbox.global_position.y - n_half * 3 - 3
			if h >= 0:
				vbox.get_node("body").custom_minimum_size.y = h
			else: # 提前判定掉防止错位
				# note_judged.emit("Perfect", "完成") # 如果尾部算一个音符的话可以取消注释这个
				_generate_particle("Perfect", vbox.get_node("head").global_position + Vector2(float(note_visual_width)/2, n_half))
				_remove_note(note)
				active_holds.erase(touch_id)
				continue
			
			# 加分及加combo
			if note.cooldown > 0.25: # 0.25是触发频率
				note.cooldown = 0
				long_holding.emit(note.long_instance_id)
			else:
				note.cooldown += delta
