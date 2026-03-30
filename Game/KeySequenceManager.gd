## 键序列管理器
## 负责将MIDI Note分类为gameSequences和backgroundSequences
## 以及生成游戏键位的映射
extends Node

class_name KeySequenceManager

## 块类型枚举
enum BlockType {
	INSTANT = 0,  # 瞬间块（duration <= instant_block_threshold）
	SHORT = 1,    # 短块（duration <= short_block_threshold）
	LONG = 2      # 长块（duration > short_block_threshold，需按住）
}

## 单例实例
static var instance: KeySequenceManager

## 游戏序列（玩家操作的键）
class GameSequence:
	var note_index: int         # 原始Note在all_notes中的索引
	var key_id: int             # 生成的键ID
	var pitch: int              # MIDI音符号（主要pitch）
	var start_time_ms: float    # 开始时间
	var duration_ms: float      # 持续时间
	var screen_x: float         # 屏幕X位置（键盘映射）
	var octave: int             # 八度
	var velocity: int           # 力度
	var block_type: int = BlockType.INSTANT  # 块类型（INSTANT/SHORT/LONG）
	var pitch_list: Array[int] = []  # 同lane合并的所有pitch列表（便于同时发出多个音）
	var connected_prev: bool = false  # 是否与前一块连接
	var original_notes: Array[MidiParser.Note] = []  # 保留该块包含的原始Note列表
	var flow_note_ref: Object = null  # 新增：指向对应的FlowArea.Note（演奏模式使用）
	
	func _init(idx: int, key: int, p: int, start: float, dur: float, x: float, oct: int, vel: int) -> void:
		note_index = idx
		key_id = key
		pitch = p
		start_time_ms = start
		duration_ms = dur
		screen_x = x
		octave = oct
		velocity = vel
		pitch_list = [p]  # 初始化pitch列表
		original_notes = []  # 初始化Note列表

## 背景序列（背景伴奏）
class BackgroundSequence:
	var track_index: int        # 所在轨道
	var notes: Array            # 包含的所有Note（MidiParser.NoteEvent）
	
	func _init(track: int) -> void:
		track_index = track
		notes = []

## 块信息（生成后的块对象）
class BlockInfo:
	var notes: Array[MidiParser.Note] = []  # 合并后该块包含的所有原始Note对象
	var batch: int = -1          # 批次编号（用于与Unity一致的连块语义）
	var lane: int = 0           # 轨道编号（由pitch计算）
	var x: float = 0.0          # 屏幕X位置
	var start_time_ms: float = 0.0  # 块的起始时间
	var end_time_ms: float = 0.0    # 块的结束时间（多个Note时取最大）
	var duration_ms: float = 0.0    # 块的显示持续时间
	var type: int = BlockType.INSTANT  # 判定后的块类型
	var touch_index: int = -1   # 分配的虚拟触点ID (-1表示未分配)
	var prev_block: BlockInfo = null  # 指向前一个块（用于连块判定）
	var pitch_list: Array[int] = []  # 合并块的所有pitch值
	var connected_prev: bool = false  # 是否与前一块连接
	
	func _init() -> void:
		notes = []
		pitch_list = []
		connected_prev = false

## 虚拟触点信息（表示虚拟手指状态）
class VirtualTouch:
	var index: int = -1         # 虚拟触点ID
	var is_free: bool = true        # 是否空闲
	var last_press_x: float = 0.0   # 最后按下的屏幕X位置
	var last_press_time_ms: float = -INF  # 最后按下的时间
	var holding_block: BlockInfo = null  # 正在按住的LONG块
	var last_press_block: BlockInfo = null  # 最后按下的块对象
	
	func _init(idx: int) -> void:
		index = idx
		is_free = true
		last_press_x = 0.0
		last_press_time_ms = -INF
		holding_block = null
		last_press_block = null

## 当前MIDI数据
var current_midi_data: MidiData

## 所有音符列表
var all_notes: Array = []

## MIDI时间基准和BPM时间线（用于tick到毫秒的转换）
var midi_timebase: int = 480  # 默认MIDI时间基准
var bpm_timeline: Array = []  # BPM时间线数据

## 生成的游戏键列表
var game_sequences: Array[GameSequence] = []

## 背景伴奏序列
var background_sequences: Array[BackgroundSequence] = []

## 生成后的手动控制notes（演奏模式可触发）
var last_manual_control_notes: Array = []
## 生成后的自动播放notes（背景伴奏）
var last_auto_play_notes: Array = []

## 键ID计数器
var next_key_id: int = 0

## 屏幕宽度（用于键位映射）
var screen_width: float = 1920.0

## 每个键的宽度
var key_width: float = 40.0

## 最小音符间距（毫秒，防止键位重叠）
var min_note_spacing_ms: float = 10.0

## ========== 键生成配置参数 ==========
var lane_count: int = 12  # 轨道数量
var block_coalesce_seconds: float = 0.1  # 批次合并时间窗口（秒）
var instant_block_threshold: float = 0.1  # INSTANT块时长阈值（秒）
var short_block_threshold: float = 0.5  # SHORT块时长阈值（秒）
var min_tap_interval: float = 0.2  # 最小敲击间隔（秒）
var cooldown_seconds: float = 0.2  # 触点冷却时间（秒）
var max_touch_move_velocity: float = 400.0  # 最大触点移动速度（像素/秒）
var max_touch_count: int = 2  # 最大同时活跃键数
var generate_instant_connect: bool = true  # 是否生成INSTANT连块
var generate_short_connect: bool = true  # 是否生成SHORT连块
var max_instant_connect_seconds: float = 0.5  # INSTANT连块最大间隔（秒）

## 信号：序列分类完成
signal sequences_classified(game_seq_count: int, bg_seq_count: int)

## 信号：键位生成完成
signal keys_generated(key_count: int)

## 信号：键位优化完成
signal keys_optimized(key_count: int)

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	
	add_to_group("singleton")
	# 从ConfigManager加载键生成参数
	_load_config_parameters()
	
	# 监听配置变更信号（新增）
	if EventBus.instance:
		EventBus.instance.config_changed.connect(_on_config_changed)

## 设置MIDI时间参数（用于tick到毫秒的转换）
func set_midi_time_parameters(timebase: int, bpm_timeline_data: Array = []) -> void:
	midi_timebase = timebase if timebase > 0 else 480
	bpm_timeline = bpm_timeline_data.duplicate()
	GameLogger.instance.info("MIDI time parameters set: timebase=%d, bpm_timeline_size=%d" % [midi_timebase, bpm_timeline.size()], "KeySequenceManager")

## 将MIDI tick转换为毫秒
func _tick_to_ms(tick: float) -> float:
	# 使用BPM时间线计算（如果可用）
	if bpm_timeline.size() > 0:
		return _calculate_position_with_bpm_timeline(tick)
	
	# 后备：使用120 BPM（默认）
	return (tick / float(midi_timebase)) * (60000.0 / 120.0)

## 使用BPM时间线计算位置
func _calculate_position_with_bpm_timeline(tick: float) -> float:
	if bpm_timeline.is_empty():
		return (tick / float(midi_timebase)) * (60000.0 / 120.0)

	var cumulative_time_ms: float = 0.0

	# 与MidiPlaybackManager一致：按BPM段累计到当前tick
	for i in range(bpm_timeline.size()):
		var entry = bpm_timeline[i]
		var entry_tick: float = float(entry.get("tick", 0.0))

		var next_tempo_tick: float
		if i + 1 < bpm_timeline.size():
			next_tempo_tick = float(bpm_timeline[i + 1].get("tick", entry_tick))
		else:
			next_tempo_tick = tick + 1000000.0

		if tick < next_tempo_tick:
			var bpm = float(entry.get("bpm", 120.0))
			var tick_delta = tick - entry_tick
			var ms_per_tick = (60000.0 / bpm) / float(midi_timebase)
			return cumulative_time_ms + tick_delta * ms_per_tick
		else:
			if i + 1 < bpm_timeline.size():
				var bpm = float(entry.get("bpm", 120.0))
				var tick_delta = float(bpm_timeline[i + 1].get("tick", entry_tick)) - entry_tick
				var ms_per_tick = (60000.0 / bpm) / float(midi_timebase)
				cumulative_time_ms += tick_delta * ms_per_tick

	return cumulative_time_ms

## 将tick时长转换为毫秒时长（考虑BPM变化）
func _tick_duration_to_ms(start_tick: float, duration_tick: float) -> float:
	if duration_tick <= 0.0:
		return 0.0
	var start_ms = _tick_to_ms(start_tick)
	var end_ms = _tick_to_ms(start_tick + duration_tick)
	return max(0.0, end_ms - start_ms)

## 设置屏幕尺寸（用于键位映射计算）
func set_screen_size(width: float) -> void:
	screen_width = width

## 从ConfigManager加载所有键生成配置参数
func _load_config_parameters() -> void:
	var config_manager = ConfigManager.instance
	
	# 从Lane段读取lane_count
	lane_count = config_manager.get_int("Lane", "lane_count", 12)
	
	# 从Generator段读取生成相关参数
	var gen_cfg = "Generator"
	instant_block_threshold = config_manager.get_float(gen_cfg, "instant_block_max_time", 0.1)
	short_block_threshold = config_manager.get_float(gen_cfg, "short_block_max_time", 0.5)
	max_touch_count = config_manager.get_int(gen_cfg, "max_simultaneous_blocks", 2)
	min_tap_interval = config_manager.get_float(gen_cfg, "min_tap_interval", 0.2)
	cooldown_seconds = config_manager.get_float(gen_cfg, "min_touch_cooldown_time", 0.2)
	max_touch_move_velocity = config_manager.get_float(gen_cfg, "max_touch_move_speed", 400.0)
	block_coalesce_seconds = config_manager.get_float(gen_cfg, "max_block_coalesce_time", 0.1)
	
	# 从Appearance段读取连块参数
	var app_cfg = "Appearance"
	generate_short_connect = config_manager.get_bool(app_cfg, "generate_short_connect", true)
	generate_instant_connect = config_manager.get_bool(app_cfg, "generate_instant_connect", true)
	max_instant_connect_seconds = config_manager.get_float(app_cfg, "instant_connect_max_time", 0.5)
	key_width = config_manager.get_float(app_cfg, "block_size", key_width)
	
	# 键盘模式特殊处理：禁用触摸移动速度限制
	var keyboard_mode_enabled = config_manager.get_int("Lane", "keyboard_mode", 0) == 1
	if keyboard_mode_enabled:
		max_touch_move_velocity = 999999.0
		GameLogger.instance.info(
			"Keyboard mode enabled: max_touch_move_velocity set to unlimited (999999.0)",
			"KeySequenceManager"
		)
	
	GameLogger.instance.info(
		"KeyGeneration config loaded: block_coalesce=%.2fs, instant=%.2fs, short=%.2fs, maxTouch=%d, max_touch_velocity=%.1f" % 
		[block_coalesce_seconds, instant_block_threshold, short_block_threshold, max_touch_count, max_touch_move_velocity],
		"KeySequenceManager"
	)
func classify_sequences(midi_data: MidiData, all_midi_notes: Array) -> bool:
	if midi_data == null or all_midi_notes.is_empty():
		return false
	
	current_midi_data = midi_data
	all_notes = all_midi_notes
	
	# 清空之前的分类
	game_sequences.clear()
	background_sequences.clear()
	next_key_id = 0
	
	# 根据选中的轨道创建背景序列
	for track_idx in range(midi_data.track_count):
		var bg_seq = BackgroundSequence.new(track_idx)
		background_sequences.append(bg_seq)
	
	# 将音符分配到对应的背景序列
	for note_idx in range(all_notes.size()):
		var note = all_notes[note_idx] as MidiParser.NoteEvent
		if note.track_index < background_sequences.size():
			background_sequences[note.track_index].notes.append(note)
	
	# 发出分类完成信号
	sequences_classified.emit(game_sequences.size(), background_sequences.size())
	
	return true

## 生成游戏使用的键
## 实现完整的批次合并、去重、虚拟触点匹配、块类型判定、连块生成算法
## 注意：传入的game_notes应该已经被筛选为只包含启用的音轨的音符
## PlayView会根据TrackView中的selected_track_configs筛选出启用的音轨，然后传入这里
func generate_keys(game_notes: Array) -> bool:
	print("Generating keys from %d game notes..." % game_notes.size())
	if game_notes.is_empty():
		game_sequences.clear()
		keys_generated.emit(0)
		return true
	
	game_sequences.clear()
	background_sequences.clear()
	next_key_id = 0
	
	# 从MidiPlaybackManager获取时间参数
	var midi_mgr = MidiPlaybackManager.instance
	if midi_mgr != null:
		set_midi_time_parameters(midi_mgr.midi_timebase, midi_mgr.bpm_timeline)
	
	# Step 1: 转换Note对象为统一格式（确保start_time_ms和duration_ms为毫秒）
	var converted_notes = _convert_notes_to_internal_format(game_notes)
	
	# Step 2: 按时间排序Note
	var sorted_notes = converted_notes.duplicate()
	sorted_notes.sort_custom(func(a, b):
		if a["start_time_ms"] == b["start_time_ms"]:
			return a.get("channel", 0) < b.get("channel", 0)
		return a["start_time_ms"] < b["start_time_ms"]
	)
	
	# Step 3: 执行批次合并（Step A）
	var batches := _batch_notes_by_coalesce(sorted_notes)
	GameLogger.instance.info("Batch merge: created %d batches from %d notes" % [batches.size(), sorted_notes.size()], "KeySequenceManager")
	
	# Step 4: 为每个批次执行去重（Step B）
	var all_blocks: Array[BlockInfo] = []
	var bg_notes: Array = []
	for batch_idx in range(batches.size()):
		var deduped_blocks = _dedup_batch(batches[batch_idx], bg_notes, batch_idx)
		all_blocks.append_array(deduped_blocks)
	
	GameLogger.instance.info("Dedup: generated %d blocks, %d background notes" % [all_blocks.size(), bg_notes.size()], "KeySequenceManager")
	
	# Step 5: 虚拟触点匹配和块类型判定（Step C + Step D）
	_assign_touches_and_judge_types(all_blocks)
	
	# Step 6: 连块生成（Step E）
	_generate_connects(all_blocks)
	
	# Step 7: 转换为GameSequence集合
	_convert_blocks_to_game_sequences(all_blocks)
	
	# Step 8: 添加背景序列（与Unity一致：输出单一背景序列）
	bg_notes.sort_custom(func(a, b):
		var a_start = _get_note_start_time_ms(a)
		var b_start = _get_note_start_time_ms(b)
		if a_start == b_start:
			return _get_note_pitch(a) < _get_note_pitch(b)
		return a_start < b_start
	)
	var bg_seq = BackgroundSequence.new(0)
	bg_seq.notes = bg_notes
	background_sequences.append(bg_seq)
	
	# 在generate_keys完成后立即进行分类统计
	_finalize_notes_classification()
	
	keys_generated.emit(game_sequences.size())
	return true

## 将Note对象转换为内部格式（确保使用毫秒单位）
func _convert_notes_to_internal_format(game_notes: Array) -> Array:
	var converted: Array = []
	
	for note in game_notes:
		var note_dict: Dictionary = {}
		
		# 处理Note对象（包含event: NoteEvent）
		if note is MidiParser.Note:
			var evt = note.event
			note_dict["pitch"] = evt.pitch
			note_dict["velocity"] = evt.velocity
			note_dict["track_index"] = evt.track_index
			note_dict["channel"] = evt.channel
			note_dict["start_time_ms"] = _tick_to_ms(evt.start_time)
			note_dict["duration_ms"] = _tick_duration_to_ms(evt.start_time, evt.duration)
			note_dict["original_note"] = note
		else:
			# 如果已经是字典或其他格式，尝试直接使用
			note_dict = note if note is Dictionary else {}
		
		if not note_dict.is_empty():
			converted.append(note_dict)
	
	return converted

## Step A: 批次合并 - 按blockCoalesceSeconds分组
func _batch_notes_by_coalesce(sorted_notes: Array) -> Array:
	var batches: Array = []
	if sorted_notes.is_empty():
		return batches
	
	var current_batch: Array = []
	var current_batch_start_time: float = -1.0
	
	for note in sorted_notes:
		var note_time = note.start_time_ms
		
		# 初始化第一个批次
		if current_batch_start_time < 0:
			current_batch_start_time = note_time
			current_batch.append(note)
		# 如果Note在当前批次窗口内，添加到当前批次
		elif note_time <= current_batch_start_time + (block_coalesce_seconds * 1000.0):
			current_batch.append(note)
		# 否则触发批次并开始新批次
		else:
			if not current_batch.is_empty():
				batches.append(current_batch)
			current_batch = [note]
			current_batch_start_time = note_time
	
	# 添加最后一个批次
	if not current_batch.is_empty():
		batches.append(current_batch)
	
	return batches

## Step B: 去重与冲突消除 - 同lane保留高音符，低音移入背景（Unity兼容版本）
func _dedup_batch(batch: Array, bg_notes: Array, batch_idx: int) -> Array[BlockInfo]:
	var blocks: Array[BlockInfo] = []
	var lane_to_note: Dictionary = {}  # lane -> note_dict
	
	# 第1步：按lane去重（同lane保留最高音符）
	for note in batch:
		var pitch = note.get("pitch", 0)
		var lane = pitch % lane_count
		
		if lane_to_note.has(lane):
			var existing_note = lane_to_note[lane]
			var existing_pitch = existing_note.get("pitch", 0)
			# 比较音高，保留更高的
			if pitch > existing_pitch:
				# 将旧的加入背景
				_append_note_to_background(existing_note, bg_notes)
				lane_to_note[lane] = note
			else:
				# 将当前的加入背景
				_append_note_to_background(note, bg_notes)
		else:
			lane_to_note[lane] = note
	
	# 第2步：为保留下来的Note创建BlockInfo
	for lane in lane_to_note.keys():
		var note = lane_to_note[lane]
		var block = BlockInfo.new()
		block.batch = batch_idx
		# 添加原始Note对象（BlockInfo._init()已初始化notes为[]）
		if note.has("original_note"):
			block.notes.append(note["original_note"])
		block.lane = lane
		block.start_time_ms = note.get("start_time_ms", 0.0)
		block.end_time_ms = block.start_time_ms + note.get("duration_ms", 0.0)
		block.duration_ms = note.get("duration_ms", 0.0)
		# 将pitch添加到pitch_list（使用append而不是直接赋值）
		block.pitch_list.append(note.get("pitch", 0))
		block.x = _calculate_lane_position(lane)
		blocks.append(block)
	
	# 第3步：按音高排序并移除超过maxTouchCount的块（与Unity版本一致）
	if blocks.size() > max_touch_count:
		blocks.sort_custom(func(a, b): return a.pitch_list[0] > b.pitch_list[0])  # 降序排序
		while blocks.size() > max_touch_count:
			var removed_block = blocks.pop_back()
			# 将移除的块的Note加入背景
			for removed_note in removed_block.notes:
				_append_note_to_background(removed_note, bg_notes)
	
	return blocks

## 将各种中间格式的note统一追加到背景列表
## 优先保留 MidiParser.Note（便于后续精确分类）；其次使用 NoteEvent；最后兜底字典
func _append_note_to_background(note_data: Variant, bg_notes: Array) -> void:
	if note_data == null:
		return

	if note_data is MidiParser.Note:
		bg_notes.append(note_data)
		return

	if note_data is MidiParser.NoteEvent:
		bg_notes.append(note_data)
		return

	if note_data is Dictionary:
		if note_data.has("original_note"):
			var original_note = note_data["original_note"]
			if original_note is MidiParser.Note or original_note is MidiParser.NoteEvent:
				bg_notes.append(original_note)
				return
		bg_notes.append(note_data)
		return

	bg_notes.append(note_data)

## 提取note所属轨道索引（兼容 Note / NoteEvent / Dictionary）
func _get_note_track_index(note_data: Variant) -> int:
	if note_data == null:
		return 0

	if note_data is MidiParser.Note:
		if note_data.event:
			return note_data.event.track_index
		return 0

	if note_data is MidiParser.NoteEvent:
		return note_data.track_index

	if note_data is Dictionary:
		if note_data.has("track_index"):
			return int(note_data.get("track_index", 0))
		if note_data.has("original_note") and note_data["original_note"] is MidiParser.Note:
			var original_note = note_data["original_note"]
			if original_note.event:
				return original_note.event.track_index

	return 0

## 提取note起始时间（毫秒，兼容 Note / NoteEvent / Dictionary）
func _get_note_start_time_ms(note_data: Variant) -> float:
	if note_data == null:
		return 0.0

	if note_data is MidiParser.Note:
		if note_data.event:
			return _tick_to_ms(note_data.event.start_time)
		return 0.0

	if note_data is MidiParser.NoteEvent:
		return _tick_to_ms(note_data.start_time)

	if note_data is Dictionary:
		if note_data.has("start_time_ms"):
			return float(note_data.get("start_time_ms", 0.0))
		if note_data.has("start_time"):
			return _tick_to_ms(float(note_data.get("start_time", 0.0)))

	return 0.0

## 提取note音高（兼容 Note / NoteEvent / Dictionary）
func _get_note_pitch(note_data: Variant) -> int:
	if note_data == null:
		return 0

	if note_data is MidiParser.Note:
		if note_data.event:
			return int(note_data.event.pitch)
		return 0

	if note_data is MidiParser.NoteEvent:
		return int(note_data.pitch)

	if note_data is Dictionary:
		if note_data.has("pitch"):
			return int(note_data.get("pitch", 0))
		if note_data.has("original_note") and note_data["original_note"] is MidiParser.Note:
			var original_note = note_data["original_note"]
			if original_note.event:
				return int(original_note.event.pitch)

	return 0

## Step C/D: 虚拟触点匹配和块类型判定
func _assign_touches_and_judge_types(blocks: Array[BlockInfo]) -> void:
	if blocks.is_empty():
		return
	
	# 初始化虚拟触点
	var touches: Array[VirtualTouch] = []
	for i in range(max_touch_count):
		touches.append(VirtualTouch.new(i))

	# 与Unity一致：按批次处理触点匹配与块类型判定
	var blocks_by_batch: Dictionary = {}
	for block in blocks:
		if not blocks_by_batch.has(block.batch):
			blocks_by_batch[block.batch] = []
		blocks_by_batch[block.batch].append(block)

	var batch_ids: Array = blocks_by_batch.keys()
	batch_ids.sort()

	for batch_id in batch_ids:
		var batch_blocks_raw: Array = blocks_by_batch[batch_id]
		var batch_blocks: Array[BlockInfo] = []
		for b in batch_blocks_raw:
			batch_blocks.append(b as BlockInfo)
		_match_blocks_to_touches(batch_blocks, touches)

		# Unity在批内按start顺序进行判型与状态推进
		batch_blocks.sort_custom(func(a, b):
			if a.start_time_ms == b.start_time_ms:
				return a.lane < b.lane
			return a.start_time_ms < b.start_time_ms
		)
		for block in batch_blocks:
			_judge_block_type(block, touches)

## 虚拟触点匹配 - 递归回溯找成本最小的分配方案（Unity兼容版本）
func _match_blocks_to_touches(blocks_in_group: Array[BlockInfo], touches: Array[VirtualTouch]) -> void:
	if blocks_in_group.is_empty():
		return
	
	# 按X位置排序块（为了后续匹配）
	var sorted_blocks = blocks_in_group.duplicate()
	sorted_blocks.sort_custom(func(a, b): return a.x < b.x)
	
	# 初始化最优匹配跟踪
	var min_matching_touch_index: Array = []
	for i in range(sorted_blocks.size()):
		min_matching_touch_index.append(-1)
	
	# 递归回溯：找最小成本分配
	var min_cost_holder = [INF]  # 使用数组以便在递归中修改
	_find_optimal_matching(sorted_blocks, touches, 0, 0, [], min_matching_touch_index, min_cost_holder)
	
	# 应用最优分配
	for i in range(sorted_blocks.size()):
		var block = sorted_blocks[i]
		var touch_idx = min_matching_touch_index[i]
		block.touch_index = touch_idx

## 递归回溯：找最优的块→触点分配，最小化移动成本（Unity兼容版本）
## 关键修复：(1)修正成本函数仅为移动距离，(2)使用递增的touchIndex避免重复分配
func _find_optimal_matching(
	blocks: Array[BlockInfo], 
	touches: Array[VirtualTouch],
	block_idx: int,
	last_touch_idx: int,
	current_assignment: Array,
	out_min_matching_touch_index: Array,
	inout_min_cost: Array  # 使用数组以便修改内容
) -> void:
	# 基础情况：已分配所有块
	if block_idx >= blocks.size():
		# 计算当前分配方案的总成本（仅为移动距离）
		var total_cost = 0.0
		for i in range(blocks.size()):
			if current_assignment[i] >= 0:
				var blk = blocks[i]
				var touch = touches[current_assignment[i]]
				# ✅ 修正：成本函数仅为移动距离（与Unity版本一致）
				total_cost += abs(touch.last_press_x - blk.x)
		
		# 更新最小成本和对应的分配
		if total_cost < inout_min_cost[0]:
			inout_min_cost[0] = total_cost
			for i in range(blocks.size()):
				out_min_matching_touch_index[i] = current_assignment[i]
		return
	
	var block = blocks[block_idx]
	
	# 与Unity一致：使用递增touch索引，避免同批次重复分配同一触点
	for touch_idx in range(last_touch_idx, touches.size()):
		# 尝试分配此块给此触点
		current_assignment.append(touch_idx)
		_find_optimal_matching(blocks, touches, block_idx + 1, touch_idx + 1, current_assignment, out_min_matching_touch_index, inout_min_cost)
		current_assignment.pop_back()

## 检查块是否可以分配给该触点（考虑冷却和移动速度约束）
func _can_assign_block_to_touch(block: BlockInfo, touch: VirtualTouch) -> bool:
	# 如果touch为null，则允许（用于未分配情况）
	if touch == null:
		return true
	
	# 检查冷却时间：触点必须已释放（或从未使用过）
	if touch.holding_block != null:
		# 如果正在按住LONG块，检查当前块是否在hold期内
		if block.start_time_ms < touch.holding_block.end_time_ms:
			return false
		# 检查冷却期
		if block.start_time_ms - touch.holding_block.end_time_ms < (cooldown_seconds * 1000.0):
			return false
	elif touch.last_press_block != null:
		# 检查冷却期
		if block.start_time_ms - touch.last_press_block.end_time_ms < (cooldown_seconds * 1000.0):
			return false
	
	# 检查移动速度约束
	if touch.last_press_time_ms >= 0:
		var time_delta = (block.start_time_ms - touch.last_press_time_ms) / 1000.0
		if time_delta > 0:
			var distance = abs(block.x - touch.last_press_x)
			var required_speed = distance / time_delta
			if required_speed > max_touch_move_velocity:
				return false
	
	return true

## Step D: 块类型判定与触点状态管理（Unity兼容版本）
## 完整实现冷却期检查、移动速度限制、触点状态更新
func _judge_block_type(block: BlockInfo, touches: Array[VirtualTouch]) -> void:
	var duration_sec = block.duration_ms / 1000.0
	
	if block.touch_index < 0 or block.touch_index >= touches.size():
		return
	
	var touch = touches[block.touch_index]
	
	# ========== 第1步：按duration判定基础类型 ==========
	if duration_sec <= instant_block_threshold:
		block.type = BlockType.INSTANT
	elif duration_sec <= short_block_threshold:
		block.type = BlockType.SHORT
	else:
		block.type = BlockType.LONG
	
	# ========== 第2步：检查冷却期（触点可用性） ==========
	if not touch.is_free:
		# ✅ 修正：检查触点是否从hold状态释放
		if touch.holding_block == null and block.start_time_ms > touch.last_press_time_ms + (cooldown_seconds * 1000.0):
			touch.is_free = true
			touch.last_press_block = null
		else:
			# ✅ 修正：触点仍被占用，连接到前一个块
			block.prev_block = touch.last_press_block
			# ✅ 修正：硬性限制移动速度
			var time_delta_ms = block.start_time_ms - touch.last_press_time_ms
			if time_delta_ms > 0:
				var time_delta_sec = time_delta_ms / 1000.0
				var max_offset = max_touch_move_velocity * time_delta_sec
				var distance = abs(block.x - touch.last_press_x)
				if distance > max_offset:
					# 限制块位置
					if block.x > touch.last_press_x:
						block.x = touch.last_press_x + max_offset
					else:
						block.x = touch.last_press_x - max_offset
	
	# ========== 第3步：检查是否在LONG块内 ==========
	if touch.holding_block != null:
		if block.start_time_ms < touch.holding_block.end_time_ms:
			# ✅ 修正：强制为INSTANT
			block.type = BlockType.INSTANT
		else:
			# LONG块结束
			touch.holding_block = null
	
	# ========== 第4步：检查敲击间隔（minTapInterval） ==========
	if touch.last_press_time_ms >= 0:
		var gap = (block.start_time_ms - touch.last_press_time_ms) / 1000.0
		if gap < min_tap_interval:
			# ✅ 修正：强制为INSTANT
			block.type = BlockType.INSTANT
	
	# ========== 第5步：更新触点状态 ==========
	if block.type == BlockType.LONG:
		touch.holding_block = block
	
	touch.is_free = false
	touch.last_press_time_ms = block.start_time_ms
	touch.last_press_x = block.x
	touch.last_press_block = block

## Step E: 连块生成
func _generate_connects(blocks: Array[BlockInfo]) -> void:
	if blocks.is_empty() or not (generate_instant_connect or generate_short_connect):
		return

	# 先清理旧连接状态
	for block in blocks:
		block.connected_prev = false

	# InstantConnect 对齐 Unity：基于触点前驱 prev_block 判定
	if generate_instant_connect:
		for block in blocks:
			var prev = block.prev_block
			if block.type == BlockType.INSTANT and prev != null and prev.type == BlockType.INSTANT:
				var gap = (block.start_time_ms - prev.start_time_ms) / 1000.0
				if gap <= max_instant_connect_seconds:
					block.connected_prev = true

	# ShortConnect 对齐 Unity：每个批次仅连接最左与最右块
	if generate_short_connect:
		var blocks_by_batch: Dictionary = {}
		for block in blocks:
			if not blocks_by_batch.has(block.batch):
				blocks_by_batch[block.batch] = []
			blocks_by_batch[block.batch].append(block)

		for batch_blocks in blocks_by_batch.values():
			if batch_blocks.size() <= 1:
				continue

			var min_block: BlockInfo = batch_blocks[0]
			var max_block: BlockInfo = batch_blocks[0]
			for b in batch_blocks:
				if b.x < min_block.x:
					min_block = b
				if b.x > max_block.x:
					max_block = b

			if min_block != max_block:
				max_block.connected_prev = true
				max_block.prev_block = min_block

## 转换BlockInfo到GameSequence
func _convert_blocks_to_game_sequences(blocks: Array[BlockInfo]) -> void:
	for block in blocks:
		if block.notes.is_empty():
			continue
		
		# 使用第一个note作为主note
		var main_note = block.notes[0]
		if main_note == null or main_note.event == null:
			continue
		
		var evt = main_note.event
		var octave_info = MidiParser.get_note_octave_and_relative_pitch(evt.pitch)
		
		var game_seq = GameSequence.new(
			0,  # note_index
			next_key_id,
			evt.pitch,
			block.start_time_ms,
			block.duration_ms,
			block.x,
			octave_info["octave"],
			evt.velocity
		)
		
		game_seq.block_type = block.type
		game_seq.pitch_list = block.pitch_list.duplicate()
		game_seq.connected_prev = block.connected_prev
		game_seq.original_notes = block.notes.duplicate()
		
		game_sequences.append(game_seq)
		next_key_id += 1

## 计算lane对应的屏幕X位置
func _calculate_lane_position(lane: int) -> float:
	# 与Unity一致：两侧保留半个块宽度
	if lane_count <= 1:
		return screen_width * 0.5

	var lane_start = key_width * 0.5
	var lane_spacing = (screen_width - key_width) / float(lane_count - 1)
	return lane_start + float(lane) * lane_spacing

## 优化生成的键
## 实现难度自适应过滤、重叠消除等优化
func optimize_keys() -> bool:
	if game_sequences.is_empty():
		keys_optimized.emit(0)
		return true
	
	# 可选优化1：根据maxTouchCount过滤同时活跃块数过多的部分
	# （当前默认在虚拟触点匹配中已处理）
	
	# 可选优化2：LONG块冷却期验证
	for i in range(game_sequences.size() - 1):
		var current = game_sequences[i]
		var next_seq = game_sequences[i + 1]
		
		if current.block_type == BlockType.LONG and next_seq.block_type == BlockType.LONG:
			# 验证冷却期
			var gap = (next_seq.start_time_ms - current.start_time_ms - current.duration_ms) / 1000.0
			if gap < cooldown_seconds:
				# 可选：转换为INSTANT处理
				pass
	
	GameLogger.instance.info("Optimization complete: %d sequences" % game_sequences.size(), "KeySequenceManager")
	keys_optimized.emit(game_sequences.size())
	return true


## 获取游戏序列列表
func get_game_sequences() -> Array[GameSequence]:
	return game_sequences.duplicate()

## 获取背景序列列表
func get_background_sequences() -> Array[BackgroundSequence]:
	return background_sequences.duplicate()

## 获取特定键ID对应的GameSequence
func get_game_sequence_by_key_id(key_id: int) -> GameSequence:
	for seq in game_sequences:
		if seq.key_id == key_id:
			return seq
	return null

## 按时间获取应该显示的键（用于UI渲染）
## start_time和end_time用于定义显示的时间窗口
func get_visible_keys(start_time_ms: float, end_time_ms: float) -> Array[GameSequence]:
	var visible: Array[GameSequence] = []
	
	for seq in game_sequences:
		if seq.start_time_ms >= start_time_ms and seq.start_time_ms <= end_time_ms:
			visible.append(seq)
	
	return visible


## 生成后的有效Notes分类（在generate_keys()后调用）
## 在generate_keys()的最后调用此方法，统计真实分类
func _finalize_notes_classification() -> void:
	last_manual_control_notes.clear()
	last_auto_play_notes.clear()
	
	# 从game_sequences中收集所有manual_control_notes
	for game_seq in game_sequences:
		if game_seq and not game_seq.original_notes.is_empty():
			for note in game_seq.original_notes:
				if note not in last_manual_control_notes:
					last_manual_control_notes.append(note)
	
	# 从background_sequences中收集所有auto_play_notes
	for bg_seq in background_sequences:
		if bg_seq and not bg_seq.notes.is_empty():
			for note in bg_seq.notes:
				# 处理可能的Note对象或NoteEvent对象
				if note not in last_auto_play_notes:
					last_auto_play_notes.append(note)
	
	GameLogger.instance.info(
		"Notes classification finalized: %d manual-control, %d auto-play" % 
		[last_manual_control_notes.size(), last_auto_play_notes.size()],
		"KeySequenceManager"
	)

## 获取最后一次生成的分类结果
func get_last_notes_classification() -> Dictionary:
	return {
		"manual_control_notes": last_manual_control_notes.duplicate(),
		"auto_play_notes": last_auto_play_notes.duplicate()
	}

## 清空所有序列
func clear_sequences() -> void:
	game_sequences.clear()
	background_sequences.clear()
	all_notes.clear()
	next_key_id = 0
	current_midi_data = null

## 从配置中应用键优化参数
## 此方法待后续完善，用于接收GameplayManager或ConfigLoader的设置
func apply_optimization_config(config: Dictionary) -> void:
	# 框架：接收配置参数
	# 示例配置:
	# {
	#   "difficulty": "normal",  # easy/normal/hard
	#   "auto_filter": true,
	#   "min_note_spacing": 10,
	#   "clustering_threshold": 100
	# }
	
	if config.has("min_note_spacing_ms"):
		min_note_spacing_ms = config["min_note_spacing_ms"]
	
	# 待后续实现具体的优化逻辑

## 统计信息
func get_statistics() -> Dictionary:
	return {
		"total_notes": all_notes.size(),
		"game_sequences_count": game_sequences.size(),
		"background_sequences_count": background_sequences.size(),
		"background_notes_count": _count_background_notes()
	}

## 统计背景Note总数
func _count_background_notes() -> int:
	var count = 0
	for bg_seq in background_sequences:
		count += bg_seq.notes.size()
	return count

## 配置变更回调（新增）
func _on_config_changed(key: String, section: String, value: Variant) -> void:
	# 处理 Lane 相关配置变更
	if section == "Lane":
		match key:
			"lane_count":
				lane_count = int(value)
				GameLogger.instance.info("Lane count changed to: %d" % lane_count, "KeySequenceManager")
				# 如果已经有生成的键，需要重新生成
				if not game_sequences.is_empty():
					GameLogger.instance.warning("Lane count changed while sequences exist, regeneration may be needed", "KeySequenceManager")
			
			"keyboard_mode":
				var keyboard_mode_enabled = int(value) == 1
				# 更新触摸移动速度限制
				if keyboard_mode_enabled:
					max_touch_move_velocity = 999999.0
					GameLogger.instance.info("Keyboard mode enabled: max_touch_move_velocity set to unlimited", "KeySequenceManager")
				else:
					# 恢复到配置中的值
					var config_manager = ConfigManager.instance
					max_touch_move_velocity = config_manager.get_float("Generator", "max_touch_move_speed", 500.0)
					GameLogger.instance.info("Keyboard mode disabled: max_touch_move_velocity restored to %.1f" % max_touch_move_velocity, "KeySequenceManager")
	
	# 处理 Generator 相关配置变更
	elif section == "Generator":
		match key:
			"instant_block_max_time":
				instant_block_threshold = float(value)
			"short_block_max_time":
				short_block_threshold = float(value)
			"max_simultaneous_blocks":
				max_touch_count = int(value)
			"min_tap_interval":
				min_tap_interval = float(value)
			"min_touch_cooldown_time":
				cooldown_seconds = float(value)
			"max_touch_move_speed":
				# 仅在非键盘模式下更新（键盘模式时保持999999）
				if ConfigManager.instance.get_int("Lane", "keyboard_mode", 0) == 0:
					max_touch_move_velocity = float(value)
				else:
					GameLogger.instance.info("Ignored max_touch_move_speed change (keyboard mode active)", "KeySequenceManager")
			"max_block_coalesce_time":
				block_coalesce_seconds = float(value)
	
	# 处理 Appearance 相关配置变更
	elif section == "Appearance":
		match key:
			"generate_short_connect":
				generate_short_connect = value in ["1", "true", "True", "yes", "Yes"]
			"generate_instant_connect":
				generate_instant_connect = value in ["1", "true", "True", "yes", "Yes"]
			"instant_connect_max_time":
				max_instant_connect_seconds = float(value)
			"block_size":
				key_width = float(value)
