## 排序MIDI视图
## 显示按特定条件排序或搜索后的MIDI列表
extends BaseScrollList

class_name SortedMidiView

## 当前显示的MIDI列表
var current_midis: Array[MidiData] = []

## 管理器引用
@onready var sm: UIStateManager = UIStateManager.instance
@onready var dm: DataManager = DataManager.instance
@onready var eb: EventBus = EventBus.instance
@onready var se: SortingEngine = SortingEngine.instance

## 是否正在加载
var _is_loading: bool = false

var item_bg: ButtonGroup = null

func _ready() -> void:	
	if not dm or not eb or not se:
		push_error("SortedMidiView: Missing manager instances")
		return
	
	work_state = UIStateManager.UIState.SORTED_VIEW
	item_height = 179 # 间距29 项高150
	item_spacing = 29

	# 连接事件
	eb.search_query_changed.connect(_on_search_query_changed)
	eb.sort_finished.connect(_load_sorted_midis)

	super._ready()

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
	clear_items()
	
	if not item_bg:
		item_bg = ButtonGroup.new()
	
	if refectch:
		current_midis = se.get_midis()
	
	_is_loading = true
	for midi in current_midis:
		if not _is_loading:
			_load_abort.emit()
			break
		
		var node = create_and_add_item(midi.id, "midi")
		node.setup_with_midi(midi, 0, item_bg)
		
		await get_tree().process_frame
	
	_is_loading = false

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
