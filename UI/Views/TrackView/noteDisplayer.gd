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

# 活动音符状态列表（替代 N 个 ColorRect 节点，由 _draw_node 批量绘制）
var active_notes: Array[NoteState] = []

# 按 (track, channel) 分组的音轨容器（替代扁平 current_notes）
# 每 bucket 自带 cursor，懒生成时按 bucket 独立推进
var buckets: Array[TrackNoteBucket] = []

# MIDI 最大 end_tick（所有 bucket 中最后一个音符的结束 tick）
# 用于检测 ct 异常：循环播放时 Sequencer.Position 可能继续增长而不跳回 0，
# 导致 ct 超过所有音符的 end_tick，active_notes 被清空。此时跳过移除操作等待循环恢复
var _max_end_tick: int = 0
# 上一帧的 ct，用于检测 ct 回退（循环跳回 0）时重置 cursor
var _last_ct: float = -1.0

# track view节点
var master_node: Node = null

# 是否是主显示器
var is_master: bool = false

var note_color: Color

## 音频延迟补偿（毫秒，正值=音频输出有延迟需延后视觉，负值=音频提前需提前视觉）
## 与 PlayView.FlowArea 保持一致：TrackView 存在人声/MIDI 同步播放场景，
## 视觉音符需与音频到达耳朵的时刻对齐，否则会出现"看到的音符"与"听到的声音"错位
## 来源：ConfigManager [Gameplay] audio_playback_delay，由 DelayAdjust 校准得出
var _audio_playback_delay_ms: float = 0.0

# 批量绘制节点（单 Node2D 替代 N 个 ColorRect，参考 LaneEffect.BeamNode 设计）
var _draw_node: NoteDrawNode = null

# 单个音符的最小渲染信息（仅绘制必需字段，与音频播放用的 MidiParser.Note 解耦）
# 使用 tick 作为时间单位，与 MIDI 原始数据一致，ct 也从 ms 转成 tick 保证同参考系
class NoteRenderInfo:
	extends RefCounted
	var pitch: int = 0        # 决定 y 坐标（lane_index）
	var start_tick: int = 0   # 判定 is_passed + 懒生成
	var end_tick: int = 0     # 判定离开视野 + 计算 x + 宽度 w
	# 无 track_index/channel/color/duration：这些都在 bucket 级

# 音轨级容器（持有该 (track, channel) 的元数据 + 音符列表）
# 过滤粒度从「每音符」提升到「每音轨」：master 模式下整 bucket 启用/禁用
class TrackNoteBucket:
	extends RefCounted
	var track_index: int = 0
	var channel: int = 0
	var hue: float = 0.0              # 颜色色相（由 track_index 查 colors_set 一次）
	var notes: Array[NoteRenderInfo] = []  # 按 start_tick 升序（_build_buckets 中排序）
	var cursor: int = 0               # 懒生成游标（指向下一个待生成的音符）
	var is_enabled: bool = true       # master 用：该音轨是否启用

# 音符运行时状态（替代 ColorRect + meta Dictionary）
# 使用 RefCounted 自动管理生命周期，无需 queue_free
class NoteState:
	extends RefCounted
	var pitch: int = 0
	var start_tick: int = 0
	var end_tick: int = 0
	var bucket: TrackNoteBucket = null  # 反向引用所在 bucket（_draw 查 hue）
	var is_passed: bool = false
	# 位置和尺寸字段（_process 写入，_draw 读取，同线程无竞争）
	var x: float = 0.0
	var y: float = 0.0
	var w: float = 0.0
	var h: float = 0.0

# 单 Node2D 批量绘制所有音符，消除 N 个 ColorRect 的节点/布局/transform 开销
# clip_children（CanvasItem 属性）对 Node2D 子节点同样生效，裁剪逻辑不变
class NoteDrawNode:
	extends Node2D
	# 与 NoteDisplayer.active_notes 共享同一数组引用（只做原地修改，不重新赋值）
	var notes: Array = []
	# 单色模式：子 displayer 的 note_color 已设置，所有音符同色，_draw 直接读 single_color
	var single_color: Color = Color.WHITE
	var use_single_color: bool = false

	func _draw() -> void:
		if use_single_color:
			# 子 displayer 单色模式：active_notes 里的音符全是已启用 bucket 的，无需再判 is_enabled
			for n in notes:
				draw_rect(Rect2(n.x, n.y, n.w, n.h), single_color)
		else:
			# master 多色模式：颜色由 bucket.hue 实时读
			for n in notes:
				draw_rect(Rect2(n.x, n.y, n.w, n.h), Color.from_hsv(n.bucket.hue, 1, 0.9, 0.8))

func _ready():

	if size.y > 250:
		lane_count = 24
	_on_flow_area_resized()

	flow_area.resized.connect(_on_flow_area_resized)

	# 创建批量绘制节点（替代 N 个 ColorRect 子节点）
	_draw_node = NoteDrawNode.new()
	_draw_node.name = "NoteDrawNode"
	_draw_node.notes = active_notes  # 共享数组引用，原地修改对 _draw 可见
	flow_area.add_child(_draw_node)

	# 初始化音频延迟补偿，并监听配置变更
	# 与 PlayView.FlowArea 保持一致，使 TrackView 的视觉音符与音频时序对齐
	_audio_playback_delay_ms = float(ConfigManager.instance.get_int("Gameplay", "audio_playback_delay", 0))
	if EvtBus and not EvtBus.config_changed.is_connected(_on_config_changed):
		EvtBus.config_changed.connect(_on_config_changed)


func _exit_tree() -> void:
	# NoteDisplayer 实例随 MidiTrack 销毁时断开信号，避免引用悬空
	if EvtBus and EvtBus.config_changed.is_connected(_on_config_changed):
		EvtBus.config_changed.disconnect(_on_config_changed)
	# 清空音符状态引用（_draw_node 随父节点 queue_free 自动释放）
	active_notes.clear()


## 配置变更回调：仅关注 audio_playback_delay，实时更新延迟补偿值
func _on_config_changed(key: String, section: String, value: Variant) -> void:
	if section == "Gameplay" and key == "audio_playback_delay":
		_audio_playback_delay_ms = float(value)


func _on_flow_area_resized():
	area_height = flow_area.get_rect().size.y
	area_width = flow_area.get_rect().size.x
	lane_height = area_height / lane_count

	if is_master:
		refresh_notes_lane(int(lane_count))

func update_color():
	if _draw_node == null:
		return
	# note_color 已设置（子 displayer）→ 单色模式；未设置（master）→ 多色模式（颜色由 bucket.hue 实时读）
	if note_color != Color(0, 0, 0, 0):
		_draw_node.use_single_color = true
		_draw_node.single_color = note_color
	else:
		_draw_node.use_single_color = false
	_draw_node.queue_redraw()

func _process(_delta):
	if master_node == null or buckets.is_empty():
		return

	# flow_area 不在屏幕内时跳过整个 _process（音符位置计算 + queue_redraw）
	# ScrollContainer 滚动使子节点滑出视口时，get_global_rect() 与视口无交集
	var viewport_rect = get_viewport_rect()
	var flow_rect = flow_area.get_global_rect()
	if not flow_rect.intersects(viewport_rect):
		return

	var midi_mgr = MidiPlaybackManager.instance
	if midi_mgr == null or not midi_mgr.is_playing:
		# 不主动 set_process(false)：由 TrackView._set_note_displayers_process 统一管理启停
		# 否则 MIDI 循环播放时 is_playing 短暂变化会导致 _process 永久停止，画面冻结
		return

	# 应用音频延迟补偿：将播放位置减去延迟后转换为 tick
	# 与 PlayView.FlowArea.set_current_time 逻辑一致（time_ms - _audio_playback_delay_ms）
	# 使视觉音符的通过时刻与音频到达耳朵的时刻对齐
	# ct 与音符的 start_tick/end_tick 在同一 tick 参考系，保证视觉与音频同步
	var delayed_ms: float = midi_mgr.get_position_ms() - _audio_playback_delay_ms
	var ct: float = midi_mgr._calculate_tick_from_position_with_bpm_timeline(delayed_ms, midi_mgr.midi_timebase)

	# ct 异常保护：循环播放时 Sequencer.Position 可能继续增长而不跳回 0，
	# 导致 ct 超过所有音符的 end_tick。此时不做移除操作，等待 TrackView 循环检测恢复
	# 同时清空 active_notes，防止旧音符残留累积拖慢渲染
	if _max_end_tick > 0 and ct > _max_end_tick + area_width / scale_factor:
		if not active_notes.is_empty():
			active_notes.clear()
		_last_ct = ct
		return

	# 检测 ct 回退（循环跳回 0 或 seek 回退）：重置所有 bucket cursor 和 active_notes
	# 防止 cursor 在末尾时 ct 回退到开头，懒生成无法推进
	# 同时清空 active_notes，避免上一轮的旧音符（end_tick 很大）残留累积拖慢渲染
	if _last_ct >= 0 and ct < _last_ct - area_width / scale_factor:
		for b in buckets:
			b.cursor = 0
		active_notes.clear()
	_last_ct = ct

	# 提前计算视野边界
	var view_right_bound = ct + area_width / scale_factor

	# 按 bucket 懒生成：每 bucket 独立游标，信任 bucket 内顺序
	# master 模式下整个 disabled bucket 跳过，不再 per-note 判定
	for b in buckets:
		if is_master and not b.is_enabled:
			continue
		while b.cursor < b.notes.size() and b.notes[b.cursor].start_tick < view_right_bound:
			_create_note(b.notes[b.cursor], b)
			b.cursor += 1

	# 移动和更新音符（原地修改 NoteState 字段，不触发布局）
	var to_remove: Array[NoteState] = []

	for n in active_notes:
		# 计算位置
		var x = area_width - (n.end_tick - ct) * scale_factor

		# 判断是否完全离开视野
		if n.end_tick < ct:  # 音符已经完全播放完毕
			to_remove.append(n)
			continue

		# 更新位置（仅写字段，_draw 读取时绘制）
		n.x = x

		# 标记已通过的音符
		# 使用 ct > start_tick 而不是 ct >= start_tick
		# 这样能避免 start_tick=0 的音符在播放开始时被错误计入
		# active_notes 里的音符已全部是 enabled bucket 的（master 模式下），无需再判 is_enabled
		if not n.is_passed and ct > n.start_tick:
			n.is_passed = true
			note_count_passed.text = str(int(note_count_passed.text) + 1)

	# 移除已完成音符（原地删除，保持 _draw_node.notes 引用有效）
	if not to_remove.is_empty():
		for n in to_remove:
			active_notes.erase(n)

	# 单帧一次重绘，批量提交所有音符的 draw_rect
	if _draw_node:
		_draw_node.queue_redraw()

func _create_note(info: NoteRenderInfo, bucket: TrackNoteBucket):
	var state := NoteState.new()
	# 反转lane_index，使高音在上（Y值小），低音在下（Y值大）
	var lane_index: int = lane_count - 1 - ((info.pitch - 21) % lane_count)
	state.pitch = info.pitch
	state.start_tick = info.start_tick
	state.end_tick = info.end_tick
	state.bucket = bucket
	state.is_passed = false
	state.w = (info.end_tick - info.start_tick) * scale_factor
	state.h = lane_height * 0.8
	state.y = (lane_height * lane_index) + (lane_height - state.h) / 2.0
	state.x = -state.w  # 初始在视野左侧外
	active_notes.append(state)
	# _draw_node.notes 与 active_notes 共享引用，append 后立即可见

## 初始化 displayer
## master: 传入所有 buckets，由 sync_from_midi_data 控制 bucket.is_enabled
## 子 displayer: 传入单个 bucket 的数组，bucket.is_enabled 恒 true
func init_displayer_with_buckets(mn: Node, track_buckets: Array[TrackNoteBucket]) -> void:
	# 清空活动音符状态（RefCounted 自动释放，无需 queue_free）
	active_notes.clear()
	master_node = mn
	buckets = track_buckets

	# 重置每个 bucket 的游标；子 displayer 永远启用
	_max_end_tick = 0
	for b in buckets:
		b.cursor = 0
		if not is_master:
			b.is_enabled = true
		# 计算 MIDI 最大 end_tick（用于检测 ct 异常）
		# 遍历所有音符取最大 end_tick，不能只取最后一个（排序按 start_tick，end_tick 最大值可能在中间）
		for n in b.notes:
			if n.end_tick > _max_end_tick:
				_max_end_tick = n.end_tick

	# 计算初始 passed/total（master 模式下只统计 enabled bucket）
	var passed_count := 0
	var total_count := 0
	var ct := 0.0
	if master_node != null:
		ct = float(master_node.current_tick)
	for b in buckets:
		if is_master and not b.is_enabled:
			continue
		total_count += b.notes.size()
		for n in b.notes:
			if n.start_tick < ct:
				passed_count += 1
			else:
				break  # bucket 内已排序，提前退出

	note_count_passed.text = str(passed_count)
	note_count_total.text = str(total_count)

	# 初始化后重绘一次
	if _draw_node:
		_draw_node.queue_redraw()

# 重置播放头位置 - 用于进度条跳转
func reset_playhead_position(target_ms: float) -> void:
	if buckets.is_empty() or master_node == null:
		return

	# 确保 _process 处于启用状态：防止之前因 is_playing 短暂 false 导致 _process 停止后
	# 拖动进度条时音符不更新（虽然 _process 已不再主动 set_process(false)，但防御性启用）
	set_process(true)

	# 获取MidiPlaybackManager以计算tick
	var midi_playback_mgr = MidiPlaybackManager.instance
	if midi_playback_mgr == null:
		return

	# 计算目标tick（根据BPM时间线）
	# 后端统一为 MeltySynth，直接使用其维护的 midi_timebase
	var target_tick = midi_playback_mgr._calculate_tick_from_position_with_bpm_timeline(
		target_ms, midi_playback_mgr.midi_timebase)

	# 清空所有活动的音符状态（原地清空，_draw_node.notes 引用保持有效）
	active_notes.clear()

	# 计算视野右边界对应的tick
	var view_right_bound = target_tick + area_width / scale_factor

	# 每 bucket 独立查找首个 end_tick >= target_tick 的音符，再生成视野内音符
	for b in buckets:
		if is_master and not b.is_enabled:
			b.cursor = b.notes.size()  # 跳过整个 bucket
			continue
		var i = 0
		while i < b.notes.size() and b.notes[i].end_tick < target_tick:
			i += 1
		# 从 i 开始生成视野内音符
		while i < b.notes.size() and b.notes[i].start_tick < view_right_bound:
			_create_note(b.notes[i], b)
			i += 1
		b.cursor = i

	# 重新计算已通过的音符数（master 仅统计 enabled bucket）
	var passed_count = 0
	for b in buckets:
		if is_master and not b.is_enabled:
			continue
		for n in b.notes:
			if n.start_tick < target_tick:
				passed_count += 1
			else:
				break  # bucket 内已排序，可以提前退出
	# 标记活动列表中 start_tick < target_tick 的音符为已通过（与 _process 逻辑一致）
	for n in active_notes:
		if n.start_tick < target_tick:
			n.is_passed = true
	note_count_passed.text = str(passed_count)

	# 重置后重绘
	if _draw_node:
		_draw_node.queue_redraw()

# 刷新音符位置
func refresh_notes_lane(lane_ctn: int):
	lane_count = lane_ctn

	for n in active_notes:
		# 反转lane_index，使高音在上（Y值小），低音在下（Y值大）
		var lane_index = lane_count - 1 - ((n.pitch - 21) % lane_count)
		n.h = lane_height * 0.8
		n.y = (lane_height * lane_index) + (lane_height - n.h) / 2.0

	if _draw_node:
		_draw_node.queue_redraw()

func toggle_track(toggled_on: bool, track_index: int):
	# bucket 级过滤：找到对应 track_index 的 bucket，切换其 is_enabled
	# 已生成的 active_notes 中的音符保留（不清空），避免 seek 回去时重新生成
	# 禁用 bucket 的新音符不会再被 _process 懒生成
	for b in buckets:
		if b.track_index == track_index:
			b.is_enabled = toggled_on

	if _draw_node:
		_draw_node.queue_redraw()

## 从MidiData同步启用的(track, channel)配置
## bucket 级一次性过滤：替代旧的每音符 is_track_channel_selected 查询
func sync_from_midi_data(midi_data: MidiData) -> void:
	if midi_data == null:
		return

	# bucket 级一次性过滤
	for b in buckets:
		b.is_enabled = midi_data.is_track_channel_selected(b.track_index, b.channel)

	# 重算 total/passed（master 才需要，子 displayer 永远全启用）
	if is_master:
		var total := 0
		var passed := 0
		var ct := 0.0
		if master_node != null:
			ct = float(master_node.current_tick)
		for b in buckets:
			if not b.is_enabled:
				continue
			total += b.notes.size()
			for n in b.notes:
				if n.start_tick < ct:
					passed += 1
				else:
					break
		note_count_total.text = str(total)
		note_count_passed.text = str(passed)

	if _draw_node:
		_draw_node.queue_redraw()
