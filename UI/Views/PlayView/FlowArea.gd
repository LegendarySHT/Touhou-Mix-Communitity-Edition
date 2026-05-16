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
var check_slide_when_finger_up: bool = true  # Judge/check_instant_blocks_when_finger_up
var only_perfect_slides: bool = false  # Judge/only_perfect_instant_blocks_before_judge
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
# 渲染裁剪参数：仅影响可见性，不影响判定/时序
var _note_cull_margin_top: float = 120.0
var _note_cull_margin_bottom: float = 180.0
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

# 音符对象池：分离三种类型，避免重复创建节点（第1阶段：基础框架）
const _NOTE_POOL_BLOCK_SIZE = 30   # Block 音符池大小
const _NOTE_POOL_SLIDE_SIZE = 30   # Slide 音符池大小
const _NOTE_POOL_LONG_SIZE = 6     # Long 音符池大小
var _note_pool_block: Array[Node] = []   # Block 音符复用池
var _note_pool_slide: Array[Node] = []   # Slide 音符复用池
var _note_pool_long: Array[Node] = []    # Long 音符复用池

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

# 输入去重：防止桌面环境下鼠标与触摸事件双触发导致一次点击判定多个音符
const _PRESS_DEDUP_MS: float = 5.0
const _PRESS_DEDUP_DISTANCE: float = 6.0
var _last_press_time_ms: float = -1000000.0
var _last_press_pos: Vector2 = Vector2(-1000000.0, -1000000.0)
var _last_press_was_mouse: bool = false

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
		rect = rt

func init_flow_area():
	# 保存 notes_list，因为 clear_flow_area() 会清空它
	var saved_notes = notes_list.duplicate()
	clear_flow_area()
	notes_list = saved_notes
	note_idx = 0

	if EventBus.instance and not EventBus.instance.config_changed.is_connected(_on_config_changed):
		EventBus.instance.config_changed.connect(_on_config_changed)

	auto_mode = ConfigManager.instance.get_int("Playback", "auto_mode", 0) == 1
	
	# 从配置读取判定模式和判定宽度
	judge_mode = ConfigManager.instance.get_int("Judge", "touch_judging_criteria", NoteJudger.JudgeMode.BEST_TIMING_FIFO)
	note_judge_width = ConfigManager.instance.get_int("Judge", "block_judging_width", 100)
	check_slide_when_finger_up = ConfigManager.instance.get_int("Judge", "check_instant_blocks_when_finger_up", 1) == 1
	only_perfect_slides = ConfigManager.instance.get_int("Judge", "only_perfect_instant_blocks_before_judge", 0) == 1
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
	_init_note_pool()
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
	if section == "Playback" and key == "auto_mode":
		auto_mode = int(value) == 1
		GameLogger.instance.info("FlowArea auto_mode updated: %s" % ("ON" if auto_mode else "OFF"), "FlowArea")
		return

	if section == "Judge":
		if key == "touch_judging_criteria":
			judge_mode = int(value)
			return
		if key == "block_judging_width":
			note_judge_width = int(value)
			return
		if key == "check_instant_blocks_when_finger_up":
			check_slide_when_finger_up = int(value) == 1
			return
		if key == "only_perfect_instant_blocks_before_judge":
			only_perfect_slides = int(value) == 1
			return

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
		# 关键：使用 custom_minimum_size 而非 size.x（修复 VBoxContainer 覆盖问题）
		nt.custom_minimum_size = Vector2(wid, 0)
		nt.size.x = wid  # 保留兼容性
		if nt == nt_l:
			nt.get_node("VBoxC").custom_minimum_size = Vector2(wid, 0)
			nt.get_node("VBoxC").size.x = wid  # 保留兼容性
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
			# 改为回池而不是 queue_free()
			_return_note_to_pool(note.rect, note.type)
			note.rect = null

	active_notes.clear()
	active_holds.clear()
	touch_positions.clear()
	pressed_keys.clear()
	note_idx = 0

## 检查是否还有活跃音符（用于游戏结束后等待音符自然消除）
func has_active_notes() -> bool:
	return active_notes.size() > 0


var _note_max_size_y: float = 0
var _note_fall_speed: float = 0
var _note_fall_distance: float = 0

func _create_note(tp: NoteType, x: float, lane_idx: int = -1) -> Node:
	var cl: Color = parent_node.get_lane_color(lane_idx)
	
	# 改为从池中取而不是 duplicate()
	var note_rect: Node = _get_note_from_pool(tp)
	note_rect.visible = true  # 从池中取出后立即可见
	
	match tp:
		NoteType.Block:
			if lane_idx != -1:
				note_rect.get_node("core").modulate = cl
		NoteType.Slide:
			if lane_idx != -1:
				note_rect.get_node("core").modulate = cl
		NoteType.Long:
			if lane_idx != -1:
				for i in note_rect.get_node("VBoxC").get_children():
					i.get_node("core").modulate = cl
	
	note_rect.position = Vector2(x, -note_rect.size.y)

	return note_rect

func _spawn_note(note_index: int) -> void:
	if note_index >= notes_list.size():
		return
	
	var nt = notes_list[note_index]
	# 关键：重置 Note 数据对象的判定状态（修复多音符同时判定问题）
	nt.is_judged = false
	nt.can_judge = false
	nt.is_held = false
	nt.held_by_touch_id = -1
	nt.cooldown = 0
	if nt.type == NoteType.Long:
		nt.long_head_height = 0.0
		nt.long_tail_height = 0.0

	# 计算音符位置
	var beam_node_for_note = parent_node.lane_area.get_lane_by_idx(nt.lane)
	var beam_margin = max(0.0, (beam_node_for_note.beam_size.x - note_visual_width) / 2.0)
	var start_x = beam_node_for_note.position.x + beam_margin
	
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
	# 关键：保存 Tween 引用用于复用前清理（修复 Tween lambda 被释放错误）
	rect.set_meta("_last_tween", tween)

	tween.finished.connect(func():
		if nt.is_judged or nt.rect == null:
			return

		if nt.type == NoteType.Slide:
			_check_slide_stat(nt)

		if auto_mode and nt.type != NoteType.Long:
			_auto_click(nt)
			if nt.is_judged or nt.rect == null:
				return

		var t = create_tween()
		var window_y = get_viewport().get_visible_rect().size.y
		var after_line_distance = max(1.0, window_y - target_pos_y)
		var after_line_time = _note_fall_calculator.compute_after_line_duration_seconds(after_line_distance, _note_fall_speed, _note_fall_speed_after_judge_multiplier)
		t.tween_property(rect, "position:y", window_y , after_line_time).set_trans(trans_after_line).set_ease(ease_after_line)

		# 创建Note对象并添加到活跃列表	
		nt.tween = t
		# 关键：保存第二个 Tween 引用用于复用前清理
		rect.set_meta("_last_tween", t)

		# 动画结束后回收音符
		t.finished.connect(func():
			if nt.rect and not nt.is_judged:
				_remove_note(nt)
				# 只有在音符播放完毕但未被击打时才判定为Miss
				note_judged.emit("Miss", "", nt.type, 1.0, 0.0)
		)
	)

func _compute_center_y_by_judge_time(judge_time_ms: float, current_time_ms: float, half_height: float) -> float:
	var pre_ms = max(1.0, _note_fall_time_seconds * 1000.0)
	var spawn_time_ms = judge_time_ms - pre_ms

	if current_time_ms <= judge_time_ms:
		if current_time_ms < spawn_time_ms:
			# 提前生成时继续保持匀速下落，避免音符在顶端静止等待
			var early_dt_ms = spawn_time_ms - current_time_ms
			return jl.position.y - _note_fall_distance - early_dt_ms * _note_fall_speed
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
	if note.is_held:
		head_center = jl.position.y
	var tail_center = _compute_center_y_by_judge_time(note.start_time + max(0.0, note.duration), current_time_ms, tail_half)

	var tail_top = tail_center - tail_half
	var tail_bottom = tail_center + tail_half
	var tail_judge_y = tail_center  # 使用 tail 中心而非顶部判定，避免特效位置过低
	var head_top = head_center - head_half

	body.custom_minimum_size.y = max(0.0, head_top - tail_bottom)
	note.rect.position.y = tail_top

	if not note.is_judged and not note.is_held and note.held_by_touch_id < 0:
		var window_y = get_viewport().get_visible_rect().size.y
		if tail_judge_y >= window_y:
			_remove_note(note)
			note_judged.emit("Miss", "", note.type, 1.0, 0.0)

func _update_note_visibility(note: Note) -> void:
	# 仅做渲染层裁剪：不移除，不影响判定，仅设置 visible
	if not note or not note.rect:
		return

	var rect_ctrl := note.rect as Control
	if rect_ctrl == null:
		return

	var top_y := rect_ctrl.position.y
	var visual_height := rect_ctrl.size.y

	if note.type == NoteType.Long and rect_ctrl.has_node("VBoxC"):
		var vbox := rect_ctrl.get_node("VBoxC") as Control
		if vbox:
			visual_height = max(visual_height, vbox.size.y)

	var bottom_y = top_y + max(1.0, visual_height)
	var view_h := get_viewport().get_visible_rect().size.y
	var visible_top := -_note_cull_margin_top
	var visible_bottom := view_h + _note_cull_margin_bottom

	rect_ctrl.visible = (bottom_y >= visible_top and top_y <= visible_bottom)

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

# ========== 音符对象池管理（第1阶段：框架 + 第2阶段：重置逻辑） =========
func _get_pool_by_type(tp: NoteType) -> Array[Node]:
	"""根据音符类型返回对应的池"""
	match tp:
		NoteType.Block:
			return _note_pool_block
		NoteType.Slide:
			return _note_pool_slide
		NoteType.Long:
			return _note_pool_long
		_:
			return _note_pool_block  # 默认

func _get_pool_max_size(tp: NoteType) -> int:
	"""根据音符类型返回池的最大大小"""
	match tp:
		NoteType.Block:
			return _NOTE_POOL_BLOCK_SIZE
		NoteType.Slide:
			return _NOTE_POOL_SLIDE_SIZE
		NoteType.Long:
			return _NOTE_POOL_LONG_SIZE
		_:
			return _NOTE_POOL_BLOCK_SIZE

func _reset_note_for_reuse(note: Node, note_type: NoteType) -> void:
	"""重用节点前的完整状态重置。避免上一次使用的残留（第2阶段关键）"""
	
	# ✅ P0: 位置、可见性、基础属性
	note.position = Vector2.ZERO  # 关键：重置到原点（后续会在 _spawn_note 重新设置）
	note.visible = true
	note.modulate = Color.WHITE  # 清除任何颜色/透明残留
	note.z_index = 0
	note.scale = Vector2.ONE
	note.rotation = 0.0
	
	# ✅ P1: 关键 - 重新应用尺寸约束（用 custom_minimum_size 而非 size）
	# 这是之前失败的核心原因！VBoxContainer 会覆盖 size.x，但尊重 custom_minimum_size
	match note_type:
		NoteType.Block, NoteType.Slide:
			note.custom_minimum_size = Vector2(note_visual_width, 0)
		NoteType.Long:
			note.custom_minimum_size = Vector2(note_visual_width, 0)
			# 长条还要重置内部 VBoxC
			var vbox = note.get_node("VBoxC")
			vbox.custom_minimum_size = Vector2(note_visual_width, 0)
			# 清理长条的长条特有状态
			note.set_meta("_needs_height_recalc", true)  # 标记需要在 _spawn_note 里重新计算
	
	# ✅ P2: 清理动画状态（关键！）
	if note.has_meta("_last_tween"):
		var old_tween = note.get_meta("_last_tween")
		if old_tween and old_tween.is_valid():
			old_tween.kill()
		note.remove_meta("_last_tween")
	
	# ✅ P3: 清理子节点状态
	for child in note.get_children():
		child.visible = true
		child.modulate = Color.WHITE

func _init_note_pool() -> void:
	"""初始化音符对象池：预创建固定数量的节点并复用"""
	# Block 音符池
	for _i in _NOTE_POOL_BLOCK_SIZE:
		var note_node = nt_b.duplicate()
		note_node.visible = false
		canvas.add_child(note_node)
		_note_pool_block.append(note_node)
	
	# Slide 音符池
	for _i in _NOTE_POOL_SLIDE_SIZE:
		var note_node = nt_s.duplicate()
		note_node.visible = false
		canvas.add_child(note_node)
		_note_pool_slide.append(note_node)
	
	# Long 音符池
	for _i in _NOTE_POOL_LONG_SIZE:
		var note_node = nt_l.duplicate()
		note_node.visible = false
		canvas.add_child(note_node)
		_note_pool_long.append(note_node)

func _get_note_from_pool(tp: NoteType) -> Node:
	"""从池中获取一个音符节点，如果池空则创建新的"""
	var pool = _get_pool_by_type(tp)
	
	# 关键：清理池中已释放的节点（解决 queue_free 延迟导致的无效节点问题）
	while not pool.is_empty():
		var note = pool.pop_back()
		if is_instance_valid(note):
			# 从池取出后立即重置（修复尺寸、位置等问题）
			_reset_note_for_reuse(note, tp)
			return note
		# 否则继续弹出下一个（跳过已释放的节点）
	
	# 池空或所有节点都已释放：发出警告并创建新节点作为临时扩容
	GameLogger.instance.warning("Note pool overflow for type %d, creating new node" % tp, "FlowArea")
	var new_node = null
	match tp:
		NoteType.Block:
			new_node = nt_b.duplicate()
		NoteType.Slide:
			new_node = nt_s.duplicate()
		NoteType.Long:
			new_node = nt_l.duplicate()
		_:
			new_node = nt_b.duplicate()
	_reset_note_for_reuse(new_node, tp)
	canvas.add_child(new_node)
	return new_node

func _return_note_to_pool(note: Node, tp: NoteType) -> void:
	"""将音符节点返回到池中重复使用"""
	note.visible = false
	var pool = _get_pool_by_type(tp)
	if pool.size() < _get_pool_max_size(tp):
		# 仍有空间，加入池
		pool.append(note)
	else:
		# 池满时仍保留节点并加入池，避免隐藏孤儿节点和后续状态错乱
		note.position = Vector2.ZERO
		note.visible = false
		pool.append(note)

func _remove_note(note: Note) -> void:
	if note.rect:
		# 改为回池而不是 queue_free()
		_return_note_to_pool(note.rect, note.type)
		note.rect = null
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
				_handle_release(event.index, event_time_ms)
			elif event.index >= 0:
				# 诊断：收到释放事件但无对应按下记录（可能是极快轻触导致按下事件被丢弃）
				push_warning("[FlowArea] Orphan touch release: index=%d, no corresponding press found" % event.index)
	
	# 处理触摸拖动
	elif event is InputEventScreenDrag:
		touch_positions[event.index] = event.position
		_handle_touch_drag(event.index, event.position)
	# 桌面端鼠标点击/松开（复用触摸逻辑）
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_press(-1, event.position, event_time_ms)
		else:
			_handle_release(-1, event_time_ms)
	# 桌面端鼠标拖动（用于长条跟随）
	elif event is InputEventMouseMotion:
		if -1 in active_holds:
			_handle_touch_drag(-1, event.position)

	# 仅在拖动时检查 slide 可判定状态，避免点按误标记同轨道其他 slide 为可判定
	if event is InputEventScreenDrag and event.index in touch_positions:
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
				var released_lane = parent_node.key_map.find(event.keycode)
				_handle_release(event.keycode, _get_realtime_position_ms(), released_lane)
		elif event.keycode == KEY_ESCAPE and event.pressed:
			parent_node.show_or_hide_menu()

# 处理触摸按下
func _handle_press(touch_id: int, pos: Vector2, input_time_ms: float = -1.0) -> void:
	var judge_time_ms := input_time_ms
	if judge_time_ms < 0.0:
		judge_time_ms = _get_realtime_position_ms()

	# 去重逻辑：部分 Android 设备单次触摸会同时发送鼠标+触摸双事件
	# - 触摸事件间不互相去重（保留多指能力）
	# - 触摸事件仅在前一次是鼠标事件时去重（处理 Android 模拟鼠标）
	# - 鼠标事件始终去重（桌面端原生防重复）
	var should_dedup := false
	if touch_id == -1:
		# 鼠标事件：始终检查去重
		should_dedup = abs(judge_time_ms - _last_press_time_ms) <= _PRESS_DEDUP_MS and pos.distance_to(_last_press_pos) <= _PRESS_DEDUP_DISTANCE
	else:
		# 触摸事件：仅在前一次是鼠标事件时去重
		should_dedup = _last_press_was_mouse and abs(judge_time_ms - _last_press_time_ms) <= _PRESS_DEDUP_MS and pos.distance_to(_last_press_pos) <= _PRESS_DEDUP_DISTANCE
	_last_press_was_mouse = touch_id == -1
	_last_press_time_ms = judge_time_ms
	_last_press_pos = pos
	if should_dedup:
		return

	var candidate_notes: Array = active_notes
	if only_perfect_slides:
		# 仅判定完美滑块开启时，点击/按键选音符阶段直接忽略滑块
		candidate_notes = active_notes.filter(func(n):
			return n.type != NoteType.Slide
		)

	var note = note_judger.find_best_note(pos, candidate_notes, jl.position.y, note_judge_width, judge_mode)
	if note == null:
		return
	if parent_node.play_mode and note.game_sequence_ref:
		_trigger_midi_notes_from_sequence(note.game_sequence_ref)
	if note.type == NoteType.Slide:
		# 仅在关闭“仅判定完美滑块”时允许点击滑块，且按点块计分
		_judge_note(note, true, judge_time_ms, NoteType.Block)
	else:
		_judge_note(note, true, judge_time_ms)
	if note.type == NoteType.Long:
		_hold_long_note(touch_id, note)

# 处理触摸松开 释放长条音符
func _handle_release(touch_id: int, input_time_ms: float = -1.0, released_lane: int = -1) -> void:
	var judge_time_ms := input_time_ms if input_time_ms >= 0.0 else _get_realtime_position_ms()

	if check_slide_when_finger_up:
		_judge_slides_on_release(touch_id, released_lane, judge_time_ms)

	# 清理与该触点/按键绑定的滑块按住状态，避免后续拖动或同帧事件误判
	for note in active_notes:
		if note.type != NoteType.Slide:
			continue
		if released_lane >= 0:
			if note.lane == released_lane:
				note.can_judge = false
				note.held_by_touch_id = -1
		elif note.held_by_touch_id == touch_id:
			note.can_judge = false
			note.held_by_touch_id = -1

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
	# 兜底：长条进入按住态后不应再走未判定 Miss 分支
	note.is_judged = true
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
		if note == null or note.rect == null or not is_instance_valid(note.rect):
			continue
		var rect = note.rect as Control
		if rect == null:
			continue

		# 如果slide音符在触摸点范围内
		var note_x = rect.position.x + rect.size.x / 2
		var distance_to_touch = abs(pos.x - note_x)

		if note.can_judge and note.held_by_touch_id == touch_id and distance_to_touch > note_judge_width:
			note.can_judge = false
			note.held_by_touch_id = -1

		if distance_to_touch < note_judge_width and not note.can_judge:
			note.can_judge = true
			note.held_by_touch_id = touch_id
			# return

func _check_slide_stat(note: Note):
	if note.is_judged:
		return

	if note.lane in pressed_keys.values():
		if parent_node.play_mode and note.game_sequence_ref:
			_trigger_midi_notes_from_sequence(note.game_sequence_ref)
		if only_perfect_slides:
			_judge_note(note, false, note.start_time, -1, "Perfect")
		else:
			_judge_note(note)
		note.can_judge = false
		return

	if note.can_judge:
		if parent_node.play_mode and note.game_sequence_ref:
			_trigger_midi_notes_from_sequence(note.game_sequence_ref)
		if only_perfect_slides:
			_judge_note(note, false, note.start_time, -1, "Perfect")
		else:
			_judge_note(note)
		note.can_judge = false

func _judge_slides_on_release(touch_id: int, released_lane: int, judge_time_ms: float) -> void:
	var perfect_window_ms = float(judge_windows["perfect"])
	var pending_notes: Array[Note] = []

	for note in active_notes:
		if note == null or note.is_judged or note.is_held or note.type != NoteType.Slide:
			continue
		if note.rect == null or not is_instance_valid(note.rect):
			continue

		if released_lane >= 0:
			if note.lane != released_lane or not note.can_judge:
				continue
		elif note.held_by_touch_id != touch_id or not note.can_judge:
			continue

		if abs(judge_time_ms - note.start_time) <= perfect_window_ms:
			pending_notes.append(note)

	for note in pending_notes:
		if parent_node.play_mode and note.game_sequence_ref:
			_trigger_midi_notes_from_sequence(note.game_sequence_ref)
		_judge_note(note, false, judge_time_ms, -1, "Perfect")

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
		if only_perfect_slides and note.type == NoteType.Slide:
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
		if best_note.type == NoteType.Slide:
			# 键盘点击滑块按点块计分；与按住触发（滑块计分）路径互斥
			_judge_note(best_note, true, input_time_ms, NoteType.Block)
		else:
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
			var track_idx := int(evt.track_index)
			
			# 触发note_on
			if midi_player.has_method("trigger_note_on"):
				midi_player.call("trigger_note_on", evt.pitch, evt.velocity, evt.channel, track_idx)
			elif midi_player.has_method("note_on"):
				midi_player.note_on(evt.channel, evt.pitch, evt.velocity)

			# 非阻塞调度 note_off（避免循环内 await 导致后续音符串行延后）
			var delay_seconds = (game_seq.duration_ms / 1000.0) if game_seq.duration_ms > 0 else 0.1
			_schedule_note_off(midi_player, evt.pitch, evt.velocity, evt.channel, delay_seconds, track_idx)

func _schedule_note_off(midi_player: Object, pitch: int, velocity: int, channel: int, delay_seconds: float, track_index: int = 0) -> void:
	var timer = get_tree().create_timer(max(delay_seconds, 0.01))
	timer.timeout.connect(func():
		if not is_instance_valid(midi_player):
			return
		if midi_player.has_method("trigger_note_off"):
			midi_player.call("trigger_note_off", pitch, velocity, channel, track_index)
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

func _judge_note(judge_note: Note, trigger_vibration: bool = false, input_time_ms: float = -1.0,
		block_type_override: int = -1, result_override: String = ""):
	# 防止重复判定：如果该note已被判定过，直接返回
	if judge_note.is_judged:
		return

	var judge_time_ms := input_time_ms if input_time_ms >= 0.0 else _get_realtime_position_ms()
	var time_diff = judge_note.start_time - judge_time_ms  # 毫秒，优先使用事件时刻的实时播放位置
	var abs_diff = abs(time_diff)
	var result: String = result_override

	if result.is_empty():
		result = "Bad"
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
	# 默认将 NoteType 映射到 BlockType；点击滑块时可覆盖为 INSTANT
	var block_type: int = block_type_override if block_type_override >= 0 else judge_note.type

	# 标记该note已被判定，防止重复
	judge_note.is_judged = true
	var hit_pos := Vector2.ZERO
	if judge_note.rect:
		hit_pos = judge_note.rect.position + judge_note.rect.size / 2.0
	
	note_judged.emit(result, "%s%.1f ms" % ["+" if time_diff>=0 else "", time_diff],
		block_type, timing_sec, signed_offset_sec)
	if trigger_vibration:
		_trigger_touch_vibration()
	if judge_note.type != NoteType.Long:
		_remove_note(judge_note)

	# 特效
	var light_color = note_color_short if judge_note.type == NoteType.Block else (note_color_slide if judge_note.type == NoteType.Slide else note_color_long)
	get_parent().lane_area.light_lane(judge_note.lane, light_color)
	
	if judge_note.type != NoteType.Long and hit_pos != Vector2.ZERO:
		_generate_particle(result, hit_pos)

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
		if note.type == NoteType.Long:
			_update_long_note_fall(note, _synced_current_time)
		_update_note_visibility(note)
	
	# 自动按长条
	if auto_mode:
		for long in active_notes.filter(func(nt):
			if nt.type == NoteType.Long and not nt.is_held:
				var head = nt.rect.get_node("VBoxC/head")
				return abs(head.global_position.y + head.size.y/2 - jl.position.y) < 12
			return false):
			_auto_click(long)

	# 更新长条音符的按住进度和显示
	for touch_id in active_holds.keys():
		var note = active_holds[touch_id]
		if not note or not note.rect or not note.is_held:
			continue

		var long_end_time = note.start_time + max(0.0, note.duration)
		if _synced_current_time >= long_end_time:
			var head = note.rect.get_node("VBoxC/head") as Control
			var n_half = head.size.y * 0.5
			_generate_particle("Perfect", head.global_position + Vector2(float(note_visual_width) * 0.5, n_half))
			_remove_note(note)
			active_holds.erase(touch_id)
			continue

		# 加分及加combo
		if note.cooldown > 0.25: # 0.25是触发频率
			note.cooldown = 0
			long_holding.emit(note.long_instance_id)
		else:
			note.cooldown += delta
