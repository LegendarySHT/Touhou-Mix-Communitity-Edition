## UI状态管理器
## 使用状态机管理应用的UI状态
extends Node

class_name UIStateManager

## UI状态枚举
enum UIState {
	NONE = -1,           # 无状态
	ALBUM_VIEW = 0,      # 专辑列表页面
	SONG_VIEW = 1,       # 歌曲选择页面
	MIDI_VIEW = 2,       # MIDI详细页面
	TRACK_VIEW = 21, 	 # 音轨界面
	SORTED_VIEW = 3,     # 排序后的MIDI列表页面
	STORE_VIEW = 4,      # Store页面
	SETTINGS_VIEW = 5,   # 设置页面
	PLAY_VIEW = 6,		 # 打歌界面
	SCORE_VIEW = 61,	 # 结算界面
}

## 当前UI状态
var current_state: UIState = UIState.ALBUM_VIEW

## 上一个UI状态（用于返回）
var previous_state: UIState = UIState.ALBUM_VIEW

## 状态历史栈
var state_history: Array[UIState] = []

## 状态改变信号
signal state_changed(old_state: UIState, new_state: UIState)
# signal state_entering(state: UIState)
# signal state_exiting(state: UIState)

## 最大历史记录深度
const MAX_HISTORY_DEPTH: int = 10

var signal_conn:bool = false

var transition_version: int = 0

var _data_ready: bool = false  ## 数据是否已加载完成（替代 is_loading 轮询）

func _ready() -> void:
	add_to_group("singleton")
	# 监听 DataManager 加载完成信号
	DataMGR.data_loaded.connect(_on_data_loaded)
	# 防止 data_loaded 在 _ready 之前已发射：一次性检查
	if not DataMGR.is_loading:
		_data_ready = true

func _on_data_loaded() -> void:
	_data_ready = true

# func _process(delta: float) -> void:
# 	# 连接场景退出信号
# 	if not signal_conn:
# 		var ANI: AnimationManager = AniMGR
# 		if ANI:
# 			ANI.scene_transition_fin.connect(_scene_transition_exit)
# 			signal_conn = true

## 转换状态
func change_state(new_state: UIState, stash_state: bool = true) -> void:
	if new_state == current_state:
		GLogger.warning("can not change state", "UiStatMGR")
		return
	
	if not _data_ready:
		return
	
	var old_state = current_state
	
	# 发出状态退出信号)
	# state_exiting.emit(old_state)
	# 记录历史
	if stash_state:
		if state_history.size() >= MAX_HISTORY_DEPTH:
			state_history.pop_front()
		state_history.append(old_state)
	
	# 更新状态
	previous_state = old_state
	current_state = new_state
	transition_version += 1

	state_changed.emit(old_state, new_state)

# 收到动画结束信号再发射新状态信号 (感觉可能可以改成通知ui释放组件的)
# func _scene_transition_exit() -> void:
# 	# 发出状态进入和改变信号
# 	print("Change state to %s" % get_state_name(current_state))
# 	state_entering.emit(current_state)

## 返回上一个状态
func go_back() -> bool:
	if state_history.is_empty():
		return false
	if not _data_ready:
		return false
	var back_state = state_history.pop_back()
	# 检查历史栈是否还有元素，有则更新previous_state
	var old_state = current_state
	if not state_history.is_empty():
		previous_state = state_history.back()
	transition_version += 1
	current_state = back_state
	state_changed.emit(old_state, back_state)
	return true

## 直接返回到目标状态，跳过中间层级，只发一次 state_changed 信号
## 用于级联删除等需要跳过多级 UI 的场景
func go_back_to(target_state: UIState) -> bool:
	if current_state == target_state:
		return false
	if not _data_ready:
		return false
	# 弹出历史栈直到找到目标状态，或清空为止
	while not state_history.is_empty() and state_history.back() != target_state:
		state_history.pop_back()
	if not state_history.is_empty():
		state_history.pop_back()  # 弹出 target_state 本身
	if not state_history.is_empty():
		previous_state = state_history.back()
	var old_state = current_state
	current_state = target_state
	transition_version += 1
	state_changed.emit(old_state, target_state)
	return true

## 获取当前状态
func get_current_state() -> UIState:
	return current_state

## 检查是否在特定状态
func is_in_state(state: UIState) -> bool:
	return current_state == state

## 获取状态名称（调试用）
func get_state_name(state: UIState) -> String:
	match state:
		UIState.ALBUM_VIEW:
			return "ALBUM_VIEW"
		UIState.SONG_VIEW:
			return "SONG_VIEW"
		UIState.MIDI_VIEW:
			return "MIDI_VIEW"
		UIState.SORTED_VIEW:
			return "SORTED_VIEW"
		UIState.STORE_VIEW:
			return "STORE_VIEW"
		UIState.SETTINGS_VIEW:
			return "SETTINGS_VIEW"
		UIState.TRACK_VIEW:
			return "TRACK_VIEW"
		UIState.PLAY_VIEW:
			return "PLAY_VIEW"
		UIState.SCORE_VIEW:
			return "SCORE_VIEW"
		_:
			return "UNKNOWN_STATE"

## 打印当前状态（调试）
func print_state_info() -> void:
	GLogger.info("Current State: %s (%d)" % [get_state_name(current_state), current_state], "UiStatMGR")
	GLogger.info("Previous State: %s (%d)" % [get_state_name(previous_state), previous_state], "UiStatMGR")
	GLogger.info("History Depth: %d" % state_history.size(), "UiStatMGR")
