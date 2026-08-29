## 键序列管理器
## 负责将MIDI Note分类为gameSequences和backgroundSequences
## 以及生成游戏键位的映射
extends Node

class_name KeySequenceManager

## 块类型枚举（与 ScoreCalculator.BlockType / FlowNote.NoteType 保持同名同值）
enum BlockType {
	Block = 0,  # 点块（duration <= short_block_threshold）
	Slide = 1,  # 滑块（duration <= instant_block_threshold）
	Long = 2    # 长条（duration > short_block_threshold，需按住）
}

## 单例实例
static var instance: KeySequenceManager

## 游戏序列（玩家操作的键）
class GameSequence:
	var key_id: int             # 生成的键ID
	var pitch: int              # MIDI音符号（主要pitch）
	var start_time_ms: float    # 开始时间
	var duration_ms: float      # 持续时间
	var screen_x: float         # 屏幕X位置（键盘映射）
	var octave: int             # 八度
	var velocity: int           # 力度
	var block_type: int = BlockType.Block  # 块类型（Block/Slide/Long）
	var pitch_list: Array[int] = []  # 同lane合并的所有pitch列表（便于同时发出多个音）
	var connected_prev: bool = false  # 是否与前一块连接
	var original_notes: Array[MidiParser.NoteEvent] = []  # 保留该块包含的原始 NoteEvent 列表
	var flow_note_ref: Object = null  # 新增：指向对应的FlowArea.Note（演奏模式使用）
	var lane: int = -1  # 视觉轨道索引（可能因 max_touch_move_velocity 限制而偏离 pitch % lane_count）
	
	func _init(key: int, p: int, start: float, dur: float, x: float, oct: int, vel: int) -> void:
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
	var type: int = BlockType.Block  # 判定后的块类型
	var slide_forced: bool = false  # 由长条覆盖/手指预算在分组阶段强制为 Slide，判型时不再改判
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
	var last_press_block: BlockInfo = null  # 最后按下的块对象（含长条，占用期统一用其 end 表达）
	# 手部模型字段
	var hand: int = 1  # 0=左手, 1=右手, -1=无归属（键盘模式或max_touch_count=1）
	var home_x: float = 0.0  # 当前绑定的原位X坐标
	var hand_home_positions: Array[float] = []  # 本手所有原位X列表

	func _init(idx: int) -> void:
		index = idx
		is_free = true
		last_press_x = 0.0
		last_press_time_ms = -INF
		last_press_block = null
		hand = 1
		home_x = 0.0
		hand_home_positions = []

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
var density_cap_per_sec: int = 8  # 音符生成密度上限（每 1 秒最多保留的按压时刻组数；0 = 跳过密度削减）
var instant_block_threshold: float = 0.2  # 滑块(Slide)时长阈值（秒）；配置键保持旧名 instant_block_max_time
var short_block_threshold: float = 1.0  # 点块(Block)时长阈值（秒）；配置键保持旧名 short_block_max_time
var min_tap_interval: float = 1.0  # 最小敲击间隔（秒）
var cooldown_seconds: float = 2.0  # 触点冷却时间（秒）
var max_touch_move_velocity: float = 300.0  # 最大触点移动速度（像素/秒）
var max_touch_count: int = 2  # 最大同时活跃键数
var generate_instant_connect: bool = true  # 是否生成滑块(Slide)连块；配置键保持旧名
var generate_short_connect: bool = true  # 是否生成点块(Block)连块；配置键保持旧名
var max_instant_connect_seconds: float = 1.0  # 滑块(Slide)连块最大间隔（秒）；配置键保持旧名
var min_block_spacing: int = 1  # 并排音符最小横向间距（轨道数，0=关闭）

# ========== 手部模型常量 ==========
const HOME_BIAS_COEFF: float = 0.4  # 原位偏好系数：偏离原位的惩罚权重
const CROSS_HAND_PENALTY_MULT: float = 2.0  # 跨手惩罚倍数（× screen_width）
var hand_model_enabled: bool = true  # 手部模型是否启用（键盘模式关闭）

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
	density_cap_per_sec = config_manager.get_int(gen_cfg, "max_block_coalesce_time", 8)

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
		hand_model_enabled = false  # 键盘模式禁用手部模型
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
		"KeyGeneration config loaded: density=%d/sec, slide=%.2fs, block=%.2fs, maxTouch=%d, max_touch_velocity=%.1f, min_block_spacing=%d" %
		[density_cap_per_sec, instant_block_threshold, short_block_threshold, max_touch_count, max_touch_move_velocity, min_block_spacing],
		"KeySequenceManager"
	)
func classify_sequences(midi_data: MidiData, all_midi_notes: Array) -> bool:
	if midi_data == null or all_midi_notes.is_empty():
		return false
	
	current_midi_data = midi_data
	all_notes = all_midi_notes
	
	# 清空之前的分类
	game_sequences = []
	background_sequences = []
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
func generate_keys(game_notes: Array, midi_id: String = "", enabled_pairs: Dictionary = {}, timebase: int = -1, bpm_timeline_data: Array = []) -> bool:
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
		# 命中缓存：直接共享缓存引用（不深拷贝）。
		# 原因：深拷贝原先在本 worker 内克隆共享数组，会与主线程清缓存并发读到被截短的
		# 同一数组 → "Out of bounds get index" 越界。改为共享后，需要独立可写副本的消费方
		# （如 PlayView 改写 flow_note_ref）在各自准备阶段自行 clone_game_sequences()，
		# 克隆移出 worker 后不再并发读共享缓存，越界问题结构性消除，也省去预览路径的多余拷贝
		game_sequences = _cached_sequences
		background_sequences = _cached_background_sequences
		last_manual_control_notes = _cached_manual_notes
		last_auto_play_notes = _cached_auto_notes
		GLogger.debug("generate_keys HIT cache, share %d sequences" % game_sequences.size(), "KSM")
		return true
	GLogger.debug("generate_keys MISS cache, regenerating...", "KSM")
	if game_notes.is_empty():
		game_sequences = []
		return true

	# 缓存与运行态解耦：重建为新数组对象，而非 clear()。
	# 原因：_cached_* 与 game_* 引用共享同一对象，若用 clear() 就地清空，会把 _cached_sequences 仍指向的上一次缓存对象一并清空
	game_sequences = []
	background_sequences = []
	last_manual_control_notes = []
	last_auto_play_notes = []
	next_key_id = 0

	# 获取时间参数：显式传入（midi 自己的 timebase/bpm_timeline）优先，否则回退读 MidiPlaybackManager
	# 旧实现 MidiListItem 靠临时改写 pm.bpm_timeline/midi_timebase 全局字段喂参，
	# 与 PlayView.load_midi 的写入交错会产生竞态（生成用错时间线 → 音符缺失/错位）
	var midi_mgr = MidiPlaybackManager.instance
	if timebase <= 0:
		timebase = midi_mgr.midi_timebase if midi_mgr != null else 480
	if bpm_timeline_data.is_empty() and midi_mgr != null:
		bpm_timeline_data = midi_mgr.bpm_timeline
	set_midi_time_parameters(timebase, bpm_timeline_data)

	# Step 1~3: 直接消费已按 start_time 有序的 game_notes，按按压时刻分组 → 同轨去重 → 间距/数量约束
	# 毫秒值在分组时经 _tick_ms_cache 即时换算，省去中间 TempNote 数组与一趟全量转换循环
	var all_blocks: Array[BlockInfo] = []
	var bg_notes: Array = []
	_build_chords(game_notes, all_blocks, bg_notes)

	# Step 3.5: 立即释放分组建的 _tick_ms_cache（可达 5-12MB），后续高开销步骤不再需要
	# _tick_ms_cache 在 Step 8 背景排序时经 _get_note_start_time_ms 会按需重建
	_tick_ms_cache.clear()

	# Step 5: 虚拟触点匹配和块类型判定（Step C + Step D)
	_assign_touches_and_judge_types(all_blocks, bg_notes)

	# Step 5.5: 密度削减（后置）——触点判定拿到真实块类型后，按每秒按压时刻组数控制密度
	_reduce_density_by_second(all_blocks, bg_notes)

	# Step 6: 连块生成（Step E）
	_generate_connects(all_blocks)

	# Step 7: 转换为GameSequence集合
	_convert_blocks_to_game_sequences(all_blocks)

	# Step 7.5: 释放 all_blocks（GameSequence 已持有 original_notes 引用）
	# 必须先断开 prev_block 链：_judge_block_type 跨批次累积形成的 prev_block 链可能上万节点，
	# 原实现每间隔 2000 个块断一个并不能保证切断跳跃型长链（该链可能指回很早的块），
	# 此处在 clear() 前线性遍历全断 prev_block，避免引用计数级联析构（A→B→C→...）导致 Android ARM 栈溢出
	for _block in all_blocks:
		_block.prev_block = null
	all_blocks.clear()
	all_blocks = []

	# Step 8: 添加背景序列（与Unity一致：输出单一背景序列）
	var bg_count := bg_notes.size()
	var bg_times := PackedFloat32Array()
	bg_times.resize(bg_count)
	for i in range(bg_count):
		bg_times[i] = _get_note_start_time_ms(bg_notes[i])
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
	# game_sequences/background_sequences/last_* 在此后不再修改；
	# 下次 generate_keys 命中缓存时直接共享本引用（见上方 cache hit 分支）。
	# 需要独立可写副本的消费方（PlayView）在准备阶段自行 clone_game_sequences()，
	# 此处保证 _cached_* 引用的内容本身不被外部修改
	_cache_key = cache_key
	_cached_sequences = game_sequences
	_cached_background_sequences = background_sequences
	_cached_manual_notes = last_manual_control_notes
	_cached_auto_notes = last_auto_play_notes

	return true

## 深拷贝 GameSequence 数组（由 clone_game_sequences 调用，给消费方独立副本，避免污染共享缓存）
## 返回类型必须与 game_sequences 一致（Array[GameSequence]），否则克隆赋值会报
## "Trying to assign an array of type Array to a variable of type Array[GameSequence]"
func _clone_game_sequences(src: Array[GameSequence]) -> Array[GameSequence]:
	var result: Array[GameSequence] = []
	result.resize(src.size())
	for i in range(src.size()):
		var s: GameSequence = src[i]
		var c := GameSequence.new(s.key_id, s.pitch, s.start_time_ms, s.duration_ms, s.screen_x, s.octave, s.velocity)
		c.block_type = s.block_type
		c.pitch_list = s.pitch_list.duplicate()
		c.connected_prev = s.connected_prev
		c.original_notes = s.original_notes.duplicate()
		c.lane = s.lane
		# flow_note_ref 不复制：由消费方按需设置，避免残留引用污染
		result[i] = c
	return result

## 单任务模式：同一时间只允许一个 generate_keys worker 运行
## 新任务启动前必须等待旧任务完成（防止并发写入 game_sequences 等共享字段）
## ⚠️ WorkerThreadPool 语义（Godot 引擎 worker_thread_pool.cpp）：
##   - wait_for_task_completion() 会在任务完成后把该任务从线程池移除，之后同一 task_id
##     立即失效，再调 is_task_completed()/wait_for_task_completion() 会报 "Invalid Task ID"。
##   - 因此约定：① join 恰好一次，且全文件唯一 join 点是 _finalize_task；
##     ② 等待方只轮询"任务槽 _generate_task_id 是否清空"，绝不轮询旧任务 id；
##     ③ is_task_completed() 只能用于"尚未 join、仍在自己手上的任务 id"。
##   - 旧版共享 "_done" 标志会被多个等待方（MidiListItem 统计 + PlayView 生成）同时消费，
##     各自清标志/各自起新任务 → 两个 worker 并发写 game_sequences/_cached_sequences（数据竞争）
var _generate_task_id: int = -1

## join 指定任务并清空任务槽（幂等：仅当该任务仍是当前槽任务时才 join + 清槽；
## 避免旧等待方 join 到他人新启动的任务，或对已移除的任务重复 join）
func _finalize_task(task_id: int) -> void:
	if task_id == -1:
		return
	if _generate_task_id == task_id:
		WorkerThreadPool.wait_for_task_completion(task_id)
		_generate_task_id = -1

## 串行启动一个 generate_keys worker：等待任务槽清空
## （旧任务由它的 join 方清理后 _generate_task_id 才回到 -1，因此这里只轮询槽、不碰任务 id）
## 返回新任务 task_id
func _launch_generate_task(run: Callable) -> int:
	while _generate_task_id != -1:
		await Engine.get_main_loop().process_frame
	var task_id := WorkerThreadPool.add_task(run, false, "KSM generate_keys")
	_generate_task_id = task_id
	return task_id

## 启动 generate_keys（WorkerThreadPool 后台线程执行，保留 async 签名以兼容调用方 await）
## 线程安全：generate_keys 仅访问 self 字段与 MidiPlaybackManager.instance 静态字段，不访问场景树
## RefCounted 对象（BlockInfo/GameSequence）在 worker 创建/析构安全：
##   - prev_block 链在 Step 7.5 已断开，避免级联析构栈溢出
##   - GLogger 已用 call_deferred 保护，无 StringName 引用计数竞态
## timebase/bpm_timeline_data：显式时间参数（调用方直接给 midi 自己的值），
## 避免依赖/改写 MidiPlaybackManager 的全局时间线字段（见 generate_keys）
## 返回值：task_id（-1 表示未启动，如 game_notes 为空）
func start_generate_keys_async(game_notes: Array, midi_id: String = "", enabled_pairs: Dictionary = {}, timebase: int = -1, bpm_timeline_data: Array = []) -> int:
	# 空数组时主线程同步清理 game_sequences（与 generate_keys_async 行为一致）
	if game_notes.is_empty():
		generate_keys(game_notes, midi_id, enabled_pairs, timebase, bpm_timeline_data)
		return -1
	# 启动 worker 线程（_launch_generate_task 内部串行等待旧任务，避免并发写入共享字段）
	return await _launch_generate_task(func():
		generate_keys(game_notes, midi_id, enabled_pairs, timebase, bpm_timeline_data)
	)

## 等待 generate_keys 完成（每帧让出主线程，动画继续推进）
## 按任务 id 精确等待：该 id 在本函数 join 前不会被移除（同一任务只 await 一次）
func await_generate_keys(task_id: int) -> void:
	if task_id == -1:
		return
	while not WorkerThreadPool.is_task_completed(task_id):
		await Engine.get_main_loop().process_frame
	_finalize_task(task_id)
	# 再等任务槽清空：若期间已有后续任务（如 MidiListItem 统计）开始重建共享
	# game_sequences，调用方紧接着读共享结果时可能读到半个重建中的数组
	while _generate_task_id != -1:
		await Engine.get_main_loop().process_frame

## 异步生成游戏键（WorkerThreadPool 后台线程执行，保留 async 签名以兼容调用方 await）
## 线程安全：同 start_generate_keys_async
## 代价：66k 音符时 worker 约跑 200-800ms，主线程每帧让出不卡顿（命中缓存时 0ms）
func generate_keys_async(game_notes: Array, midi_id: String = "", enabled_pairs: Dictionary = {}, timebase: int = -1, bpm_timeline_data: Array = []) -> bool:
	# 空数组快速路径：主线程直接执行（generate_keys 内部仅 clear）
	if game_notes.is_empty():
		generate_keys(game_notes, midi_id, enabled_pairs, timebase, bpm_timeline_data)
		return true
	# 启动 worker 线程（内部串行等待旧任务）并等待完成
	var task_id := await _launch_generate_task(func():
		generate_keys(game_notes, midi_id, enabled_pairs, timebase, bpm_timeline_data)
	)
	await await_generate_keys(task_id)
	return true

## 同刻和弦合并容差（毫秒）：两个音符开始时间差 <= 该值视为"同刻"（并列落下）
const CHORD_TOLERANCE_MS: float = 10.0

## Step A/B 替代实现（单趟流式）+ 长条覆盖导致的 Slide 判定：
## 直接消费已按 start_time 有序的 NoteEvent，按"按压时刻"分组（≈10ms 同刻=和弦，同轨去重保高音）
## 毫秒值经 _tick_ms_cache 即时换算（同 tick 只真正算一次），省去中间 TempNote 数组
## 每个和弦内执行最小横向间距 + 手指预算（同刻可操作音符 Block+Slide 总数 ≤ max_touch_count，
## 进行中长条不占名额；超出优先移除普通 Block 再移除 Slide；有长条时就近把普通转 Slide 便于操作）
## 长条覆盖判定：维护每条轨道的"进行中长条结束时间"数组，同轨音符起始时间在长条结束前 → 强制 Slide
## 顺序保证：先定去留（去重/间距/预算），确认保留后才注册长条 → 被剔入背景的长条不会残留脏状态
## 数组为局部作用域，分组结束自动释放；密度削减仍后置在触点判定后（_reduce_density_by_second）
func _build_chords(game_notes: Array, all_blocks: Array, bg_notes: Array) -> void:
	if game_notes.is_empty():
		return
	var n: int = game_notes.size()
	var i: int = 0
	var chord_idx: int = 0
	# 每条轨道的进行中长条结束时间（-1 = 无进行中长条）
	var lane_long_end := PackedFloat32Array()
	lane_long_end.resize(lane_count)
	lane_long_end.fill(-1.0)
	while i < n:
		var chord_note: MidiParser.NoteEvent = game_notes[i]
		var chord_start: float = _tick_to_ms(chord_note.start_time)
		# 计数此刻仍进行中的长条（先前已确认保留的长条）
		var active_longs: int = 0
		for l in range(lane_count):
			if lane_long_end[l] > chord_start:
				active_longs += 1
		# 同刻合并 + 同 lane 去重（同 lane 保留高音，低音移入背景）
		var lane_map: Dictionary = {}
		var j: int = i
		while j < n:
			var note: MidiParser.NoteEvent = game_notes[j]
			if _tick_to_ms(note.start_time) - chord_start > CHORD_TOLERANCE_MS:
				break
			var lane: int = note.pitch % lane_count
			if lane_map.has(lane):
				var existing: MidiParser.NoteEvent = lane_map[lane]
				if note.pitch > existing.pitch:
					_append_note_to_background(existing, bg_notes)
					lane_map[lane] = note
				else:
					_append_note_to_background(note, bg_notes)
			else:
				lane_map[lane] = note
			j += 1
		i = j
		if lane_map.is_empty():
			continue
		# 为和弦内保留音符建 BlockInfo（batch = 和弦索引）
		var chord_blocks: Array[BlockInfo] = []
		for lane in lane_map.keys():
			var note: MidiParser.NoteEvent = lane_map[lane]
			var start_ms: float = _tick_to_ms(note.start_time)
			var dur_ms: float = _tick_duration_to_ms(note.start_time, note.duration)
			var block := BlockInfo.new()
			block.batch = chord_idx
			block.notes.append(note)
			block.lane = lane
			block.start_time_ms = start_ms
			block.end_time_ms = start_ms + dur_ms
			block.duration_ms = dur_ms
			block.pitch_list.append(note.pitch)
			block.x = _calculate_lane_position(lane)
			# 同轨进行中的长条覆盖到本时刻 → 强制 Slide（几何+时间判据，与手指分配解耦）
			if lane_long_end[lane] > start_ms:
				block.slide_forced = true
				block.type = BlockType.Slide
			chord_blocks.append(block)
		# 最小横向间距（仍可能剔除到背景）
		chord_blocks = _enforce_min_lane_spacing(chord_blocks, bg_notes)
		# 手指预算（同刻总数口径；进行中长条不占名额）：
		# 1) 有进行中长条时，就近把紧邻长条的普通音符转 Slide，减少玩家从长条滑动的距离（不增名额）
		# 2) 同刻可操作音符总数（普通 Block + Slide，含长条覆盖/就近转的）≤ max_touch_count
		#    超出按序移除：优先移除普通 Block（低音先删），仍超出再移除 Slide，保证几何/长条相关 Slide 尽量保留
		if max_touch_count > 0 and not chord_blocks.is_empty():
			# (1) 就近转 Slide
			if active_longs > 0:
				var active_long_lanes: Array[int] = []
				for l in range(lane_count):
					if lane_long_end[l] > chord_start:
						active_long_lanes.append(l)
				if not active_long_lanes.is_empty():
					var normals: Array[BlockInfo] = []
					for b2 in chord_blocks:
						if b2.type != BlockType.Slide:
							normals.append(b2)
					if not normals.is_empty():
						normals.sort_custom(func(a, b):
							return _min_lane_dist_to_longs(a.lane, active_long_lanes) < _min_lane_dist_to_longs(b.lane, active_long_lanes))
						var to_slide: int = mini(active_longs, normals.size())
						for k in range(to_slide):
							normals[k].slide_forced = true
							normals[k].type = BlockType.Slide
			# (2) 总数上限：普通 + Slide ≤ max_touch_count，超出移除（先普通后 Slide，均低音优先）
			if chord_blocks.size() > max_touch_count:
				var need_remove: int = chord_blocks.size() - max_touch_count
				var ordinary: Array[BlockInfo] = []
				for b2 in chord_blocks:
					if not b2.slide_forced:
						ordinary.append(b2)
				ordinary.sort_custom(func(a, b): return a.pitch_list[0] < b.pitch_list[0])  # 音高升序→低音先删
				for eb in ordinary:
					if need_remove <= 0:
						break
					if not eb.notes.is_empty():
						_append_note_to_background(eb.notes[0], bg_notes)
					chord_blocks.erase(eb)
					need_remove -= 1
				# 仍超出 → 移除 Slide（保证几何/长条 Slide 尽量保留）
				while need_remove > 0:
					var slides: Array[BlockInfo] = []
					for b2 in chord_blocks:
						if b2.slide_forced:
							slides.append(b2)
					if slides.is_empty():
						break
					slides.sort_custom(func(a, b): return a.pitch_list[0] < b.pitch_list[0])
					var eb: BlockInfo = slides[0]
					if not eb.notes.is_empty():
						_append_note_to_background(eb.notes[0], bg_notes)
					chord_blocks.erase(eb)
					need_remove -= 1
		if chord_blocks.is_empty():
			continue
		# 注册进行中的长条（仅在确认保留且非 Slide 后进行）
		for b3 in chord_blocks:
			if b3.type != BlockType.Slide and b3.duration_ms / 1000.0 > short_block_threshold:
				lane_long_end[b3.lane] = b3.end_time_ms
		all_blocks.append_array(chord_blocks)
		chord_idx += 1

## 计算某轨道到最近进行中长条轨道的最小距离（用于长条占手转 Slide 的就近选择）
func _min_lane_dist_to_longs(lane: int, long_lanes: Array[int]) -> int:
	var best := 1 << 30
	for ll in long_lanes:
		var d: int = absi(lane - ll)
		if d < best:
			best = d
	return best

## 密度削减（后置）：在触点判定拿到真实块类型后，按每秒按压时刻组数控制密度
## - 每秒总预算 = density_cap（普通块当量），Slide 计 0.33，Block/Long 计 1.0
##   （slide 容易打 → 占预算少 → 纯 slide 一秒最多可达 cap/0.33 组）
## - 先按等距时间槽取每槽 prio 最高的组作均匀骨架；超预算优先剔全 slide 组再按 prio 升序剔其余，富余按 prio 降序补入
## - 被剔除的整组移入背景。注意：这些组已完成触点判定，会留下 last_press/prev_block 等副作用
##   （方向上是"难按的连打顺延被判为滑键"，实际更好打，代价最小）
func _reduce_density_by_second(all_blocks: Array, bg_notes: Array) -> void:
	if density_cap_per_sec <= 0 or all_blocks.is_empty():
		return
	var budget: float = float(density_cap_per_sec)
	# 按 batch（同批=同按压时刻组）聚合块，并算每组真实 cost/prio
	var groups_by_batch: Dictionary = {}  # batch -> {blocks, time, cost, prio}
	for b in all_blocks:
		if not groups_by_batch.has(b.batch):
			groups_by_batch[b.batch] = {"blocks": [], "time": b.start_time_ms}
		groups_by_batch[b.batch]["blocks"].append(b)
	# 按秒桶聚合组
	var second_groups: Dictionary = {}  # sec -> Array[组]
	for batch in groups_by_batch.keys():
		var g: Dictionary = groups_by_batch[batch]
		# Dictionary 取值会丢失 Array[BlockInfo] 元素类型，手动转 typed 再传入
		var typed_blocks: Array[BlockInfo] = []
		for blk: BlockInfo in g["blocks"]:
			typed_blocks.append(blk)
		var metrics: Dictionary = _compute_chord_metrics(typed_blocks)
		g["cost"] = metrics["cost"]
		g["prio"] = metrics["prio"]
		g["slide_only"] = metrics["slide_only"]  # 记录全 slide 标记，超预算剔除时优先删
		var sec: int = int(floor(g["time"] / 1000.0))
		if not second_groups.has(sec):
			second_groups[sec] = []
		second_groups[sec].append(g)
	# 每秒骨架 + 预算决定去留
	var kept_batches: Dictionary = {}  # batch -> true
	for sec in second_groups.keys():
		var groups: Array = second_groups[sec]
		var slot_w: float = 1000.0 / budget
		var n_slots: int = density_cap_per_sec
		# 骨架：每槽保留 prio 最高的组，保证均匀覆盖
		var skeleton: Dictionary = {}  # slot -> 组索引
		for idx in range(groups.size()):
			var g: Dictionary = groups[idx]
			var t_in_sec: float = g["time"] - sec * 1000.0
			var slot: int = int(minf(floor(t_in_sec / slot_w), n_slots - 1))
			if not skeleton.has(slot) or g["prio"] > groups[skeleton[slot]]["prio"]:
				skeleton[slot] = idx
		var kept_idx: Dictionary = {}
		var total_cost: float = 0.0
		for slot in skeleton.keys():
			var idx: int = skeleton[slot]
			kept_idx[idx] = true
			total_cost += groups[idx]["cost"]
		# 超预算：优先剔除全 slide 组（易打、删了损失小），不足再按 prio 升序剔除非 slide 组
		if total_cost > budget:
			var slide_eject: Array = []
			var non_slide_eject: Array = []
			for idx in kept_idx.keys():
				if groups[idx]["slide_only"]:
					slide_eject.append(idx)
				else:
					non_slide_eject.append(idx)
			# 第一轮：剔全 slide 组（prio 升序，先剔最没保留价值的）
			slide_eject.sort_custom(func(a, b): return groups[a]["prio"] < groups[b]["prio"])
			for idx in slide_eject:
				if total_cost <= budget:
					break
				if not kept_idx.has(idx):
					continue
				kept_idx.erase(idx)
				total_cost -= groups[idx]["cost"]
			# 仍超预算：剔非 slide 组（prio 升序）
			if total_cost > budget:
				non_slide_eject.sort_custom(func(a, b): return groups[a]["prio"] < groups[b]["prio"])
				for idx in non_slide_eject:
					if total_cost <= budget:
						break
					if not kept_idx.has(idx):
						continue
					kept_idx.erase(idx)
					total_cost -= groups[idx]["cost"]
		# 富余（主要是 slide 空出的预算）：按 prio 降序补入剩余组
		if total_cost < budget:
			var remainder: float = budget - total_cost
			var candidates: Array = []
			for idx in range(groups.size()):
				if kept_idx.has(idx) or groups[idx]["cost"] > remainder:
					continue
				candidates.append(idx)
			candidates.sort_custom(func(a, b): return groups[a]["prio"] > groups[b]["prio"])
			for idx in candidates:
				if groups[idx]["cost"] <= remainder:
					kept_idx[idx] = true
					total_cost += groups[idx]["cost"]
					remainder -= groups[idx]["cost"]
		# 记录本秒保留的 batch
		for idx in kept_idx.keys():
			for b in groups[idx]["blocks"]:
				kept_batches[b.batch] = true
	# 过滤 all_blocks，被剔除的和弦整体移入背景
	var write_idx: int = 0
	for b in all_blocks:
		if kept_batches.has(b.batch):
			all_blocks[write_idx] = b
			write_idx += 1
		else:
			for note in b.notes:
				_append_note_to_background(note, bg_notes)
	all_blocks.resize(write_idx)

## 计算一个按压时刻组（和弦）的当量与保留优先级（基于触点判定后的真实块类型）
## cost（占预算）：Slide 计 0.33，Block/Long 计 1.0（slide 好打 → 占预算少 → 能出现更多）
## prio（保留优先级，越高越优先保留）：
##   1.5×(平均力度/127) + 1.5×(最大音高/127) - 0.3×(并排普通块数-1)
##   （音/音高提权 1.5 保主旋律；并排普通块略降权 → 更难按的越靠后被剔）
func _compute_chord_metrics(blocks: Array[BlockInfo]) -> Dictionary:
	var count: int = blocks.size()
	if count == 0:
		return {"cost": 0.0, "prio": 0.0}
	var cost: float = 0.0
	var vel_sum: int = 0
	var max_pitch: int = 0
	var non_slide_cnt: int = 0
	for b in blocks:
		var is_slide: bool = b.type == BlockType.Slide
		cost += 0.33 if is_slide else 1.0
		if not is_slide:
			non_slide_cnt += 1
		if not b.notes.is_empty():
			vel_sum += b.notes[0].velocity
		if not b.pitch_list.is_empty() and b.pitch_list[0] > max_pitch:
			max_pitch = b.pitch_list[0]
	var avg_vel: float = float(vel_sum) / float(count)
	var prio: float = 1.5 * avg_vel / 127.0 + 1.5 * float(max_pitch) / 127.0
	prio -= 0.3 * float(max(0, non_slide_cnt - 1))
	# slide_only：整组全是 slide（易打、删了损失小）→ 超预算剔除时优先删
	return {"cost": cost, "prio": prio, "slide_only": non_slide_cnt == 0}

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
	
	# 初始化虚拟触点（含手部归属与原位分配）
	var touches: Array[VirtualTouch] = _init_touches_with_hands()

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

## 虚拟触点匹配 - 迭代枚举所有严格递增触点组合，找成本最小的分配方案
## 替代原递归回溯 _find_optimal_matching：用字典序组合枚举避免调用栈问题（Android 大音符量崩溃）
## 原递归语义：枚举所有 C(n_touches, n_blocks) 个严格递增触点索引序列，
## 仅完整分配（所有块都有触点）才计算成本；块数 > 触点数时全 -1
## 手部模型：跨手重罚、原位偏好；第一遍带硬约束剪枝（冷却+速度），无解时回退纯软惩罚兜底
func _match_blocks_to_touches(blocks_in_group: Array[BlockInfo], touches: Array[VirtualTouch]) -> void:
	if blocks_in_group.is_empty():
		return

	# 按X位置排序块（左→右，与触点递增索引对应：左手触点在前，右手在后）
	var sorted_blocks = blocks_in_group.duplicate()
	sorted_blocks.sort_custom(func(a, b): return a.x < b.x)

	var n_blocks: int = sorted_blocks.size()
	var n_touches: int = touches.size()

	# 初始化最优匹配跟踪（全 -1 表示未分配）
	var min_matching_touch_index: Array = []
	min_matching_touch_index.resize(n_blocks)
	for i in range(n_blocks):
		min_matching_touch_index[i] = -1

	# 块数 > 触点数时无法为所有块分配触点（与原递归行为一致：全 -1）
	if n_blocks > n_touches:
		sorted_blocks.sort_custom(func(a, b):
			return a.start_time_ms < b.start_time_ms
		)
		for i in range(n_blocks):
			sorted_blocks[i].touch_index = -1
		return

	# 第一遍：带硬约束（冷却+速度），跳过不满足约束的组合
	var found_valid = _enumerate_match_pass(sorted_blocks, touches, true, min_matching_touch_index)

	# 回退：硬约束过严导致无解时，不带硬约束（仅软惩罚）再跑一遍，保证总有解
	if not found_valid:
		for i in range(n_blocks):
			min_matching_touch_index[i] = -1
		_enumerate_match_pass(sorted_blocks, touches, false, min_matching_touch_index)

	# Unity bug: 匹配结果按start_time顺序应用（而非x顺序）
	# 这会导致当批次中有2个块且x顺序与start_time顺序不一致时，
	# touch_index被错误地分配给不同的块
	sorted_blocks.sort_custom(func(a, b):
		return a.start_time_ms < b.start_time_ms
	)

	# 应用最优分配
	for i in range(n_blocks):
		sorted_blocks[i].touch_index = min_matching_touch_index[i]

## 单次字典序组合枚举：找成本最小的完整分配方案
## use_hard_constraint=true 时跳过任一分配不满足冷却/速度约束的组合（剪枝）
## 成本 = 移动距离 + 速度违规惩罚 + 跨手惩罚 + 偏离原位惩罚
## 返回是否找到至少一个有效完整分配；最优组合写入 out_matching
func _enumerate_match_pass(
	sorted_blocks: Array,
	touches: Array[VirtualTouch],
	use_hard_constraint: bool,
	out_matching: Array
) -> bool:
	var k: int = sorted_blocks.size()
	var n_touches: int = touches.size()

	# 组合以字典序生成：[0,1,...,k-1] → [0,1,...,k-2,k] → ... → [n-k,...,n-1]
	var combo: Array = []
	combo.resize(k)
	for i in range(k):
		combo[i] = i

	var min_cost: float = INF
	var found_valid: bool = false

	while true:
		# 硬约束剪枝：全部满足冷却+速度才作为候选
		if use_hard_constraint:
			var valid: bool = true
			for i in range(k):
				if not _can_assign_block_to_touch(sorted_blocks[i], touches[combo[i]]):
					valid = false
					break
			if not valid:
				# 跳过当前组合，直接生成下一个组合（字典序）
				var skip_idx: int = k - 1
				while skip_idx >= 0 and combo[skip_idx] == n_touches - k + skip_idx:
					skip_idx -= 1
				if skip_idx < 0:
					break
				combo[skip_idx] += 1
				for j in range(skip_idx + 1, k):
					combo[j] = combo[j - 1] + 1
				continue

		# 计算当前组合的成本
		var total_cost: float = 0.0
		for i in range(k):
			var blk: BlockInfo = sorted_blocks[i]
			var touch: VirtualTouch = touches[combo[i]]
			# 使用有效位置（含释放后回归原位）计算移动距离
			var touch_x = _get_touch_current_x(touch, blk.start_time_ms)
			var move_distance = abs(touch_x - blk.x)
			total_cost += move_distance
			# 速度违规惩罚：使匹配优先选择不超速的分配方案
			if touch.last_press_time_ms >= 0:
				var time_delta_sec = (blk.start_time_ms - touch.last_press_time_ms) / 1000.0
				if time_delta_sec > 0:
					var max_feasible = max_touch_move_velocity * time_delta_sec
					if move_distance > max_feasible:
						total_cost += (move_distance - max_feasible) * 10.0
			# 手部模型：跨手重罚 + 偏离原位惩罚
			if hand_model_enabled and touch.hand >= 0 and max_touch_count >= 2:
				var block_hand = _get_block_hand(blk.x)
				if block_hand != touch.hand:
					total_cost += screen_width * CROSS_HAND_PENALTY_MULT
				total_cost += abs(touch.home_x - blk.x) * HOME_BIAS_COEFF

		if total_cost < min_cost:
			min_cost = total_cost
			for i in range(k):
				out_matching[i] = combo[i]
			found_valid = true

		# 生成下一个组合（字典序）
		var idx: int = k - 1
		while idx >= 0 and combo[idx] == n_touches - k + idx:
			idx -= 1
		if idx < 0:
			break
		combo[idx] += 1
		for j in range(idx + 1, k):
			combo[j] = combo[j - 1] + 1

	return found_valid

## 检查块是否可以分配给该触点（考虑冷却和移动速度约束）
func _can_assign_block_to_touch(block: BlockInfo, touch: VirtualTouch) -> bool:
	# 如果touch为null，则允许（用于未分配情况）
	if touch == null:
		return true
	
	# 占用期 = 按下时刻 + 冷却
	if touch.last_press_time_ms >= 0:
		var occupy_end: float = touch.last_press_time_ms + (cooldown_seconds * 1000.0)
		if block.start_time_ms < occupy_end:
			return false
	
	# 检查移动速度约束（使用有效位置：含释放后回归原位）
	if touch.last_press_time_ms >= 0:
		var time_delta = (block.start_time_ms - touch.last_press_time_ms) / 1000.0
		if time_delta > 0:
			var touch_x = _get_touch_current_x(touch, block.start_time_ms)
			var distance = abs(block.x - touch_x)
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
	# 长条覆盖/手指预算已在 _build_chords 强制为 Slide，此处不再改判
	if block.slide_forced:
		block.type = BlockType.Slide
	elif duration_sec <= instant_block_threshold:
		block.type = BlockType.Slide
	elif duration_sec <= short_block_threshold:
		block.type = BlockType.Block
	else:
		block.type = BlockType.Long
	
	# ========== 第2步：检查占用期（触点可用性，统一模型） ==========
	# 占用期 = 按下时刻 + 冷却，与块类型无关
	if not touch.is_free:
		var occupy_end: float = touch.last_press_time_ms + (cooldown_seconds * 1000.0)
		if block.start_time_ms > occupy_end:
			touch.is_free = true
			touch.last_press_block = null
		else:
			# 触点仍被占用，连接到前一个块（用于连块判定）
			block.prev_block = touch.last_press_block

	# ========== 第2.5步：移动速度约束（对所有已使用触点生效，不论是否空闲） ==========
	# 修复：原实现仅在 not touch.is_free 时钳制，触点冷却释放后约束失效，
	# 导致短时间内音符水平偏移过远。现在只要触点曾经按下过就施加速度约束。
	# 使用有效位置（含释放后回归原位），与匹配阶段 _can_assign_block_to_touch 保持一致。
	if touch.last_press_time_ms >= 0:
		var time_delta_sec = (block.start_time_ms - touch.last_press_time_ms) / 1000.0
		if time_delta_sec > 0:
			var touch_x = _get_touch_current_x(touch, block.start_time_ms)
			var max_offset = max_touch_move_velocity * time_delta_sec
			var distance = abs(block.x - touch_x)
			if distance > max_offset:
				# 限制块位置：先按最大偏移钳制 x，再吸附到最近轨道中心
				if block.x > touch_x:
					block.x = touch_x + max_offset
				else:
					block.x = touch_x - max_offset
				# 同步更新 lane，使速度约束真正影响最终音符轨道
				block.lane = _calculate_lane_from_x(block.x)
				block.x = _calculate_lane_position(block.lane)
	
	# ========== 第4步：检查敲击间隔（minTapInterval） ==========
	if touch.last_press_time_ms >= 0:
		var gap = (block.start_time_ms - touch.last_press_time_ms) / 1000.0
		if gap < min_tap_interval:
			# ✅ 修正：强制为Slide（滑块）
			block.type = BlockType.Slide
	
	# ========== 第5步：更新触点状态 ==========
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

	# SlideConnect 对齐 Unity：基于触点前驱 prev_block 判定
	if generate_instant_connect:
		for block in blocks:
			var prev = block.prev_block
			if block.type == BlockType.Slide and prev != null and prev.type == BlockType.Slide:
				var gap = (block.start_time_ms - prev.start_time_ms) / 1000.0
				if gap <= max_instant_connect_seconds:
					block.connected_prev = true

	# BlockConnect 对齐 Unity：每个批次仅连接最左与最右块
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


## ========== 手部模型方法 ==========

## 初始化虚拟触点并分配手部归属与原位
func _init_touches_with_hands() -> Array[VirtualTouch]:
	var touches: Array[VirtualTouch] = []

	# 键盘模式或手部模型关闭：使用原有逻辑（无手部归属）
	if not hand_model_enabled or max_touch_count <= 0:
		for i in range(max_touch_count):
			touches.append(VirtualTouch.new(i))
		return touches

	# 每只手的原位数（各手均向上取整）
	var home_per_hand: int = ceili(float(max_touch_count) / 2.0)

	# 计算左右手的车道区域
	@warning_ignore("integer_division")
	var half_lane: int = lane_count / 2
	var left_lanes = _distribute_home_lanes(0, half_lane - 1, home_per_hand)
	var right_lanes = _distribute_home_lanes(half_lane, lane_count - 1, home_per_hand)

	# 转换为X坐标
	var left_home_xs: Array[float] = []
	for lane in left_lanes:
		left_home_xs.append(_calculate_lane_position(lane))
	var right_home_xs: Array[float] = []
	for lane in right_lanes:
		right_home_xs.append(_calculate_lane_position(lane))

	# 所有原位（max_touch_count=1 时单触点可使用双手原位）
	var all_home_xs: Array[float] = []
	all_home_xs.append_array(left_home_xs)
	all_home_xs.append_array(right_home_xs)

	if max_touch_count == 1:
		# 单触点：无手部归属，可使用所有原位
		var touch = VirtualTouch.new(0)
		touch.hand = -1
		touch.hand_home_positions = all_home_xs
		@warning_ignore("integer_division")
		touch.home_x = _calculate_lane_position(lane_count / 2)  # 屏幕中心
		touch.last_press_x = touch.home_x
		touches.append(touch)
		return touches

	# max_touch_count >= 2：按 ceil(left)/floor(right) 分配触点
	var left_count: int = ceili(float(max_touch_count) / 2.0)
	var right_count: int = max_touch_count - left_count

	var touch_idx = 0
	for i in range(left_count):
		var touch = VirtualTouch.new(touch_idx)
		touch.hand = 0  # 左手
		touch.hand_home_positions = left_home_xs.duplicate()
		touch.home_x = left_home_xs[mini(i, left_home_xs.size() - 1)]
		touch.last_press_x = touch.home_x
		touches.append(touch)
		touch_idx += 1
	for i in range(right_count):
		var touch = VirtualTouch.new(touch_idx)
		touch.hand = 1  # 右手
		touch.hand_home_positions = right_home_xs.duplicate()
		touch.home_x = right_home_xs[mini(i, right_home_xs.size() - 1)]
		touch.last_press_x = touch.home_x
		touches.append(touch)
		touch_idx += 1

	return touches

## 在车道区间 [lane_start, lane_end] 内均匀分布 count 个原位车道
func _distribute_home_lanes(lane_start: int, lane_end: int, count: int) -> Array[int]:
	var lanes: Array[int] = []
	if count <= 0 or lane_end < lane_start:
		return lanes
	if count == 1:
		@warning_ignore("integer_division")
		lanes.append((lane_start + lane_end) / 2)
		return lanes
	var span = lane_end - lane_start
	for i in range(count):
		var lane = lane_start + int(round(float(i) * float(span) / float(count - 1)))
		lanes.append(clampi(lane, lane_start, lane_end))
	return lanes

## 计算触点在指定时间的有效X位置（考虑释放后回归原位，不修改触点状态）
func _get_touch_current_x(touch: VirtualTouch, at_time_ms: float) -> float:
	if touch.last_press_time_ms < 0:
		return touch.home_x  # 从未使用过，在原位
	if not touch.is_free:
		return touch.last_press_x  # 占用中（含长条占用，is_free=false 期间位置不变）
	# 已释放：向最近原位回归
	if not hand_model_enabled or touch.hand_home_positions.is_empty():
		return touch.last_press_x  # 无原位模型
	var nearest_home = _get_nearest_home_x(touch, touch.last_press_x)
	var elapsed_sec = (at_time_ms - touch.last_press_time_ms) / 1000.0
	if elapsed_sec <= 0:
		return touch.last_press_x
	var max_offset = max_touch_move_velocity * elapsed_sec
	var distance = abs(nearest_home - touch.last_press_x)
	if distance <= max_offset:
		return nearest_home  # 已回到原位
	if nearest_home > touch.last_press_x:
		return touch.last_press_x + max_offset
	else:
		return touch.last_press_x - max_offset

## 获取触点本手原位池中距 from_x 最近的原位X
func _get_nearest_home_x(touch: VirtualTouch, from_x: float) -> float:
	if touch.hand_home_positions.is_empty():
		return touch.home_x
	var nearest = touch.hand_home_positions[0]
	var min_dist = abs(nearest - from_x)
	for hx in touch.hand_home_positions:
		var d = abs(hx - from_x)
		if d < min_dist:
			min_dist = d
			nearest = hx
	return nearest

## 判断块的X位置属于哪只手（0=左手, 1=右手）
func _get_block_hand(block_x: float) -> int:
	return 0 if block_x < screen_width * 0.5 else 1


## 深拷贝当前游戏序列为独立可写副本（消费方如 PlayView 改写 flow_note_ref 时调用，避免污染共享缓存）
## 仅主线程在 worker join 后调用（await_generate_keys 结束后），此时无 worker 并发读共享缓存
func clone_game_sequences() -> Array[GameSequence]:
	return _clone_game_sequences(game_sequences)

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
	game_sequences = []
	background_sequences = []
	all_notes = []
	next_key_id = 0
	current_midi_data = null
	# 同步清空单 slot 缓存，避免 PlayView 退出后僵尸内存驻留
	_cache_key = ""
	_cached_sequences = []
	_cached_background_sequences = []
	_cached_manual_notes = []
	_cached_auto_notes = []
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
	_cached_sequences = []
	_cached_background_sequences = []
	_cached_manual_notes = []
	_cached_auto_notes = []

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
				density_cap_per_sec = int(value)
	
	# 处理 Appearance 相关配置变更
	elif section == "Appearance":
		match key:
			"generate_short_connect":
				generate_short_connect = ConfigManager.parse_bool(value, true)
			"generate_instant_connect":
				generate_instant_connect = ConfigManager.parse_bool(value, true)
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
