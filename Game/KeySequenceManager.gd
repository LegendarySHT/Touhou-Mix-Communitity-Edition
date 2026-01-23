## 键序列管理器
## 负责将MIDI Note分类为gameSequences和backgroundSequences
## 以及生成游戏键位的映射
extends Node

class_name KeySequenceManager

## 单例实例
static var instance: KeySequenceManager

## 游戏序列（玩家操作的键）
class GameSequence:
	var note_index: int         # 原始Note在all_notes中的索引
	var key_id: int             # 生成的键ID
	var pitch: int              # MIDI音符号
	var start_time_ms: float    # 开始时间
	var duration_ms: float      # 持续时间
	var screen_x: float         # 屏幕X位置（键盘映射）
	var octave: int             # 八度
	var velocity: int           # 力度
	
	func _init(idx: int, key: int, p: int, start: float, dur: float, x: float, oct: int, vel: int) -> void:
		note_index = idx
		key_id = key
		pitch = p
		start_time_ms = start
		duration_ms = dur
		screen_x = x
		octave = oct
		velocity = vel

## 背景序列（背景伴奏）
class BackgroundSequence:
	var track_index: int        # 所在轨道
	var notes: Array            # 包含的所有Note（MidiParser.NoteEvent）
	
	func _init(track: int) -> void:
		track_index = track
		notes = []

## 当前MIDI数据
var current_midi_data: MidiData

## 所有音符列表
var all_notes: Array = []

## 生成的游戏键列表
var game_sequences: Array[GameSequence] = []

## 背景伴奏序列
var background_sequences: Array[BackgroundSequence] = []

## 键ID计数器
var next_key_id: int = 0

## 屏幕宽度（用于键位映射）
var screen_width: float = 1920.0

## 每个键的宽度
var key_width: float = 40.0

## 最小音符间距（毫秒，防止键位重叠）
var min_note_spacing_ms: float = 10.0

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

## 设置屏幕尺寸（用于键位映射计算）
func set_screen_size(width: float) -> void:
	screen_width = width

## 分类MIDI音符为游戏序列和背景序列
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
## 这是一个框架方法，具体的键生成算法待后续完善
func generate_keys(game_notes: Array) -> bool:
	if game_notes.is_empty():
		game_sequences.clear()
		keys_generated.emit(0)
		return true
	
	# 清空之前的游戏序列
	game_sequences.clear()
	next_key_id = 0
	
	# 按时间排序Note
	var sorted_notes = MidiParser.sort_notes_by_time(game_notes)
	
	# 为每个Note生成对应的键
	for note_idx in range(sorted_notes.size()):
		var note = sorted_notes[note_idx] as MidiParser.NoteEvent
		
		# 计算键的屏幕位置（基于八度循环）
		var octave_info = MidiParser.get_note_octave_and_relative_pitch(note.pitch)
		var screen_x = _calculate_key_position(note.pitch)
		
		# 创建GameSequence
		var game_seq = GameSequence.new(
			note_idx,
			next_key_id,
			note.pitch,
			note.start_time_ms,
			note.duration_ms,
			screen_x,
			octave_info["octave"],
			note.velocity
		)
		
		game_sequences.append(game_seq)
		next_key_id += 1
	
	keys_generated.emit(game_sequences.size())
	return true

## 优化生成的键
## 这是一个框架方法，具体的优化算法待后续完善
func optimize_keys() -> bool:
	# 框架实现：当前不做任何优化
	# 待后续实现：
	# - 难度自适应过滤
	# - 重叠消除算法
	# - 键位聚类
	# - 节奏感优化
	
	keys_optimized.emit(game_sequences.size())
	return true

## 辅助函数：根据音高计算屏幕X位置
## 基于八度循环，每个八度分配到整个屏幕宽度
func _calculate_key_position(midi_note: int) -> float:
	# 提取相对音高（0-11，C到B）
	var relative_pitch = midi_note % 12
	
	# 在屏幕宽度内均匀分配
	var position_ratio = float(relative_pitch) / 12.0
	return screen_width * position_ratio

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

## 判定一个键是否应该在给定时间被触发
## 返回判定等级：PERFECT(0), GOOD(1), OK(2), MISS(3)
## 判定窗口由GameplayManager或配置文件提供
func judge_key(key_id: int, hit_time_ms: float, judge_windows: Dictionary) -> int:
	var seq = get_game_sequence_by_key_id(key_id)
	if seq == null:
		return 3  # MISS
	
	var time_diff = abs(hit_time_ms - seq.start_time_ms)
	
	# 判定逻辑（具体参数由GameplayManager提供）
	if time_diff <= judge_windows.get("perfect", 50):
		return 0  # PERFECT
	elif time_diff <= judge_windows.get("good", 100):
		return 1  # GOOD
	elif time_diff <= judge_windows.get("ok", 150):
		return 2  # OK
	else:
		return 3  # MISS

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
