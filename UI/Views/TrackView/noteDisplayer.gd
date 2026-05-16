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
var _midi_data_for_filter: Object = null  # 用于 channel 级别过滤

var note_color: Color

# 诊断计数（用于周期性输出日志）
#var _diagnostic_frame_count: int = 0
#var _last_logged_tick: float = 0.0

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
	
	if size.y > 250:
		lane_count = 24
	_on_flow_area_resized()	

	flow_area.resized.connect(_on_flow_area_resized)
	

func _on_flow_area_resized():
	area_height = flow_area.get_rect().size.y
	area_width = flow_area.get_rect().size.x
	lane_height = area_height / lane_count

	if is_master:
		refresh_notes_lane(int(lane_count))
	
func update_color():
	for i in active_notes:
		i.color = note_color

func _process(_delta):
	if master_node == null or current_notes.is_empty():
		return
	
	# 【修复】直接从MidiPlaybackManager获取tick，确保与实际播放位置同步
	var midi_mgr = MidiPlaybackManager.instance
	var ct: float = 0.0
	
	if midi_mgr != null and midi_mgr.is_playing:
		# 优先使用MidiPlaybackManager的position（已校准的tick值）
		ct = midi_mgr.position
	else:
		# 回退到master_node的current_tick
		ct = float(master_node.current_tick)
	
	# 【诊断日志】每60帧输出一次tick対比信息
	#_diagnostic_frame_count += 1
	#if _diagnostic_frame_count % 60 == 0:
	#	if midi_mgr != null:
	#		var master_tick = float(master_node.current_tick) if master_node else 0.0
	#		print("[NoteDisplayer] Sync check - MidiPlaybackManager.position: %.1f | master_node.current_tick: %.1f | delta: %.1f" % 
	#			[ct, master_tick, (ct - master_tick)])
	#	_last_logged_tick = ct
	
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
			if i.self_modulate.a > 0 or not is_master:
				note_count_passed.text = str(int(note_count_passed.text) + 1)

	# 移除音符
	for i in to_remove:
		i.queue_free()
	active_notes =  active_notes.filter(func(element): return not (element in to_remove))

func _create_note(note: NoteEvent):
	var note_rect: ColorRect = ColorRect.new()
	# 反转lane_index，使高音在上（Y值小），低音在下（Y值大）
	var lane_index: int = lane_count - 1 - ((note.pitch - 21) % lane_count)
	var note_width = note.duration * scale_factor
	var note_height = lane_height * 0.8
	var start_y = (lane_height * lane_index) + (lane_height - note_height) / 2.0

	# 设置基本属性
	note_rect.size = Vector2(note_width, note_height)
	note_rect.position = Vector2(-note_width, start_y)
	note_rect.color = _get_color_by_track_idx(note.track_index)
	if is_master:
		var note_enabled = true
		if _midi_data_for_filter:
			note_enabled = _midi_data_for_filter.is_track_channel_selected(note.track_index, note.channel)
		elif note.track_index not in enable_tracks:
			note_enabled = false
		if not note_enabled:
			note_rect.self_modulate.a = 0

	# 设置自定义属性
	note_rect.set_meta("pitch", note.pitch)
	note_rect.set_meta("track_index", note.track_index)
	note_rect.set_meta("channel", note.channel)
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

	# 如果是主显示器，初始化所有轨道通道的启用状态
	if is_master:
		# Clear stale filter to prevent cross-MIDI contamination
		_midi_data_for_filter = null
		enable_tracks.clear()
		for i in notes:
			if i.track_index not in enable_tracks:
				enable_tracks.append(i.track_index)

# 重置播放头位置 - 用于进度条跳转
func reset_playhead_position(target_ms: float) -> void:
	if current_notes.is_empty() or master_node == null:
		return
	
	# 获取MidiPlaybackManager以计算tick
	var midi_playback_mgr = MidiPlaybackManager.instance
	if midi_playback_mgr == null:
		return
	
	# 计算目标tick（根据BPM时间线或默认120 BPM）
	var timebase = 480
	
	# 【修复】安全地检查 smf_data 属性（MidiPlayer 插件有此属性，MeltySynth 后端没有）
	if midi_playback_mgr.midi_player != null:
		var player = midi_playback_mgr.midi_player
		# 检查是否有 smf_data 属性（仅 MidiPlayer 插件有）
		if "smf_data" in player:
			if player.smf_data:
				timebase = player.smf_data.timebase
		else:
			# MeltySynth 或其他后端：使用默认 timebase
			timebase = midi_playback_mgr.midi_timebase
	else:
		timebase = midi_playback_mgr.midi_timebase

	var target_tick = midi_playback_mgr._calculate_tick_from_position_with_bpm_timeline(
		target_ms,
		timebase
	)
	
	print("[NoteDisplayer] Reset to position: %.1f ms (tick: %.0f)" % [target_ms, target_tick])
	
	# 清空所有活动的note
	for note_rect in active_notes:
		note_rect.queue_free()
	active_notes.clear()
	
	# 计算视野右边界对应的tick
	var view_right_bound = target_tick + area_width / scale_factor
	
	# 找到第一个 end_tick >= target_tick 的音符（即尚未完全飞出左边界的音符）
	# 这些音符可能正在播放中，仍然部分或全部可见
	var first_visible_idx = current_notes.size()
	for i in range(current_notes.size()):
		var end_tick = current_notes[i].start_tick + current_notes[i].duration
		if end_tick >= target_tick:
			first_visible_idx = i
			break
	
	# 从 first_visible_idx 开始，立即生成所有在视野范围内的音符
	var new_idx = first_visible_idx
	for i in range(first_visible_idx, current_notes.size()):
		if current_notes[i].start_tick >= view_right_bound:
			new_idx = i
			break
		# 该音符在视野内，立即生成
		_create_note(current_notes[i])
		new_idx = i + 1
	
	# 设置 current_idx 为下一个待生成的音符索引
	current_idx = new_idx
	
	# 重新计算已通过的音符数（start_tick < target_tick 且不在当前活动列表中的）
	var passed_count = 0
	for note in current_notes:
		if note.start_tick < target_tick:
			passed_count += 1
		else:
			break  # notes 已按时间排序，可以提前退出
	# 减去那些 start_tick < target_tick 但仍在活动列表中显示的音符
	for note_rect in active_notes:
		var st = note_rect.get_meta("start_tick")
		if st < target_tick:
			# 这个音符虽然 start_tick 已过，但 end_tick 还在视野内，不算passed
			# 标记为已通过（与_process中的逻辑一致）
			if not note_rect.get_meta("is_passed"):
				note_rect.set_meta("is_passed", true)
	note_count_passed.text = str(passed_count)
	
	print("[NoteDisplayer] Reset complete: current_idx=%d, visible=%d, passed=%d" % 
		[current_idx, active_notes.size(), passed_count])

# 根据音高获取颜色
func _get_color_by_track_idx(track_idx: int) -> Color:
	if note_color:
		return note_color

	var hue = MidiTrack.colors_set[track_idx % MidiTrack.colors_set.size()].h
	return Color.from_hsv(hue, 1, 0.9, 0.8)

# 批量生成示例音符（测试用）
func _generate_test_notes():
	var notes: Array[NoteEvent] = []
	for i in range(40):
		notes.append(NoteEvent.new(5, 60, i * 200, 50, i, 0))

	init_displayer(self, notes)

# 刷新音符位置
func refresh_notes_lane(lane_ctn: int):
	lane_count = lane_ctn

	for i in active_notes:
		# 反转lane_index，使高音在上（Y值小），低音在下（Y值大）
		var lane_index = lane_count - 1 - ((i.get_meta("pitch") - 21) % lane_count)
		var start_y = (lane_height * lane_index) + (lane_height - i.size.y) / 2.0
		i.size.y = lane_height * 0.8
		i.position = Vector2(i.position.x, start_y)

func toggle_track(toggled_on: bool, track_index: int):
	if toggled_on:
		enable_tracks.append(track_index)
	else:
		enable_tracks.erase(track_index)

	for i in active_notes:
		if i.get_meta("track_index") == track_index:
			i.self_modulate.a = 1 if toggled_on else 0

## 从MidiData同步启用的(track, channel)配置
func sync_from_midi_data(midi_data: MidiData) -> void:
	if midi_data == null:
		return
	
	# 保存引用，供 _create_note 使用 channel 级别过滤
	_midi_data_for_filter = midi_data
	
	# 重建enable_tracks列表（保留向后兼容的track级别过滤）
	enable_tracks.clear()
	for track_idx in midi_data.selected_track_configs.keys():
		enable_tracks.append(track_idx)
	
	# 更新所有活动的音符的显示状态
	for note_rect in active_notes:
		var track_idx = note_rect.get_meta("track_index")
		var channel = note_rect.get_meta("channel")
		
		# 检查该(track, channel)是否启用
		var is_enabled = midi_data.is_track_channel_selected(track_idx, channel)
		note_rect.self_modulate.a = 1.0 if is_enabled else 0.0

	# Recalculate enabled note total for master displayer
	if is_master:
		var enabled_total = 0
		for note in current_notes:
			if midi_data.is_track_channel_selected(note.track_index, note.channel):
				enabled_total += 1
		note_count_total.text = str(enabled_total)
