## 排序MIDI视图
## 显示按特定条件排序或搜索后的MIDI列表
extends BaseScrollList

class_name SortedMidiView

## 当前显示的MIDI列表
var current_midis: Array[MidiData] = []

## 管理器引用
@onready var sm: UIStateManager = UiStatMGR
@onready var dm: DataManager = DataMGR
@onready var eb: EventBus = EvtBus
@onready var se: SortingEngine = SortEngine

## 空结果提示节点
@onready var no_items_node: Label = get_node_or_null("/root/Main/skew/C/NoItems")

## 是否正在加载
var _is_loading: bool = false

var item_bg: ButtonGroup = null

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
		# 退回专辑/歌曲视图：清空列表，释放节点
		_is_loading = false
		clear_items()
		current_midis.clear()

func _process(delta):
	super._process(delta)

func _gui_input(event):
	super._gui_input(event)

func on_item_button_confirmed(index: int) -> void:
	var midi:MidiData = current_midis[index]
	print("选中：%s / %s" % [midi.song_data.name, midi.name])
	if eb and midi:
		sm.change_state(UIStateManager.UIState.MIDI_VIEW)
		eb.emit_midi_selected(midi.id, midi)

signal _load_abort
var _ignore_sort_finished_signal: bool = false
## 加载排序的MIDI列表（启动新的加载任务）
## 复用机制：切换内容时不全量清空，先尝试替换现有项的数据，多余项从尾部清理，不足项新建
func _load_sorted_midis(refectch: bool = true) -> void:
	if _ignore_sort_finished_signal:
		return

	if not dm or not se:
		print("Missing manager instances")
		return

	# 检查是否已经有加载任务在进行
	if _is_loading:
		# 中断当前的加载任务
		_is_loading = false
		await _load_abort

	if not item_bg:
		item_bg = ButtonGroup.new()

	if refectch:
		current_midis = se.get_midis()

	no_items_node.visible = current_midis.size() == 0

	# 同步项数：复用现有项，多余的从尾部清理，不足的新建
	var target_count: int = current_midis.size()
	var existing_count: int = list_items.size()
	if existing_count > target_count:
		for i in range(existing_count - 1, target_count - 1, -1):
			var extra_item: ListItemBase = list_items[i]
			if is_instance_valid(extra_item):
				extra_item.queue_free()
			list_items.remove_at(i)
		# 等待多余项实际释放，避免下帧悬挂引用
		await get_tree().process_frame

	# 重置选中与吸附状态（复用项内容已变，原选中索引不再有效）
	selected_item = -1
	need_snap = false
	_snap_active = false

	_is_loading = true
	var counter = 0
	for midi in current_midis:
		if not _is_loading:
			_load_abort.emit()
			return

		var node: SortedMidiListItem
		if counter < existing_count:
			# 复用现有项：setup_with_midi 内部会调 _refresh_display 刷新数据
			node = list_items[counter] as SortedMidiListItem
		else:
			# 新建项
			node = create_and_add_item(midi.id, "midi") as SortedMidiListItem
		node.setup_with_midi(midi, counter, item_bg)
		counter += 1

		await get_tree().process_frame

	_is_loading = false
	# 列表构建完成，触发封面涟漪加载
	trigger_cover_chain()

## 搜索查询改变
func _on_search_query_changed(query: String) -> void:
	if not se or not dm:
		return
	
	if query.is_empty():
		# 如果搜索为空，恢复正常排序视图
		current_midis = se.get_midis()
	else:
		# 执行搜索
		if not se.current_midis:
			se.set_sort_mode()
			_ignore_sort_finished_signal = true
			await EvtBus.sort_finished
			_ignore_sort_finished_signal = false
		current_midis = se.search_midis(se.get_midis(), query)
		print("过滤后midi数量：%d" % current_midis.size())
	
	_load_sorted_midis(false)

func _hide_label(_old,_new):
	if no_items_node.visible:
		no_items_node.visible = false

## 收藏夹被选中浏览：加载该收藏夹的所有 midi
func _on_favorite_selected_for_browse(fav_id: String) -> void:
	if not FavoriteManager.instance:
		return
	current_midis = FavoriteManager.instance.get_midis_of_favorite(fav_id)
	_load_sorted_midis(false)
