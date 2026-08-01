## 专辑视图
## 显示所有专辑列表，支持排序和搜索
extends BaseScrollList

class_name AlbumView

## 当前显示的专辑列表
var current_albums: Array[AlbumData] = []

## 排序引擎引用
@onready var data_manager: DataManager = DataMGR
@onready var event_bus: EventBus = EvtBus

## 列表刷新控制（LazyListLoader 负责增量让帧 + 取消）
var _loader: LazyListLoader
var _album_build_counter: int = 0
var _album_build_bg: ButtonGroup
@onready var _loading_node: Control = get_parent().get_node("Loading") if get_parent() else null

func _ready() -> void:
	if not data_manager or not event_bus:
		push_error("AlbumView: Missing manager instances")
		return

	work_state = UIStateManager.UIState.ALBUM_VIEW
	snap_offset_y = 100
	# 设置直接相邻状态：切到不在此集合的状态时释放所有列表项封面
	# ALBUM_VIEW 相邻：SONG_VIEW（点进专辑）、SORTED_VIEW/STORE_VIEW/SETTINGS_VIEW（侧栏切换）
	set_adjacent_states([
		UIStateManager.UIState.SONG_VIEW,
		UIStateManager.UIState.SORTED_VIEW,
		UIStateManager.UIState.STORE_VIEW,
		UIStateManager.UIState.SETTINGS_VIEW,
	])

	# 连接事件
	data_manager.data_loaded.connect(_load_albums)
	event_bus.midi_deleted.connect(func(_id): _load_albums())
	event_bus.config_changed.connect(_on_config_changed)
	# 回到 AlbumView 时补检空列表（midi_deleted 在不活跃时触发刷新，不会显示 NoItems）
	UiStatMGR.state_changed.connect(func(_old, new):
		if new == UIStateManager.UIState.ALBUM_VIEW:
			call_deferred("_check_empty_display")
	)
	modulate.a = 0.0

	# 创建懒加载器（每 3 个专辑让一帧，匹配原有 counter % 3 节奏）
	_loader = LazyListLoader.new(3)
	_loader.first_step_completed.connect(_on_album_first_step)

	super._ready()

	# 注册主题色应用器，由 ThemeManager 在主题切换时广播调用
	if ThemeMGR:
		ThemeMGR.register_theme_applier(self)
		apply_theme()

## 应用主题色（由 ThemeManager 广播调用 + _ready 首次自调）
func apply_theme() -> void:
	if item_instance:
		ThemeMGR._style_album_instance(item_instance, ThemeMGR.get_color("primary_light"))

func _exit_tree() -> void:
	if ThemeMGR:
		ThemeMGR.unregister_theme_applier(self)

## 加载专辑数据（异步，避免阻塞主线程）
func _load_albums() -> void:
	if not data_manager:
		return

	# 取消上一轮 in-flight build
	_loader.cancel()
	current_albums = data_manager.get_sorted_albums()

	# 启动 Loading 动画
	if _loading_node:
		_loading_node.start_rotation()

	# 异步刷新列表项（内部在首个 item 出现时自动停止 Loading）
	await _refresh_display_async()

## 配置变更时重新排序（deferred，避免阻塞 save 流程）
func _on_config_changed(_key: String, section: String, _value: Variant) -> void:
	if section == "Browse":
		call_deferred("_load_albums")


## 异步刷新显示（LazyListLoader 增量让帧 + 取消机制）
func _refresh_display_async() -> void:
	clear_items()

	var is_active := UiStatMGR.current_state == UIStateManager.UIState.ALBUM_VIEW
	var no_items := get_node_or_null("/root/Main/skew/C/NoItems")

	if current_albums.is_empty():
		if _loading_node:
			_loading_node.stop_rotation()
		if no_items and is_active:
			no_items.visible = true
		return

	# 列表非空，隐藏空提示
	if no_items:
		no_items.visible = false

	_album_build_counter = 0
	_album_build_bg = ButtonGroup.new()
	var completed: bool = await _loader.build(current_albums.size(), _create_album_item)
	if not completed:
		return  # 被取消（新的 _load_albums 触发）
	if _album_build_counter:
		_connect_head_and_tail()
		# 列表构建完成，触发未加载项的封面加载（首次进入或刷新后）
		trigger_cover_chain()


## AlbumView 工厂：创建一个专辑列表项
func _create_album_item(index: int) -> Variant:
	var album: AlbumData = current_albums[index]
	var item = create_and_add_item(album.id, "album")
	if item:
		item.setup_with_album(self, album, _album_build_counter, _album_build_bg)
		_album_build_counter += 1
		return [item]
	return []


## 首个专辑项出现时：停止 Loading + fade-in
func _on_album_first_step() -> void:
	if _loading_node:
		_loading_node.stop_rotation()
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)

func _process(delta):
	super._process(delta)

	if selected_item == -1 and not is_scrolling():
		need_snap = true

func _gui_input(event: InputEvent) -> void:
	super._gui_input(event)

## 状态变化时补检空列表显示（由 state_changed call_deferred 调用）
func _check_empty_display() -> void:
	var no_items := get_node_or_null("/root/Main/skew/C/NoItems")
	if not current_albums.is_empty():
		if no_items:
			no_items.visible = false
		return
	if _loading_node:
		_loading_node.stop_rotation()
	if no_items:
		no_items.visible = true

func reset_selection():
	if selected_item == -1:
		return
	get_selected_node().button.button_pressed = false

	selected_item= -1

func on_item_button_confirmed(index: int):
	var album_id = current_albums[index].id
	if container.get_child(index).expand_tween:
		await container.get_child(index).expand_tween.finished
	event_bus.album_selected.emit(album_id)
	UiStatMGR.change_state(UiStatMGR.UIState.SONG_VIEW)
