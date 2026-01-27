extends HBoxContainer

class_name NoteDisplayer

@onready var flow_area: Panel = $noteFlowArea/canvas
@onready var note_count_passed: Label = $noteTotal/VBoxC/passedNote
@onready var note_count_total: Label = $noteTotal/VBoxC/totalNote

var area_height: float = 160
var area_width: float = 0
var lane_count: int = 12

# tick转像素时的缩放因子
var scale_factor: float = 0.5

# 每个车道的高度
var lane_height: float = 0

# 存储所有生成的音符，用于管理和清理
var active_notes: Array[ColorRect] = []
var current_notes: Array[NoteEvent] = []
var current_idx: int = 0

# track view节点
var master_node: Node = null

class NoteEvent:
	var pitch: int			  # MIDI音符号 (0-127)
	var velocity: int		   # 速度/力度 (1-127)
	var start_tick: int			# 开始时间 (tick)
	var duration: int	  		# 持续时间 (tick)
	var track_index: int		# 所在轨道索引
	var channel: int			# MIDI通道号 (0-15)

	func _init(p: int, v: int, start: int, dur: int, track: int, ch: int) -> void:
		pitch = p
		velocity = v
		start_tick = start
		duration = dur
		track_index = track
		channel = ch

func _ready():
	
	_on_flow_area_resized()	

	flow_area.resized.connect(_on_flow_area_resized)
	# _generate_test_notes()

func _on_flow_area_resized():
	if size.y > 250:
		lane_count = 24

	area_height = flow_area.get_rect().size.y
	area_width = flow_area.get_rect().size.x
	lane_height = area_height / lane_count
	


func _process(_delta):
	if master_node == null or not current_notes:
		return
	# 获取当前tick
	var ct = master_node.current_tick

	# 提前计算视野边界
	var view_right_bound = ct + area_width / scale_factor

	# 生成音符
	while current_idx < current_notes.size() and current_notes[current_idx].start_tick < view_right_bound:
		_create_note(current_notes[current_idx])
		current_idx += 1

	# 移动和更新音符
	var to_remove: Array[ColorRect] = []
	
	var need_redirect = false
	for i in active_notes:
		var start_tick = i.get_meta("start_tick")
		var duration = i.get_meta("duration")
		var end_tick = start_tick + duration
		
		# 计算位置
		var x = area_width - (end_tick - ct) * scale_factor
		
		# 判断是否完全离开视野
		if end_tick < ct:  # 音符已经完全播放完毕
			to_remove.append(i)
			continue
			
		if start_tick > view_right_bound:  # 音符还没进入视野
			to_remove.append(i)
			need_redirect = true	
			continue
			
		# 更新位置
		i.position = Vector2(x, i.position.y)
		
		# 标记已通过的音符
		if not i.get_meta("is_passed") and ct >= start_tick:
			i.set_meta("is_passed", true)
			note_count_passed.text = str(int(note_count_passed.text) + 1)

	# 移除音符
	for i in to_remove:
		i.queue_free()
		active_notes.erase(i)

	# 如果回退进度，需要重新定位并生成音符
	if need_redirect:
		_redirect_index(ct , view_right_bound)

func _redirect_index(ct, view_right_bound):
	for i in current_notes:
		if i.start_tick > view_right_bound:
			current_idx = current_notes.find(i)
			print("current_idx: %d ct: %d nst: %d" % [current_idx, ct, i.start_tick])
			break

	# 重新生成正在场上的音符
	var recreate_ctn = 0
	for i in range(0, current_idx):
		if current_notes[i].start_tick < view_right_bound:
			_create_note(current_notes[i])
			recreate_ctn += 1
	note_count_passed.text = str(current_idx - recreate_ctn)

func _create_note(note: NoteEvent):
	var note_rect: ColorRect = ColorRect.new()
	var lane_index: int = note.track_index % lane_count
	var note_width = note.duration * scale_factor
	var note_height = lane_height * 0.8
	var start_y = (lane_height * lane_index) + (lane_height - note_height) / 2.0

	# 设置基本属性
	note_rect.size = Vector2(note_width, note_height)
	note_rect.position = Vector2(-note_width, start_y)
	note_rect.color = _get_color_by_pitch(note.pitch)

	# 设置自定义属性
	note_rect.set_meta("lane_index", lane_index)
	note_rect.set_meta("start_tick", note.start_tick)
	note_rect.set_meta("duration", note.duration)
	note_rect.set_meta("is_passed", false)

	# 添加到场景和活动列表
	flow_area.add_child(note_rect)
	active_notes.append(note_rect)

func init_displayer(mn: Node, notes: Array[NoteEvent]):
	for note in active_notes:
		note.queue_free()

	master_node = mn

	active_notes.clear()
	note_count_passed.text = "0"
	note_count_total.text = str(notes.size())

	current_notes = notes
	current_idx = 0

# 根据音高获取颜色
func _get_color_by_pitch(pitch: int) -> Color:
	# 将MIDI音高（0-127）映射到色相（0-360度）
	var hue = float(pitch % 12) / 12.0  # 八度内音高循环
	return Color.from_hsv(hue, 0.7, 0.9, 0.8)

# 批量生成示例音符（测试用）
func _generate_test_notes():
	var notes: Array[NoteEvent] = []
	for i in range(40):
		notes.append(NoteEvent.new(5, 60, i * 200, 50, i, 0))

	init_displayer(self, notes)
