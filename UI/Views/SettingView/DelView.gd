extends HBoxContainer
class_name DelView

enum Tab {MIDI = 0, AUDIO = 1, SF2 = 2}

@onready var sidebar: VBoxContainer = $SideBar
@onready var content: PanelContainer = $Content
@onready var tab_btn_0: Button = $SideBar/TabBtn0
@onready var tab_btn_1: Button = $SideBar/TabBtn1
@onready var tab_btn_2: Button = $SideBar/TabBtn2

var _current_tab: Tab = Tab.MIDI
var _tab_buttons: Array[Button] = []
var _midi_items: Array[Dictionary] = []
var _audio_items: Array[Dictionary] = []
var _sf2_items: Array[Dictionary] = []

func _ready() -> void:
	_init_sidebar()
	_switch_tab(Tab.MIDI)

func _init_sidebar() -> void:
	_tab_buttons = [tab_btn_0, tab_btn_1, tab_btn_2]
	for i in _tab_buttons.size():
		_tab_buttons[i].pressed.connect(_on_tab_button_pressed.bind(i))

func _on_tab_button_pressed(idx: int) -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = (i == idx)
	_switch_tab(idx as Tab)

func _switch_tab(tab: Tab) -> void:
	_current_tab = tab
	for child in content.get_children():
		child.queue_free()

	match tab:
		Tab.MIDI:
			_build_midi_tab()
		Tab.AUDIO:
			_build_audio_tab()
		Tab.SF2:
			_build_sf2_tab()


# ============================================================
# MIDI 管理
# ============================================================

func _build_midi_tab() -> void:
	_midi_items = _scan_midi_charts()

	var vbox := _make_content_vbox()
	var top_bar := _make_top_bar("MIDI 谱面管理", "共 %d 首谱面" % _midi_items.size())
	vbox.add_child(top_bar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)

	for i in _midi_items.size():
		var row := _make_midi_row(_midi_items[i], i)
		list.add_child(row)

	vbox.add_child(scroll)

	var bottom_bar := _make_bottom_bar_midi()
	vbox.add_child(bottom_bar)

	content.add_child(vbox)

func _scan_midi_charts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	var charts_dir := PathHelper.get_charts_dir()
	if DirAccess.dir_exists_absolute(charts_dir):
		var dir := DirAccess.open(charts_dir)
		if dir:
			dir.list_dir_begin()
			var dn := dir.get_next()
			while dn != "":
				if dir.current_is_dir() and not dn.begins_with("."):
					var chart_path := charts_dir.path_join(dn)
					var midi_file := _find_file_in_dir(chart_path, "*.mid")
					var json_file := _find_file_in_dir(chart_path, "*.json")
					var mp3_files := _find_files_in_dir(chart_path, "*.mp3")
					var display_name := dn.split("_", false, 1)[1] if "_" in dn else dn
					var difficulty := _parse_difficulty(dn)
					result.append({
						"dir_name": dn,
						"path": chart_path,
						"display_name": display_name,
						"difficulty": difficulty,
						"midi_file": midi_file,
						"json_file": json_file,
						"mp3_count": mp3_files.size(),
						"is_builtin": false,
						"selected": false,
					})
				dn = dir.get_next()
			dir.list_dir_end()

	result.sort_custom(func(a, b): return a["display_name"] < b["display_name"])
	return result

func _parse_difficulty(dir_name: String) -> String:
	if "_Easy" in dir_name or "_easy" in dir_name:
		return "Easy"
	elif "_Normal" in dir_name or "_normal" in dir_name:
		return "Normal"
	elif "_Hard" in dir_name or "_hard" in dir_name:
		return "Hard"
	return "?"

func _make_midi_row(item: Dictionary, idx: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var cb := CheckBox.new()
	cb.toggled.connect(func(on): _midi_items[idx]["selected"] = on)
	row.add_child(cb)

	var name_label := Label.new()
	name_label.text = "%s  [%s]" % [item["display_name"], item["difficulty"]]
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(name_label)

	var info_label := Label.new()
	info_label.text = "MIDI + JSON" if item["mp3_count"] == 0 else "MIDI + JSON + %d MP3" % item["mp3_count"]
	ThemeManager.instance.style_delview_info_label(info_label)
	row.add_child(info_label)

	return row

func _make_bottom_bar_midi() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)

	var select_all := _make_action_button("全选", 110, _on_midi_select_all)
	bar.add_child(select_all)

	var deselect_all := _make_action_button("取消全选", 130, _on_midi_deselect_all)
	bar.add_child(deselect_all)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var delete_btn := Button.new()
	delete_btn.text = "删除选中"
	delete_btn.custom_minimum_size = Vector2(150, 50)
	delete_btn.pressed.connect(_on_midi_delete_selected)
	ThemeManager.instance.style_delview_delete_button(delete_btn)
	bar.add_child(delete_btn)

	var reload_btn := _make_action_button("恢复默认歌曲", 180, _on_midi_reload_default)
	bar.add_child(reload_btn)

	return bar

func _make_action_button(text: String, min_width: float, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(min_width, 50)
	btn.pressed.connect(callback)
	return btn

func _on_midi_select_all() -> void:
	for i in _midi_items.size():
		_midi_items[i]["selected"] = true
	_refresh_current_tab()

func _on_midi_deselect_all() -> void:
	for i in _midi_items.size():
		_midi_items[i]["selected"] = false
	_refresh_current_tab()

func _on_midi_delete_selected() -> void:
	var to_delete: Array[Dictionary] = []
	for item in _midi_items:
		if item["selected"]:
			to_delete.append(item)
	if to_delete.is_empty():
		return

	for item in to_delete:
		var err := _remove_dir_recursive(item["path"])
		if err:
			print("[DelView] 已删除谱面: %s" % item["display_name"])
		else:
			push_error("[DelView] 删除失败: %s" % item["path"])

	_refresh_current_tab()

func _on_midi_reload_default() -> void:
	var res_dir := "res://Resources/Charts/"
	if not DirAccess.dir_exists_absolute(res_dir):
		push_error("[DelView] 内置谱面目录不存在: " + res_dir)
		return

	var charts_dir := PathHelper.get_charts_dir()
	PathHelper.ensure_dir_exists(charts_dir)

	var dir := DirAccess.open(res_dir)
	if not dir:
		return

	dir.list_dir_begin()
	var dn := dir.get_next()
	var copied := 0
	while dn != "":
		if dir.current_is_dir() and not dn.begins_with("."):
			var src := res_dir.path_join(dn)
			var dst := charts_dir.path_join(dn)
			var ok := _copy_dir_recursive(src, dst)
			if ok:
				copied += 1
		dn = dir.get_next()
	dir.list_dir_end()

	print("[DelView] 已恢复 %d 首默认歌曲到 %s" % [copied, charts_dir])
	_refresh_current_tab()

# ============================================================
# 音频管理
# ============================================================

func _build_audio_tab() -> void:
	_audio_items = _scan_audio_files()

	var vbox := _make_content_vbox()
	var top_bar := _make_top_bar("人声音频管理", "共 %d 个 MP3 文件" % _audio_items.size())
	vbox.add_child(top_bar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)

	for i in _audio_items.size():
		var row := _make_audio_row(_audio_items[i], i)
		list.add_child(row)

	vbox.add_child(scroll)

	var bottom_bar := _make_bottom_bar_audio()
	vbox.add_child(bottom_bar)

	content.add_child(vbox)

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
			var mp3_files := _find_files_in_dir(chart_path, "*.mp3")
			for mp3 in mp3_files:
				var mp3_path := chart_path.path_join(mp3)
				result.append({
					"file_name": mp3,
					"path": mp3_path,
					"chart_name": dn,
					"selected": false,
				})
		dn = dir.get_next()
	dir.list_dir_end()

	result.sort_custom(func(a, b): return a["file_name"] < b["file_name"])
	return result

func _make_audio_row(item: Dictionary, idx: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var cb := CheckBox.new()
	cb.toggled.connect(func(on): _audio_items[idx]["selected"] = on)
	row.add_child(cb)

	var name_label := Label.new()
	name_label.text = item["file_name"]
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(name_label)

	var info_label := Label.new()
	info_label.text = "来自: " + item["chart_name"]
	ThemeManager.instance.style_delview_info_label(info_label)
	row.add_child(info_label)

	return row

func _make_bottom_bar_audio() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)

	var select_all := _make_action_button("全选", 110, _on_audio_select_all)
	bar.add_child(select_all)

	var deselect_all := _make_action_button("取消全选", 130, _on_audio_deselect_all)
	bar.add_child(deselect_all)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var delete_btn := Button.new()
	delete_btn.text = "删除选中"
	delete_btn.custom_minimum_size = Vector2(150, 50)
	delete_btn.pressed.connect(_on_audio_delete_selected)
	ThemeManager.instance.style_delview_delete_button(delete_btn)
	bar.add_child(delete_btn)

	return bar

func _on_audio_select_all() -> void:
	for i in _audio_items.size():
		_audio_items[i]["selected"] = true
	_refresh_current_tab()

func _on_audio_deselect_all() -> void:
	for i in _audio_items.size():
		_audio_items[i]["selected"] = false
	_refresh_current_tab()

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

	_refresh_current_tab()

# ============================================================
# SF2 管理
# ============================================================

func _build_sf2_tab() -> void:
	_sf2_items = _scan_sf2_files()

	var vbox := _make_content_vbox()
	var top_bar := _make_top_bar("SF2 音源管理", "共 %d 个音源" % _sf2_items.size())
	vbox.add_child(top_bar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)

	if _sf2_items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "未安装任何 SF2 音源"
		ThemeManager.instance.style_delview_info_label(empty_label)
		list.add_child(empty_label)
	else:
		for i in _sf2_items.size():
			var row := _make_sf2_row(_sf2_items[i], i)
			list.add_child(row)

	vbox.add_child(scroll)
	content.add_child(vbox)

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
					result.append({
						"file_name": fn,
						"path": user_dir.path_join(fn),
						"is_builtin": false,
						"size_mb": 0,
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
						result.append({
							"file_name": fn,
							"path": res_dir.path_join(fn),
							"is_builtin": true,
							"size_mb": 0,
						})
				fn = dir.get_next()
			dir.list_dir_end()

	for item in result:
		var f := FileAccess.open(item["path"], FileAccess.READ)
		if f:
			item["size_mb"] = snapped(f.get_length() / 1048576.0, 0.1)
			f.close()

	result.sort_custom(func(a, b):
		if a["is_builtin"] != b["is_builtin"]:
			return not a["is_builtin"]
		return a["file_name"] < b["file_name"]
	)
	return result

func _make_sf2_row(item: Dictionary, idx: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_label := Label.new()
	name_label.text = item["file_name"]
	if item["is_builtin"]:
		name_label.text += " [内置]"
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(name_label)

	var size_label := Label.new()
	size_label.text = "%.1f MB" % item["size_mb"]
	ThemeManager.instance.style_delview_info_label(size_label)
	row.add_child(size_label)

	if not item["is_builtin"]:
		var del_btn := Button.new()
		del_btn.text = "删除"
		del_btn.custom_minimum_size = Vector2(80, 40)
		del_btn.pressed.connect(_on_sf2_delete.bind(idx))
		ThemeManager.instance.style_delview_delete_button(del_btn)
		row.add_child(del_btn)

	return row

func _on_sf2_delete(idx: int) -> void:
	var item := _sf2_items[idx]
	var err := DirAccess.remove_absolute(item["path"])
	if err == OK:
		print("[DelView] 已删除音源: %s" % item["file_name"])
	else:
		push_error("[DelView] 删除失败: %s" % item["path"])
	_refresh_current_tab()

# ============================================================
# 通用工具
# ============================================================

func _refresh_current_tab() -> void:
	_switch_tab(_current_tab)


func _make_content_vbox() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.size_flags_vertical = SIZE_EXPAND_FILL
	return vbox


func _make_top_bar(title: String, subtitle: String) -> HBoxContainer:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 40)
	top.add_child(title_label)

	var info_label := Label.new()
	info_label.text = subtitle
	ThemeManager.instance.style_delview_info_label(info_label)
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(info_label)

	return top

func _find_file_in_dir(dir_path: String, pattern: String) -> String:
	var d := DirAccess.open(dir_path)
	if not d:
		return ""
	var ext := pattern.replace("*.", ".")
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn.ends_with(ext) and not d.current_is_dir():
			d.list_dir_end()
			return fn
		fn = d.get_next()
	d.list_dir_end()
	return ""

func _find_files_in_dir(dir_path: String, pattern: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var d := DirAccess.open(dir_path)
	if not d:
		return result
	var ext := pattern.replace("*.", ".")
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn.ends_with(ext) and not d.current_is_dir():
			result.append(fn)
		fn = d.get_next()
	d.list_dir_end()
	return result

func _remove_dir_recursive(dir_path: String) -> bool:
	var d := DirAccess.open(dir_path)
	if not d:
		return false
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn == "." or fn == "..":
			fn = d.get_next()
			continue
		var full := dir_path.path_join(fn)
		if d.current_is_dir():
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		fn = d.get_next()
	d.list_dir_end()
	return DirAccess.remove_absolute(dir_path) == OK

func _copy_dir_recursive(src_dir: String, dst_dir: String) -> bool:
	PathHelper.ensure_dir_exists(dst_dir)
	var d := DirAccess.open(src_dir)
	if not d:
		return false
	d.list_dir_begin()
	var fn := d.get_next()
	var ok := true
	while fn != "":
		if fn == "." or fn == "..":
			fn = d.get_next()
			continue
		var src := src_dir.path_join(fn)
		var dst := dst_dir.path_join(fn)
		if d.current_is_dir():
			ok = _copy_dir_recursive(src, dst) and ok
		else:
			var err := DirAccess.copy_absolute(src, dst)
			if err != OK:
				push_error("[DelView] 复制失败: %s -> %s" % [src, dst])
				ok = false
		fn = d.get_next()
	d.list_dir_end()
	return ok
