extends HBoxContainer
class_name DelView

enum Tab {MIDI = 0, AUDIO = 1, SF2 = 2, SKIN = 3, BG = 4}

const TREE_ROOT_SCENE := preload("res://UI/Views/SettingView/TreeRoot.tscn")
const TREE_ITEM_SCENE := preload("res://UI/Views/SettingView/TreeItem.tscn")
const TextScrollHelper = preload("res://UI/Components/TextScrollHelper.gd")

# ── Sidebar ──
@onready var _tab_buttons: Array[Button] = [
	$SideBar/TabBtn0,
	$SideBar/TabBtn1,
	$SideBar/TabBtn2,
	$SideBar/TabBtn3,
	$SideBar/TabBtn4,
]

# ── TopBar ──
@onready var _tab_title := $Content/PC/TopBar/TabTitle as Label
@onready var _item_sum := $Content/PC/TopBar/ItemSum/Text as Label
var _item_sum_scroll_state: TextScrollHelper.State = null

# ── PageContainer ──
@onready var _page_container := $Content/PageContainer as TabContainer

# ── MIDI 页面 ──
@onready var _midi_list := $Content/PageContainer/MidiPage2/MidiList as VBoxContainer

# ── 音频页面 ──
@onready var _audio_list := $Content/PageContainer/AudioPage/AudioList as VBoxContainer

# ── SF2 页面 ──
@onready var _sf2_list := $Content/PageContainer/Sf2Page/Sf2List as VBoxContainer

# ── 皮肤页面 ──
@onready var _skin_list := $Content/PageContainer/SkinPage/SkinList as VBoxContainer

# ── 背景页面 ──
@onready var _bg_list := $Content/PageContainer/BgPage/BgList as VBoxContainer

# ── 共享底栏 ──
@onready var _select_toggle := $Content/BottomBarPC/BottomBar/SelectToggle as Button
@onready var _collapse_toggle := $Content/BottomBarPC/BottomBar/CollapseToggle as Button
@onready var _delete_btn := $Content/BottomBarPC/BottomBar/DeleteBtn as Button

# ── TopBar 控件 ──
@onready var _search_box := $Content/PC/TopBar/SearchBox as LineEdit
@onready var _order_btn := $Content/PC/TopBar/OrderBtn as Button

var _current_tab: Tab = Tab.MIDI
var _tab_sort_ascending: Array[bool] = [true, true, true, true, true]
var _search_query: String = ""

# MIDI 数据
var _midi_path_map: Dictionary = {}             # chart_id → folder_path
var _midi_selected: Dictionary = {}              # midi_id → bool
var _midi_root_map: Dictionary = {}              # album_id → TreeRoot node
var _midi_item_map: Dictionary = {}              # midi_id → TreeItem node
var _midi_album_order: Array = []        # 当前排序的 album_id 列表
var _midi_album_midi_map: Dictionary = {}        # album_id → Array[String] midi_id

# Audio 数据 — 按 song_name 分组
var _audio_items: Array[Dictionary] = []         # 扁平数据（保留用于搜索/选中状态）
var _audio_root_map: Dictionary = {}             # song_name → TreeRoot node
var _audio_item_map: Dictionary = {}             # flat_index → TreeItem node
var _audio_group_order: Array = []       # 当前排序的 song_name 列表
var _audio_items_in_group: Dictionary = {}       # song_name → Array[int] flat indices

# SF2/Skin/BG 数据
var _sf2_items: Array[Dictionary] = []
var _sf2_nodes: Dictionary = {}                  # index → TreeRoot node
var _skin_items: Array[Dictionary] = []
var _skin_nodes: Dictionary = {}                 # index → TreeRoot node
var _bg_items: Array[Dictionary] = []
var _bg_nodes: Dictionary = {}                   # index → TreeRoot node

# 缓存标记 & 构建锁
var _tab_data_built: Array[bool] = [false, false, false, false, false]
var _build_loading: bool = false


func _ready() -> void:
	print("[DelView] _ready start")
	for i in _tab_buttons.size():
		_tab_buttons[i].pressed.connect(_on_tab_button_pressed.bind(i))

	_select_toggle.toggled.connect(_on_select_toggled)
	_delete_btn.pressed.connect(_on_delete_pressed)
	_collapse_toggle.toggled.connect(_on_collapse_toggled)

	DataMGR.data_loaded.connect(_on_data_loaded)

	_search_box.text_changed.connect(_on_search_text_changed)
	_order_btn.pressed.connect(_on_order_btn_pressed)

	print("[DelView] _ready calling _switch_tab(MIDI)")
	_switch_tab(Tab.MIDI)
	print("[DelView] _ready done")


# ============================================================
# Tab 切换
# ============================================================

func _on_tab_button_pressed(idx: int) -> void:
	if idx == _current_tab:
		return
	_switch_tab(idx as Tab)


func _switch_tab(tab: Tab) -> void:
	print("[DelView] _switch_tab: %d, cached=%s" % [tab, _tab_data_built[tab]])
	_current_tab = tab
	_tab_buttons[tab].set_pressed_no_signal(true)
	_page_container.current_tab = tab

	_order_btn.icon = load("res://Resources/icon/Sort/Ordering/Ascent.png" if _tab_sort_ascending[tab] else "res://Resources/icon/Sort/Ordering/Descent.png")
	_search_box.text = ""
	_search_query = ""

	_collapse_toggle.visible = (tab == Tab.MIDI or tab == Tab.AUDIO)

	if _tab_data_built[tab]:
		print("[DelView] Tab %d cached, updating header only" % tab)
		_update_tab_header(tab)
		_apply_search_filter()
		return

	match tab:
		Tab.MIDI:
			_tab_title.text = "MIDI 谱面管理"
			_build_midi_page()
		Tab.AUDIO:
			_tab_title.text = "人声音频管理"
			_build_audio_page()
		Tab.SF2:
			_tab_title.text = "SF2 音源管理"
			_build_sf2_page()
		Tab.SKIN:
			_tab_title.text = "皮肤管理"
			_build_skin_page()
		Tab.BG:
			_tab_title.text = "背景管理"
			_build_bg_page()


func _on_select_toggled(toggled: bool) -> void:
	match _current_tab:
		Tab.MIDI:
			_on_midi_select_toggled(toggled)
		Tab.AUDIO:
			_on_audio_select_toggled(toggled)
		Tab.SF2:
			_on_sf2_select_toggled(toggled)
		Tab.SKIN:
			_on_skin_select_toggled(toggled)
		Tab.BG:
			_on_bg_select_toggled(toggled)


func _on_delete_pressed() -> void:
	match _current_tab:
		Tab.MIDI:
			_on_midi_delete_selected()
		Tab.AUDIO:
			_on_audio_delete_selected()
		Tab.SF2:
			_on_sf2_delete_selected()
		Tab.SKIN:
			_on_skin_delete_selected()
		Tab.BG:
			_on_bg_delete_selected()


func _update_tab_header(tab: Tab) -> void:
	_collapse_toggle.visible = (tab == Tab.MIDI or tab == Tab.AUDIO)
	match tab:
		Tab.MIDI:
			_tab_title.text = "MIDI 谱面管理"
			_update_item_sum("共 %d 首谱面" % _midi_selected.size())
			_update_midi_toggle_state()
		Tab.AUDIO:
			_tab_title.text = "人声音频管理"
			_update_item_sum("共 %d 个音频文件" % _audio_items.size())
			_update_flat_toggle_state(_audio_items)
		Tab.SF2:
			_tab_title.text = "SF2 音源管理"
			_update_item_sum("共 %d 个音源" % _sf2_items.size())
			_update_flat_toggle_state(_sf2_items)
		Tab.SKIN:
			_tab_title.text = "皮肤管理"
			_update_item_sum("共 %d 个皮肤" % _skin_items.size())
			_update_flat_toggle_state(_skin_items)
		Tab.BG:
			_tab_title.text = "背景管理"
			_update_item_sum("共 %d 张背景" % _bg_items.size())
			_update_flat_toggle_state(_bg_items)


# ============================================================
# MIDI 管理 — TreeRoot（专辑）+ TreeItem（歌曲）
# ============================================================

func _build_midi_page() -> void:
	print("[DelView] _build_midi_page called, loading=%s" % _build_loading)
	if _build_loading:
		return
	_build_loading = true
	_tab_data_built[Tab.MIDI] = false

	_clear_page(_midi_list, [_midi_root_map, _midi_item_map, _midi_path_map, _midi_selected])
	_midi_album_order.clear()
	_midi_album_midi_map.clear()

	# 构建 chart_id → path 映射
	var charts_index := FileSystemManager.instance.get_charts_index()
	for folder_name in charts_index:
		var meta: ChartMetadata = charts_index[folder_name]
		_midi_path_map[meta.id] = meta.path

	var dm := DataMGR
	print("[DelView] DataMGR midis: %d, midi_tree albums: %d" % [dm.midis.size(), dm.midi_tree.size()])

	if dm.midi_tree.is_empty() and dm.midis.is_empty():
		if dm.is_loading:
			print("[DelView] DataMGR still loading, waiting for signal")
			_update_item_sum("数据加载中...")
			_update_midi_toggle_state()
			_build_loading = false
			return
		else:
			print("[DelView] No MIDI data, showing empty state")
			_update_item_sum("无谱面数据")
			_update_midi_toggle_state()
			_tab_data_built[Tab.MIDI] = true
			_build_loading = false
			return

	# 按 album 分组
	var album_midi_map: Dictionary = {}
	var accounted_midis: Array[String] = []

	for album_id in dm.midi_tree:
		var song_dict: Dictionary = dm.midi_tree[album_id]
		if not album_midi_map.has(album_id):
			album_midi_map[album_id] = []
		for song_id in song_dict:
			var midi_ids: Array = song_dict[song_id]
			for midi_id in midi_ids:
				album_midi_map[album_id].append(midi_id)
				accounted_midis.append(midi_id)

	for midi_id in dm.midis:
		if midi_id not in accounted_midis:
			if not album_midi_map.has("__unknown__"):
				album_midi_map["__unknown__"] = []
			album_midi_map["__unknown__"].append(midi_id)

	print("[DelView] Albums to display: %d" % album_midi_map.size())

	# 排序专辑
	var album_ids := album_midi_map.keys()
	album_ids.sort_custom(func(a, b):
		if a == "__unknown__":
			return false
		if b == "__unknown__":
			return true
		var na = dm.albums[a].name if dm.albums.has(a) else a
		var nb = dm.albums[b].name if dm.albums.has(b) else b
		return na < nb if _tab_sort_ascending[_current_tab] else na > nb
	)
	_midi_album_order = album_ids

	var total_count := 0

	for idx in album_ids.size():
		var album_id: String = album_ids[idx]
		var album_name: String
		if album_id == "__unknown__":
			album_name = "Unknown"
		elif dm.albums.has(album_id):
			album_name = dm.albums[album_id].name
		else:
			album_name = album_id

		var midi_ids: Array = album_midi_map[album_id]
		# 排序专辑内的 MIDI
		midi_ids.sort_custom(func(a, b):
			var ma := dm.midis[a] as MidiData
			var mb := dm.midis[b] as MidiData
			return ma.name < mb.name if _tab_sort_ascending[_current_tab] else ma.name > mb.name
		)
		_midi_album_midi_map[album_id] = midi_ids

		# 用搜索词过滤后计数（专辑名匹配时其下所有谱面都显示）
		var album_match := _search_query.is_empty() or _search_query.to_lower() in album_name.to_lower()
		var filtered_count := 0
		for midi_id in midi_ids:
			var midi_data: MidiData = dm.midis.get(midi_id)
			if not midi_data:
				continue
			if not _search_query.is_empty() and not album_match and not _search_query.to_lower() in midi_data.name.to_lower():
				continue
			filtered_count += 1

		if filtered_count == 0:
			continue  # 无匹配子项，跳过整个专辑

		# 创建 TreeRoot（专辑）
		var root_node := _create_tree_root(album_name, "%d 首" % filtered_count, album_id)
		_midi_list.add_child(root_node)
		_midi_root_map[album_id] = root_node
		# 连接勾选信号
		var root_cb := root_node.get_node("CheckBox") as CheckBox
		root_cb.toggled.connect(_on_midi_root_checkbox_toggled.bind(album_id))

		for midi_id in midi_ids:
			var midi_data: MidiData = dm.midis.get(midi_id)
			if not midi_data:
				continue

			if not _search_query.is_empty() and not album_match and not _search_query.to_lower() in midi_data.name.to_lower():
				continue

			var author := midi_data.artist_name if not midi_data.artist_name.is_empty() else "-"
			var name_text := "    %s" % midi_data.name

			var item_node := _create_tree_item(name_text, author)
			_midi_list.add_child(item_node)
			_midi_item_map[midi_id] = item_node
			_midi_selected[midi_id] = false

			# 连接勾选信号
			var item_cb := item_node.get_node("CheckBox") as CheckBox
			item_cb.toggled.connect(_on_midi_item_checkbox_toggled.bind(midi_id, album_id))

			total_count += 1

		if idx % 3 == 2:  # 每 3 个专辑 yield 一次
			await get_tree().process_frame

	# 构建期间切了 Tab，不覆写当前页面的 header
	if _current_tab != Tab.MIDI:
		_build_loading = false
		return

	print("[DelView] Total MIDI items created: %d" % total_count)
	_update_item_sum("共 %d 首谱面" % total_count)
	_update_midi_toggle_state()
	await _apply_scrolls_to_container(_midi_list)
	_tab_data_built[Tab.MIDI] = true
	_build_loading = false

	# 确保 header 显示与实际内容一致
	_update_tab_header(Tab.MIDI)


func _on_data_loaded() -> void:
	print("[DelView] data_loaded signal received")
	if Tab.MIDI == _current_tab:
		_tab_data_built[Tab.MIDI] = false
		_build_midi_page()

# ── MIDI 勾选逻辑 ──

func _on_midi_root_checkbox_toggled(toggled: bool, album_id: String) -> void:
	var midi_ids: Array = _midi_album_midi_map.get(album_id, [])
	for midi_id in midi_ids:
		if not _midi_selected.has(midi_id):
			continue
		_midi_selected[midi_id] = toggled
		if _midi_item_map.has(midi_id):
			var item_node: HBoxContainer = _midi_item_map[midi_id]
			var cb := item_node.get_node("CheckBox") as CheckBox
			cb.set_pressed_no_signal(toggled)
	# 清除不确定状态
	var root_node: HBoxContainer = _midi_root_map.get(album_id)
	if root_node:
		var root_cb := root_node.get_node("CheckBox") as CheckBox
		_set_indeterminate(root_cb, false)
	_update_midi_toggle_state()


func _on_midi_item_checkbox_toggled(toggled: bool, midi_id: String, album_id: String) -> void:
	_midi_selected[midi_id] = toggled
	_update_root_check_state(album_id)
	_update_midi_toggle_state()


func _update_root_check_state(album_id: String) -> void:
	if not _midi_root_map.has(album_id):
		return
	var root_node: HBoxContainer = _midi_root_map[album_id]
	var root_cb := root_node.get_node("CheckBox") as CheckBox

	var midi_ids: Array = _midi_album_midi_map.get(album_id, [])
	var checked_count := 0
	var total := 0
	for midi_id in midi_ids:
		if not _midi_selected.has(midi_id):
			continue
		total += 1
		if _midi_selected[midi_id]:
			checked_count += 1

	if total == 0:
		root_cb.set_pressed_no_signal(false)
		_set_indeterminate(root_cb, false)
	elif checked_count == total:
		root_cb.set_pressed_no_signal(true)
		_set_indeterminate(root_cb, false)
	elif checked_count == 0:
		root_cb.set_pressed_no_signal(false)
		_set_indeterminate(root_cb, false)
	else:
		root_cb.set_pressed_no_signal(false)
		_set_indeterminate(root_cb, true)


func _on_midi_select_toggled(toggled: bool) -> void:
	_select_toggle.text = "取消全选" if toggled else "全选"
	for album_id in _midi_root_map:
		var midi_ids: Array = _midi_album_midi_map.get(album_id, [])
		for midi_id in midi_ids:
			if not _midi_selected.has(midi_id):
				continue
			_midi_selected[midi_id] = toggled
			if _midi_item_map.has(midi_id):
				var item_node: HBoxContainer = _midi_item_map[midi_id]
				var cb := item_node.get_node("CheckBox") as CheckBox
				cb.set_pressed_no_signal(toggled)
		var root_node: HBoxContainer = _midi_root_map[album_id]
		var root_cb := root_node.get_node("CheckBox") as CheckBox
		root_cb.set_pressed_no_signal(toggled)
		_set_indeterminate(root_cb, false)
	_update_midi_toggle_state()


func _update_midi_toggle_state() -> void:
	if _midi_selected.is_empty():
		_select_toggle.set_pressed_no_signal(false)
		_select_toggle.text = "全选"
		_select_toggle.disabled = true
		_delete_btn.disabled = true
		return

	var all_selected := true
	var any_selected := false
	for midi_id in _midi_selected:
		if _midi_selected[midi_id]:
			any_selected = true
		else:
			all_selected = false

	_select_toggle.disabled = false
	_select_toggle.set_pressed_no_signal(all_selected)
	_select_toggle.text = "取消全选" if all_selected else "全选"
	_delete_btn.disabled = not any_selected


func _on_midi_delete_selected() -> void:
	var to_delete: Array[String] = []
	for midi_id in _midi_selected:
		if _midi_selected[midi_id]:
			to_delete.append(midi_id)

	if to_delete.is_empty():
		return

	# 先收集路径信息，然后立即清空页面（视觉即时反馈）
	var path_map: Dictionary = {}
	for midi_id in to_delete:
		path_map[midi_id] = _midi_path_map.get(midi_id, "")

	_clear_page(_midi_list, [_midi_root_map, _midi_item_map])
	_midi_album_order.clear()
	_midi_album_midi_map.clear()
	_midi_path_map.clear()
	_midi_selected.clear()
	_update_midi_toggle_state()
	await get_tree().process_frame

	# 清除搜索状态，确保重建后显示全部内容
	_search_box.text = ""
	_search_query = ""

	for midi_id in to_delete:
		var path: String = path_map.get(midi_id, "")
		if path.is_empty():
			push_error("[DelView] 找不到谱面路径: %s" % midi_id)
			continue
		if FileSystemManager.instance.delete_chart(midi_id):
			print("[DelView] 已删除谱面: %s" % path)
			DataMGR.remove_midi(midi_id)
			# 通知其他视图刷新
			EvtBus.midi_deleted.emit(midi_id)
		else:
			push_error("[DelView] 删除失败: %s" % path)

	await get_tree().process_frame
	_build_midi_page()


# ============================================================
# 音频管理 — TreeRoot（歌曲）+ TreeItem（文件）
# ============================================================

func _build_audio_page() -> void:
	print("[DelView] _build_audio_page called, loading=%s" % _build_loading)
	if _build_loading:
		return
	_build_loading = true
	_tab_data_built[Tab.AUDIO] = false

	_clear_page(_audio_list, [_audio_root_map, _audio_item_map])
	_audio_group_order.clear()
	_audio_items_in_group.clear()

	_update_item_sum("扫描中...")
	await get_tree().process_frame

	_audio_items = await _scan_audio_files()

	if _audio_items.is_empty():
		_update_item_sum("无音频文件")
		_update_flat_toggle_state(_audio_items)
		_tab_data_built[Tab.AUDIO] = true
		_build_loading = false
		return

	# 按 song_name 分组
	var groups: Dictionary = {}
	for i in _audio_items.size():
		var song_name: String = _audio_items[i]["song_name"]
		if not groups.has(song_name):
			groups[song_name] = []
		groups[song_name].append(i)

	# 排序分组
	var group_names := groups.keys()
	group_names.sort_custom(func(a, b): return a < b if _tab_sort_ascending[_current_tab] else a > b)
	_audio_group_order = group_names
	_audio_items_in_group = groups

	for gi in group_names.size():
		var song_name: String = group_names[gi]
		var indices: Array = groups[song_name]
		var file_count := indices.size()

		# 创建 TreeRoot
		var root_node := _create_tree_root(song_name, "%d 个" % file_count, song_name)
		_audio_list.add_child(root_node)
		_audio_root_map[song_name] = root_node

		var root_cb := root_node.get_node("CheckBox") as CheckBox
		root_cb.toggled.connect(_on_audio_root_checkbox_toggled.bind(song_name))

		for idx in indices:
			var item: Dictionary = _audio_items[idx]
			var fmt: String = item.get("format", "")
			var item_node := _create_tree_item(item["file_name"], fmt)
			_audio_list.add_child(item_node)
			_audio_item_map[idx] = item_node

			var item_cb := item_node.get_node("CheckBox") as CheckBox
			item_cb.toggled.connect(_on_audio_item_checkbox_toggled.bind(idx, song_name))

		if gi % 5 == 4:
			await get_tree().process_frame

	# 构建期间切了 Tab，不覆写当前页面的 header
	if _current_tab != Tab.AUDIO:
		_build_loading = false
		return

	_update_item_sum("共 %d 个音频文件" % _audio_items.size())
	_update_flat_toggle_state(_audio_items)
	await _apply_scrolls_to_container(_audio_list)
	_tab_data_built[Tab.AUDIO] = true
	_build_loading = false

	# 确保 header 显示与实际内容一致
	_update_tab_header(Tab.AUDIO)


func _scan_audio_files() -> Array[Dictionary]:
	# 优先从 FileSystemManager 索引读取
	var fs_mgr = FileSystemManager.instance
	if fs_mgr and not fs_mgr.audio_files_index.is_empty():
		var result: Array[Dictionary] = []
		for entry in fs_mgr.audio_files_index:
			result.append({
				"file_name": entry["file_name"],
				"path": entry["path"],
				"format": entry["format"],
				"song_name": entry["song_name"],
				"selected": false,
			})
		return result
	
	# 回退：独立扫描文件系统
	var result: Array[Dictionary] = []
	var charts_dir := PathHelper.get_charts_dir()
	if not DirAccess.dir_exists_absolute(charts_dir):
		return result

	var dir := DirAccess.open(charts_dir)
	if not dir:
		return result

	var audio_exts := ["ogg", "mp3", "wav", "flac"]
	dir.list_dir_begin()
	var dn := dir.get_next()
	var dir_count := 0
	while dn != "":
		if dir.current_is_dir() and not dn.begins_with("."):
			var chart_path := charts_dir.path_join(dn)
			var song_name: String = dn
			var hash_idx := song_name.find("_")
			if hash_idx >= 0:
				song_name = song_name.substr(hash_idx + 1)
			for ext in audio_exts:
				var files := FileSystemManager.instance.find_files_in_dir(chart_path, "*." + ext)
				for f in files:
					result.append({
						"file_name": f,
						"path": chart_path.path_join(f),
						"format": ext,
						"song_name": song_name,
						"selected": false,
					})
			dir_count += 1
			if dir_count % 5 == 0:
				await get_tree().process_frame
		dn = dir.get_next()
	dir.list_dir_end()

	result.sort_custom(func(a, b):
		var cmp_song = a["song_name"] < b["song_name"] if _tab_sort_ascending[_current_tab] else a["song_name"] > b["song_name"]
		if cmp_song: return true
		if a["song_name"] > b["song_name"] if _tab_sort_ascending[_current_tab] else a["song_name"] < b["song_name"]: return false
		return a["format"] < b["format"] if _tab_sort_ascending[_current_tab] else a["format"] > b["format"]
	)
	return result


func _on_audio_root_checkbox_toggled(toggled: bool, song_name: String) -> void:
	var indices: Array = _audio_items_in_group.get(song_name, [])
	for idx in indices:
		_audio_items[idx]["selected"] = toggled
		if _audio_item_map.has(idx):
			var item_node: HBoxContainer = _audio_item_map[idx]
			var cb := item_node.get_node("CheckBox") as CheckBox
			cb.set_pressed_no_signal(toggled)
	# 清除不确定状态
	var root_node: HBoxContainer = _audio_root_map.get(song_name)
	if root_node:
		var root_cb := root_node.get_node("CheckBox") as CheckBox
		_set_indeterminate(root_cb, false)
	_update_flat_toggle_state(_audio_items)


func _on_audio_item_checkbox_toggled(toggled: bool, idx: int, song_name: String) -> void:
	_audio_items[idx]["selected"] = toggled
	_update_audio_root_check_state(song_name)
	_update_flat_toggle_state(_audio_items)


func _update_audio_root_check_state(song_name: String) -> void:
	if not _audio_root_map.has(song_name):
		return
	var root_node: HBoxContainer = _audio_root_map[song_name]
	var root_cb := root_node.get_node("CheckBox") as CheckBox

	var indices: Array = _audio_items_in_group.get(song_name, [])
	var checked_count := 0
	for idx in indices:
		if _audio_items[idx]["selected"]:
			checked_count += 1

	if indices.is_empty():
		root_cb.set_pressed_no_signal(false)
		_set_indeterminate(root_cb, false)
	elif checked_count == indices.size():
		root_cb.set_pressed_no_signal(true)
		_set_indeterminate(root_cb, false)
	elif checked_count == 0:
		root_cb.set_pressed_no_signal(false)
		_set_indeterminate(root_cb, false)
	else:
		root_cb.set_pressed_no_signal(false)
		_set_indeterminate(root_cb, true)


func _on_audio_select_toggled(toggled: bool) -> void:
	for i in _audio_items.size():
		_audio_items[i]["selected"] = toggled
		if _audio_item_map.has(i):
			var item_node: HBoxContainer = _audio_item_map[i]
			var cb := item_node.get_node("CheckBox") as CheckBox
			cb.set_pressed_no_signal(toggled)
	# 同步所有 TreeRoot 的勾选状态
	for song_name in _audio_root_map:
		var root_node: HBoxContainer = _audio_root_map[song_name]
		var root_cb := root_node.get_node("CheckBox") as CheckBox
		root_cb.set_pressed_no_signal(toggled)
		_set_indeterminate(root_cb, false)
	_select_toggle.text = "取消全选" if toggled else "全选"
	_update_flat_toggle_state(_audio_items)


func _on_audio_delete_selected() -> void:
	var to_delete: Array[Dictionary] = []
	for item in _audio_items:
		if item["selected"]:
			to_delete.append(item)

	if to_delete.is_empty():
		return

	# 先清空页面（视觉即时反馈）
	_clear_page(_audio_list, [_audio_root_map, _audio_item_map])
	_audio_group_order.clear()
	_audio_items_in_group.clear()
	_audio_items.clear()
	_update_flat_toggle_state(_audio_items)
	await get_tree().process_frame

	# 清除搜索状态
	_search_box.text = ""
	_search_query = ""

	for item in to_delete:
		if FileSystemManager.instance.delete_audio(item["path"]):
			print("[DelView] 已删除音频: %s" % item["file_name"])
		else:
			push_error("[DelView] 删除失败: %s" % item["path"])

	await get_tree().process_frame
	_build_audio_page()


# ============================================================
# SF2 管理 — 扁平 TreeRoot
# ============================================================

func _build_sf2_page() -> void:
	if _build_loading:
		return
	_build_loading = true
	_tab_data_built[Tab.SF2] = false

	_clear_page(_sf2_list, [_sf2_nodes])
	_sf2_items = _scan_sf2_files()

	if _sf2_items.is_empty():
		_update_item_sum("无 SF2 音源")
		_update_flat_toggle_state(_sf2_items)
		_tab_data_built[Tab.SF2] = true
		_build_loading = false
		return

	for i in _sf2_items.size():
		var item: Dictionary = _sf2_items[i]
		var display_name: String = item["file_name"]
		if item["is_builtin"]:
			display_name += " [内置]"
		var size_text := "%.1f MB" % item["size_mb"]

		var root_node := _create_tree_root(display_name, size_text, "")
		root_node.set_meta("flat_index", i)
		_sf2_list.add_child(root_node)
		_sf2_nodes[i] = root_node

		var cb := root_node.get_node("CheckBox") as CheckBox
		cb.button_pressed = item["selected"]
		if item["is_builtin"]:
			cb.disabled = true
		cb.toggled.connect(func(on: bool):
			_sf2_items[i]["selected"] = on
			_update_flat_toggle_state(_sf2_items)
		)

		# 扁平项不折叠，隐藏点击展开事件
		root_node.get_node("RightLabel").visible = true

	_update_item_sum("共 %d 个音源" % _sf2_items.size())
	_update_flat_toggle_state(_sf2_items)
	await _apply_scrolls_to_container(_sf2_list)
	_tab_data_built[Tab.SF2] = true
	_build_loading = false


func _scan_sf2_files() -> Array[Dictionary]:
	# 优先从 FileSystemManager 索引读取
	var fs_mgr = FileSystemManager.instance
	if fs_mgr:
		var sf_index = fs_mgr.get_soundfonts_index()
		if not sf_index.is_empty():
			var result: Array[Dictionary] = []
			for sf_name in sf_index:
				var entry = sf_index[sf_name]
				result.append({
					"file_name": sf_name + ".sf2",
					"path": entry["path"],
					"is_builtin": entry["is_builtin"],
					"size_mb": entry["size_mb"],
					"selected": false,
				})
			return result
	
	# 回退：独立扫描文件系统
	var result: Array[Dictionary] = []

	var user_dir := PathHelper.get_soundfont_dir()
	if DirAccess.dir_exists_absolute(user_dir):
		var dir := DirAccess.open(user_dir)
		if dir:
			dir.list_dir_begin()
			var fn := dir.get_next()
			while fn != "":
				if fn.ends_with(".sf2") and not dir.current_is_dir():
					var f := FileAccess.open(user_dir.path_join(fn), FileAccess.READ)
					var size_mb := 0.0
					if f:
						size_mb = snapped(f.get_length() / 1048576.0, 0.1)
						f.close()
					result.append({
						"file_name": fn,
						"path": user_dir.path_join(fn),
						"is_builtin": false,
						"size_mb": size_mb,
						"selected": false,
					})
				fn = dir.get_next()
			dir.list_dir_end()

	var res_dir := "res://Resources/Soundfont/"
	if DirAccess.dir_exists_absolute(res_dir):
		var dir := DirAccess.open(res_dir)
		if dir:
			dir.list_dir_begin()
			var fn := dir.get_next()
			while fn != "":
				if fn.ends_with(".sf2") and not dir.current_is_dir():
					var already_in_user := false
					for item in result:
						if item["file_name"] == fn:
							already_in_user = true
							break
					if not already_in_user:
						var f := FileAccess.open(res_dir.path_join(fn), FileAccess.READ)
						var size_mb := 0.0
						if f:
							size_mb = snapped(f.get_length() / 1048576.0, 0.1)
							f.close()
						result.append({
							"file_name": fn,
							"path": res_dir.path_join(fn),
							"is_builtin": true,
							"size_mb": size_mb,
							"selected": false,
						})
				fn = dir.get_next()
			dir.list_dir_end()

	result.sort_custom(func(a, b):
		if a["is_builtin"] != b["is_builtin"]:
			return not a["is_builtin"]
		return a["file_name"] < b["file_name"] if _tab_sort_ascending[_current_tab] else a["file_name"] > b["file_name"]
	)
	return result


func _on_sf2_select_toggled(toggled: bool) -> void:
	for i in _sf2_items.size():
		if not _sf2_items[i]["is_builtin"]:
			_sf2_items[i]["selected"] = toggled
		if _sf2_nodes.has(i):
			var cb := _sf2_nodes[i].get_node("CheckBox") as CheckBox
			if not _sf2_items[i]["is_builtin"]:
				cb.set_pressed_no_signal(toggled)
	_select_toggle.text = "取消全选" if toggled else "全选"
	_update_flat_toggle_state(_sf2_items)


func _on_sf2_delete_selected() -> void:
	var to_delete: Array[Dictionary] = []
	for item in _sf2_items:
		if item["selected"] and not item["is_builtin"]:
			to_delete.append(item)

	if to_delete.is_empty():
		return

	for item in to_delete:
		if FileSystemManager.instance.delete_soundfont(item["path"]):
			print("[DelView] 已删除音源: %s" % item["file_name"])
		else:
			push_error("[DelView] 删除失败: %s" % item["path"])

	await get_tree().process_frame
	_build_sf2_page()


# ============================================================
# 皮肤管理 — 扁平 TreeRoot
# ============================================================

func _build_skin_page() -> void:
	if _build_loading:
		return
	_build_loading = true
	_tab_data_built[Tab.SKIN] = false

	_clear_page(_skin_list, [_skin_nodes])

	var skins_index := SkinMGR.get_skins_index()
	_skin_items.clear()

	for skin_name in skins_index:
		var meta: SkinMetadata = skins_index[skin_name]
		_skin_items.append({
			"name": skin_name,
			"path": meta.path,
			"is_builtin": meta.is_builtin,
			"selected": false,
		})

	_skin_items.sort_custom(func(a, b):
		if a["is_builtin"] != b["is_builtin"]:
			return not a["is_builtin"]
		return a["name"] < b["name"] if _tab_sort_ascending[_current_tab] else a["name"] > b["name"]
	)

	if _skin_items.is_empty():
		_update_item_sum("无皮肤")
		_update_flat_toggle_state(_skin_items)
		_tab_data_built[Tab.SKIN] = true
		_build_loading = false
		return

	for i in _skin_items.size():
		var item: Dictionary = _skin_items[i]
		var display_name: String = item["name"]
		if item["is_builtin"]:
			display_name += " [内置]"

		var root_node := _create_tree_root(display_name, "", "")
		root_node.get_node("RightLabel").visible = false  # 皮肤无格式信息
		root_node.set_meta("flat_index", i)
		_skin_list.add_child(root_node)
		_skin_nodes[i] = root_node

		var cb := root_node.get_node("CheckBox") as CheckBox
		cb.button_pressed = item["selected"]
		if item["is_builtin"]:
			cb.disabled = true
		cb.toggled.connect(func(on: bool):
			_skin_items[i]["selected"] = on
			_update_flat_toggle_state(_skin_items)
		)

	_update_item_sum("共 %d 个皮肤" % _skin_items.size())
	_update_flat_toggle_state(_skin_items)
	await _apply_scrolls_to_container(_skin_list)
	_tab_data_built[Tab.SKIN] = true
	_build_loading = false


func _on_skin_select_toggled(toggled: bool) -> void:
	for i in _skin_items.size():
		if not _skin_items[i]["is_builtin"]:
			_skin_items[i]["selected"] = toggled
		if _skin_nodes.has(i):
			var cb := _skin_nodes[i].get_node("CheckBox") as CheckBox
			if not _skin_items[i]["is_builtin"]:
				cb.set_pressed_no_signal(toggled)
	_select_toggle.text = "取消全选" if toggled else "全选"
	_update_flat_toggle_state(_skin_items)


func _on_skin_delete_selected() -> void:
	var to_delete: Array[Dictionary] = []
	for item in _skin_items:
		if item["selected"] and not item["is_builtin"]:
			to_delete.append(item)

	if to_delete.is_empty():
		return

	for item in to_delete:
		if SkinMGR.remove_skin(item["name"]):
			print("[DelView] 已删除皮肤: %s" % item["name"])
		else:
			push_error("[DelView] 皮肤已从列表移除，但文件夹删除失败，请手动清理: %s" % item["path"])

	await get_tree().process_frame
	_build_skin_page()


# ============================================================
# 背景管理 — 扁平 TreeRoot
# ============================================================

func _build_bg_page() -> void:
	if _build_loading:
		return
	_build_loading = true
	_tab_data_built[Tab.BG] = false

	_clear_page(_bg_list, [_bg_nodes])

	var bg_index := FileSystemManager.instance.get_backgrounds_index()
	_bg_items.clear()

	for bg_name in bg_index:
		var path: String = bg_index[bg_name]
		var ext := path.get_extension().to_lower() if not path.is_empty() else ""
		_bg_items.append({
			"name": bg_name,
			"path": path,
			"ext": ext,
			"selected": false,
		})

	_bg_items.sort_custom(func(a, b): return a["name"] < b["name"] if _tab_sort_ascending[_current_tab] else a["name"] > b["name"])

	if _bg_items.is_empty():
		_update_item_sum("无背景图片")
		_update_flat_toggle_state(_bg_items)
		_tab_data_built[Tab.BG] = true
		_build_loading = false
		return

	for i in _bg_items.size():
		var item: Dictionary = _bg_items[i]
		var ext: String = item.get("ext", "")
		var root_node := _create_tree_root(item["name"], ext, "")
		root_node.set_meta("flat_index", i)
		_bg_list.add_child(root_node)
		_bg_nodes[i] = root_node

		var cb := root_node.get_node("CheckBox") as CheckBox
		cb.button_pressed = item["selected"]
		cb.toggled.connect(func(on: bool):
			_bg_items[i]["selected"] = on
			_update_flat_toggle_state(_bg_items)
		)

	_update_item_sum("共 %d 张背景" % _bg_items.size())
	_update_flat_toggle_state(_bg_items)
	await _apply_scrolls_to_container(_bg_list)
	_tab_data_built[Tab.BG] = true
	_build_loading = false


func _on_bg_select_toggled(toggled: bool) -> void:
	for i in _bg_items.size():
		_bg_items[i]["selected"] = toggled
		if _bg_nodes.has(i):
			var cb := _bg_nodes[i].get_node("CheckBox") as CheckBox
			cb.set_pressed_no_signal(toggled)
	_select_toggle.text = "取消全选" if toggled else "全选"
	_update_flat_toggle_state(_bg_items)


func _on_bg_delete_selected() -> void:
	var to_delete: Array[Dictionary] = []
	for item in _bg_items:
		if item["selected"]:
			to_delete.append(item)

	if to_delete.is_empty():
		return

	for item in to_delete:
		if FileSystemManager.instance.delete_background(item["path"]):
			print("[DelView] 已删除背景: %s" % item["name"])
		else:
			push_error("[DelView] 删除失败: %s" % item["path"])

	await get_tree().process_frame
	_build_bg_page()


# ============================================================
# 折叠 / 展开
# ============================================================

func _on_collapse_toggled(toggled: bool) -> void:
	_collapse_toggle.text = "展开全部" if toggled else "收起全部"
	match _current_tab:
		Tab.MIDI:
			for album_id in _midi_root_map:
				var root_node: HBoxContainer = _midi_root_map[album_id]
				root_node.set_meta("collapsed", toggled)
			_apply_collapse_visibility(_midi_list)
		Tab.AUDIO:
			for song_name in _audio_root_map:
				var root_node: HBoxContainer = _audio_root_map[song_name]
				root_node.set_meta("collapsed", toggled)
			_apply_collapse_visibility(_audio_list)


func _on_root_label_gui_input(event: InputEvent, root_node: HBoxContainer) -> void:
	if not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	# 排除 CheckBox 区域的点击
	var cb := root_node.get_node("CheckBox") as CheckBox
	if cb.get_global_rect().has_point(event.global_position):
		return
	if event.pressed:
		# 记录按下位置，用于判断是否为点击（非拖动）
		root_node.set_meta("_press_pos", event.global_position)
	else:
		# 松手时判断：位置偏移小 → 点击，偏移大 → 拖动，不触发
		var press_pos: Vector2 = root_node.get_meta("_press_pos", Vector2.INF)
		root_node.remove_meta("_press_pos")
		if press_pos == Vector2.INF:
			return
		if event.global_position.distance_to(press_pos) < 10.0:
			_toggle_root_collapse(root_node)


func _toggle_root_collapse(root_node: HBoxContainer) -> void:
	var collapsed: bool = root_node.get_meta("collapsed", false)
	var new_state := not collapsed
	root_node.set_meta("collapsed", new_state)

	var list_container := root_node.get_parent() as VBoxContainer
	if not list_container:
		return

	var children := list_container.get_children()
	var found_self := false
	for child in children:
		if child == root_node:
			found_self = true
			continue
		if not found_self:
			continue
		# 遇到下一个 TreeRoot（有 collapsed meta）时停止
		if child.has_meta("collapsed"):
			break
		child.visible = not new_state  # collapsed=true → visible=false


func _apply_collapse_visibility(list_container: VBoxContainer) -> void:
	var children := list_container.get_children()
	var current_root: HBoxContainer = null
	for child in children:
		if child.has_meta("collapsed"):
			current_root = child as HBoxContainer
			continue
		if current_root:
			var collapsed: bool = current_root.get_meta("collapsed", false)
			child.visible = not collapsed


# ============================================================
# 搜索 / 排序
# ============================================================

func _on_search_text_changed(new_text: String) -> void:
	_search_query = new_text.strip_edges()
	_apply_search_filter()


func _apply_search_filter() -> void:
	# 空搜索：恢复全部可见
	if _search_query.is_empty():
		match _current_tab:
			Tab.MIDI:
				_reset_midi_visibility()
				_update_item_sum("共 %d 首谱面" % _midi_selected.size())
			Tab.AUDIO:
				_reset_grouped_visibility(_audio_list, _audio_root_map, _audio_item_map)
				_update_item_sum("共 %d 个音频文件" % _audio_items.size())
			Tab.SF2:
				_reset_flat_visibility(_sf2_nodes)
				_update_item_sum("共 %d 个音源" % _sf2_items.size())
			Tab.SKIN:
				_reset_flat_visibility(_skin_nodes)
				_update_item_sum("共 %d 个皮肤" % _skin_items.size())
			Tab.BG:
				_reset_flat_visibility(_bg_nodes)
				_update_item_sum("共 %d 张背景" % _bg_items.size())
		return

	match _current_tab:
		Tab.MIDI:
			_apply_midi_search()
		Tab.AUDIO:
			_apply_grouped_search(_audio_list, _audio_root_map, _audio_item_map,
				_audio_group_order, _audio_items_in_group, _audio_items,
				"song_name", "file_name", "个音频文件")
		Tab.SF2:
			_apply_flat_search(_sf2_nodes, _sf2_items, "file_name", "个音源")
		Tab.SKIN:
			_apply_flat_search(_skin_nodes, _skin_items, "name", "个皮肤")
		Tab.BG:
			_apply_flat_search(_bg_nodes, _bg_items, "name", "张背景")


func _apply_midi_search() -> void:
	var query_lower := _search_query.to_lower()
	var dm := DataMGR
	var visible_count := 0

	for album_id in _midi_album_order:
		var album_name := _get_album_name(album_id)
		var album_match := query_lower in album_name.to_lower()
		var has_visible_child := false
		var root_node: HBoxContainer = _midi_root_map.get(album_id)

		var midi_ids: Array = _midi_album_midi_map.get(album_id, [])
		for midi_id in midi_ids:
			if not _midi_item_map.has(midi_id):
				continue
			var midi_data: MidiData = dm.midis.get(midi_id)
			if not midi_data:
				continue
			var midi_match := query_lower in midi_data.name.to_lower()
			var item_node: HBoxContainer = _midi_item_map[midi_id]

			if album_match or midi_match:
				var collapsed: bool = root_node.get_meta("collapsed", false) if root_node else false
				item_node.visible = not collapsed
				has_visible_child = true
				visible_count += 1
			else:
				item_node.visible = false

		if root_node:
			root_node.visible = has_visible_child

	_update_item_sum("共 %d 首谱面 (匹配 %d 首)" % [_midi_selected.size(), visible_count])


func _get_album_name(album_id: String) -> String:
	if album_id == "__unknown__":
		return "Unknown"
	var dm := DataMGR
	if dm.albums.has(album_id):
		return dm.albums[album_id].name
	return album_id


func _apply_grouped_search(list: VBoxContainer, root_map: Dictionary, item_map: Dictionary,
		group_order: Array, items_in_group: Dictionary, data: Array,
		root_key: String, item_key: String, unit: String) -> void:
	var query_lower := _search_query.to_lower()
	var visible_count := 0

	for group_name in group_order:
		var group_match := query_lower in str(group_name).to_lower()
		var has_visible := false
		var root_node: HBoxContainer = root_map.get(group_name)

		for idx in items_in_group[group_name]:
			var text: String = data[idx].get(item_key, "")
			var matches := group_match or (query_lower in text.to_lower())
			if item_map.has(idx):
				var collapsed: bool = root_node.get_meta("collapsed", false) if root_node else false
				item_map[idx].visible = matches and not collapsed
			if matches:
				has_visible = true
				visible_count += 1

		if root_node:
			root_node.visible = has_visible

	_update_item_sum("共 %d %s (匹配 %d 个)" % [data.size(), unit, visible_count])


func _apply_flat_search(nodes: Dictionary, items: Array, key: String, unit: String) -> void:
	var query_lower := _search_query.to_lower()
	var visible_count := 0
	for i in items.size():
		var text: String = items[i].get(key, "")
		var matches := query_lower in text.to_lower()
		if nodes.has(i):
			nodes[i].visible = matches
		if matches:
			visible_count += 1
	_update_item_sum("共 %d %s (匹配 %d 个)" % [items.size(), unit, visible_count])


func _reset_midi_visibility() -> void:
	for album_id in _midi_root_map:
		_midi_root_map[album_id].visible = true
	for midi_id in _midi_item_map:
		_midi_item_map[midi_id].visible = true
	_apply_collapse_visibility(_midi_list)


func _reset_grouped_visibility(list: VBoxContainer, root_map: Dictionary, item_map: Dictionary) -> void:
	for key in root_map:
		root_map[key].visible = true
	for key in item_map:
		item_map[key].visible = true
	_apply_collapse_visibility(list)


func _reset_flat_visibility(nodes: Dictionary) -> void:
	for idx in nodes:
		nodes[idx].visible = true


# ── 排序 ──

func _on_order_btn_pressed() -> void:
	_tab_sort_ascending[_current_tab] = not _tab_sort_ascending[_current_tab]
	_order_btn.icon = load("res://Resources/icon/Sort/Ordering/Ascent.png" if _tab_sort_ascending[_current_tab] else "res://Resources/icon/Sort/Ordering/Descent.png")
	match _current_tab:
		Tab.MIDI:
			_resort_midi_instant()
		Tab.AUDIO:
			_resort_audio_instant()
		Tab.SF2:
			_resort_flat_instant(_sf2_items, _sf2_nodes, _sf2_list, "_compare_sf2")
		Tab.SKIN:
			_resort_flat_instant(_skin_items, _skin_nodes, _skin_list, "_compare_skin")
		Tab.BG:
			_resort_flat_instant(_bg_items, _bg_nodes, _bg_list, "_compare_bg")


func _resort_midi_instant() -> void:
	var dm := DataMGR
	# 1. 排序专辑顺序
	_midi_album_order.sort_custom(func(a, b):
		if a == "__unknown__":
			return false
		if b == "__unknown__":
			return true
		var na = dm.albums[a].name if dm.albums.has(a) else a
		var nb = dm.albums[b].name if dm.albums.has(b) else b
		return na < nb if _tab_sort_ascending[_current_tab] else na > nb
	)

	# 2. 排序每个专辑内的 MIDI
	for album_id in _midi_album_midi_map:
		var arr: Array = _midi_album_midi_map[album_id]
		arr.sort_custom(func(a: String, b: String):
			if not dm.midis.has(a) or not dm.midis.has(b):
				return false
			var ma := (dm.midis[a] as MidiData).name
			var mb := (dm.midis[b] as MidiData).name
			return ma < mb if _tab_sort_ascending[_current_tab] else ma > mb
		)

	# 3. 原地重新排序 VBoxContainer 子节点
	for album_id in _midi_album_order:
		if not _midi_root_map.has(album_id):
			continue
		var root_node: HBoxContainer = _midi_root_map[album_id]
		_midi_list.move_child(root_node, -1)
		for midi_id in _midi_album_midi_map.get(album_id, []):
			if _midi_item_map.has(midi_id):
				_midi_list.move_child(_midi_item_map[midi_id], -1)


func _resort_audio_instant() -> void:
	# 1. 排序分组
	_audio_group_order.sort_custom(func(a, b): return a < b if _tab_sort_ascending[_current_tab] else a > b)

	# 2. 排序每组内的项
	for song_name in _audio_items_in_group:
		var indices: Array = _audio_items_in_group[song_name]
		indices.sort_custom(func(ai: int, bi: int):
			var fa = _audio_items[ai]["format"]
			var fb = _audio_items[bi]["format"]
			return fa < fb if _tab_sort_ascending[_current_tab] else fa > fb
		)

	# 3. 原地重新排序
	for song_name in _audio_group_order:
		if not _audio_root_map.has(song_name):
			continue
		var root_node: HBoxContainer = _audio_root_map[song_name]
		_audio_list.move_child(root_node, -1)
		for idx in _audio_items_in_group.get(song_name, []):
			if _audio_item_map.has(idx):
				_audio_list.move_child(_audio_item_map[idx], -1)


func _resort_flat_instant(items: Array, nodes: Dictionary, list: VBoxContainer, compare_func: String) -> void:
	# 1. 排序索引
	var indices: Array = range(items.size())
	indices.sort_custom(func(a: int, b: int): return call(compare_func, items[a], items[b]))

	# 2. 原地重新排序
	for i in indices:
		if nodes.has(i):
			list.move_child(nodes[i], -1)


# 比较函数（用于 _resort_flat_instant）
func _compare_sf2(a: Dictionary, b: Dictionary) -> bool:
	if a["is_builtin"] != b["is_builtin"]:
		return not a["is_builtin"]
	return a["file_name"] < b["file_name"] if _tab_sort_ascending[_current_tab] else a["file_name"] > b["file_name"]


func _compare_skin(a: Dictionary, b: Dictionary) -> bool:
	if a["is_builtin"] != b["is_builtin"]:
		return not a["is_builtin"]
	return a["name"] < b["name"] if _tab_sort_ascending[_current_tab] else a["name"] > b["name"]


func _compare_bg(a: Dictionary, b: Dictionary) -> bool:
	return a["name"] < b["name"] if _tab_sort_ascending[_current_tab] else a["name"] > b["name"]


# ============================================================
# 通用工具
# ============================================================

func _update_item_sum(text: String) -> void:
	_item_sum.text = text
	_item_sum_scroll_state = TextScrollHelper.setup(_item_sum, _item_sum.get_parent(), text, _item_sum_scroll_state)


func _create_tree_root(left_text: String, right_text: String, group_id: String) -> HBoxContainer:
	var node := TREE_ROOT_SCENE.instantiate() as HBoxContainer
	var left_label := node.get_node("LeftLabel/label") as Label
	var right_label := node.get_node("RightLabel/label") as Label
	var left_clip := node.get_node("LeftLabel") as Control
	var right_clip := node.get_node("RightLabel") as Control
	left_label.text = left_text
	right_label.text = right_text
	node.set_meta("group_id", group_id)
	node.set_meta("collapsed", false)
	# 点击 TreeRoot 的非 CheckBox 区域 → 折叠/展开
	node.gui_input.connect(_on_root_label_gui_input.bind(node))
	return node


func _create_tree_item(left_text: String, right_text: String) -> HBoxContainer:
	var node := TREE_ITEM_SCENE.instantiate() as HBoxContainer
	var left_label := node.get_node("LeftLabel/label") as Label
	var right_label := node.get_node("RightLabel/label") as Label
	var left_clip := node.get_node("LeftLabel") as Control
	var right_clip := node.get_node("RightLabel") as Control
	left_label.text = left_text
	right_label.text = right_text
	return node


func _apply_scrolls_to_container(container: VBoxContainer) -> void:
	if container.get_child_count() == 0:
		return
	await get_tree().process_frame
	for child in container.get_children():
		var left_label := child.get_node_or_null("LeftLabel/label") as Label
		var left_clip := child.get_node_or_null("LeftLabel") as Control
		if left_label and left_clip:
			TextScrollHelper.setup(left_label, left_clip, left_label.text)
		var right_label := child.get_node_or_null("RightLabel/label") as Label
		var right_clip := child.get_node_or_null("RightLabel") as Control
		if right_label and right_clip:
			TextScrollHelper.setup(right_label, right_clip, right_label.text)


func _set_indeterminate(cb: CheckBox, indeterminate: bool) -> void:
	if indeterminate:
		cb.self_modulate = Color(0.5, 0.5, 0.5, 1.0)
		cb.tooltip_text = "部分选中"
	else:
		cb.self_modulate = Color.WHITE
		cb.tooltip_text = ""


func _clear_page(container: VBoxContainer, collections: Array) -> void:
	for child in container.get_children():
		child.queue_free()
	for col in collections:
		if col is Dictionary:
			col.clear()
		elif col is Array:
			col.clear()


func _update_flat_toggle_state(items: Array) -> void:
	if items.is_empty():
		_select_toggle.set_pressed_no_signal(false)
		_select_toggle.text = "全选"
		_select_toggle.disabled = true
		_delete_btn.disabled = true
		return

	var all_checked := true
	var any_checked := false

	for item in items:
		if item["selected"]:
			any_checked = true
		else:
			all_checked = false

	_select_toggle.disabled = false
	_select_toggle.set_pressed_no_signal(all_checked)
	_select_toggle.text = "取消全选" if all_checked else "全选"
	_delete_btn.disabled = not any_checked
