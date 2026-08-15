## 专辑视图
## 显示所有专辑列表，支持排序和搜索
extends BaseScrollList

class_name AlbumView

## 当前显示的专辑列表
var current_albums: Array = []

## 排序引擎引用
@onready var data_manager: DataManager = DataMGR
@onready var event_bus: EventBus = EvtBus

## 加载 generation（单调递增，使在途加载循环自动失效；替代 LazyListLoader 取消机制）
var _load_generation: int = 0
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
	event_bus.midis_deleted.connect(func(_ids): _load_albums())
	event_bus.config_changed.connect(_on_config_changed)
	# 回到 AlbumView 时补检空列表（midi_deleted 在不活跃时触发刷新，不会显示 NoItems）
	UiStatMGR.state_changed.connect(func(_old, new):
		if new == UIStateManager.UIState.ALBUM_VIEW:
			call_deferred("_check_empty_display")
	)
	modulate.a = 0.0

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

	# 递增 generation，使之前在途的加载循环自动失效（旧循环检测到不匹配后 return）
	_load_generation += 1
	current_albums = data_manager.get_sorted_albums()

	# 启动 Loading 动画（复用已有项时下面立即停止；空列表重建才保留到首项出现）
	if _loading_node:
		_loading_node.start_rotation()

	await _refresh_display_async(_load_generation)

## 配置变更时重新排序（deferred，避免阻塞 save 流程）
func _on_config_changed(_key: String, section: String, _value: Variant) -> void:
	if section == "Browse":
		call_deferred("_load_albums")


## 异步刷新显示：两阶段构建
## Phase A（同步、无 await）：裁剪多余项 + 一帧内建满全部节点，仅绑定身份（bind_with_dict）
##   —— 项高固定（tscn custom_minimum_size），滚动条长度只由 add_child 时机决定，一帧完成即立即稳定
## Phase B（异步）：每帧分批填充显示（fill_display：标签/封面/名称滚动），ChartDB 封面查询摊到帧间
## generation 守卫与复用逻辑保持不变（避免 clear_items 全清重建造成的闪烁 + 封面重载）
func _refresh_display_async(my_generation: int) -> void:
	var is_active := UiStatMGR.current_state == UIStateManager.UIState.ALBUM_VIEW
	var no_items := get_node_or_null(PathRegistry.NO_ITEMS)

	if current_albums.is_empty():
		clear_items()
		if _loading_node:
			_loading_node.stop_rotation()
		if no_items and is_active:
			no_items.visible = true
		return

	# 列表非空，隐藏空提示
	if no_items:
		no_items.visible = false

	var had_items: bool = not list_items.is_empty()

	# ===== Phase A：同步建足节点（滚动条立即稳定） =====
	# 同步项数：多余的从尾部清理（释放封面使在途回调失效）
	var target_count: int = current_albums.size()
	var existing_count: int = list_items.size()
	if existing_count > target_count:
		for i in range(existing_count - 1, target_count - 1, -1):
			var extra_item: ListItemBase = list_items[i]
			if is_instance_valid(extra_item):
				if extra_item is CoverListItemBase:
					(extra_item as CoverListItemBase).release_cover()
				extra_item.queue_free()
			list_items.remove_at(i)
		# 裁剪后等待一帧：让 queue_free 的节点从容器移除，再继续建新项/连头尾
		await get_tree().process_frame
		# await 后校验:若期间被新调用取代,静默退出
		if my_generation != _load_generation:
			return

	# 重置选中与吸附状态（复用项内容已变，原选中索引不再有效）
	selected_item = -1
	need_snap = false
	_snap_active = false

	# 有复用项（列表本就可见）时立即停止 Loading，无需 fade-in
	if had_items and _loading_node:
		_loading_node.stop_rotation()

	_album_build_bg = ButtonGroup.new()
	existing_count = list_items.size()

	var counter := 0
	for album in current_albums:
		var item
		if counter < existing_count:
			# 复用现有项：仅绑定新身份（显示在 Phase B 填充）
			item = list_items[counter]
		else:
			# 新建项；空列表重建的首项触发停止 Loading + fade-in
			item = create_and_add_item(String(album.get("id", "")), "album")
			if not had_items and counter == 0:
				_on_album_first_step()
		item.bind_with_dict(self, album, counter, _album_build_bg)
		counter += 1

	# ===== Phase B：异步分批填充显示 =====
	const FILL_BATCH_SIZE := 6
	var filled := 0
	for item in list_items:
		# generation 校验:若期间被新调用取代,静默退出（新调用会自行构建列表）
		if my_generation != _load_generation:
			return
		if is_instance_valid(item):
			(item as AlbumListItem).fill_display()
			filled += 1
			if filled % FILL_BATCH_SIZE == 0:
				await get_tree().process_frame
				# await 后校验:若期间被新调用取代,静默退出
				if my_generation != _load_generation:
					return

	# 最终校验:仅当本次 generation 仍最新时连接头尾 + 触发未加载项封面加载
	if my_generation == _load_generation:
		if list_items.size() >= 2:
			_connect_head_and_tail()
		trigger_cover_chain()


## 首个专辑项出现时：停止 Loading + fade-in
func _on_album_first_step() -> void:
	if _loading_node:
		_loading_node.stop_rotation()
	AniMGR.create_managed_tween(self).tween_property(self, "modulate:a", 1.0, 0.3)

func _process(delta):
	super._process(delta)

	if selected_item == -1 and not is_scrolling():
		need_snap = true

func _gui_input(event: InputEvent) -> void:
	super._gui_input(event)

## 状态变化时补检空列表显示（由 state_changed call_deferred 调用）
func _check_empty_display() -> void:
	var no_items := get_node_or_null(PathRegistry.NO_ITEMS)
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
	var album_id: String = String(current_albums[index].get("id", ""))
	if container.get_child(index).expand_tween:
		await container.get_child(index).expand_tween.finished
	# 记录导航位置：进入 SongView 时记录所选专辑（清空更深的 song/midi 记录）
	NavigationState.save(album_id, "", "")
	event_bus.album_selected.emit(album_id)
	UiStatMGR.change_state(UiStatMGR.UIState.SONG_VIEW)


func _on_random_select_btn_pressed() -> void:
	if work_state != UiStatMGR.current_state:
		return
	if current_albums.is_empty() or list_items.is_empty():
		return
	var random_index := randi() % current_albums.size()
	# 用 force_snap_to：列表滚动中也要立即取消惯性并吸附到随机项（普通 need_snap 会被滚动状态门控）
	force_snap_to(random_index)
