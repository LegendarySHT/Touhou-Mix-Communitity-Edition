## MIDI列表项组件
## 继承自 ListItemBase，显示MIDI谱面信息
extends ListItemBase

const TextScrollHelper = preload("res://UI/Components/TextScrollHelper.gd")

## 引用节点
@onready var status_label: Label = $VBoxC/HBoxC/status
@onready var midi_name_label: Label = $VBoxC/NameBox/MidiName
@onready var name_box: Control = $VBoxC/NameBox
@onready var author_label: Label = $VBoxC/HBoxC/Author
@onready var cover: TextureRect = $cover

## MIDI数据
var midi_data: MidiData

## 文字滚动状态
var _name_scroll_state: TextScrollHelper.State = null

## 展开动画补间
var expand_tween: Tween

var INDICATOR = "/root/Main/skew/C/MidiView/LeftArea/InfoWindow/HBoxC/Right/Center/Indicator"

## ========== 信息缓存（静态，跨实例共享）==========
## schema: { midi_id: { "time_str", "bpm_str", "bpm_timeline", "timebase",
##                      "note_str"?, "mpp_str"? } }
## note_str / mpp_str 键缺席 → 需（重新）计算 Note 数量
static var _info_cache: Dictionary = {}

## MIDI 解析后台线程（每实例独立）
var _compute_thread: Thread = null
## 线程解析的目标 midi_data（用于回调时校验）
var _thread_target_midi: MidiData = null

func _ready() -> void:
	if EvtBus:
		EvtBus.config_changed.connect(_on_config_changed)
	if UiStatMGR:
		UiStatMGR.state_changed.connect(_on_ui_state_changed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		if EvtBus and EvtBus.config_changed.is_connected(_on_config_changed):
			EvtBus.config_changed.disconnect(_on_config_changed)
		if UiStatMGR and UiStatMGR.state_changed.is_connected(_on_ui_state_changed):
			UiStatMGR.state_changed.disconnect(_on_ui_state_changed)
		if _compute_thread != null and _compute_thread.is_alive():
			_compute_thread.wait_to_finish()

func _update_display() -> void:
	# 初始化显示
	if not status_label:
		status_label = get_node("VBoxC/HBoxC/status")
	if not midi_name_label:
		midi_name_label = get_node("VBoxC/NameBox/MidiName")
	if not name_box:
		name_box = get_node("VBoxC/NameBox")
	if not author_label:
		author_label = get_node("VBoxC/HBoxC/Author")
	status_label.text = midi_data.status
	midi_name_label.text = midi_data.name
	author_label.text = midi_data.artist_name if not midi_data.artist_name.is_empty() else "Unknown"
	# 启动/重算名称滚动动画（如名称过长）
	call_deferred("_setup_name_scroll")


## 启动/重算 MIDI 名称滚动动画
func _setup_name_scroll() -> void:
	if not is_instance_valid(midi_name_label) or not is_instance_valid(name_box):
		return
	# 循环等待 NameBox 布局完成（最多 5 帧），确保 size 正确
	var max_wait := 5
	while name_box.size.y <= 10.0 and max_wait > 0:
		await get_tree().process_frame
		max_wait -= 1
	_name_scroll_state = TextScrollHelper.setup(
		midi_name_label, name_box, midi_name_label.text, _name_scroll_state
	)

## 从MidiData初始化显示
func setup_with_midi(parent: MidiView, midi: MidiData, index: int, bg: ButtonGroup) -> void:
	midi_data = midi
	item_id = midi.id
	item_type = "midi"
	item_index = index

	button = self
	button.button_group = bg

	init_btn(button, parent)

	_update_display()
	_load_cover_image()
	
	btn_confirmed.connect(parent._show_midi_list)

	# if index == 0:
	# 	button.button_pressed = true

## 加载封面图片
func _load_cover_image() -> void:
	if not cover:
		cover = get_node_or_null("cover")
	
	if not cover:
		print("[MidiListItem] Cover node not found!")
		return
	
	# 从 FileSystemManager 获取封面路径
	var fs_manager = FileSystemManager.instance
	if not fs_manager:
		print("[MidiListItem] FileSystemManager not found, using default cover")
		return
	cover.texture = fs_manager.get_cover_by_midiData(midi_data)

## 按钮切换回调
func on_item_button_toggled(toggled_on: bool):
	if not parent_node.current_midis.size() > 1 and not toggled_on:
		return
	# 展开状态下：按钮保持 pressed 却收到 false toggle → 拖拽取消，忽略
	#（ButtonGroup 正常切项时按钮会变 unpressed，只有拖拽才会有 pressed + false 的状态矛盾）
	if not toggled_on and not parent_node._collapsed and button.button_pressed:
		return
	# 更新该项的指示器颜色（开=高亮，关=白色）
	var indicator_node := get_node(INDICATOR)
	var primary_dark := Color(0.129, 0.412, 0.702)
	if ThemeMGR:
		primary_dark = ThemeMGR.get_color("primary_dark")
	create_tween().tween_property(indicator_node.get_child(item_index), "color", primary_dark if toggled_on else Color(1, 1, 1), 0.15)
	if toggled_on:
		# 切换到新 MIDI 项时，清理上一个 MIDI 的运行时缓存（parsed_notes + GameSequence + 播放管理器）
		# 避免浏览多个大 MIDI 后 parsed_notes 累积导致内存增长
		if parent_node.selected_item != -1 and parent_node.selected_item != item_index:
			var prev_midi = parent_node.get_selection()
			if prev_midi != null:
				parent_node.cleanup_midi_cache(prev_midi)
		parent_node.selected_item = item_index
		# 收起状态点击 → 自动展开全部；展开状态 → 直接吸附
		if parent_node._collapsed:
			parent_node._show_midi_list(item_index)
		else:
			parent_node.need_snap = true
			# 指示器移到新选中项
			create_tween().tween_property(indicator_node, "offset_transform_position:y", 100 - item_index * 24, 0.35)
		_update_data_display()

## 设置展开/收起（由 MidiList._show_midi_list 批量调用）
func set_expanded(expanded: bool) -> void:
	if expand_tween:
		expand_tween.kill()
	var expa := 1 if expanded else 0
	expand_tween = create_tween()
	expand_tween.set_ease(Tween.EASE_OUT)
	expand_tween.set_trans(Tween.TRANS_QUINT)
	expand_tween.set_parallel(true)
	expand_tween.tween_property(self, "custom_minimum_size", Vector2(750, 150 + 240 * expa), 0.35)
	expand_tween.tween_property(midi_name_label, "theme_override_font_sizes/font_size", 30 + 10 * expa, 0.25)
	# 指示器颜色
	var indicator_node := get_node(INDICATOR)
	var primary_dark := Color(0.129, 0.412, 0.702)
	if ThemeMGR:
		primary_dark = ThemeMGR.get_color("primary_dark")
	var highlight = expanded and (parent_node.selected_item == item_index)
	expand_tween.tween_property(indicator_node.get_child(item_index), "color", primary_dark if highlight else Color(1, 1, 1), 0.15)
	expand_tween.finished.connect(func():
		expand_tween.kill()
		expand_tween = null
		call_deferred("_setup_name_scroll")
	)


## 更新信息面板（入口）
func _update_data_display() -> void:
	var info_node: GridContainer = get_node_or_null("/root/Main/skew/C/MidiView/LeftArea/DetailData")
	var description: RichTextLabel = get_node_or_null("/root/Main/skew/C/MidiView/LeftArea/InfoWindow/HBoxC/Description")
	if not (info_node and description):
		push_error("[MidiNode] Info Set Failed")
		return

	# --- 实时数据（无需缓存）---
	info_node.get_node("Play/Label").text = "%d" % midi_data.trial_count
	info_node.get_node("UpCount/Label").text = "%d" % midi_data.up_count
	info_node.get_node("AvgAcc/Label").text = "%.2f" % midi_data.avg_accuracy
	# info_node.get_node("AvgPP/Label") 暂未实现，留空
	description.text = midi_data.description

	# --- 缓存/计算数据 ---
	var entry: Dictionary = _info_cache.get(midi_data.id, {})

	info_node.get_node("Time/Label").text = entry.get("time_str", "...")
	info_node.get_node("BPM/Label").text = entry.get("bpm_str", "...")
	info_node.get_node("Note/Label").text = entry.get("note_str", "...")
	info_node.get_node("MPP/Label").text = entry.get("mpp_str", "...")

	# 如果缓存不完整，后台触发计算
	if not entry.has("time_str") or not entry.has("note_str"):
		_start_midi_compute()


## 触发后台计算（若已有解析结果则仅重算 Note，否则先解析再算）
func _start_midi_compute() -> void:
	var midi := midi_data
	if midi == null:
		return

	# 若 parsed_notes 已有（之前解析过或 MidiPlaybackManager加载过），直接算 Note 数量
	if midi.duration_ms > 0 and not midi.parsed_notes.is_empty():
		var entry: Dictionary = _info_cache.get(midi.id, {})
		# 补全 time / bpm 缓存（可能之前没建过）
		if not entry.has("time_str"):
			_fill_time_bpm_cache(midi, entry)
			_info_cache[midi.id] = entry
		# 重算 Note / MPP
		_compute_and_cache_notes(midi)
		return

	# 需要解析 MIDI 文件 ─ 避免对同一文件重复启动线程
	# （线程已启动但 _on_parse_done 尚未 deferred 执行时也命中）
	if _thread_target_midi == midi:
		return

	# 在主线程取文件路径（FileSystemManager 不是线程安全的）
	var pm := MidiPlaybackManager.instance
	if pm == null:
		return
	var path: String = pm._locate_midi_file(midi)
	if path.is_empty():
		_info_cache[midi.id] = {"time_str": "—", "bpm_str": "—", "note_str": "—", "mpp_str": "—"}
		_apply_display()
		return

	# 等待旧线程退出
	if _compute_thread != null:
		_compute_thread.wait_to_finish()

	_thread_target_midi = midi
	_compute_thread = Thread.new()
	_compute_thread.start(_parse_thread_func.bind(path))


## 在后台线程中解析 MIDI 文件（仅读文件，无场景树访问）
func _parse_thread_func(path: String) -> void:
	var result: Dictionary = MidiParser.load_and_parse_midi(path)
	call_deferred("_on_parse_done", result)


## 解析完成回调（主线程，call_deferred 保证）
func _on_parse_done(result: Dictionary) -> void:
	if _compute_thread != null:
		_compute_thread.wait_to_finish()
		_compute_thread = null

	var midi := _thread_target_midi
	_thread_target_midi = null

	if midi == null:
		return

	if not result.get("success", false):
		_info_cache[midi.id] = {"time_str": "—", "bpm_str": "—", "note_str": "—", "mpp_str": "—"}
		_apply_display()
		return

	# 将解析结果回填到 MidiData（若 MidiPlaybackManager 尚未填入）
	if midi.duration_ms <= 0:
		midi.duration_ms = result.get("duration", 0.0)
	if midi.bpm <= 0.0 or midi.bpm == 120.0:
		midi.bpm = result.get("bpm", 120.0)
	if midi.parsed_notes.is_empty():
		midi.parsed_notes = result.get("notes", [])
	if midi.bpm_timeline.is_empty():
		midi.bpm_timeline = result.get("bpm_timeline", [])
		midi.midi_timebase = result.get("timebase", 480)
	# 同步回填 _runtime_track_infos，使 MidiPlaybackManager.preparse_midi_async 缓存命中
	# （命中条件：parsed_notes + _runtime_track_infos 同时非空，见 MidiPlaybackManager.gd:431）
	# 缺失此行会导致进入 TrackView 时 worker 线程重新解析整个 MIDI，造成 ~18MB 临时峰值
	if midi._runtime_track_infos.is_empty():
		midi._runtime_track_infos = result.get("track_infos", [])

	# 构建并缓存 Time / BPM 字段
	var entry: Dictionary = _info_cache.get(midi.id, {})
	_fill_time_bpm_cache(midi, entry)
	_info_cache[midi.id] = entry

	# 立即刷新 Time / BPM（Note 还没算完，先显示 ...）
	_apply_display()

	# 计算 Note / MPP（主线程，同步执行，游戏未运行时安全）
	_compute_and_cache_notes(midi)


## 填写 time_str 和 bpm_str 到给定字典（不含 Note）
func _fill_time_bpm_cache(midi: MidiData, entry: Dictionary) -> void:
	# Time
	if midi.duration_ms > 0:
		var s := int(midi.duration_ms / 1000.0)
		@warning_ignore("integer_division")
		entry["time_str"] = "%d:%02d" % [s / 60, s % 60]
	else:
		entry["time_str"] = "—"

	# 获取 bpm_timeline：优先使用 MidiData 自持，其次 MidiPlaybackManager
	var timeline: Array = midi.bpm_timeline
	if timeline.is_empty():
		var pm := MidiPlaybackManager.instance
		if pm and pm.current_midi_data == midi:
			timeline = pm.bpm_timeline

	# BPM
	if timeline.is_empty():
		entry["bpm_str"] = ("%.1f" % midi.bpm) if midi.bpm > 0 else "—"
	elif timeline.size() <= 1:
		entry["bpm_str"] = "%.1f" % timeline[0].get("bpm", midi.bpm)
	else:
		# 若所有 BPM 变化均发生在第一个音符开始之前，则游玩区间内 BPM 恒定，不加 "~"
		var first_note_tick: float = INF
		for note in midi.parsed_notes:
			if note is MidiParser.Note and note.event != null:
				first_note_tick = min(first_note_tick, float(note.event.start_time))

		# 检查 index 1 起的所有变速点是否都早于第一个音符
		var all_before_first_note := first_note_tick < INF
		if all_before_first_note:
			for i in range(1, timeline.size()):
				if float(timeline[i].get("tick", 0)) > first_note_tick:
					all_before_first_note = false
					break

		if all_before_first_note:
			# 取第一个音符前最后一次 BPM 值（即实际游玩时的恒定 BPM）
			entry["bpm_str"] = "%.1f" % timeline[-1].get("bpm", midi.bpm)
		else:
			# 变速 BPM：对时间段加权平均，加 "~" 前缀
			var total_ms: float = midi.duration_ms if midi.duration_ms > 0 else 1.0
			var weighted: float = 0.0
			for i in range(timeline.size()):
				var seg_bpm: float = timeline[i].get("bpm", 120.0)
				var seg_start: float = timeline[i].get("time_ms", 0.0)
				var seg_end: float = (timeline[i + 1].get("time_ms", total_ms)
						if i + 1 < timeline.size() else total_ms)
				weighted += seg_bpm * (seg_end - seg_start)
			entry["bpm_str"] = "~%.1f" % (weighted / total_ms)

	# 缓存时间轴以供 Note 计算时传参
	entry["bpm_timeline"] = timeline
	entry["timebase"] = midi.midi_timebase


## 在主线程计算 Note / MPP 并写入缓存，完成后刷新显示
func _compute_and_cache_notes(midi: MidiData) -> void:
	var ksm := KeySequenceManager.instance
	if ksm == null or midi.parsed_notes.is_empty():
		return

	# 构建 (track, channel) 启用集合，键格式："track:channel"
	# selected_track_configs 为空有两种情况：
	#   1. 从未进过 TrackView（_track_config_initialized == false）→ 默认全部启用
	#   2. 用户在 TrackView 逐一禁用了所有轨道（_track_config_initialized == true）→ 显示 0
	var configs_initialized: bool = midi._track_config_initialized \
			or not midi.selected_track_configs.is_empty()
	var enabled_pairs: Dictionary = midi.get_enabled_pairs_flat() if configs_initialized else {}

	# 声明 entry 变量，传递缓存数据
	var entry: Dictionary = _info_cache.get(midi.id, {})
	
	# 全部禁用时直接写 0，不需要走 generate_keys
	if configs_initialized and enabled_pairs.is_empty():
		entry["note_str"] = "0"
		entry["mpp_str"] = "—"
		_info_cache[midi.id] = entry
		_apply_display()
		return

	# 按 (track, channel) 筛选音符
	var filtered: Array = []
	for note in midi.parsed_notes:
		if note is MidiParser.Note and note.event != null:
			if not configs_initialized:
				# 未初始化：全部纳入
				filtered.append(note)
			else:
				var key := "%d:%d" % [note.event.track_index, note.event.channel]
				if enabled_pairs.has(key):
					filtered.append(note)

	if filtered.is_empty():
		entry["note_str"] = "0"
		entry["mpp_str"] = "—"
		_info_cache[midi.id] = entry
		_apply_display()
		return

	# 若 MidiPlaybackManager 当前加载的不是本 midi，暂时注入 bpm 参数供 generate_keys 使用
	var pm := MidiPlaybackManager.instance
	var saved_timeline: Array = []
	var saved_timebase: int = 480
	var need_restore := false
	if pm != null and pm.current_midi_data != midi:
		saved_timeline = pm.bpm_timeline.duplicate()
		saved_timebase = pm.midi_timebase
		pm.bpm_timeline = entry.get("bpm_timeline", midi.bpm_timeline)
		pm.midi_timebase = entry.get("timebase", midi.midi_timebase)
		need_restore = true

	# 异步生成（WorkerThreadPool 后台线程），避免 6 万音符时主线程阻塞 200-800ms
	# worker 期间主线程 await 让出，pm.bpm_timeline 不会被其他地方修改（本函数是 MidiView 选中项触发的）
	await ksm.generate_keys_async(filtered, midi.id, enabled_pairs)

	if need_restore:
		pm.bpm_timeline = saved_timeline
		pm.midi_timebase = saved_timebase

	# 切换项守卫：await 期间用户可能已切到其他 MIDI 项，本 item 不再是选中项
	# 仍写入 _info_cache（缓存供下次使用），但 _apply_display 会自行判断是否刷新共享面板
	var count: int = ksm.game_sequences.size()
	if count > 0 and midi.duration_ms > 0:
		entry["note_str"] = "%d" % count
		entry["mpp_str"] = "%.1f" % (count / (midi.duration_ms / 60000.0))
	else:
		entry["note_str"] = "%d" % count
		entry["mpp_str"] = "—"

	_info_cache[midi.id] = entry
	_apply_display()


## 将当前 midi_data 的缓存内容刷新到信息面板（仅当本 item 为选中项时有效）
func _apply_display() -> void:
	if not is_inside_tree() or midi_data == null:
		return
	if parent_node == null or parent_node.selected_item != item_index:
		return # 本 item 未展开，无需刷新共享面板

	var info_node: GridContainer = get_node_or_null("/root/Main/skew/C/MidiView/LeftArea/DetailData")
	if info_node == null:
		return

	var entry: Dictionary = _info_cache.get(midi_data.id, {})
	info_node.get_node("Time/Label").text = entry.get("time_str", "...")
	info_node.get_node("BPM/Label").text = entry.get("bpm_str", "...")
	info_node.get_node("Note/Label").text = entry.get("note_str", "...")
	info_node.get_node("MPP/Label").text = entry.get("mpp_str", "...")


## 配置变更：仅影响 Note 数量/连接关系的字段才清除缓存并重算
## Appearance 段中只有 generate_short_connect / generate_instant_connect / instant_connect_max_time / block_size
## 会影响谱面（连接合并、尺寸换算），block_skin_preset 等纯贴图字段不应触发重算
func _on_config_changed(key: String, section: String, _value: Variant) -> void:
	var should_recompute := false
	match section:
		"Generator", "Lane":
			should_recompute = true
		"Appearance":
			# 仅这些字段影响 Note 数量或 MPP 显示
			should_recompute = key in [
				"generate_short_connect",
				"generate_instant_connect",
				"instant_connect_max_time",
				"block_size",
			]
	if not should_recompute:
		return
	for mid_id in _info_cache.keys():
		_info_cache[mid_id].erase("note_str")
		_info_cache[mid_id].erase("mpp_str")
	# 若本 item 正展开，立即重新触发计算
	if parent_node and parent_node.selected_item == item_index and midi_data != null:
		var info_node = get_node_or_null("/root/Main/skew/C/MidiView/LeftArea/DetailData")
		if info_node:
			info_node.get_node("Note/Label").text = "..."
			info_node.get_node("MPP/Label").text = "..."
		_start_midi_compute()


## 状态切换：从 TRACK_VIEW 返回 MIDI_VIEW → 轨道启用状态可能已变，清除 Note 缓存
func _on_ui_state_changed(old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	if old_state == UIStateManager.UIState.TRACK_VIEW \
			and new_state == UIStateManager.UIState.MIDI_VIEW:
		for mid_id in _info_cache.keys():
			_info_cache[mid_id].erase("note_str")
			_info_cache[mid_id].erase("mpp_str")
		# 若本 item 正展开，立即重触发
		if parent_node and parent_node.selected_item == item_index and midi_data != null:
			var info_node = get_node_or_null("/root/Main/skew/C/MidiView/LeftArea/DetailData")
			if info_node:
				info_node.get_node("Note/Label").text = "..."
				info_node.get_node("MPP/Label").text = "..."
			# parsed_notes 已有，直接重算（不用启线程）
			_start_midi_compute()
