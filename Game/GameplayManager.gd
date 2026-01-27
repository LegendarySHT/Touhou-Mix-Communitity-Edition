## 游戏主管理器
## 负责游戏逻辑的核心流程控制
extends Node

class_name GameplayManager

## 单例实例
static var instance: GameplayManager

## 游戏状态枚举
enum GameState {
	IDLE = 0,              # 空闲状态
	LOADING = 1,           # 加载中
	PLAYING = 2,           # 游戏进行中
	PAUSED = 3,            # 已暂停
	FINISHED = 4,          # 游戏结束
	GAME_OVER = 5          # 失败
}

## 当前游戏状态
var current_state: GameState = GameState.IDLE

## 当前选中的MIDI谱面
var current_midi: MidiData

## 当前选中的歌曲
var current_song: SongData

## 当前选中的专辑
var current_album: AlbumData

## 游戏时间（秒）
var game_time: float = 0.0

## 总谱面长度（秒）
var total_duration: float = 0.0

## 是否处于调试模式
var debug_mode: bool = false

## ========== MIDI相关组件 ==========

## MIDI播放管理器引用
var midi_playback_manager: MidiPlaybackManager

## 键序列管理器引用
var key_sequence_manager: KeySequenceManager

## 音频管理器引用
var audio_manager: AudioManager

## NotesRenderer引用（待实现的UI组件）
var notes_renderer: Node

## ScoreCalculator引用
var score_calculator: Node

## 游戏状态改变信号
signal game_state_changed(old_state: GameState, new_state: GameState)
signal game_time_updated(current_time: float, total_time: float)
signal midi_loaded(midi_data: MidiData)
signal game_started
signal game_paused
signal game_resumed
signal game_finished(score_data: Dictionary)

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
	add_to_group("singleton")
	
	# 获取管理器引用
	_initialize_managers()
	
	# 连接事件总线信号
	if EventBus.instance:
		EventBus.instance.midi_selected.connect(_on_midi_selected)

func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		_update_game_time(delta)
		_sync_playback_position()

## 初始化管理器引用
func _initialize_managers() -> void:
	midi_playback_manager = MidiPlaybackManager.instance
	key_sequence_manager = KeySequenceManager.instance
	audio_manager = AudioManager.instance
	
	# 连接MIDI播放管理器信号
	if midi_playback_manager:
		midi_playback_manager.midi_finished.connect(_on_midi_finished)

## 设置游戏状态
func set_game_state(new_state: GameState) -> void:
	if new_state == current_state:
		return
	
	var old_state = current_state
	current_state = new_state
	game_state_changed.emit(old_state, new_state)
	
	match new_state:
		GameState.PLAYING:
			game_started.emit()
		GameState.PAUSED:
			game_paused.emit()
		GameState.FINISHED:
			_on_game_finished()

## 开始游戏
## 加载MIDI、初始化播放、分类Note、启动背景音乐
func start_game(midi: MidiData) -> void:
	current_midi = midi
	set_game_state(GameState.LOADING)
	
	# 异步加载和初始化MIDI
	_load_and_initialize_midi_async(midi)

## 加载并初始化MIDI（异步）
func _load_and_initialize_midi_async(midi: MidiData) -> void:
	var thread = Thread.new()
	var result = thread.start(_load_midi_thread.bind(midi))
	thread.wait_to_finish()
	
	# 初始化完成，进入播放状态
	set_game_state(GameState.PLAYING)
	midi_loaded.emit(midi)

## MIDI加载线程
## 负责MIDI加载、解析、Note分类等耗时操作
func _load_midi_thread(midi: MidiData) -> void:
	if midi_playback_manager == null:
		push_error("MidiPlaybackManager not initialized")
		return
	
	# 1. 加载MIDI文件
	var load_success = midi_playback_manager.load_midi(midi)
	if not load_success:
		push_error("Failed to load MIDI: %s" % midi.name)
		return
	
	# 获取加载后的MIDI数据（已为Note对象）
	var parsed_notes = midi_playback_manager.current_notes
	var track_infos = midi_playback_manager.get_track_infos()
	
	if parsed_notes.is_empty():
		push_error("No notes found in MIDI: %s" % midi.name)
		return
	
	# 2. 更新游戏时长
	total_duration = midi_playback_manager.duration_ms / 1000.0
	
	# 3. 调用MidiPlaybackManager的分类接口
	# 获取选中轨道作为手动控制轨道（示例，实际可从MidiData配置中读取）
	var manual_track_indices = midi.selected_track_indices if midi.selected_track_indices.size() > 0 else []
	var classified_notes = midi_playback_manager.classify_notes(parsed_notes, manual_track_indices)
	
	var auto_play_notes = classified_notes["auto_play_notes"]
	var manual_control_notes = classified_notes["manual_control_notes"]
	
	# 4. 通知MidiPlayer哪些note需要手动控制
	midi_playback_manager.set_manual_control_notes(manual_control_notes)
	
	# 5. KeySequenceManager处理（使用手动控制的note生成游戏键）
	if key_sequence_manager != null:
		key_sequence_manager.classify_sequences(midi, parsed_notes)
		
		# 使用手动控制的note生成键
		key_sequence_manager.generate_keys(manual_control_notes)
		
		# 应用配置文件中的优化设置（可选）
		if ConfigLoader.new().load_config("res://Resources/Config/config.ini").has("Gameplay"):
			var config = ConfigLoader.new().load_config("res://Resources/Config/config.ini")
			var min_spacing = config.get("Gameplay", {}).get("min_note_spacing_ms", 10.0)
			key_sequence_manager.apply_optimization_config({"min_note_spacing_ms": min_spacing})
		
		# 执行键优化（框架）
		key_sequence_manager.optimize_keys()
	
	print("[GameplayManager] MIDI loaded: %s, Total duration: %.2f seconds, Total Notes: %d (Auto: %d, Manual: %d)" %
		[midi.name, total_duration, parsed_notes.size(), auto_play_notes.size(), manual_control_notes.size()])

## 暂停游戏
func pause_game() -> void:
	if current_state == GameState.PLAYING:
		set_game_state(GameState.PAUSED)
		if midi_playback_manager != null:
			midi_playback_manager.pause()

## 恢复游戏
func resume_game() -> void:
	if current_state == GameState.PAUSED:
		set_game_state(GameState.PLAYING)
		if midi_playback_manager != null:
			midi_playback_manager.resume()
		game_resumed.emit()

## 结束游戏
func finish_game() -> void:
	set_game_state(GameState.FINISHED)
	if midi_playback_manager != null:
		midi_playback_manager.stop()

## 游戏失败
func game_over() -> void:
	set_game_state(GameState.GAME_OVER)
	if midi_playback_manager != null:
		midi_playback_manager.stop()

## 重新开始游戏
func restart_game() -> void:
	game_time = 0.0
	if midi_playback_manager != null:
		midi_playback_manager.stop()
	start_game(current_midi)

## 返回菜单
func return_to_menu() -> void:
	current_midi = null
	current_song = null
	current_album = null
	game_time = 0.0
	total_duration = 0.0
	set_game_state(GameState.IDLE)
	
	if midi_playback_manager != null:
		midi_playback_manager.stop()
	
	if key_sequence_manager != null:
		key_sequence_manager.clear_sequences()

## 更新游戏时间
func _update_game_time(delta: float) -> void:
	game_time += delta
	game_time_updated.emit(game_time, total_duration)

## 同步播放位置（从MidiPlaybackManager获取）
func _sync_playback_position() -> void:
	if midi_playback_manager == null:
		return
	
	# 从MidiPlaybackManager获取当前播放位置（使用get_position_ms()方法）
	var midi_position_ms = midi_playback_manager.get_position_ms()
	game_time = midi_position_ms / 1000.0
	
	# 启动MIDI播放（第一次调用时）
	if not midi_playback_manager.is_playing and current_state == GameState.PLAYING:
		midi_playback_manager.play()

## 游戏结束处理
func _on_game_finished() -> void:
	var score_data = _calculate_final_score()
	game_finished.emit(score_data)

## 计算最终分数（占位符）
func _calculate_final_score() -> Dictionary:
	return {
		"perfect_count": 0,
		"good_count": 0,
		"ok_count": 0,
		"miss_count": 0,
		"total_score": 0,
		"accuracy": 0.0,
		"rank": "F"
	}

## MIDI播放完成回调
func _on_midi_finished() -> void:
	finish_game()

## MIDI选择信号处理
func _on_midi_selected(_midi_id: String, midi_data: MidiData) -> void:
	current_midi = midi_data
	if current_song:
		print("Selected MIDI: %s from %s" % [midi_data.name, current_song.name])

## 获取游戏状态名称（调试）
func get_state_name(state: GameState) -> String:
	match state:
		GameState.IDLE:
			return "IDLE"
		GameState.LOADING:
			return "LOADING"
		GameState.PLAYING:
			return "PLAYING"
		GameState.PAUSED:
			return "PAUSED"
		GameState.FINISHED:
			return "FINISHED"
		GameState.GAME_OVER:
			return "GAME_OVER"
		_:
			return "UNKNOWN"
