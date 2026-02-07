extends Panel

class_name FlowArea

# 判定线
@onready var jl: HSeparator = $JudgeLine
@onready var ui: UIStateManager = UIStateManager.instance
@onready var canvas: CanvasLayer = $SVP

########## 配置参数 #############
var lane_count: int = 12
var judge_line_offset_y: int = 250
var judge_area_width: int = 150
#判定模式 0 最佳时间 1 最佳距离 2 最下音符
var judge_mode = 1

var note_judge_width: int = 120
var note_visual_width: int = 200

# 音符下落动画
var trans_before_line = Tween.TRANS_LINEAR
var ease_before_line = Tween.EASE_IN_OUT
var trans_after_line = Tween.TRANS_LINEAR
var ease_after_line = Tween.EASE_OUT

# 判定参数
var judge_windows: Dictionary = {
	"perfect": 25,    # 完美判定窗口
	"great": 50,      # 良好判定窗口
	"good": 100       # 一般判定窗口
}

# 音符生成提前量（毫秒） - 确保音符在到达判定线前有足够时间显示 - 调下落速度也是用它（
var note_generation_lead_time: float = 900.0

# 音符特效缩放
var particle_scale: float = 0.8
###################################

signal note_judged(result: String, offset: String)

# 音符相关
var lane_width: float = 0
var active_notes: Array = []  # 存储活跃的音符

@onready var nt_b = load("res://UI/Views/PlayView/note_block.tscn")
@onready var nt_s = load("res://UI/Views/PlayView/note_slide.tscn")
@onready var nt_l = load("res://UI/Views/PlayView/note_long.tscn")

var parent_node: Node = null

# 修改为从PlayView传入的音符列表
var notes_list: Array[Note] = []  # 移除测试用的音符
var note_idx: int = 0

# 多点触控支持
var touch_positions: Dictionary = {}  # 存储每个触摸点的位置
var active_holds: Dictionary = {}     # 存储正在按住长条音符的触摸点ID和对应的音符
var slide_notes_near_line: Dictionary = {}  # 存储接近判定线的slide音符

enum NoteType {
	Block = 0,
	Slide,
	Long
}

class Note:
	var rect: Node
	var start_time: float    	# 生成note时的时间
	# var arrival_time: float  	# 音符前端到达判定线的时间
	var duration: float
	var type: NoteType
	var lane: int            	# 轨道索引
	var tween: Tween
	var is_held: bool = false    # 是否被按住（用于长条音符）
	var panel_size_y: float = 0.0    # VBoxC的偏移量（用于长条音符）
	var held_by_touch_id: int = -1  # 按住该音符的触摸点ID
	
	func _init(tp: NoteType, st: float, dur: float, l: int):
		start_time = st
		duration = dur
		type = tp
		lane = l
	
	func set_rect(rt: Node):
		if rect :
			rect.queue_free()
		rect = rt

func _ready() -> void:
	# 启用多点触控
	get_viewport().gui_embed_subwindows = false

func _create_note(tp: NoteType, width: float, x: float) -> Node:
	var note_rect: Node = null
	match tp:
		NoteType.Block:
			note_rect = nt_b.instantiate()
		NoteType.Slide:
			note_rect = nt_s.instantiate()
		NoteType.Long:
			note_rect = nt_l.instantiate()
			note_rect.get_node("VBoxC").size.x = width
	
	note_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_rect.size.x = width
	note_rect.position = Vector2(x + (lane_width - width)/2, -note_rect.size.y)
	canvas.add_child(note_rect)

	return note_rect

func _spawn_note(note_index: int) -> void:
	if note_index >= notes_list.size():
		return
	
	var nt = notes_list[note_index]
	var lane = nt.lane

	# 计算音符位置
	var start_x = lane * lane_width  # 加5像素边距
	
	var rect = _create_note(nt.type, note_visual_width, start_x)
	nt.set_rect(rect)

	# print("ct: %f st: %f" % [parent_node.current_time, nt.start_time])
	var speed = jl.position.y / note_generation_lead_time

	# 计算下落位置
	var note_c = rect.size.y/2
	if nt.type == NoteType.Long:
		var box = nt.rect.get_node("VBoxC")
		box.get_node("body").custom_minimum_size.y = speed * nt.duration

		await get_tree().process_frame
		nt.rect.size.y = box.size.y
		nt.rect.position.y = - box.size.y
		
		note_c = box.get_node("tail").size.y/2
	
	var fall_finl_pos = jl.position.y - note_c   # 从顶部到判定线的距离
	
	var long_note_offset = ((nt.rect.size.y + note_c) / speed) if nt.type == NoteType.Long else 0
	var fall_time = (note_generation_lead_time + long_note_offset) / 1000.0

	# 使用Tween创建下落动画
	var tween = create_tween()
	tween.tween_property(rect, "position:y", fall_finl_pos, fall_time).set_trans(trans_before_line).set_ease(ease_before_line)
	
	# 判定线后动画
	var window_y = get_viewport().get_visible_rect().size.y
	var after_line_time = (judge_line_offset_y / speed) / 1000.0
	tween.tween_property(rect, "position:y", window_y, after_line_time).set_trans(trans_after_line).set_ease(ease_after_line)

	# 创建Note对象并添加到活跃列表
	active_notes.append(nt)
	nt.tween = tween

	# 动画结束后回收音符
	tween.finished.connect(func():
		if nt.rect:
			# 如果是长条音符且被按住，不要判定为Miss
			if nt.type == NoteType.Long and nt.is_held:
				# 提前释放长条音符
				_release_hold_note(nt.held_by_touch_id)
			else:
				_remove_note(nt)
				# 只有在音符播放完毕但未被击打时才判定为Miss
				note_judged.emit("Miss", "")
	)

# 因为在for循环遍历时erase会导致漏元素，所以推迟元素的移除
func _delay_free(list, item_to_free):
	list.erase(item_to_free)

func _remove_note(note: Note) -> void:
	if note.rect:
		note.rect.visible = false
		note.rect.queue_free()
		call_deferred("_delay_free", active_notes, note)
	
	# 如果是被按住的长条音符，清理触摸点
	if note.is_held and note.held_by_touch_id in active_holds:
		call_deferred("_delay_free", active_holds, note.held_by_touch_id)

func init_flow_area(notes: Array[Note]):
	clear_flow_area()
	notes_list = notes
	note_idx = 0

	# 初始化轨道宽度
	lane_width = size.x / lane_count
	
	# 设置判定线位置
	jl.position.y = get_viewport().get_visible_rect().size.y - judge_line_offset_y

func clear_flow_area():
	if not notes_list:
		return
	
	print("clear notes %d" % active_notes.size())
	notes_list.clear()
	for i in active_notes:
		_remove_note(i)
	note_idx = 0
	active_holds.clear()
	slide_notes_near_line.clear()

func _gui_input(event: InputEvent) -> void:
	# 处理触摸事件（支持多点触控）
	if event is InputEventScreenTouch:
		if event.pressed:
			# 手指按下
			touch_positions[event.index] = event.position
			_handle_touch_press(event.index, event.position)
		else:
			# 手指松开
			if event.index in touch_positions:
				touch_positions.erase(event.index)
			_handle_touch_release(event.index)
	
	# 处理触摸拖动
	elif event is InputEventScreenDrag:
		touch_positions[event.index] = event.position
		_handle_touch_drag(event.index, event.position)
	
	if ui.current_state == ui.UIState.PLAY_VIEW and event is InputEventKey:
		print("[PlayView FA]input accepted")
		accept_event()

# 处理触摸按下
func _handle_touch_press(touch_id: int, pos: Vector2) -> void:
	# 先检查是否按在长条音符上
	var long_note = _get_long_note_at_position(pos)
	if long_note and not long_note.is_held:
		# 按住长条音符
		_hold_long_note(touch_id, long_note)
		return
	
	# 检查是否按在slide音符上
	var slide_note = _get_slide_note_at_position(pos)
	if slide_note:
		# 点击slide音符
		_judge_note_at_position(slide_note)
		return
	
	# 否则进行普通判定
	var mouse_x = pos.x
	@warning_ignore("integer_division")
	var click_lane_l: int = clampi(int((mouse_x-judge_area_width/2) / lane_width), 0, lane_count - 1)
	@warning_ignore("integer_division")
	var click_lane_r: int = clampi(int((mouse_x+judge_area_width/2) / lane_width), 0, lane_count - 1)
	judge_note_at_lane(click_lane_l, click_lane_r)

# 处理触摸松开
func _handle_touch_release(touch_id: int) -> void:
	if touch_id in active_holds:
		_release_hold_note(touch_id)

# 处理触摸拖动
func _handle_touch_drag(touch_id: int, pos: Vector2) -> void:
	if touch_id in active_holds:
		var note = active_holds[touch_id]
		_update_hold_note_position(touch_id, note, pos)

# 获取指定位置的长条音符
func _get_long_note_at_position(pos: Vector2) -> Note:
	for note in active_notes:
		if note.type == NoteType.Long and not note.is_held:
			var rect = note.rect as Control
			if rect:
				var note_rect = Rect2(rect.global_position, rect.size)
				if note_rect.has_point(pos):
					return note
	return null

# 获取指定位置的slide音符
func _get_slide_note_at_position(pos: Vector2) -> Note:
	for note in active_notes:
		if note.type == NoteType.Slide:
			var rect = note.rect as Control
			if rect:
				var note_rect = Rect2(rect.global_position, rect.size)
				if note_rect.has_point(pos):
					return note
	return null

# 按住长条音符
func _hold_long_note(touch_id: int, note: Note) -> void:
	note.is_held = true
	note.held_by_touch_id = touch_id
	active_holds[touch_id] = note
	
	# 将音符移动到手指位置（下边界与判定线对齐）
	var rect = note.rect as Control
	if rect:
		# 初始化VBoxC偏移
		note.panel_size_y = 0.0
		_update_long_note_display(note)
	
	# 立即判定为Perfect（开始长按）
	var current_time = parent_node.current_time if parent_node else 0
	var time_diff = current_time - note.start_time
	note_judged.emit("Perfect", "%s%.1f ms" % ["+" if time_diff>=0 else "", time_diff])

# 更新长条音符显示
func _update_long_note_display(note: Note) -> void:
	if note.type != NoteType.Long or not note.rect:
		return
	
	var vbox = note.rect.get_node("VBoxC") as VBoxContainer
	if vbox:
		# 根据进度设置VBoxC的偏移
		note.rect.size.y = note.panel_size_y

# 更新按住的长条音符位置
func _update_hold_note_position(touch_id: int, note: Note, pos: Vector2) -> void:
	if not note.is_held or note.held_by_touch_id != touch_id:
		return
	
	var rect = note.rect as Control
	if rect:
		# 只更新x位置，y位置保持与判定线对齐
		var target_y = jl.position.y - rect.size.y
		rect.position = Vector2(pos.x - rect.size.x / 2, target_y)
		
		# 限制在屏幕范围内
		rect.position.x = clamp(rect.position.x, 0, size.x - rect.size.x)

# 释放长条音符
func _release_hold_note(touch_id: int) -> void:
	if touch_id not in active_holds:
		return
	
	var note = active_holds[touch_id]
	note.is_held = false
	
	# 如果VBoxC没有完全移动完毕，提前判定
	if note.panel_size_y < note.rect.size.y * 0.8:
		# 判定为Good（提前释放）
		note_judged.emit("Good", "提前释放")
	
	# 移除音符
	_remove_note(note)
	active_holds.erase(touch_id)

# 检查slide音符是否在手指范围内
func _check_slide_notes_in_touch_range(touch_id: int, pos: Vector2) -> void:
	if touch_id not in touch_positions:
		return
	
	for note in active_notes:
		if note.type == NoteType.Slide:
			var rect = note.rect as Control
			if rect:
				var note_y = rect.position.y + rect.size.y / 2
				var distance_to_line = abs(jl.position.y - note_y)
				
				# 如果slide音符接近判定线且在触摸点范围内
				if distance_to_line < judge_area_width:
					var note_x = rect.position.x + rect.size.x / 2
					var distance_to_touch = abs(pos.x - note_x)
					
					if distance_to_touch < judge_area_width:
						# 自动判定slide音符
						_judge_note_at_position(note)
						return

# 在指定位置判定音符
func _judge_note_at_position(note: Note) -> void:
	var time_diff = parent_node.current_time - note.start_time
	
	var result: String = "Bad"
	if abs(time_diff) <= judge_windows["perfect"]:
		result = "Perfect"
	elif abs(time_diff) <= judge_windows["great"]:
		result = "Great"
	elif abs(time_diff) <= judge_windows["good"]:
		result = "Good"
	
	note_judged.emit(result, "%s%.1f ms" % ["+" if time_diff>=0 else "", time_diff])
	_remove_note(note)

func judge_note_at_lane(lane_l: int, lane_r: int) -> void:
	# 查找该轨道上最接近判定线的音符
	var best_note = null
	var best_diff = INF
	
	for note in active_notes:
		if note.lane >= lane_l and note.lane <= lane_r and not note.is_held:
			match judge_mode:
				0:
					var time_diff = abs(parent_node.current_time - note.arrival_time)
					
					if time_diff < best_diff:
						best_diff = time_diff
						best_note = note
				1:
					var note_y = note.rect.position.y
					var diff_y = abs(jl.position.y - note_y)
					if diff_y < best_diff:
						best_diff = diff_y
						best_note = note
				2:
					if note.arrival_time > best_diff:
						best_diff = note.arrival_time
						best_note = note

	
	if best_note:
		get_parent().lane_area.light_lane(best_note.lane, Color.BLUE)
		
		# 根据时间差进行判定
		_judge_note(best_note)
		
		_remove_note(best_note)

var particle = load("res://UI/Views/PlayView/particleSquare.tscn")
func _generate_particle(type: String, pos: Vector2):
	var ptc = particle.instantiate()
	
	set_particle_scale(particle_scale)
	
	canvas.add_child(ptc)
	ptc.position = pos
	ptc.play(type)

# 修改特效大小
func set_particle_scale(scl: float):
	var ptc = particle.instantiate()
	ptc.set_particle_scale(scl)
	ptc.queue_free()

func _judge_note(judge_note: Note):
	var current_time = parent_node.current_time if parent_node else 0
	var time_diff = current_time - judge_note.start_time
	var result: String = "Bad"

	if abs(time_diff) <= judge_windows["perfect"]:
		result = "Perfect"
	elif abs(time_diff) <= judge_windows["great"]:
		result = "Great"
	elif abs(time_diff) <= judge_windows["good"]:
		result = "Good"

	# 发射判定结果
	note_judged.emit(result, "%s%.1f ms" % ["+" if time_diff>=0 else "", time_diff])

	# 播放粒子
	_generate_particle(result, judge_note.rect.position + judge_note.rect.size/2)

var _is_pause: bool = false
func _process(_delta: float) -> void:
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
	var current_time = parent_node.current_time if parent_node else 0
	var max_preview_time = current_time + note_generation_lead_time
	
	while note_idx < notes_list.size() and notes_list[note_idx].start_time < max_preview_time:
		_spawn_note(note_idx)
		note_idx += 1
	
	# 更新长条音符的按住进度和显示
	for touch_id in active_holds:
		var note = active_holds[touch_id]
		if note.is_held:
			# 更新进度
			var vbox = note.rect.get_node("VBoxC")
			note.panel_size_y = jl.position.y - vbox.global_position.y

			# 限制最大偏移
			if note.rect.position.y >= jl.position.y - 50:
				# 长条音符完成，判定为Perfect
				note_judged.emit("Perfect", "完成")
				_remove_note(note)
				active_holds.erase(touch_id)
			else:
				# 更新显示
				_update_long_note_display(note)
	
	# 检查接近判定线的slide音符是否在手指范围内
	for touch_id in touch_positions:
		_check_slide_notes_in_touch_range(touch_id, touch_positions[touch_id])
