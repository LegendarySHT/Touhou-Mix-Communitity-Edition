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

## 可懒加载的视图路径（UIState → PackedScene 路径）
const LAZY_VIEW_PATHS := {
	UIState.MIDI_VIEW: "res://UI/Views/MidiView/MidiView.tscn",
	UIState.STORE_VIEW: "res://UI/Views/StoreView/MidiStore.tscn",
	UIState.TRACK_VIEW: "res://UI/Views/TrackView/TrackView.tscn",
	UIState.SETTINGS_VIEW: "res://UI/Views/SettingView/SettingView.tscn",
	UIState.PLAY_VIEW: "res://UI/Views/PlayView/PlayView.tscn",
	UIState.SCORE_VIEW: "res://UI/Views/ScoreView/ScoreView.tscn",
}

## 视图父节点路径（与 Main.tscn 结构对应）
const LAZY_VIEW_PARENTS := {
	UIState.MIDI_VIEW: "/root/Main/skew/C",
	UIState.STORE_VIEW: "/root/Main",
	UIState.TRACK_VIEW: "/root/Main/skew/C",
	UIState.SETTINGS_VIEW: "/root/Main/skew/C",
	UIState.PLAY_VIEW: "/root/Main",
	UIState.SCORE_VIEW: "/root/Main",
}

## 已加载的懒加载视图实例 {UIState: Node}
var _loaded_lazy_views: Dictionary = {}

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

## 确保懒加载视图已实例化（首次进入对应 state 时调用）
## 返回实例化的节点，失败返回 null
func ensure_view_loaded(state: UIState) -> Node:
	if _loaded_lazy_views.has(state):
		var existing = _loaded_lazy_views[state]
		if is_instance_valid(existing):
			return existing
		_loaded_lazy_views.erase(state)
	if not LAZY_VIEW_PATHS.has(state):
		return null
	var packed: PackedScene = load(LAZY_VIEW_PATHS[state])
	if packed == null:
		push_error("Failed to load view: %s" % LAZY_VIEW_PATHS[state])
		return null
	var instance: Node = packed.instantiate()
	var parent: Node = get_node_or_null(LAZY_VIEW_PARENTS[state])
	if parent == null:
		push_error("Parent not found for view: %s" % state)
		return null
	# 特殊 z_index 处理（与原 Main._init_ui 逻辑一致）
	match state:
		UIState.STORE_VIEW:
			instance.z_index = 10
		UIState.PLAY_VIEW:
			instance.z_index = 21
	instance.visible = false
	parent.add_child(instance)
	# 恢复原 _init_ui 的 move_child(RB_Btn/LT_Btn, -1) 行为：
	# 对于 z_index < 20 的 Main 直接子视图（StoreView=10, ScoreView=0），
	# 需确保 RB_Btn(z_index=20)/LT_Btn(z_index=20) 在场景树末尾，
	# 否则全屏 ScrollContainer 会拦截按钮的点击输入。
	# PlayView(z_index=21) 高于按钮，且 PlayView 时按钮不可见，无需移动。
	if parent == get_node_or_null("/root/Main") and instance.z_index < 20:
		for btn_path in ["/root/Main/RB_Btn", "/root/Main/LT_Btn"]:
			var btn := get_node_or_null(btn_path)
			if btn != null and btn.get_parent() == parent:
				parent.move_child(btn, -1)
	_loaded_lazy_views[state] = instance
	# 主题色由视图自身 _ready 注册到 ThemeMGR._theme_appliers 并自调 apply_theme() 完成，
	# 不再需要在此手动补应用（见 ThemeManager.register_theme_applier）
	return instance

## 转换状态
func change_state(new_state: UIState, stash_state: bool = true) -> void:
	if new_state == current_state:
		GLogger.warning("can not change state", "UiStatMGR")
		return

	if not _data_ready:
		return

	# 确保目标视图已加载（懒加载）
	if LAZY_VIEW_PATHS.has(new_state):
		ensure_view_loaded(new_state)
	# 提前加载后续界面
	match new_state:
		UIState.MIDI_VIEW:
			ensure_view_loaded(UIState.TRACK_VIEW)
			ensure_view_loaded(UIState.PLAY_VIEW)
			ensure_view_loaded(UIState.SCORE_VIEW)

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
