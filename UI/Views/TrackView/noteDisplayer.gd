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

# 是否是主显示器
var is_master: bool = false
var enable_tracks: Array[int] = []

var note_color: Color

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
	

func _on_flow_area_resized():
	if size.y > 250:
		lane_count = 24

	area_height = flow_area.get_rect().size.y
	area_width = flow_area.get_rect().size.x
	lane_height = area_height / lane_count
	
func update_color():
	for i in active_notes:
		i.color = note_color

func _process(_delta):
	if master_node == null or current_notes.is_empty():
		return
	# 获取当前tick
	var ct = master_node.current_tick
	#print("Current Tick: %d" % ct)
	# 提前计算视野边界
	var view_right_bound = ct + area_width / scale_factor

	# 生成音符
	while current_idx < current_notes.size() and current_notes[current_idx].start_tick < view_right_bound:
		_create_note(current_notes[current_idx])
		current_idx += 1

	# 移动和更新音符
	var to_remove: Array[ColorRect] = []
	
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
			
		# 更新位置
		i.position = Vector2(x, i.position.y)
		
		# 标记已通过的音符
		# 使用 ct > start_tick 而不是 ct >= start_tick
		# 这样能避免 start_tick=0 的音符在播放开始时被错误计入
		if not i.get_meta("is_passed") and ct > start_tick:
			i.set_meta("is_passed", true)
			note_count_passed.text = str(int(note_count_passed.text) + 1)

	# 移除音符
	for i in to_remove:
		i.queue_free()
	active_notes =  active_notes.filter(func(element): return not (element in to_remove))

func _create_note(note: NoteEvent):
	var note_rect: ColorRect = ColorRect.new()
	var lane_index: int = note.pitch % lane_count
	var note_width = note.duration * scale_factor
	var note_height = lane_height * 0.8
	var start_y = (lane_height * lane_index) + (lane_height - note_height) / 2.0

	# 设置基本属性
	note_rect.size = Vector2(note_width, note_height)
	note_rect.position = Vector2(-note_width, start_y)
	note_rect.color = _get_color_by_pitch(note.pitch)
	if is_master and note.track_index not in enable_tracks:
		note_rect.self_modulate.a = 0

	# 设置自定义属性
	note_rect.set_meta("lane_index", lane_index)
	note_rect.set_meta("track_index", note.track_index)
	note_rect.set_meta("start_tick", note.start_tick)
	note_rect.set_meta("duration", note.duration)
	note_rect.set_meta("is_passed", false)

	# 添加到场景和活动列表
	flow_area.add_child(note_rect)
	active_notes.append(note_rect)

func init_displayer(mn: Node, notes: Array[NoteEvent]):

	# debug
	print("音符可视化初始化，音符总数：%d" % notes.size())

	for note in active_notes:
		note.queue_free()

	master_node = mn

	active_notes.clear()
	current_notes = notes
	current_idx = 0
	
	# 计算当前已播放的音符数（如果master_node存在）
	var passed_count = 0
	if master_node != null:
		var ct = master_node.current_tick
		# 计算所有已播放的音符（start_tick < ct的音符）
		for note in notes:
			if note.start_tick < ct:
				passed_count += 1
			else:
				# 由于notes已排序，可以提前break
				break
	
	note_count_passed.text = str(passed_count)
	note_count_total.text = str(notes.size())

	# 如果是主显示器，初始化所有轨道的启用状态
	if is_master:
		for i in notes:
			if i.track_index not in enable_tracks:
				enable_tracks.append(i.track_index)

# 重置播放头位置 - 用于进度条跳转
func reset_playhead_position(target_ms: float) -> void:
	# return
	if current_notes.is_empty() or master_node == null:
		return
	
	# 获取MidiPlaybackManager以计算tick
	var midi_playback_mgr = MidiPlaybackManager.instance
	if midi_playback_mgr == null or midi_playback_mgr.midi_player == null:
		return
	
	# 计算目标tick（根据BPM时间线或默认120 BPM）
	var target_tick = midi_playback_mgr._calculate_tick_from_position_with_bpm_timeline(
		target_ms, 
		midi_playback_mgr.midi_player.smf_data.timebase if midi_playback_mgr.midi_player.smf_data else 480
	)
	
	print("[NoteDisplayer] Reset to position: %.1f ms (tick: %.0f)" % [target_ms, target_tick])
	
	# 更新current_idx - 找到第一个start_tick >= target_tick的note
	var new_idx = 0
	for i in range(current_notes.size()):
		if current_notes[i].start_tick >= target_tick:
			new_idx = i
			break
		new_idx = i + 1  # 如果都小于target，则new_idx为notes.size()
	
	# 清空所有活动的note
	for note_rect in active_notes:
		note_rect.queue_free()
	active_notes.clear()
	
	# 重置索引和计数
	current_idx = new_idx
	
	# 重新计算已通过的音符数
	note_count_passed.text = str(new_idx - active_notes.size())
	
	print("[NoteDisplayer] Reset complete: current_idx=%d, passed=%s" % [current_idx, note_count_passed.text])

# 根据音高获取颜色
func _get_color_by_pitch(pitch: int) -> Color:
	if note_color:
		return note_color

	# 将MIDI音高（0-127）映射到色相（0-360度）
	var hue = float(pitch % 12) / 12.0  # 八度内音高循环
	return Color.from_hsv(hue, 0.7, 0.9, 0.8)

# 批量生成示例音符（测试用）
func _generate_test_notes():
	var notes: Array[NoteEvent] = []
	for i in range(40):
		notes.append(NoteEvent.new(5, 60, i * 200, 50, i, 0))

	init_displayer(self, notes)

func toggle_track(toggled_on: bool, track_index: int):
	if toggled_on:
		enable_tracks.append(track_index)
	else:
		enable_tracks.erase(track_index)

	for i in active_notes:
		if i.get_meta("track_index") == track_index:
			i.self_modulate.a = 1 if toggled_on else 0