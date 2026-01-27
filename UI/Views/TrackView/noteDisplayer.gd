extends HBoxContainer

class_name NoteDisplayer

@onready var flow_area: Panel = $noteFlowArea/canvas
@onready var note_count_passed: Label = $noteTotal/VBoxC/passedNote
@onready var note_count_total: Label = $noteTotal/VBoxC/totalNote

var flow_area_height: float = 160
var flow_area_width: float = 0
var flow_area_lane_count: int = 12

# 每个车道的高度
var lane_height: float = 0

# 存储所有生成的音符，用于管理和清理
var active_notes: Array = []

# 基础移动速度（像素/秒），可根据BPM计算
var base_scroll_speed: float = 200.0

func _ready():
	if size.y > 250:
		flow_area_lane_count = 24
	flow_area_height = flow_area.get_parent().size.y
	flow_area_width = flow_area.get_parent().size.x
	lane_height = flow_area_height / flow_area_lane_count

	# init_display(20)
	# generate_test_notes()

# 生成一个新音符
# 参数说明：
# note_duration: 音符持续时间（秒）
# lane_index: 轨道索引（0到flow_area_lane_count-1）
# speed_factor: 速度系数（1.0为正常速度）
# pitch: 音高（MIDI音符编号，0-127，用于颜色映射）
func create_note(note_duration: float, lane_index: int, speed_factor: float = 1.0, pitch: int = 60):
	# 1. 参数验证和边界处理
	var clamped_lane = clampi(lane_index, 0, flow_area_lane_count - 1)
	
	# 2. 创建ColorRect节点
	var note_rect = ColorRect.new()
	note_rect.name = "Note_%d_%d" % [lane_index, Time.get_ticks_msec()]
	
	# 3. 设置音符初始属性
	# 宽度：根据持续时间计算（时间×速度）
	var note_width = note_duration * base_scroll_speed * speed_factor
	# 高度：略小于车道高度，留出间隔
	var note_height = lane_height * 0.8
	
	note_rect.size = Vector2(note_width, note_height)
	
	# 4. 设置初始位置
	var start_y = (lane_height * clamped_lane) + (lane_height - note_height) / 2.0
	
	note_rect.position = Vector2(-note_width, start_y)
	
	# 5. 设置颜色（根据音高）
	note_rect.color = _get_color_by_pitch(pitch)
	
	# 6. 为音符添加自定义属性（用于后续移动和控制）
	note_rect.set_meta("lane_index", clamped_lane)
	note_rect.set_meta("scroll_speed", base_scroll_speed * speed_factor)
	note_rect.set_meta("duration", note_duration)
	note_rect.set_meta("pitch", pitch)
	note_rect.set_meta("is_active", true)
	note_rect.set_meta("is_passed", false)
	
	# 8. 添加到场景和活动列表
	flow_area.add_child(note_rect)
	active_notes.append(note_rect)
	
	# 9. 更新总音符计数
	return note_rect

# 根据音高获取颜色
func _get_color_by_pitch(pitch: int) -> Color:
	# 将MIDI音高（0-127）映射到色相（0-360度）
	var hue = float(pitch % 12) / 12.0  # 八度内音高循环
	return Color.from_hsv(hue, 0.7, 0.9, 0.8)
	
# 设置音符交互效果
func setup_note_interaction(note_rect: ColorRect):
	# 启用鼠标检测
	note_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# 添加悬停效果信号
	note_rect.mouse_entered.connect(_on_note_mouse_entered.bind(note_rect))
	note_rect.mouse_exited.connect(_on_note_mouse_exited.bind(note_rect))

# 音符鼠标悬停效果
func _on_note_mouse_entered(note_rect: ColorRect):
	# 悬停时高亮显示
	var original_color = note_rect.color
	note_rect.color = Color(original_color.r, original_color.g, original_color.b, 1.0)
	# 可以添加其他效果，如稍微放大
	note_rect.scale = Vector2(1.05, 1.05)

func _on_note_mouse_exited(note_rect: ColorRect):
	# 恢复原始状态
	var original_color = note_rect.color
	note_rect.color = Color(original_color.r, original_color.g, original_color.b, 0.8)
	note_rect.scale = Vector2(1.0, 1.0)

# 在_process中更新音符位置
func _process(delta):
	# 临时存储需要移除的音符
	var notes_to_remove = []
	var flow_rect = flow_area.get_rect()

	for i in range(active_notes.size() - 1, -1, -1):
		var note = active_notes[i]
		
		if note and note.has_meta("is_active") and note.get_meta("is_active"):
			# 获取音符的移动速度
			var speed = note.get_meta("scroll_speed")
			
			note.position.x += speed * delta
			
			# 如果音符完全移出屏幕，标记为待移除
			if note.position.x > flow_rect.position.x:	
				if not flow_rect.encloses(note.get_rect()) and not note.get_meta("is_passed"):
						note.set_meta("is_passed", true)
						note_count_passed.text = str(int(note_count_passed.text) + 1)
				if not flow_rect.intersects(note.get_rect()):
					notes_to_remove.append(note)
				
	# 清理移出屏幕的音符
	for note in notes_to_remove:
		if note in active_notes:
			active_notes.erase(note)
			note.queue_free()

# 初始化显示并设置总音符数量
func init_display(total_notes: int = 0):
	for note in active_notes:
		note.queue_free()
	active_notes.clear()
	note_count_passed.text = "0"
	note_count_total.text = str(total_notes)

# 批量生成示例音符（测试用）
func generate_test_notes():
	# 生成一些测试音符
	for i in range(20):
		# 随机参数
		var lane = randi() % flow_area_lane_count
		var duration = randf_range(0.5, 2.0)
		var speed = 1 #randf_range(0.8, 1.2)
		var pitch = 48 + (lane * 2)  # 根据轨道决定基础音高
		
		# 稍作延迟，使音符分批出现
		await get_tree().create_timer(i * 0.1).timeout
		create_note(duration, lane, speed, pitch)
