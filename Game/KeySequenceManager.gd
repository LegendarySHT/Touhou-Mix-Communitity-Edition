## 键序列管理器
## 负责将MIDI Note分类为gameSequences和backgroundSequences
## 以及生成游戏键位的映射
extends Node

class_name KeySequenceManager

## 块类型枚举
enum BlockType {
	INSTANT = 0,  # 滑块（duration <= instant_block_threshold）
	SHORT = 1,    # 点块（duration <= short_block_threshold）
	LONG = 2      # 长条（duration > short_block_threshold，需按住）
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
	var original_notes: Array[MidiParser.NoteEvent] = []  # 保留该块包含的原始 NoteEvent 列表
	var flow_note_ref: Object = null  # 新增：指向对应的FlowArea.Note（演奏模式使用）
	var lane: int = -1  # 视觉轨道索引（可能因 max_touch_move_velocity 限制而偏离 pitch % lane_count）
	
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
	var notes: Array            # 包含的所有 NoteEvent

	func _init(track: int) -> void:
		track_index = track
		notes = []

## 块信息（生成后的块对象）
class BlockInfo:
	var notes: Array[MidiParser.NoteEvent] = []  # 合并后该块包含的所有原始 NoteEvent 对象
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

## 临时音符对象（generate_keys 流水线中间格式）
## 替代旧版 Dictionary（每音符 7 个 StringName key + Variant 装箱，6 万音符约 16.8MB 临时内存）
## typed class 字段直接访问，比 Dictionary.get 哈希查找快 5-10 倍；单实例约 160 字节 vs Dict ~280 字节
class TempNote:
	var pitch: int = 0
	var velocity: int = 0
	var track_index: int = 0
	var channel: int = 0
	var start_time_ms: float = 0.0
	var duration_ms: float = 0.0
	var original_note: MidiParser.NoteEvent = null  # 直接引用 NoteEvent

## 当前MIDI数据
var current_midi_data: MidiData

## 所有音符列表
var all_notes: Array = []

## MIDI时间基准和BPM时间线（用于tick到毫秒的转换）
var midi_timebase: int = 480  # 默认MIDI时间基准
var bpm_timeline: Array = []  # BPM时间线数据
var _tick_ms_cache: Dictionary = {}  # tick->ms cache, avoids repeated BPM timeline scans
var _bpm_lookup: Array = []  # Pre-built BPM lookup table for O(1) segment search

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

## 键序列生成缓存（避免选歌预览与 PlayView 重复生成）
var _cache_key: String = ""
var _cached_sequences: Array[GameSequence] = []
var _cached_background_sequences: Array[BackgroundSequence] = []
var _cached_manual_notes: Array = []
var _cached_auto_notes: Array = []

## 屏幕宽度（用于键位映射）
var screen_width: float = 1920.0

## 每个键的宽度
var key_width: float = 40.0

## ========== 键生成配置参数 ==========
var lane_count: int = 12  # 轨道数量
var block_coalesce_seconds: float = 0.25  # 批次合并时间窗口（秒）
var instant_block_threshold: float = 0.2  # INSTANT块时长阈值（秒）
var short_block_threshold: float = 1.0  # SHORT块时长阈值（秒）
var min_tap_interval: float = 1.0  # 最小敲击间隔（秒）
var cooldown_seconds: float = 2.0  # 触点冷却时间（秒）
var max_touch_move_velocity: float = 300.0  # 最大触点移动速度（像素/秒）
var max_touch_count: int = 2  # 最大同时活跃键数
var generate_instant_connect: bool = true  # 是否生成INSTANT连块
var generate_short_connect: bool = true  # 是否生成SHORT连块
var max_instant_connect_seconds: float = 1.0  # INSTANT连块最大间隔（秒）
var min_block_spacing: int = 1  # 并排音符最小横向间距（轨道数，0=关闭）

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
	if EvtBus:
		EvtBus.config_changed.connect(_on_config_changed)

## 设置MIDI时间参数（用于tick到毫秒的转换）
func set_midi_time_parameters(timebase: int, bpm_timeline_data: Array = []) -> void:
	midi_timebase = timebase if timebase > 0 else 480
	bpm_timeline = bpm_timeline_data.duplicate()
	_tick_ms_cache.clear()  # Invalidate tick->ms cache when timeline changes
	# Pre-build BPM lookup table: arrays of [tick, bpm, cumulative_ms] for fast O(1) field access
	_bpm_lookup.clear()
	var _cum: float = 0.0
	for _i in range(bpm_timeline.size()):
		var _e = bpm_timeline[_i]
		var _tk: float = float(_e.get("tick", 0.0))
		var _bpm: float = float(_e.get("bpm", 120.0))
		_bpm_lookup.append([_tk, _bpm, _cum])
		if _i + 1 < bpm_timeline.size():
			var _nt: float = float(bpm_timeline[_i + 1].get("tick", _tk))
			var _mspt: float = (60000.0 / _bpm) / float(midi_timebase)
			_cum += (_nt - _tk) * _mspt
	GLogger.info("MIDI time parameters set: timebase=%d, bpm_timeline_size=%d" % [midi_timebase, bpm_timeline.size()], "KeySequenceManager")

## 将MIDI tick转换为毫秒
func _tick_to_ms(tick: float) -> float:
	# Check cache first to avoid repeated BPM timeline scans
	if _tick_ms_cache.has(tick):
		return _tick_ms_cache[tick]
	# 使用BPM时间线计算（如果可用）
	var result: float
	if bpm_timeline.size() > 0:
		result = _calculate_position_with_bpm_timeline(tick)
	else:
		# 后备：使用120 BPM（默认）
		result = (tick / float(midi_timebase)) * (60000.0 / 120.0)
	_tick_ms_cache[tick] = result
	return result

## 使用BPM时间线计算位置
## 二分查找定位 tick 所在的 BPM 段：O(log N) 替代旧版线性扫描 O(N)
## 6 万音符 + 多段 BPM 时间线下从 ~N×S 次比较降至 N×log(S)
## 注意：_bpm_lookup 按 tick 升序构建（set_midi_time_parameters 中按 bpm_timeline 顺序追加）
func _calculate_position_with_bpm_timeline(tick: float) -> float:
	# Uses pre-built _bpm_lookup array of [tick, bpm, cumulative_ms]
	# Array indexing is much faster than dict.get() in the hot loop
	var n: int = _bpm_lookup.size()
	if n == 0:
		return (tick / float(midi_timebase)) * (60000.0 / 120.0)

	var tick_delta: float
	var ms_per_tick: float

	# 边界快速路径：tick 在第一段之前或最后一段之后
	var first_entry = _bpm_lookup[0]
	if tick <= first_entry[0]:
		# tick 在首个 BPM 段起点之前（含 0）：直接用第一段算
		tick_delta = tick - first_entry[0]
		ms_per_tick = (60000.0 / first_entry[1]) / float(midi_timebase)
		return first_entry[2] + tick_delta * ms_per_tick
	var last_entry = _bpm_lookup[n - 1]
	if tick >= last_entry[0]:
		# tick 在最后一段内（含尾部）
		tick_delta = tick - last_entry[0]
		ms_per_tick = (60000.0 / last_entry[1]) / float(midi_timebase)
		return last_entry[2] + tick_delta * ms_per_tick

	# 二分查找：找最后一个 tick <= target 的段（即 target 所在的 BPM 段）
	# _bpm_lookup 已按 tick 升序排列
	var lo: int = 0
	var hi: int = n - 1
	while lo < hi:
		var mid: int = (lo + hi + 1) >> 1  # 上取整避免死循环
		if _bpm_lookup[mid][0] <= tick:
			lo = mid
		else:
			hi = mid - 1
	var entry = _bpm_lookup[lo]
	tick_delta = tick - entry[0]
	ms_per_tick = (60000.0 / entry[1]) / float(midi_timebase)
	return entry[2] + tick_delta * ms_per_tick

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
	instant_block_threshold = config_manager.get_float(gen_cfg, "instant_block_max_time", 0.2)
	short_block_threshold = config_manager.get_float(gen_cfg, "short_block_max_time", 1.0)
	max_touch_count = config_manager.get_int(gen_cfg, "max_simultaneous_blocks", 2)
	min_tap_interval = config_manager.get_float(gen_cfg, "min_tap_interval", 1.0)
	cooldown_seconds = config_manager.get_float(gen_cfg, "min_touch_cooldown_time", 2.0)
	max_touch_move_velocity = config_manager.get_float(gen_cfg, "max_touch_move_speed", 300.0)
	block_coalesce_seconds = config_manager.get_float(gen_cfg, "max_block_coalesce_time", 0.25)

	# 从Judge段读取并排音符最小横向间距（单位：轨道数）
	# 兼容旧版未实装的像素单位值：超出合理范围（>= lane_count）则重置为默认值1
	min_block_spacing = _validate_min_block_spacing(
		config_manager.get_int("Judge", "min_block_spacing", 1)
	)
	
	# 从Appearance段读取连块参数
	var app_cfg = "Appearance"
	generate_short_connect = config_manager.get_bool(app_cfg, "generate_short_connect", true)
	generate_instant_connect = config_manager.get_bool(app_cfg, "generate_instant_connect", true)
	max_instant_connect_seconds = config_manager.get_float(app_cfg, "instant_connect_max_time", 1.0)
	key_width = config_manager.get_float(app_cfg, "block_size", key_width)
	
	# 键盘模式特殊处理：禁用触摸移动速度限制，并调整轨道数为按键数
	var keyboard_mode_enabled = config_manager.get_int("Lane", "keyboard_mode", 0) == 1
	if keyboard_mode_enabled:
		max_touch_move_velocity = 999999.0
		# 键盘模式下，有效轨道数 = 键盘按键数，保证 KeySequenceManager 与 PlayView 一致
		var keyboard_keys_str = config_manager.get_string("Lane", "keyboard_mode_keys", "A,S,D,F,J,K,L,;")
		var key_map = ConfigParser.parse_keyboard_keys(keyboard_keys_str)
		if key_map.size() > 0:
			lane_count = key_map.size()
		GLogger.info(
			"Keyboard mode enabled: max_touch_move_velocity set to unlimited, lane_count adjusted to %d" % lane_count,
			"KeySequenceManager"
		)
	
	GLogger.info(
		"KeyGeneration config loaded: block_coalesce=%.2fs, instant=%.2fs, short=%.2fs, maxTouch=%d, max_touch_velocity=%.1f, min_block_spacing=%d" %
		[block_coalesce_seconds, instant_block_threshold, short_block_threshold, max_touch_count, max_touch_move_velocity, min_block_spacing],
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

	return true

## 生成游戏使用的键
## 实现完整的批次合并、去重、虚拟触点匹配、块类型判定、连块生成算法
## 注意：传入的game_notes应该已经被筛选为只包含启用的音轨的音符
## PlayView会根据TrackView中的selected_track_configs筛选出启用的音轨，然后传入这里
## 线程安全：本方法可在 WorkerThreadPool 后台线程执行（仅访问 self 字段与 MidiPlaybackManager.instance 静态字段，
## 不访问场景树）。调用期间主线程不得读写 KeySequenceManager 的任何字段。
func generate_keys(game_notes: Array, midi_id: String = "", enabled_pairs: Dictionary = {}) -> bool:
	# 构造缓存键（midi_id + 启用轨道对哈希）
	# 注意：screen_width 不进 cache_key。它只影响 _judge_block_type 速度限制里极少数音符的
	# lane 钳制，且防窗口变化的设计实际没生效（PlayView 的 size_changed 不重算 generate_keys）。
	# FlowArea 显示位置由 viewport 宽度算，与 KSM 的 screen_width 无关。
	# 加入 cache_key 会导致 MidiView(默认1920) 与 PlayView(lane_area.size.x) 调用永远 miss。
	var pairs_hash := ""
	for k in enabled_pairs.keys():
		pairs_hash += str(k) + ","
	var cache_key := "%s|%s" % [midi_id, pairs_hash.hash()]
	if cache_key == _cache_key and not _cached_sequences.is_empty():
		# 命中缓存，直接复用（选歌预览与 PlayView 重复生成时命中）
		game_sequences = _cached_sequences.duplicate()
		background_sequences = _cached_background_sequences.duplicate()
		last_manual_control_notes = _cached_manual_notes.duplicate()
		last_auto_play_notes = _cached_auto_notes.duplicate()
		GLogger.debug("generate_keys HIT cache, reuse %d sequences" % game_sequences.size(), "KSM")
		return true
	GLogger.debug("generate_keys MISS cache, regenerating...", "KSM")
	if game_notes.is_empty():
		game_sequences.clear()
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

	# Step 2: 按时间排序Note（in-place 排序，避免 duplicate 整个数组）
	# 6 万音符时 duplicate 会产生 ~24MB 临时内存峰值
	# 注：MidiParser 末尾已对 notes 按 start_time 排序，但筛选后顺序仍保序；
	# 此处仍执行一次 sort 保证稳定性（_tick_to_ms 是 tick 的单调函数，已排序输入下 sort 是 no-op）
	converted_notes.sort_custom(func(a, b):
		if a.start_time_ms == b.start_time_ms:
			return a.channel < b.channel
		return a.start_time_ms < b.start_time_ms
	)

	# Step 3: 执行批次合并（Step A）
	var batches := _batch_notes_by_coalesce(converted_notes)
	GLogger.info("Batch merge: created %d batches from %d notes" % [batches.size(), converted_notes.size()], "KeySequenceManager")

	# Step 4: 为每个批次执行去重（Step B）
	var all_blocks: Array[BlockInfo] = []
	var bg_notes: Array = []
	for batch_idx in range(batches.size()):
		var deduped_blocks = _dedup_batch(batches[batch_idx], bg_notes, batch_idx)
		all_blocks.append_array(deduped_blocks)

	GLogger.info("Dedup: generated %d blocks, %d background notes" % [all_blocks.size(), bg_notes.size()], "KeySequenceManager")

	# Step 5: 虚拟触点匹配和块类型判定（Step C + Step D）
	_assign_touches_and_judge_types(all_blocks, bg_notes)

	# Step 6: 连块生成（Step E）
	_generate_connects(all_blocks)

	# Step 7: 转换为GameSequence集合
	_convert_blocks_to_game_sequences(all_blocks)

	# Step 8: 添加背景序列（与Unity一致：输出单一背景序列）
	# 预计算 start_time_ms 到 PackedFloat32Array，避免排序时反复调用 _get_note_start_time_ms
	# 同时避免为每个 note 构建 Dictionary 包装（6 万音符时省 ~5-10MB 临时内存）
	var bg_count := bg_notes.size()
	var bg_times := PackedFloat32Array()
	bg_times.resize(bg_count)
	for i in range(bg_count):
		bg_times[i] = _get_note_start_time_ms(bg_notes[i])
	# 按预计算时间排序索引数组，再用排序后的索引重建 bg_notes
	var bg_indices := range(bg_count)
	bg_indices.sort_custom(func(a, b):
		if bg_times[a] == bg_times[b]:
			return _get_note_pitch(bg_notes[a]) < _get_note_pitch(bg_notes[b])
		return bg_times[a] < bg_times[b]
	)
	var sorted_bg_notes: Array = []
	sorted_bg_notes.resize(bg_count)
	for i in range(bg_count):
		sorted_bg_notes[i] = bg_notes[bg_indices[i]]
	bg_notes = sorted_bg_notes
	var bg_seq = BackgroundSequence.new(0)
	bg_seq.notes = bg_notes
	background_sequences.append(bg_seq)

	# 在generate_keys完成后立即进行分类统计
	_finalize_notes_classification()

	# 写入缓存（引用共享，不 duplicate）
	# game_sequences/background_sequences/last_* 在此后不再修改，
	# 下次 generate_keys 命中缓存时会 duplicate 一份给 game_sequences 使用（见上方 cache hit 分支），
	# 因此 _cached_* 引用的内容不会被外部修改
	_cache_key = cache_key
	_cached_sequences = game_sequences
	_cached_background_sequences = background_sequences
	_cached_manual_notes = last_manual_control_notes
	_cached_auto_notes = last_auto_play_notes

	return true

## 单任务模式：同一时间只允许一个 generate_keys worker 运行
## 新任务启动前必须等待旧任务完成（防止并发写入 game_sequences 等共享字段）
var _generate_task_id: int = -1
var _generate_done_flag: Dictionary = {}  # worker 写 "done":true，主线程读
var _generate_task_waited: bool = false   # wait_for_task_completion 是否已调（幂等保护）

## 清理当前 task（幂等：多处调用安全，wait_for_task_completion 只调一次）
func _wait_and_cleanup_current_task() -> void:
	if _generate_task_id == -1:
		return
	if not _generate_task_waited:
		WorkerThreadPool.wait_for_task_completion(_generate_task_id)
		_generate_task_waited = true
	_generate_task_id = -1
	_generate_task_waited = false

## 启动 generate_keys worker（async，调用方须 await）
## 若有旧任务在跑，先等它完成再启动新任务
func start_generate_keys_async(game_notes: Array, midi_id: String = "", enabled_pairs: Dictionary = {}) -> int:
	# 等待旧任务完成（用 done_flag 轮询 + await 让出主线程，不阻塞动画）
	if _generate_task_id != -1:
		while not _generate_done_flag.get("done", false):
			await Engine.get_main_loop().process_frame
		_wait_and_cleanup_current_task()

	_generate_done_flag = {"done": false}
	_generate_task_id = WorkerThreadPool.add_task(
		func():
			generate_keys(game_notes, midi_id, enabled_pairs)
			_generate_done_flag["done"] = true,
		false,
		"KeySequenceManager.generate_keys"
	)
	return _generate_task_id

## 等待 generate_keys worker 完成（每帧让出主线程）
func await_generate_keys(task_id: int) -> void:
	# task_id == -1 表示未启动任务（如 enabled_notes 为空）
	if task_id == -1:
		return
	# while 同时检查 task_id 是否仍为当前任务：若已被新任务替换，说明旧任务已被
	# start_generate_keys_async 内部清理，直接返回
	while task_id == _generate_task_id and not _generate_done_flag.get("done", false):
		await Engine.get_main_loop().process_frame
	if task_id != _generate_task_id:
		return
	_wait_and_cleanup_current_task()

## 异步生成游戏键（start_generate_keys_async + await_generate_keys 的便捷封装）
func generate_keys_async(game_notes: Array, midi_id: String = "", enabled_pairs: Dictionary = {}) -> bool:
	var task_id := await start_generate_keys_async(game_notes, midi_id, enabled_pairs)
	await await_generate_keys(task_id)
	return true

## 将 NoteEvent 对象转换为内部格式（确保使用毫秒单位）
## 返回 Array[TempNote]，替代旧版 Array[Dictionary]
## TempNote 字段直接访问比 Dictionary.get 哈希查找快 5-10 倍，内存占用降 ~40%
func _convert_notes_to_internal_format(game_notes: Array) -> Array:
	var converted: Array = []

	for note in game_notes:
		if note is MidiParser.NoteEvent:
			var tn := TempNote.new()
			tn.pitch = note.pitch
			tn.velocity = note.velocity
			tn.track_index = note.track_index
			tn.channel = note.channel
			tn.start_time_ms = _tick_to_ms(note.start_time)
			tn.duration_ms = _tick_duration_to_ms(note.start_time, note.duration)
			tn.original_note = note
			converted.append(tn)
		# 其他格式跳过（不应出现）

	return converted

## Step A: 批次合并 - 按blockCoalesceSeconds分组
func _batch_notes_by_coalesce(sorted_notes: Array) -> Array:
	var batches: Array = []
	if sorted_notes.is_empty():
		return batches

	var current_batch: Array = []
	var current_batch_start_time: float = -1.0

	for note in sorted_notes:
		# TempNote 字段直接访问
		var note_time: float = note.start_time_ms

		if current_batch_start_time < 0:
			current_batch_start_time = note_time
			current_batch.append(note)
		elif note_time <= current_batch_start_time + (block_coalesce_seconds * 1000.0):
			current_batch.append(note)
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
	var lane_to_note: Dictionary = {}  # lane -> TempNote

	# 第1步：按lane去重（同lane保留最高音符）
	for note in batch:
		var pitch: int = note.pitch
		var lane: int = pitch % lane_count

		if lane_to_note.has(lane):
			var existing_note = lane_to_note[lane]
			var existing_pitch: int = existing_note.pitch
			# 比较音高，保留更高的
			if pitch > existing_pitch:
				# 将旧的加入背景
				_append_note_to_background(existing_note.original_note, bg_notes)
				lane_to_note[lane] = note
			else:
				# 将当前的加入背景
				_append_note_to_background(note.original_note, bg_notes)
		else:
			lane_to_note[lane] = note

	# 第2步：为保留下来的Note创建BlockInfo
	for lane in lane_to_note.keys():
		var note: TempNote = lane_to_note[lane]
		var block = BlockInfo.new()
		block.batch = batch_idx
		# 添加原始Note对象（BlockInfo._init()已初始化notes为[]）
		block.notes.append(note.original_note)
		block.lane = lane
		block.start_time_ms = note.start_time_ms
		block.end_time_ms = block.start_time_ms + note.duration_ms
		block.duration_ms = note.duration_ms
		# 将pitch添加到pitch_list
		block.pitch_list.append(note.pitch)
		block.x = _calculate_lane_position(lane)
		blocks.append(block)

	# 第3步：执行最小横向间距约束（并排音符轨道间距）
	blocks = _enforce_min_lane_spacing(blocks, bg_notes)

	# 第4步：按音高排序并移除超过maxTouchCount的块（与Unity版本一致）
	if blocks.size() > max_touch_count:
		blocks.sort_custom(func(a, b): return a.pitch_list[0] > b.pitch_list[0])
		while blocks.size() > max_touch_count:
			var removed_block = blocks.pop_back()
			if not removed_block.notes.is_empty():
				_append_note_to_background(removed_block.notes[0], bg_notes)

	return blocks

## 校验并排音符最小横向间距取值
## min_block_spacing 为轨道数：0 表示关闭约束；负数或 >= lane_count 属于无效/旧版像素残留，重置为默认值1
func _validate_min_block_spacing(value: int) -> int:
	if value < 0 or value >= lane_count:
		return 1
	return value

## 强制并排音符的最小横向间距约束
## 当两个块的轨道号差绝对值 <= min_block_spacing 时，移除音高较低的块到背景
## 与同 lane 去重逻辑一致：优先保留高音
func _enforce_min_lane_spacing(blocks: Array[BlockInfo], bg_notes: Array) -> Array[BlockInfo]:
	if blocks.size() <= 1 or min_block_spacing <= 0:
		return blocks

	# 按音高降序排序，优先保留高音（与现有去重逻辑一致）
	var sorted_blocks: Array[BlockInfo] = []
	sorted_blocks.append_array(blocks)
	sorted_blocks.sort_custom(func(a, b): return a.pitch_list[0] > b.pitch_list[0])

	var kept: Array[BlockInfo] = []
	for block in sorted_blocks:
		var conflict := false
		for kept_block in kept:
			if abs(block.lane - kept_block.lane) <= min_block_spacing:
				conflict = true
				break
		if conflict:
			# 移入背景（与现有去重/超限逻辑一致）
			if not block.notes.is_empty():
				_append_note_to_background(block.notes[0], bg_notes)
		else:
			kept.append(block)

	return kept

## 钳制后重新校验 min_block_spacing（后置修复）
## _judge_block_type 的速度限制会将 block.lane 钳制到触点附近，可能使其与同批次
## 其他块的 lane 过近，破坏 _enforce_min_lane_spacing 在去重阶段已保证的间距。
## 此函数按批次分组，对已钳制的 lane 重新执行间距校验，将冲突块移入背景。
## 性能：用 Dictionary set 做 O(1) 查找 + 一次原地过滤，避免旧版 blocks.erase 的 O(K×N)
## 以及 kept.has() 的 O(N) 线性扫描（6 万音符时 K×N 可达上亿次比较）
func _reconcile_spacing_after_clamp(blocks: Array[BlockInfo], bg_notes: Array) -> void:
	if blocks.size() <= 1 or min_block_spacing <= 0:
		return

	# 按批次分组（min_block_spacing 仅约束同一批次内的并排音符）
	var by_batch: Dictionary = {}
	for block in blocks:
		if not by_batch.has(block.batch):
			by_batch[block.batch] = []
		by_batch[block.batch].append(block)

	# 用 Dictionary set 收集需移除的块（key=block 对象引用，value 占位 true）
	# 替代旧版 Array[BlockInfo] + blocks.erase：erase 每次 O(N)，K 次共 O(K×N)
	# Dictionary.has 是 O(1)，后续过滤单次 O(N) 完成
	var to_remove_set: Dictionary = {}
	for batch_id in by_batch.keys():
		var batch_blocks: Array = by_batch[batch_id]
		if batch_blocks.size() <= 1:
			continue
		# 转换为类型数组以匹配 _enforce_min_lane_spacing 签名
		var typed_blocks: Array[BlockInfo] = []
		for b in batch_blocks:
			typed_blocks.append(b as BlockInfo)
		var kept = _enforce_min_lane_spacing(typed_blocks, bg_notes)
		# 用 Dictionary set 做 kept 查找（O(1)），替代旧版 kept.has() 的 O(N) 线性扫描
		var kept_set: Dictionary = {}
		for k in kept:
			kept_set[k] = true
		# 收集被移入背景的块（不在 kept 列表中的）
		for block in typed_blocks:
			if not kept_set.has(block):
				to_remove_set[block] = true

	# 单次原地过滤：用 writeidx 覆盖写入，最后 resize 截断
	# 替代旧版 for block in to_remove: blocks.erase(block) 的 O(K×N) 重复扫描
	if to_remove_set.is_empty():
		return
	var write_idx: int = 0
	for block in blocks:
		if not to_remove_set.has(block):
			blocks[write_idx] = block
			write_idx += 1
	blocks.resize(write_idx)

## 将 NoteEvent 追加到背景列表
func _append_note_to_background(note_data: MidiParser.NoteEvent, bg_notes: Array) -> void:
	if note_data == null:
		return
	bg_notes.append(note_data)

## 提取 NoteEvent 所属轨道索引
func _get_note_track_index(note_data: MidiParser.NoteEvent) -> int:
	return note_data.track_index

## 提取 NoteEvent 起始时间（毫秒）
func _get_note_start_time_ms(note_data: MidiParser.NoteEvent) -> float:
	return _tick_to_ms(note_data.start_time)

## 提取 NoteEvent 音高
func _get_note_pitch(note_data: MidiParser.NoteEvent) -> int:
	return int(note_data.pitch)

## Step C/D: 虚拟触点匹配和块类型判定
func _assign_touches_and_judge_types(blocks: Array[BlockInfo], bg_notes: Array) -> void:
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

		batch_blocks.sort_custom(func(a, b):
			return a.start_time_ms < b.start_time_ms
		)
		for block in batch_blocks:
			_judge_block_type(block, touches)

	# 钳制后重新校验 min_block_spacing：_judge_block_type 的速度限制可能将
	# 音符移动到与同批次其他音符过近的位置，违反 min_block_spacing 约束。
	# 按批次分组重新执行间距校验，将冲突块移入背景（优先保留高音，与去重逻辑一致）
	_reconcile_spacing_after_clamp(blocks, bg_notes)

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
	
	# Unity bug: 匹配结果按start_time顺序应用（而非x顺序）
	# 这会导致当批次中有2个块且x顺序与start_time顺序不一致时，
	# touch_index被错误地分配给不同的块
	sorted_blocks.sort_custom(func(a, b):
		return a.start_time_ms < b.start_time_ms
	)
	
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
		# 计算当前分配方案的总成本（移动距离 + 速度违规惩罚）
		var total_cost = 0.0
		for i in range(blocks.size()):
			if current_assignment[i] >= 0:
				var blk = blocks[i]
				var touch = touches[current_assignment[i]]
				var move_distance = abs(touch.last_press_x - blk.x)
				total_cost += move_distance
				# 速度违规惩罚：使匹配优先选择不超速的分配方案
				# 惩罚 = 超出限速的距离 × 惩罚系数，确保超速方案成本远高于可行方案
				if touch.last_press_time_ms >= 0:
					var time_delta_sec = (blk.start_time_ms - touch.last_press_time_ms) / 1000.0
					if time_delta_sec > 0:
						var max_feasible = max_touch_move_velocity * time_delta_sec
						if move_distance > max_feasible:
							total_cost += (move_distance - max_feasible) * 10.0

		# 更新最小成本和对应的分配
		if total_cost < inout_min_cost[0]:
			inout_min_cost[0] = total_cost
			for i in range(blocks.size()):
				out_min_matching_touch_index[i] = current_assignment[i]
		return
	
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
			var time_delta_ms = block.start_time_ms - touch.last_press_time_ms
			var time_delta_sec = time_delta_ms / 1000.0
			var max_offset = max_touch_move_velocity * time_delta_sec
			var distance = abs(block.x - touch.last_press_x)
			if distance > max_offset:
					# 限制块位置：先按最大偏移钳制 x，再吸附到最近轨道中心
					if block.x > touch.last_press_x:
						block.x = touch.last_press_x + max_offset
					else:
						block.x = touch.last_press_x - max_offset
					# 同步更新 lane，使速度约束真正影响最终音符轨道
					block.lane = _calculate_lane_from_x(block.x)
					block.x = _calculate_lane_position(block.lane)
	
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
			

## 转换BlockInfo到GameSequence
func _convert_blocks_to_game_sequences(blocks: Array[BlockInfo]) -> void:
	for block in blocks:
		if block.notes.is_empty():
			continue

		# 使用第一个 NoteEvent 作为主 note（block.notes 现为 Array[NoteEvent]）
		var main_note: MidiParser.NoteEvent = block.notes[0]
		if main_note == null:
			continue

		var octave_info = MidiParser.get_note_octave_and_relative_pitch(main_note.pitch)

		var game_seq = GameSequence.new(
			0,  # note_index
			next_key_id,
			main_note.pitch,
			block.start_time_ms,
			block.duration_ms,
			block.x,
			octave_info["octave"],
			main_note.velocity
		)

		game_seq.block_type = block.type
		game_seq.pitch_list = block.pitch_list.duplicate()
		game_seq.connected_prev = block.connected_prev
		game_seq.original_notes = block.notes.duplicate()
		game_seq.lane = block.lane

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

## 根据屏幕X位置反推最近的lane索引（_calculate_lane_position 的逆运算）
func _calculate_lane_from_x(x: float) -> int:
	if lane_count <= 1:
		return 0
	var lane_start = key_width * 0.5
	var lane_spacing = (screen_width - key_width) / float(lane_count - 1)
	if lane_spacing <= 0.0:
		return 0
	var lane = int(round((x - lane_start) / lane_spacing))
	return clampi(lane, 0, lane_count - 1)


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
## 性能：使用 Dictionary 作为 seen-set 实现 O(1) 去重查找，避免 `not in Array` 的 O(N) 线性扫描
## 6 万音符场景下从 O(N²)≈15 亿次比较降至 O(N)≈6 万次哈希查找
func _finalize_notes_classification() -> void:
	last_manual_control_notes.clear()
	last_auto_play_notes.clear()

	# 用 Dictionary 作为 seen-set：key=note 对象引用，value 占位 true
	# Array.in 是 O(N) 线性扫描；Dictionary.has 是 O(1) 哈希查找
	var manual_set: Dictionary = {}
	for game_seq in game_sequences:
		if game_seq and not game_seq.original_notes.is_empty():
			for note in game_seq.original_notes:
				if not manual_set.has(note):
					manual_set[note] = true
					last_manual_control_notes.append(note)

	var auto_set: Dictionary = {}
	for bg_seq in background_sequences:
		if bg_seq and not bg_seq.notes.is_empty():
			for note in bg_seq.notes:
				if not auto_set.has(note):
					auto_set[note] = true
					last_auto_play_notes.append(note)
	
	GLogger.info(
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

## 清空所有序列（PlayView 退出时调用）
## 同步清空 _cached_*，避免单 slot 缓存常驻（约 3-15 MB GameSequence + 引用数组）
## 下次进入 PlayView 时 generate_keys 会重新生成并填充缓存
func clear_sequences() -> void:
	game_sequences.clear()
	background_sequences.clear()
	all_notes.clear()
	next_key_id = 0
	current_midi_data = null
	# 同步清空单 slot 缓存，避免 PlayView 退出后僵尸内存驻留
	_cache_key = ""
	_cached_sequences.clear()
	_cached_background_sequences.clear()
	_cached_manual_notes.clear()
	_cached_auto_notes.clear()
	# 同步清空 BPM 时间线相关的查找缓存（6 万音符 MIDI 的 _tick_ms_cache 可达 5-12 MB）
	# set_midi_time_parameters 下次调用时会重建 _bpm_lookup 与 _tick_ms_cache
	_tick_ms_cache.clear()
	_bpm_lookup.clear()
	bpm_timeline.clear()

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
	# 任何影响音符生成的配置变更都应清除缓存，避免返回旧结果
	# 同步清空 _cached_* 释放内存，否则旧 GameSequence 会常驻（_cache_key="" 但数组仍持有引用）
	_cache_key = ""
	_cached_sequences.clear()
	_cached_background_sequences.clear()
	_cached_manual_notes.clear()
	_cached_auto_notes.clear()

	# 处理 Lane 相关配置变更
	if section == "Lane":
		match key:
			"lane_count":
				lane_count = int(value)
				GLogger.info("Lane count changed to: %d" % lane_count, "KeySequenceManager")
				# 如果已经有生成的键，需要重新生成
				if not game_sequences.is_empty():
					GLogger.warning("Lane count changed while sequences exist, regeneration may be needed", "KeySequenceManager")
			
			"keyboard_mode":
				var keyboard_mode_enabled = int(value) == 1
				var config_manager = ConfigManager.instance
				if keyboard_mode_enabled:
					max_touch_move_velocity = 999999.0
					# 键盘模式下，有效轨道数 = 键盘按键数
					var keyboard_keys_str = config_manager.get_string("Lane", "keyboard_mode_keys", "A,S,D,F,J,K,L,;")
					var key_map = ConfigParser.parse_keyboard_keys(keyboard_keys_str)
					if key_map.size() > 0:
						lane_count = key_map.size()
					GLogger.info("Keyboard mode enabled: max_touch_move_velocity set to unlimited, lane_count adjusted to %d" % lane_count, "KeySequenceManager")
				else:
					# 恢复到配置中的值
					max_touch_move_velocity = config_manager.get_float("Generator", "max_touch_move_speed", 500.0)
					lane_count = config_manager.get_int("Lane", "lane_count", 12)
					GLogger.info("Keyboard mode disabled: max_touch_move_velocity restored to %.1f, lane_count restored to %d" % [max_touch_move_velocity, lane_count], "KeySequenceManager")
			
			"keyboard_mode_keys":
				# 键盘模式下键位变更时同步更新轨道数
				if ConfigManager.instance.get_int("Lane", "keyboard_mode", 0) == 1:
					var new_keys = ConfigParser.parse_keyboard_keys(str(value))
					if new_keys.size() > 0:
						lane_count = new_keys.size()
					GLogger.info("Keyboard mode keys changed: lane_count updated to %d" % lane_count, "KeySequenceManager")
	
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
					GLogger.info("Ignored max_touch_move_speed change (keyboard mode active)", "KeySequenceManager")
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

	# 处理 Judge 相关配置变更
	elif section == "Judge":
		match key:
			"min_block_spacing":
				min_block_spacing = _validate_min_block_spacing(int(value))
				GLogger.info("Min block spacing changed to: %d" % min_block_spacing, "KeySequenceManager")
