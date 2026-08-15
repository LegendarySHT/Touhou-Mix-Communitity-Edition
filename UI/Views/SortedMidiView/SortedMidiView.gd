## 排序MIDI视图
## 显示按特定条件排序或搜索后的MIDI列表
extends BaseScrollList

class_name SortedMidiView

## 当前显示的MIDI轻量投影（DB 返回 / 收藏夹转换），列表项直接消费，不水合完整 MidiData
var current_items: Array = []

## 收藏夹浏览模式标志：true 时 current_items 来自收藏夹，搜索/清空走收藏夹逻辑
var _favorites_mode: bool = false
## 当前收藏夹的谱面 id 列表（缓存，用于搜索时按 keys 过滤）
var _favorite_ids: Array = []

## 管理器引用
@onready var sm: UIStateManager = UiStatMGR
@onready var dm: DataManager = DataMGR
@onready var eb: EventBus = EvtBus
@onready var se: SortingEngine = SortEngine

## 空结果提示节点
@onready var no_items_node: Label = get_node_or_null(PathRegistry.NO_ITEMS)

var item_bg: ButtonGroup = null

## 加载 generation 计数器（单调递增）
## 每次 _load_sorted_midis 调用递增,使之前在途的加载循环自动失效
## 替代旧的 _is_loading + _load_abort 机制,消除多调用重叠时的竞态:
##   旧机制问题:_is_loading 既做互斥又做取消,Call 2 置 false 取消 Call 1 时
##   会误打开闸门让 Call 3 跳过互斥检查,导致 Call 1/Call 3 并发修改 list_items
##   且 Call 2 永久 await _load_abort 挂起(协程泄漏)
## 新机制:每次调用获得唯一 generation,循环中校验 generation 一致性,
##   旧循环自然退出,无信号 await,无并发
var _load_generation: int = 0

func _ready() -> void:
	if not dm or not eb or not se:
		push_error("SortedMidiView: Missing manager instances")
		return

	work_state = UIStateManager.UIState.SORTED_VIEW
	# 设置直接相邻状态：切到不在此集合的状态时释放所有列表项封面
	# SORTED_VIEW 相邻：ALBUM_VIEW（侧栏返回）、MIDI_VIEW（点进 MIDI）
	set_adjacent_states([
		UIStateManager.UIState.ALBUM_VIEW,
		UIStateManager.UIState.MIDI_VIEW,
	])
	# 连接事件
	eb.search_query_changed.connect(_on_search_query_changed)
	eb.sort_finished.connect(_load_sorted_midis)
	sm.state_changed.connect(_hide_label)
	eb.favorite_selected_for_browse.connect(_on_favorite_selected_for_browse)

	super._ready()

## 重写基类状态切换处理：退回 ALBUM_VIEW/SONG_VIEW 时清空列表节点
## 其它状态（如 MIDI_VIEW 点进 MIDI）保留列表，返回时无需重建
func _on_state_changed(old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	super._on_state_changed(old_state, new_state)
	if new_state in [UIStateManager.UIState.ALBUM_VIEW, UIStateManager.UIState.SONG_VIEW]:
		# 退回专辑/歌曲视图：递增 generation 使在途加载失效,清空列表,释放节点
		_load_generation += 1
		clear_items()
		current_items.clear()
		_favorites_mode = false

func _process(delta):
	super._process(delta)

func _gui_input(event):
	super._gui_input(event)

func on_item_button_confirmed(index: int) -> void:
	if index < 0 or index >= current_items.size():
		return
	var item: Dictionary = current_items[index]
	var midi_id: String = String(item.get("id", ""))
	# 点击时才惰性水合完整 MidiData（仅 1 个），列表本身只持有轻量投影
	var midi: MidiData = DataMGR.get_midi_by_id(midi_id)
	if midi and eb:
		sm.change_state(UIStateManager.UIState.MIDI_VIEW)
		eb.emit_midi_selected(midi.id, midi)

## 加载排序的MIDI列表（启动新的加载任务）
## 复用机制：切换内容时不全量清空，先尝试替换现有项的数据，多余项从尾部清理，不足项新建
func _load_sorted_midis(refectch: bool = true) -> void:
	if not dm or not se:
		GLogger.warning("Missing manager instances", "SortedMidiView")
		return

	# 递增 generation,使之前在途的加载循环自动失效(旧循环检测到 generation 不匹配后 return)
	_load_generation += 1
	var my_generation := _load_generation

	if not item_bg:
		item_bg = ButtonGroup.new()

	if refectch:
		# DB 排序路径：取排序引擎的轻量投影；同时退出收藏夹模式
		current_items = se.get_items()
		_favorites_mode = false

	no_items_node.visible = current_items.size() == 0

	# 同步项数：复用现有项，多余的从尾部清理，不足的新建
	var target_count: int = current_items.size()
	var existing_count: int = list_items.size()
	if existing_count > target_count:
		for i in range(existing_count - 1, target_count - 1, -1):
			var extra_item: ListItemBase = list_items[i]
			if is_instance_valid(extra_item):
				# 先释放封面：清空 _loading_path 使在途回调失效，避免帧末 free 前回调浪费 CPU
				if extra_item is CoverListItemBase:
					(extra_item as CoverListItemBase).release_cover()
				extra_item.queue_free()
			list_items.remove_at(i)
		# 等待多余项实际释放，避免下帧悬挂引用
		await get_tree().process_frame
		# await 后校验:若期间被新调用取代,静默退出
		if my_generation != _load_generation:
			return

	# 重置选中与吸附状态（复用项内容已变，原选中索引不再有效）
	selected_item = -1
	need_snap = false
	_snap_active = false

	var counter = 0
	for item in current_items:
		# generation 校验:若期间被新调用取代,静默退出(新调用会自行构建列表)
		if my_generation != _load_generation:
			return

		var node: SortedMidiListItem
		if counter < existing_count:
			# 复用现有项：setup_with_dict 内部会调 _refresh_display 刷新数据
			node = list_items[counter] as SortedMidiListItem
		else:
			# 新建项
			node = create_and_add_item(String(item.get("id", "")), "midi") as SortedMidiListItem
		node.setup_with_dict(item, counter, item_bg)
		counter += 1

		# 与 AlbumView 一致：每 3 项让出一帧，避免数百项列表逐个等待帧导致构建耗时数秒
		if counter % 3 == 0:
			await get_tree().process_frame

	# 最终校验:仅当本次 generation 仍为最新时触发未加载项的封面加载
	if my_generation == _load_generation:
		trigger_cover_chain()

## 搜索查询改变
## DB 模式：搜索词并入 C# FilterSearch（状态过滤+字段排序+搜索一次完成，含简繁日规范化），
## 完成经 sort_finished → _load_sorted_midis(true) 自动重载；收藏夹模式：按收藏 keys 过滤。
func _on_search_query_changed(query: String) -> void:
	if not se:
		return
	# 就地搜索已接管 AlbumView/SongView/MidiView：仅当本视图激活时才处理搜索
	# （搜索不再自动跳转 SORTED_VIEW，避免后台误改排序状态）
	if sm.current_state != UIStateManager.UIState.SORTED_VIEW:
		return

	if query.is_empty():
		if _favorites_mode:
			# 收藏夹模式：清空搜索词恢复全部收藏
			current_items = ChartDB.GetMidiListItemsByKeys(_favorite_ids, "")
			_load_sorted_midis(false)
		else:
			# DB 模式：恢复当前排序集合（sort_finished → _load_sorted_midis(true)）
			se.set_sort_mode(se.current_sort_stat_field, se.current_sort_field, se.current_sort_direction)
		return

	if _favorites_mode:
		# 收藏夹内搜索（保持顺序，经 C# FilterSearch 含简繁日规范化）
		current_items = ChartDB.GetMidiListItemsByKeys(_favorite_ids, query)
		_load_sorted_midis(false)
	else:
		# DB 全库搜索（sort_finished → _load_sorted_midis(true)）
		se.set_sort_mode_with_query(query)

func _hide_label(_old,_new):
	if no_items_node.visible:
		no_items_node.visible = false

## 收藏夹被选中浏览：加载该收藏夹的所有 midi（轻量投影，不水合完整 MidiData）
func _on_favorite_selected_for_browse(fav_id: String) -> void:
	if not FavoriteManager.instance:
		return
	var fav = FavoriteManager.instance.get_favorite(fav_id)
	if not fav:
		return
	_favorites_mode = true
	_favorite_ids = fav.midi_ids.duplicate()
	current_items = ChartDB.GetMidiListItemsByKeys(_favorite_ids, "")
	_load_sorted_midis(false)
