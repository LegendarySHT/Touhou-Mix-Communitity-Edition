## UI状态管理器
## 使用状态机管理应用的UI状态
extends Node

class_name UIStateManager

## 单例实例
static var instance: UIStateManager

## UI状态枚举
enum UIState {
	NONE = -1,           # 无状态
	ALBUM_VIEW = 0,      # 专辑列表页面
	SONG_VIEW = 1,       # 歌曲选择页面
	MIDI_VIEW = 2,       # MIDI谱面列表页面
	SORTED_VIEW = 20,    # 排序后的MIDI列表页面
	DETAIL_VIEW = 30,    # 详情页面
	STORE_VIEW = 40,     # Store页面
	SETTINGS_VIEW = 50   # 设置页面
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

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
	add_to_group("singleton")

# func _process(delta: float) -> void:
# 	# 连接场景退出信号
# 	if not signal_conn:
# 		var ANI: AnimationManager = AniMGR.instance
# 		if ANI:
# 			ANI.scene_transition_fin.connect(_scene_transition_exit)
# 			signal_conn = true

## 转换状态
func change_state(new_state: UIState) -> void:
	if new_state == current_state:
		print("can not change state")
		return
	
	var old_state = current_state
	
	# 发出状态退出信号)
	# state_exiting.emit(old_state)
	# 记录历史
	if state_history.size() >= MAX_HISTORY_DEPTH:
		state_history.pop_front()
	state_history.append(old_state)
	
	# 更新状态
	previous_state = old_state
	current_state = new_state

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
	var back_state = state_history.pop_back()
	# 检查历史栈是否还有元素，有则更新previous_state
	if not state_history.is_empty():
		previous_state = state_history.back()
	
	state_changed.emit(current_state, back_state)
	current_state = back_state
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
		UIState.DETAIL_VIEW:
			return "DETAIL_VIEW"
		UIState.STORE_VIEW:
			return "STORE_VIEW"
		UIState.SETTINGS_VIEW:
			return "SETTINGS_VIEW"
		_:
			return "UNKNOWN_STATE"

## 打印当前状态（调试）
func print_state_info() -> void:
	print("Current State: %s (%d)" % [get_state_name(current_state), current_state])
	print("Previous State: %s (%d)" % [get_state_name(previous_state), previous_state])
	print("History Depth: %d" % state_history.size())
