## 谱面渲染器
## 负责MIDI谱面的解析、键位管理和Note显示
extends Node

class_name NotesRenderer

## MIDI播放管理器引用
var midi_playback_manager: MidiPlaybackManager

## 键序列管理器引用
var key_sequence_manager: KeySequenceManager

## 当前加载的MIDI数据
var current_midi_data: MidiData

## 所有解析的音符列表
var all_notes: Array = []

## 游戏序列列表
var game_sequences: Array[KeySequenceManager.GameSequence] = []

## 当前播放位置（毫秒）
var current_position: float = 0.0

## 总时长（毫秒）
var total_duration: float = 0.0

## 已判定的Note索引集合（用Array实现唯一性）
var judged_note_indices: Array[int] = []

## 屏幕可视范围大小（毫秒）
var visible_time_range_ms: float = 2000.0

## 判定窗口配置（毫秒）
var judge_windows: Dictionary = {
	"perfect": 50,
	"good": 100,
	"ok": 150,
	"miss": 200
}

## Note点击信号
signal note_hit(note_index: int, key_id: int, judge_result: String)
signal note_missed(note_index: int, key_id: int)
signal chart_loaded(midi_data: MidiData)
signal visible_notes_updated(visible_sequences: Array)

func _ready() -> void:
	add_to_group("game_logic")
	
	# 获取管理器引用
	midi_playback_manager = MidiPlaybackManager.instance
	key_sequence_manager = KeySequenceManager.instance

## 加载MIDI谱面
## 此方法由GameplayManager调用
func load_chart(midi_data: MidiData) -> bool:
	if midi_data == null:
		push_error("MidiData is null")
		return false
	
	current_midi_data = midi_data
	
	# 从MidiPlaybackManager获取已解析的音符
	if midi_playback_manager == null:
		push_error("MidiPlaybackManager not initialized")
		return false
	
	all_notes = midi_playback_manager.current_notes.duplicate()
	game_sequences = key_sequence_manager.get_game_sequences()
	
	# 设置总时长
	total_duration = midi_playback_manager.duration_ms
	
	# 从配置文件加载判定窗口
	_load_judge_windows()
	
	chart_loaded.emit(midi_data)
	print("[NotesRenderer] Chart loaded: %s, Total notes: %d, Game sequences: %d" %
		[midi_data.name, all_notes.size(), game_sequences.size()])
	
	return true

## 更新当前播放位置
func update_position(position_ms: float) -> void:
	current_position = position_ms
	
	# 获取当前应该显示的Note
	var visible_seqs = get_visible_sequences()
	visible_notes_updated.emit(visible_seqs)
	
	# 检查超期未判定的Note
	_check_missed_notes()

## 获取当前应该显示的游戏序列（键）
## 基于显示时间窗口
func get_visible_sequences() -> Array[KeySequenceManager.GameSequence]:
	var visible: Array[KeySequenceManager.GameSequence] = []
	var window_start = current_position - visible_time_range_ms * 0.3
	var window_end = current_position + visible_time_range_ms * 0.7
	
	for seq in game_sequences:
		if seq.start_time_ms >= window_start and seq.start_time_ms <= window_end:
			visible.append(seq)
	
	return visible

## 处理玩家击键，触发Note判定
func judge_note_at_key(key_id: int, hit_time_ms: float) -> String:
	if key_sequence_manager == null:
		return "miss"
	
	# 获取该键对应的GameSequence
	var seq = key_sequence_manager.get_game_sequence_by_key_id(key_id)
	if seq == null:
		return "miss"
	
	# 避免重复判定
	if judged_note_indices.has(seq.note_index):
		return "already_judged"
	
	# 计算与目标时间的偏差
	var time_diff = abs(hit_time_ms - seq.start_time_ms)
	
	# 判定等级
	var judge_result: String = "miss"
	
	if time_diff <= judge_windows["perfect"]:
		judge_result = "perfect"
	elif time_diff <= judge_windows["good"]:
		judge_result = "good"
	elif time_diff <= judge_windows["ok"]:
		judge_result = "ok"
	else:
		judge_result = "miss"
	
	# 标记为已判定
	judged_note_indices.append(seq.note_index)
	
	# 发出信号
	note_hit.emit(seq.note_index, key_id, judge_result)
	
	return judge_result

## 获取所有游戏序列（键）
func get_all_game_sequences() -> Array[KeySequenceManager.GameSequence]:
	if key_sequence_manager == null:
		return []
	return key_sequence_manager.get_game_sequences()

## 获取游戏序列总数
func get_game_sequence_count() -> int:
	return game_sequences.size()

## 获取所有Note总数
func get_all_notes_count() -> int:
	return all_notes.size()

## 清空谱面数据
func clear_chart() -> void:
	current_midi_data = null
	all_notes.clear()
	game_sequences.clear()
	current_position = 0.0
	total_duration = 0.0
	judged_note_indices.clear()
	
	if key_sequence_manager != null:
		key_sequence_manager.clear_sequences()

## 获取特定时间范围内的游戏序列
func get_sequences_in_range(start_ms: float, end_ms: float) -> Array[KeySequenceManager.GameSequence]:
	var result: Array[KeySequenceManager.GameSequence] = []
	
	for seq in game_sequences:
		if seq.start_time_ms >= start_ms and seq.start_time_ms <= end_ms:
			result.append(seq)
	
	return result

## 检查超期未判定的Note
## 判定时间过去太久（超过miss窗口）的Note应该标记为MISS
func _check_missed_notes() -> void:
	for seq in game_sequences:
		# 如果已判定，跳过
		if judged_note_indices.has(seq.note_index):
			continue
		
		# 如果Note已经过期（超过miss窗口）
		if current_position > seq.start_time_ms + judge_windows["miss"]:
			judged_note_indices.append(seq.note_index)
			note_missed.emit(seq.note_index, seq.key_id)

## 从配置文件加载判定窗口
func _load_judge_windows() -> void:
	var config_loader = ConfigLoader.new()
	var config = config_loader.load_config("res://Resources/Config/config.ini")
	
	if config.has("Gameplay"):
		var gameplay_config = config["Gameplay"]
		judge_windows["perfect"] = gameplay_config.get("judge_window_perfect", 50)
		judge_windows["good"] = gameplay_config.get("judge_window_good", 100)
		judge_windows["ok"] = gameplay_config.get("judge_window_ok", 150)
		judge_windows["miss"] = gameplay_config.get("judge_window_miss", 200)

## 设置可视时间窗口大小
func set_visible_time_range(range_ms: float) -> void:
	visible_time_range_ms = range_ms

## 获取已判定的Note数量
func get_judged_notes_count() -> int:
	return judged_note_indices.size()

## 获取统计信息
func get_statistics() -> Dictionary:
	return {
		"total_notes": all_notes.size(),
		"game_sequences_count": game_sequences.size(),
		"judged_count": get_judged_notes_count(),
		"current_position": current_position,
		"total_duration": total_duration
	}
