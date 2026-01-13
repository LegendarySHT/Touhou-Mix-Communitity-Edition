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
	# 连接事件总线信号
	if EventBus.instance:
		EventBus.instance.midi_selected.connect(_on_midi_selected)

func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		_update_game_time(delta)

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
func start_game(midi: MidiData) -> void:
	current_midi = midi
	set_game_state(GameState.LOADING)
	
	# 异步加载谱面
	_load_midi_async(midi)

## 加载MIDI谱面（异步）
func _load_midi_async(midi: MidiData) -> void:
	var thread = Thread.new()
	thread.start(_load_midi_thread.bind(midi))
	thread.wait_to_finish()
	
	set_game_state(GameState.PLAYING)
	midi_loaded.emit(midi)

## MIDI加载线程
func _load_midi_thread(midi: MidiData) -> void:
	# 这里应该加载MIDI文件、音频等资源
	# 当前为占位符
	await get_tree().process_frame
	print("Loading MIDI: %s" % midi.name)

## 暂停游戏
func pause_game() -> void:
	if current_state == GameState.PLAYING:
		set_game_state(GameState.PAUSED)

## 恢复游戏
func resume_game() -> void:
	if current_state == GameState.PAUSED:
		set_game_state(GameState.PLAYING)
		game_resumed.emit()

## 结束游戏
func finish_game() -> void:
	set_game_state(GameState.FINISHED)

## 游戏失败
func game_over() -> void:
	set_game_state(GameState.GAME_OVER)

## 重新开始游戏
func restart_game() -> void:
	game_time = 0.0
	start_game(current_midi)

## 返回菜单
func return_to_menu() -> void:
	current_midi = null
	current_song = null
	current_album = null
	game_time = 0.0
	total_duration = 0.0
	set_game_state(GameState.IDLE)

## 更新游戏时间
func _update_game_time(delta: float) -> void:
	game_time += delta
	game_time_updated.emit(game_time, total_duration)

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

## MIDI选择信号处理
func _on_midi_selected(midi_id: String, midi_data: MidiData) -> void:
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
