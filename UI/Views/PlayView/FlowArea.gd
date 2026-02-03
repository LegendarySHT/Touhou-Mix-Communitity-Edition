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

var note_width: int = 120
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

# 音符生成提前量（毫秒） - 确保音符在到达判定线前有足够时间显示
var note_generation_lead_time: float = 2000.0
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

enum NoteType {
	Block = 0,
	Slide,
	Long
}

class Note:
	var rect: Node
	var start_time: float    	# 生成note时的时间
	var arrival_time: float  	# 音符前端到达判定线的时间
	var duration: float
	var type: NoteType
	var lane: int            	# 轨道索引
	var tween: Tween
	var is_active: bool = true
		
	func _init(tp: NoteType, st: float, at: float, dur: float, l: int):
		start_time = st
		arrival_time = at
		duration = dur
		type = tp
		lane = l
	
	func set_rect(rt: Node):
		if rect :
			rect.queue_free()
		rect = rt
		is_active = true

func _ready() -> void:
	# 初始化轨道宽度
	lane_width = size.x / lane_count
	
	# 设置判定线位置
	jl.position.y -= judge_line_offset_y

func _create_note(tp: NoteType, sz: Vector2, pos: Vector2) -> Node:
	var note_rect: Node = null
	match tp:
		NoteType.Block:
			note_rect = nt_b.instantiate()
		NoteType.Slide:
			note_rect = nt_s.instantiate()
		NoteType.Long:
			note_rect = nt_l.instantiate()
	
	note_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_rect.size = sz
	note_rect.position = pos
	canvas.add_child(note_rect)

	return note_rect

func _spawn_note(note_index: int) -> void:
	if note_index >= notes_list.size():
		return
	
	var nt = notes_list[note_index]
	var lane = nt.lane

	# 计算音符位置
	var start_x = lane * lane_width + 5  # 加5像素边距
	var start_y = -50  # 从屏幕顶部开始
	
	var rect = _create_note(nt.type, Vector2(note_width, 40), Vector2(start_x, start_y))
	nt.set_rect(rect)

	# 计算下落时间（从生成到到达判定线的时间）
	# 注意：这里的fall_time应该是arrival_time - parent_node.current_time
	# 但由于音符是按顺序生成的，我们需要确保时间正确
	var current_time = parent_node.current_time if parent_node else 0
	var fall_time = (nt.arrival_time - current_time) / 1000.0  # 转换为秒

	var fall_distance = jl.position.y - rect.size.y/2  # 从顶部到判定线的距离
	
	# 使用Tween创建下落动画
	var tween = create_tween()
	tween.tween_property(rect, "position:y", fall_distance, fall_time).set_trans(trans_before_line).set_ease(ease_before_line)
	
	# 判定线后动画（如果需要）
	var window_y = get_viewport().get_visible_rect().size.y
	var after_line_time = max(nt.duration / 1000.0, 0.5)  # 至少0.5秒的后续动画
	tween.tween_property(rect, "position:y", window_y, after_line_time).set_trans(trans_after_line).set_ease(ease_after_line)

	# 创建Note对象并添加到活跃列表
	active_notes.append(nt)
	nt.tween = tween

	# 动画结束后回收音符
	tween.finished.connect(func():
		if nt.is_active:
			remove_note(nt)
			# 只有在音符播放完毕但未被击打时才判定为Miss
			# 注意：这里需要根据游戏逻辑调整
			if nt.is_active:
				note_judged.emit("Miss", "")
	)

func remove_note(note: Note) -> void:
	if not note.is_active:
		return

	note.is_active = false
	active_notes.erase(note)
	if note.rect:
		note.rect.queue_free()

func clear_flow_area():
	for i in active_notes:
		remove_note(i)
	note_idx = 0

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# 获取点击的轨道
		var mouse_x = event.position.x
		@warning_ignore("integer_division")
		var click_lane_l: int = clampi(int((mouse_x-judge_area_width/2) / lane_width), 0, lane_count - 1)
		@warning_ignore("integer_division")
		var click_lane_r: int = clampi(int((mouse_x+judge_area_width/2) / lane_width), 0, lane_count - 1)

		judge_note_at_lane(click_lane_l,click_lane_r)
	if ui.current_state == ui.UIState.PLAY_VIEW and event is InputEventKey:
		print("[PlayView FA]input accepted")
		accept_event()

#判定模式 0 最佳时间 1 最佳距离 2 最下音符
var judge_mode = 1
func judge_note_at_lane(lane_l: int, lane_r: int) -> void:
	# 查找该轨道上最接近判定线的音符
	var best_note = null
	var best_diff = INF
	
	for note in active_notes:
		if note.lane >= lane_l and note.lane <= lane_r and note.is_active:
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
		# 根据时间差进行判定
		_judge_note(best_note)
		
		remove_note(best_note)

var particle = load("res://UI/Views/PlayView/particleSquare.tscn")
var _is_scale_set: bool =false
func _generate_particle(type: String, pos: Vector2):
	var ptc = particle.instantiate()
	if not _is_scale_set:
		ptc.set_particle_scale(0.5)
		_is_scale_set = true
	canvas.add_child(ptc)
	ptc.position = pos
	ptc.play(type)

func _judge_note(judge_note: Note):
	var current_time = parent_node.current_time if parent_node else 0
	var time_diff = current_time - judge_note.arrival_time
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

var is_pause: bool = false
func _process(_delta: float) -> void:
	if not parent_node:
		return

	# 暂停处理
	if parent_node.is_pause and not is_pause:
		for i in active_notes:
			if i.tween:
				i.tween.pause()
		is_pause = true
	elif not parent_node.is_pause and is_pause:
		for i in active_notes:
			if i.tween:
				i.tween.play()
		is_pause = false

	# 生成音符
	var current_time = parent_node.current_time if parent_node else 0
	var max_preview_time = current_time + note_generation_lead_time
	
	while note_idx < notes_list.size() and notes_list[note_idx].start_time < max_preview_time:
		_spawn_note(note_idx)
		note_idx += 1
