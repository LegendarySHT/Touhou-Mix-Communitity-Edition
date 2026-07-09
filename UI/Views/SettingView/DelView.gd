extends HBoxContainer
class_name DelView

enum Tab {MIDI = 0, AUDIO = 1, SF2 = 2, SKIN = 3, BG = 4}

# ── Sidebar ──
# @onready var _sidebar := $SideBar as VBoxContainer
@onready var _tab_buttons: Array[Button] = [
	$SideBar/TabBtn0,
	$SideBar/TabBtn1,
	$SideBar/TabBtn2,
	$SideBar/TabBtn3,
	$SideBar/TabBtn4,
]

# ── TopBar ──
@onready var _tab_title := $Content/PC/TopBar/TabTitle as Label
@onready var _item_sum := $Content/PC/TopBar/ItemSum as Label

# ── PageContainer ──
@onready var _page_container := $Content/PageContainer as TabContainer

# ── MIDI 页面 ──
@onready var _midi_tree := $Content/PageContainer/MidiPage/MidiTree as Tree

# ── 音频页面 ──
@onready var _audio_list := $Content/PageContainer/AudioPage/AudioScroll/AudioList as VBoxContainer

# ── SF2 页面 ──
@onready var _sf2_list := $Content/PageContainer/Sf2Page/Sf2Scroll/Sf2List as VBoxContainer

# ── 皮肤页面 ──
@onready var _skin_list := $Content/PageContainer/SkinPage/SkinScroll/SkinList as VBoxContainer

# ── 背景页面 ──
@onready var _bg_list := $Content/PageContainer/BgPage/BgScroll/BgList as VBoxContainer

# ── 共享底栏 ──
@onready var _select_toggle := $Content/BottomBarPC/BottomBar/SelectToggle as Button
@onready var _collapse_toggle := $Content/BottomBarPC/BottomBar/CollapseToggle as Button
@onready var _delete_btn := $Content/BottomBarPC/BottomBar/DeleteBtn as Button

# ── TopBar 控件 ──
@onready var _search_box := $Content/PC/TopBar/SearchBox as LineEdit
@onready var _order_btn := $Content/PC/TopBar/OrderBtn as Button

var _current_tab: Tab = Tab.MIDI
var _sort_ascending: bool = true
var _search_query: String = ""

# MIDI 数据
var _midi_path_map: Dictionary = {}       # chart_id → folder_path
var _midi_album_items: Dictionary = {}     # album_id → TreeItem
var _midi_selected: Dictionary = {}
var _updating_checkboxes: bool = false

# 列表数据
var _audio_items: Array[Dictionary] = []
var _sf2_items: Array[Dictionary] = []
var _skin_items: Array[Dictionary] = []
var _bg_items: Array[Dictionary] = []

# 缓存标记：TabContainer 保留页面内容，切回时跳过重建
var _tab_data_built: Array[bool] = [false, false, false, false, false]
var _midi_tree_loading: bool = false


func _ready() -> void:
	print("[DelView] _ready start")
	for i in _tab_buttons.size():
		_tab_buttons[i].pressed.connect(_on_tab_button_pressed.bind(i))

	_midi_tree.item_edited.connect(_on_midi_item_edited)
	_midi_tree.gui_input.connect(_on_midi_tree_gui_input)
	_select_toggle.toggled.connect(_on_select_toggled)
	_delete_btn.pressed.connect(_on_delete_pressed)
	_collapse_toggle.toggled.connect(_on_midi_collapse_toggled)

	_midi_tree.columns = 3
	_midi_tree.set_column_title(0, "")
	_midi_tree.set_column_title(1, "名称")
	_midi_tree.set_column_title(2, "作者")
	_midi_tree.set_column_expand(0, false)
	_midi_tree.set_column_expand_ratio(0, 0)
	_midi_tree.set_column_expand(1, true)
	_midi_tree.set_column_expand_ratio(1, 2)
	_midi_tree.set_column_expand(2, false)
	_midi_tree.set_column_expand_ratio(2, 2)
	_midi_tree.set_column_custom_minimum_width(0, 80)
	_midi_tree.set_column_custom_minimum_width(2, 240)

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

	_collapse_toggle.visible = (tab == Tab.MIDI)

	if _tab_data_built[tab]:
		print("[DelView] Tab %d cached, updating header only" % tab)
		_update_tab_header(tab)
		_apply_search_filter()
		return

	_collapse_toggle.visible = (tab == Tab.MIDI)

	match tab:
		Tab.MIDI:
			_tab_title.text = "MIDI 谱面管理"
			_build_midi_tree()
		Tab.AUDIO:
			_tab_title.text = "人声音频管理"
			_build_audio_list()
		Tab.SF2:
			_tab_title.text = "SF2 音源管理"
			_build_sf2_list()
		Tab.SKIN:
			_tab_title.text = "皮肤管理"
			_build_skin_list()
		Tab.BG:
			_tab_title.text = "背景管理"
			_build_bg_list()


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
	_collapse_toggle.visible = (tab == Tab.MIDI)
	match tab:
		Tab.MIDI:
			_tab_title.text = "MIDI 谱面管理"
			_item_sum.text = "共 %d 首谱面" % _midi_selected.size()
			_update_midi_toggle_state()
		Tab.AUDIO:
			_tab_title.text = "人声音频管理"
			_item_sum.text = "共 %d 个 MP3 文件" % _audio_items.size()
			_update_list_toggle_state(false)
		Tab.SF2:
			_tab_title.text = "SF2 音源管理"
			_item_sum.text = "共 %d 个音源" % _sf2_items.size()
			_update_list_toggle_state(false)
		Tab.SKIN:
			_tab_title.text = "皮肤管理"
			_item_sum.text = "共 %d 个皮肤" % _skin_items.size()
			_update_list_toggle_state(false)
		Tab.BG:
			_tab_title.text = "背景管理"
			_item_sum.text = "共 %d 张背景" % _bg_items.size()
			_update_list_toggle_state(false)


# ============================================================
# MIDI 管理 — Tree 两级结构
# ============================================================

func _build_midi_tree() -> void:
	print("[DelView] _build_midi_tree called, loading=%s, cached=%s" % [_midi_tree_loading, _tab_data_built[Tab.MIDI]])
	if _midi_tree_loading:
		print("[DelView] _build_midi_tree blocked by loading guard")
		return
	_midi_tree_loading = true
	_tab_data_built[Tab.MIDI] = false

	_midi_tree.clear()
	_midi_path_map.clear()
	_midi_album_items.clear()
	_midi_selected.clear()

	print("[DelView] Tree visibility=%s, size=%s" % [_midi_tree.visible, _midi_tree.size])
	print("[DelView] Tree parent chain: %s" % _get_node_path_chain(_midi_tree))

	# 构建 chart_id → path 映射
	var charts_index := FileSystemManager.instance.get_charts_index()
	print("[DelView] charts_index entries: %d" % charts_index.size())
	for folder_name in charts_index:
		var meta: ChartMetadata = charts_index[folder_name]
		_midi_path_map[meta.id] = meta.path

	var dm := DataMGR
	print("[DelView] DataMGR midis: %d, midi_tree albums: %d, albums: %d" % [dm.midis.size(), dm.midi_tree.size(), dm.albums.size()])

	var root := _midi_tree.create_item()
	print("[DelView] Root item created: %s" % root)

	if dm.midi_tree.is_empty() and dm.midis.is_empty():
		if dm.is_loading:
			print("[DelView] DataMGR still loading, waiting for signal")
			_item_sum.text = "数据加载中..."
			_update_midi_toggle_state()
			_midi_tree_loading = false
			return
		else:
			print("[DelView] No MIDI data, showing empty state")
			_item_sum.text = "无谱面数据"
			_update_midi_toggle_state()
			_midi_tree_loading = false
			_tab_data_built[Tab.MIDI] = true
			return

	# 按 album 分组：album_id → [midi_id, ...]
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

	print("[DelView] Albums to display: %d (including unknown=%s)" % [album_midi_map.size(), album_midi_map.has("__unknown__")])

	var album_ids := album_midi_map.keys()
	album_ids.sort_custom(func(a, b):
		if a == "__unknown__":
			return false
		if b == "__unknown__":
			return true
		var na = dm.albums[a].name if dm.albums.has(a) else a
		var nb = dm.albums[b].name if dm.albums.has(b) else b
		return na < nb if _sort_ascending else na > nb
	)

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

		var album_item := _midi_tree.create_item(root)
		album_item.set_text(1, album_name)
		album_item.set_metadata(0, {"type": "album", "id": album_id})
		album_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		album_item.set_editable(0, true)
		album_item.set_collapsed(false)
		_midi_album_items[album_id] = album_item

		var midi_ids: Array = album_midi_map[album_id]
		midi_ids.sort_custom(func(a, b):
			var ma := dm.midis[a] as MidiData
			var mb := dm.midis[b] as MidiData
			return ma.name < mb.name if _sort_ascending else ma.name > mb.name
		)

		for midi_id in midi_ids:
			var midi_data: MidiData = dm.midis.get(midi_id)
			if not midi_data:
				continue

			if not _search_query.is_empty() and not _search_query.to_lower() in midi_data.name.to_lower():
				continue

			var author := midi_data.artist_name if not midi_data.artist_name.is_empty() else "-"

			var difficulty := _get_midi_difficulty(midi_id)

			var midi_item := _midi_tree.create_item(album_item)
			midi_item.set_text(1, "    %s  [%s]" % [midi_data.name, difficulty])
			midi_item.set_text(2, author)
			midi_item.set_metadata(0, {"type": "midi", "id": midi_id, "album_id": album_id})
			midi_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			midi_item.set_editable(0, true)
			midi_item.set_checked(0, false)
			_midi_selected[midi_id] = false
			total_count += 1

	if not _search_query.is_empty():
		var album := root.get_first_child()
		while album:
			var next_album := album.get_next()
			if album.get_first_child() == null:
				root.remove_child(album)
				album.free()
			album = next_album

	print("[DelView] Total MIDI items created: %d" % total_count)
	print("[DelView] Tree root child count: %d" % root.get_child_count())
	_item_sum.text = "共 %d 首谱面" % total_count
	_update_midi_toggle_state()
	_tab_data_built[Tab.MIDI] = true
	_midi_tree_loading = false


func _on_data_loaded() -> void:
	print("[DelView] data_loaded signal received")
	if Tab.MIDI == _current_tab:
		_tab_data_built[Tab.MIDI] = false
		_build_midi_tree()


func _get_node_path_chain(node: Node) -> String:
	var parts: Array[String] = []
	var n := node
	while n:
		parts.push_front(n.name)
		n = n.get_parent()
	return "/".join(parts)


func _get_midi_difficulty(midi_id: String) -> String:
	var charts_index := FileSystemManager.instance.get_charts_index()
	for folder_name in charts_index:
		var meta: ChartMetadata = charts_index[folder_name]
		if meta.id == midi_id:
			return _parse_difficulty(meta.folder_name)
	return "?"


func _parse_difficulty(folder_name: String) -> String:
	if "_Easy" in folder_name or "_easy" in folder_name:
		return "Easy"
	elif "_Normal" in folder_name or "_normal" in folder_name:
		return "Normal"
	elif "_Hard" in folder_name or "_hard" in folder_name:
		return "Hard"
	return "?"


func _on_midi_item_edited() -> void:
	if _updating_checkboxes:
		return
	_updating_checkboxes = true

	var item := _midi_tree.get_edited()
	if not item:
		_updating_checkboxes = false
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty():
		_updating_checkboxes = false
		return
	var checked := item.is_checked(0)
	if meta["type"] == "album":
		var child := item.get_first_child()
		while child:
			var cm: Dictionary = child.get_metadata(0)
			var midi_id: String = cm.get("id", "")
			if not midi_id.is_empty():
				_midi_selected[midi_id] = checked
				child.set_checked(0, checked)
			child = child.get_next()
		item.set_indeterminate(0, false)
	elif meta["type"] == "midi":
		var midi_id: String = meta["id"]
		_midi_selected[midi_id] = checked
		_update_album_check_state(meta.get("album_id", ""))
	_update_midi_toggle_state()
	_updating_checkboxes = false

func _on_midi_tree_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var item := _midi_tree.get_item_at_position(mb.position)
	if not item:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty():
		return
	var col := _midi_tree.get_column_at_position(mb.position)
	if col == 0:
		return
	if meta["type"] == "album":
		item.set_collapsed(not item.is_collapsed())
	elif meta["type"] == "midi":
		var midi_id: String = meta["id"]
		var cur = _midi_selected.get(midi_id, false)
		_midi_selected[midi_id] = not cur
		_updating_checkboxes = true
		item.set_checked(0, not cur)
		_updating_checkboxes = false
		_update_album_check_state(meta.get("album_id", ""))
		_update_midi_toggle_state()

func _update_album_check_state(album_id: String) -> void:
	if not _midi_album_items.has(album_id):
		return
	var album_item: TreeItem = _midi_album_items[album_id]
	var any_checked := false
	var all_checked := true
	var child := album_item.get_first_child()
	while child:
		var cm: Dictionary = child.get_metadata(0)
		var midi_id: String = cm.get("id", "")
		if not midi_id.is_empty():
			if _midi_selected.get(midi_id, false):
				any_checked = true
			else:
				all_checked = false
		child = child.get_next()
	if any_checked and all_checked:
		album_item.set_checked(0, true)
		album_item.set_indeterminate(0, false)
	elif any_checked:
		album_item.set_indeterminate(0, true)
	else:
		album_item.set_checked(0, false)
		album_item.set_indeterminate(0, false)

func _on_midi_select_toggled(toggled: bool) -> void:
	_select_toggle.text = "取消全选" if toggled else "全选"
	var root := _midi_tree.get_root()
	if not root:
		return
	var album := root.get_first_child()
	while album:
		var child := album.get_first_child()
		while child:
			var cm: Dictionary = child.get_metadata(0)
			var midi_id: String = cm.get("id", "")
			if not midi_id.is_empty():
				_midi_selected[midi_id] = toggled
				child.set_checked(0, toggled)
			child = child.get_next()
		album.set_checked(0, toggled)
		album.set_indeterminate(0, false)
		album = album.get_next()
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


func _on_midi_collapse_toggled(toggled: bool) -> void:
	_collapse_toggle.text = "展开全部" if toggled else "收起全部"
	var root := _midi_tree.get_root()
	if not root:
		return
	var album := root.get_first_child()
	while album:
		album.set_collapsed(toggled)
		album = album.get_next()

func _on_midi_delete_selected() -> void:
	var to_delete: Array[String] = []
	for midi_id in _midi_selected:
		if _midi_selected[midi_id]:
			to_delete.append(midi_id)

	if to_delete.is_empty():
		return

	for midi_id in to_delete:
		var path: String = _midi_path_map.get(midi_id, "")
		if path.is_empty():
			push_error("[DelView] 找不到谱面路径: %s" % midi_id)
			continue
		if FileSystemManager.instance.delete_directory_recursive(path):
			print("[DelView] 已删除谱面: %s" % path)
			FileSystemManager.instance.remove_from_charts_index(midi_id)
			DataMGR.remove_midi(midi_id)
		else:
			push_error("[DelView] 删除失败: %s" % path)

	await get_tree().process_frame
	_build_midi_tree()


# ============================================================
# 音频管理
# ============================================================

func _build_audio_list() -> void:
	for child in _audio_list.get_children():
		child.queue_free()
	_audio_items = _scan_audio_files()

	if _audio_items.is_empty():
		_item_sum.text = "无音频文件"
		_update_list_toggle_state(false)
		return

	for i in _audio_items.size():
		var row := _make_list_row(_audio_items[i], i, _audio_items)
		_audio_list.add_child(row)

	_item_sum.text = "共 %d 个 MP3 文件" % _audio_items.size()
	_update_list_toggle_state(false)
	_tab_data_built[Tab.AUDIO] = true


func _scan_audio_files() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var charts_dir := PathHelper.get_charts_dir()
	if not DirAccess.dir_exists_absolute(charts_dir):
		return result

	var dir := DirAccess.open(charts_dir)
	if not dir:
		return result

	dir.list_dir_begin()
	var dn := dir.get_next()
	while dn != "":
		if dir.current_is_dir() and not dn.begins_with("."):
			var chart_path := charts_dir.path_join(dn)
			var mp3_files := FileSystemManager.instance.find_files_in_dir(chart_path, "*.mp3")
			for mp3 in mp3_files:
				result.append({
					"file_name": mp3,
					"path": chart_path.path_join(mp3),
					"chart_name": dn,
					"selected": false,
				})
		dn = dir.get_next()
	dir.list_dir_end()

	result.sort_custom(func(a, b): return a["file_name"] < b["file_name"] if _sort_ascending else a["file_name"] > b["file_name"])
	return result


func _on_audio_select_toggled(toggled: bool) -> void:
	for i in _audio_items.size():
		_audio_items[i]["selected"] = toggled
	_refresh_list_checkboxes(_audio_list, toggled)
	_update_list_toggle_state(toggled)


func _on_audio_delete_selected() -> void:
	var to_delete: Array[Dictionary] = []
	for item in _audio_items:
		if item["selected"]:
			to_delete.append(item)

	if to_delete.is_empty():
		return

	for item in to_delete:
		var err := DirAccess.remove_absolute(item["path"])
		if err == OK:
			print("[DelView] 已删除音频: %s" % item["file_name"])
		else:
			push_error("[DelView] 删除失败: %s (错误码 %d)" % [item["path"], err])

	await get_tree().process_frame
	_build_audio_list()


# ============================================================
# SF2 管理
# ============================================================

func _build_sf2_list() -> void:
	for child in _sf2_list.get_children():
		child.queue_free()
	_sf2_items = _scan_sf2_files()

	if _sf2_items.is_empty():
		_item_sum.text = "无 SF2 音源"
		_update_list_toggle_state(false)
		return

	for i in _sf2_items.size():
		var item := _sf2_items[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var cb := CheckBox.new()
		cb.button_pressed = item["selected"]
		cb.toggled.connect(func(on: bool):
			_sf2_items[i]["selected"] = on
			_update_list_toggle_state(on)
		)
		row.add_child(cb)

		var name_label := Label.new()
		name_label.text = item["file_name"]
		if item["is_builtin"]:
			name_label.text += " [内置]"
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(name_label)

		var size_label := Label.new()
		size_label.text = "%.1f MB" % item["size_mb"]
		row.add_child(size_label)

		_sf2_list.add_child(row)

	_item_sum.text = "共 %d 个音源" % _sf2_items.size()
	_update_list_toggle_state(false)
	_tab_data_built[Tab.SF2] = true


func _scan_sf2_files() -> Array[Dictionary]:
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
		return a["file_name"] < b["file_name"] if _sort_ascending else a["file_name"] > b["file_name"]
	)
	return result


func _on_sf2_select_toggled(toggled: bool) -> void:
	for i in _sf2_items.size():
		if not _sf2_items[i]["is_builtin"]:
			_sf2_items[i]["selected"] = toggled
	_refresh_list_checkboxes(_sf2_list, toggled)
	_update_list_toggle_state(toggled)


func _on_sf2_delete_selected() -> void:
	var to_delete: Array[Dictionary] = []
	for item in _sf2_items:
		if item["selected"] and not item["is_builtin"]:
			to_delete.append(item)

	if to_delete.is_empty():
		return

	for item in to_delete:
		var err := DirAccess.remove_absolute(item["path"])
		if err == OK:
			print("[DelView] 已删除音源: %s" % item["file_name"])
		else:
			push_error("[DelView] 删除失败: %s" % item["path"])

	await get_tree().process_frame
	_build_sf2_list()


# ============================================================
# 皮肤管理
# ============================================================

func _build_skin_list() -> void:
	for child in _skin_list.get_children():
		child.queue_free()

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
		return a["name"] < b["name"] if _sort_ascending else a["name"] > b["name"]
	)

	if _skin_items.is_empty():
		_item_sum.text = "无皮肤"
		_update_list_toggle_state(false)
		return

	for i in _skin_items.size():
		var item := _skin_items[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var cb := CheckBox.new()
		cb.button_pressed = item["selected"]
		if item["is_builtin"]:
			cb.disabled = true
		cb.toggled.connect(func(on: bool):
			_skin_items[i]["selected"] = on
			_update_list_toggle_state(on)
		)
		row.add_child(cb)

		var name_label := Label.new()
		name_label.text = item["name"]
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(name_label)

		_skin_list.add_child(row)

	_item_sum.text = "共 %d 个皮肤" % _skin_items.size()
	_update_list_toggle_state(false)
	_tab_data_built[Tab.SKIN] = true


func _on_skin_select_toggled(toggled: bool) -> void:
	for i in _skin_items.size():
		if not _skin_items[i]["is_builtin"]:
			_skin_items[i]["selected"] = toggled
	_refresh_list_checkboxes(_skin_list, toggled)
	_update_list_toggle_state(toggled)


func _on_skin_delete_selected() -> void:
	var to_delete: Array[Dictionary] = []
	for item in _skin_items:
		if item["selected"] and not item["is_builtin"]:
			to_delete.append(item)

	if to_delete.is_empty():
		return

	for item in to_delete:
		if FileSystemManager.instance.delete_directory_recursive(item["path"]):
			print("[DelView] 已删除皮肤: %s" % item["name"])
		else:
			push_error("[DelView] 删除失败: %s" % item["path"])

	await get_tree().process_frame
	_build_skin_list()


# ============================================================
# 背景管理
# ============================================================

func _build_bg_list() -> void:
	for child in _bg_list.get_children():
		child.queue_free()

	var bg_index := FileSystemManager.instance.get_backgrounds_index()
	_bg_items.clear()

	for bg_name in bg_index:
		_bg_items.append({
			"name": bg_name,
			"path": bg_index[bg_name],
			"selected": false,
		})

	_bg_items.sort_custom(func(a, b): return a["name"] < b["name"] if _sort_ascending else a["name"] > b["name"])

	if _bg_items.is_empty():
		_item_sum.text = "无背景图片"
		_update_list_toggle_state(false)
		return

	for i in _bg_items.size():
		var item := _bg_items[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var cb := CheckBox.new()
		cb.button_pressed = item["selected"]
		cb.toggled.connect(func(on: bool):
			_bg_items[i]["selected"] = on
			_update_list_toggle_state(on)
		)
		row.add_child(cb)

		var name_label := Label.new()
		name_label.text = item["name"]
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(name_label)

		_bg_list.add_child(row)

	_item_sum.text = "共 %d 张背景" % _bg_items.size()
	_update_list_toggle_state(false)
	_tab_data_built[Tab.BG] = true


func _on_bg_select_toggled(toggled: bool) -> void:
	for i in _bg_items.size():
		_bg_items[i]["selected"] = toggled
	_refresh_list_checkboxes(_bg_list, toggled)
	_update_list_toggle_state(toggled)


func _on_bg_delete_selected() -> void:
	var to_delete: Array[Dictionary] = []
	for item in _bg_items:
		if item["selected"]:
			to_delete.append(item)

	if to_delete.is_empty():
		return

	for item in to_delete:
		var err := DirAccess.remove_absolute(item["path"])
		if err == OK:
			print("[DelView] 已删除背景: %s" % item["name"])
		else:
			push_error("[DelView] 删除失败: %s" % item["path"])

	await get_tree().process_frame
	_build_bg_list()


# ============================================================
# 搜索 / 排序
# ============================================================

func _on_search_text_changed(new_text: String) -> void:
	_search_query = new_text.strip_edges()
	_apply_search_filter()


func _apply_search_filter() -> void:
	if _search_query.is_empty():
		# 恢复所有行可见
		match _current_tab:
			Tab.AUDIO:
				for row in _audio_list.get_children():
					row.visible = true
				_item_sum.text = "共 %d 个 MP3 文件" % _audio_items.size()
			Tab.SF2:
				for row in _sf2_list.get_children():
					row.visible = true
				_item_sum.text = "共 %d 个音源" % _sf2_items.size()
			Tab.SKIN:
				for row in _skin_list.get_children():
					row.visible = true
				_item_sum.text = "共 %d 个皮肤" % _skin_items.size()
			Tab.BG:
				for row in _bg_list.get_children():
					row.visible = true
				_item_sum.text = "共 %d 张背景" % _bg_items.size()
		return

	match _current_tab:
		Tab.MIDI:
			_tab_data_built[Tab.MIDI] = false
			_build_midi_tree()
		Tab.AUDIO:
			_apply_list_filter(_audio_list, _audio_items, "file_name")
		Tab.SF2:
			_apply_list_filter(_sf2_list, _sf2_items, "file_name")
		Tab.SKIN:
			_apply_list_filter(_skin_list, _skin_items, "name")
		Tab.BG:
			_apply_list_filter(_bg_list, _bg_items, "name")


func _apply_list_filter(list_container: VBoxContainer, items: Array, name_key: String) -> void:
	var visible_count := 0
	var rows := list_container.get_children()
	var query_lower := _search_query.to_lower()
	for i in items.size():
		if i >= rows.size():
			break
		var _name: String = items[i].get(name_key, "")
		var matches := query_lower in _name.to_lower()
		rows[i].visible = matches
		if matches:
			visible_count += 1
	_item_sum.text = "共 %d 个 (匹配 %d 个)" % [items.size(), visible_count]


func _on_order_btn_pressed() -> void:
	_sort_ascending = not _sort_ascending
	_order_btn.icon = load("res://Resources/icon/Sort/Ordering/Ascent.png" if _sort_ascending else "res://Resources/icon/Sort/Ordering/Descent.png")
	_tab_data_built[_current_tab] = false
	match _current_tab:
		Tab.MIDI:
			_build_midi_tree()
		Tab.AUDIO:
			_build_audio_list()
		Tab.SF2:
			_build_sf2_list()
		Tab.SKIN:
			_build_skin_list()
		Tab.BG:
			_build_bg_list()
	if _current_tab != Tab.MIDI:
		_apply_search_filter()


# ============================================================
# 通用工具
# ============================================================

func _make_list_row(item: Dictionary, idx: int, items: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var cb := CheckBox.new()
	cb.button_pressed = item["selected"]
	cb.toggled.connect(func(on: bool):
		items[idx]["selected"] = on
		_update_list_toggle_state(on)
	)
	row.add_child(cb)

	var name_label := Label.new()
	name_label.text = item.get("file_name", item.get("name", ""))
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(name_label)

	var info_label := Label.new()
	if item.has("chart_name"):
		info_label.text = "来自: " + item["chart_name"]
	row.add_child(info_label)

	return row


func _update_list_toggle_state(_changed: bool) -> void:
	var items: Array
	match _current_tab:
		Tab.AUDIO: items = _audio_items
		Tab.SF2: items = _sf2_items
		Tab.SKIN: items = _skin_items
		Tab.BG: items = _bg_items
		_: return

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


func _refresh_list_checkboxes(list_container: VBoxContainer, checked: bool) -> void:
	for row in list_container.get_children():
		if row is HBoxContainer and row.get_child_count() > 0:
			var cb := row.get_child(0)
			if cb is CheckBox:
				cb.button_pressed = checked
