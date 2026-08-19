extends ListItemBase

class_name MidiTrack

@onready var note_display: NoteDisplayer = $HBoxC/MC/HBoxC/MC/flowArea

# 写着"Track"的按钮
@onready var track_btn: Button = $HBoxC/TR/TrackBtn
@onready var track_num: Label = $HBoxC/TR/TrackNum

@onready var channel_btn: Button = $HBoxC/CH/ChannelBtn
@onready var channel_num: Label = $HBoxC/CH/ChannelNum
# 切换轨道启用状态的按钮
@onready var enable_btn: Button = $HBoxC/MC/HBoxC/enableBtn
@onready var enable_btn_text: Label = $HBoxC/MC/HBoxC/enableBtn/HBoxC/Text
@onready var enable_btn_icon: TextureRect = $HBoxC/MC/HBoxC/enableBtn/HBoxC/Icon #这个可能需要根据乐器类型去修改

@onready var mute_btn: TextureButton = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/MuteBtn
@onready var solo_btn: TextureButton = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/SoloBtn
@onready var reset_btn: TextureButton = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/ResetBtn
@onready var volume_slider: HSlider = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/Volume/Slider
@onready var volume_label: Label = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/Volume/Label
# 乐器两级选择菜单：大类(MenuButton) → 具体乐器(子菜单)
@onready var instruments_btn: MenuButton = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/InstrumentBtn

# category(int) -> Array[String] 该类下的乐器 display_name（由 instrument_options 分组）
var _category_items: Dictionary = {}
# 当前菜单按钮显示的乐器名（完整 display_name）
var _current_display_name: String = ""
# popup -> bool 滚动拖拽中标志（用于区分"点击选中"与"拖拽滚动"）
var _drag_flags: Dictionary = {}
# 主菜单（大类）滚动挂钩是否已完成（防止 rebuild 时重复连接信号）
var _main_menu_hooked := false
# 主菜单 ScrollContainer 缓存（子菜单弹出时复位其拖拽跟随状态）
var _main_scroll: ScrollContainer = null
# 主菜单拖拽中标志：区分"点击展开子菜单"与"拖拽滚动"，仅点击时才复位滚动，避免拖拽被中断
var _main_dragging := false

# 初始化时需要调节颜色的节点 除下面的之外还有self和enable_btn
@onready var track_panel: Panel = $HBoxC/TR
@onready var channel_panel: Panel = $HBoxC/CH
@onready var note_panel: Panel = $HBoxC/MC/HBoxC/MC/flowArea/noteTotal


# 轨道属性
var track_index: int = 2
var track_channel: int = 0
var current_volume: float = 1.0
var current_instrument: String = ""

# 引用到MidiData以获取状态
var midi_data: MidiData = null

var instrument_options: Array = []

signal _init_fin

func _ready():
	await _init_fin
	
	# 连接按钮信号
	_connect_signals()
	_init_track_color()

	track_num.text = str(track_index)
	channel_num.text = str(track_channel)

	if not instrument_options:
		if not parent_node:
			push_error("轨道 %d 初始化失败: 无父节点" % track_index)
			return
		instrument_options = parent_node.instrument_options
	if not instrument_options:
		push_error("轨道 %d 初始化失败: 无可用乐器选项" % track_index)
		return

	# 构建两级乐器菜单：大类 → 具体乐器（仅首帧构建，SoundFont 变更时经 rebuild 重建）
	if instruments_btn.get_popup().item_count == 0:
		_build_category_items()
		_build_instrument_menus()

	GLogger.info("Track %d initialized with %d instrument categories" % [track_index, _category_items.size()], "MidiTrack")

	# 从MidiData读取启用状态
	if midi_data:
		var is_enabled = midi_data.is_track_channel_selected(track_index, track_channel)
		enable_btn.button_pressed = is_enabled
	
const colors_set = [
	Color.RED,
	Color.DEEP_PINK,
	Color.BROWN,
	Color.BISQUE,
	Color.GOLD,
	Color.YELLOW_GREEN,
	Color.LIME,
	Color.CYAN,
	Color.SKY_BLUE,
	Color.AQUAMARINE,
	Color.BLUE,
	Color.BLUE_VIOLET,
	Color.VIOLET,
]

var color_light: Color
var color_normal: Color
var color_dark: Color

func _init_track_color():
	var h = colors_set[track_index % colors_set.size()].h
	color_light = Color.from_hsv(h, 0.3, 0.95, 1)
	color_normal = Color.from_hsv(h, 0.9, 0.85, 1)
	color_dark = Color.from_hsv(h, 0.8, 0.5, 1)

	channel_panel.self_modulate = Color.from_hsv(colors_set[(-track_channel) % colors_set.size()].h, 0.8, 0.5, 1)
	track_panel.self_modulate = color_dark

	note_panel.self_modulate = color_light
	self_modulate = color_light
	enable_btn.self_modulate = color_normal

	note_display.note_color = color_normal

# 根据乐器大类索引设置图标区域（图标材质由外部 setup，此处仅改坐标）
# enable_btn_icon.texture 须为 AtlasTexture 才会生效
func set_instrument_category(category: int) -> void:
	var tex := enable_btn_icon.texture as AtlasTexture
	if tex:
		tex.region = InstrumentCategory.get_icon_region(category)

func _connect_signals():
	enable_btn.toggled.connect(_on_enable_toggled)
	mute_btn.toggled.connect(_on_mute_toggled)
	solo_btn.toggled.connect(_on_solo_toggled)

	volume_slider.value_changed.connect(
		func(value):
			volume_label.text = "%.2fdB" % linear_to_db(value)
			current_volume = value
	)

	if not parent_node:
		GLogger.error("轨道 %d 初始化失败: 无父节点" % track_index, "MidiTrack")
		return

	if parent_node.has_method("_on_track_enable_toggled"):
		enable_btn.toggled.connect(parent_node._on_track_enable_toggled.bind(track_index, track_channel))
	if parent_node.has_method("_on_track_mute_toggled"):
		mute_btn.toggled.connect(parent_node._on_track_mute_toggled.bind(track_index, track_channel))
	if parent_node.has_method("_on_track_solo_toggled"):
		solo_btn.toggled.connect(parent_node._on_track_solo_toggled.bind(track_index, track_channel))
	if parent_node.has_method("_on_track_volume_changed"):
		volume_slider.value_changed.connect(parent_node._on_track_volume_changed.bind(track_index, track_channel))
	if parent_node.has_method("_on_track_instrument_reset"):
		reset_btn.pressed.connect(parent_node._on_track_instrument_reset.bind(track_index, track_channel))

# 提供父节点及轨道信息，自动连接信号 乐器选项不提供时从传入的父节点获取
# channel 参数用于区分同一轨道的不同MIDI通道，后续UI完善时使用set_channel_label()显示
func setup_track(parent: Node, index: int, track_name: String, instruments: Array = [], channel: int = 0, midi_data_ref: MidiData = null):
	parent_node = parent
	track_index = index
	track_channel = channel
	midi_data = midi_data_ref
	name = track_name
	
	# 根据 channel 类型过滤乐器选项
	# 共享 parent 的乐器列表引用（不 duplicate）：instrument_options 仅读遍历，不会被修改
	# 避免每轨道复制 ~500 个字符串，30 轨道可省 ~15000 次字符串拷贝
	if channel == 9:
		# Channel 9 是鼓轨道，只显示鼓组乐器
		if "drum_instruments" in parent and not parent.drum_instruments.is_empty():
			instrument_options = parent.drum_instruments
			GLogger.info("Track %d Channel %d: 使用鼓组乐器列表 (%d 个)" % [index, channel, instrument_options.size()], "MidiTrack")
		else:
			instrument_options = instruments  # fallback
	else:
		# 普通 channel，只显示常规乐器
		if "regular_instruments" in parent and not parent.regular_instruments.is_empty():
			instrument_options = parent.regular_instruments
			GLogger.info("Track %d Channel %d: 使用常规乐器列表 (%d 个)" % [index, channel, instrument_options.size()], "MidiTrack")
		else:
			instrument_options = instruments  # fallback

	# 两级乐器菜单在 _ready 构建（此时 @onready 节点可用、enable_btn_icon 图集就绪）
	_init_fin.emit()

# 按大类把 instrument_options 分组成 _category_items（instrument_options 已按大类排序）
func _build_category_items() -> void:
	_category_items.clear()
	for display in instrument_options:
		var info := InstrumentCategory.parse_display_name(display)
		var cat := InstrumentCategory.get_category(info.get("bank", 0), info.get("program", 0))
		if not _category_items.has(cat):
			_category_items[cat] = []
		_category_items[cat].append(display)

# 用 enable_btn_icon 的同源图集生成某个大类的菜单图标
func _make_cat_icon(category: int) -> Texture2D:
	var icon_tex := enable_btn_icon.texture as AtlasTexture
	if icon_tex == null or icon_tex.atlas == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = icon_tex.atlas
	at.region = InstrumentCategory.get_icon_region(category)
	return at

# 构建大类主菜单 + 各具体乐器子菜单。
# 子菜单 PopupMenu 节点一次性创建（add_submenu_item 要求节点构建时已存在），
# 具体乐器项也在此全部填充（乐器项字符串来自共享的 instrument_options，仅存引用）。
func _build_instrument_menus() -> void:
	var popup := instruments_btn.get_popup()
	popup.clear()
	_release_submenus()
	_main_dragging = false

	# 大类主菜单滚动支持（16 类超出屏幕时可触摸拖动滚动）
	_setup_main_menu_scroll(popup)

	popup.set_block_signals(true)
	var idx := 0
	for cat in _category_items.keys():
		var sub := PopupMenu.new()
		sub.name = "Submenu_%d" % cat
		# add_submenu_item 通过 get_node_or_null 相对 popup 自身解析路径，
		# 子菜单必须挂到 popup 下才能被找到（之后作为 popup 的子树弹出）。
		popup.add_child(sub)
		popup.add_submenu_item(InstrumentCategory.CATEGORY_NAMES[cat], sub.name)
		popup.set_item_id(idx, cat)
		var icon := _make_cat_icon(cat)
		if icon:
			popup.set_item_icon(idx, icon)
		sub.about_to_popup.connect(_on_submenu_about_to_popup)
		sub.id_pressed.connect(_on_submenu_item_selected.bind(cat))
		# 一次性填充该类下的具体乐器项（不懒加载）
		var list: Array = _category_items.get(cat, [])
		for i in list.size():
			sub.add_item(list[i], i)
		# 子菜单触摸滚动支持
		_setup_submenu_scroll(sub)
		idx += 1
	popup.set_block_signals(false)

func _release_submenus() -> void:
	var popup := instruments_btn.get_popup()
	for child in popup.get_children():
		if child is PopupMenu:
			child.queue_free()
	_drag_flags.clear()

# 按大类号取对应子菜单（子菜单以固定名 "Submenu_%d" 挂在主菜单 popup 下）
func _find_submenu(category: int) -> PopupMenu:
	return instruments_btn.get_popup().get_node_or_null("Submenu_%d" % category)

# 大类主菜单（MenuButton popup）触摸滚动配置
func _setup_main_menu_scroll(popup: PopupMenu) -> void:
	if _main_menu_hooked:
		return
	_main_menu_hooked = true
	var scroll := _find_scroll_container(popup)
	if scroll == null:
		return
	_main_scroll = scroll
	# 事件穿透到 ScrollContainer 实现原生触摸拖拽
	_set_mouse_filter_recursive(scroll, Control.MOUSE_FILTER_IGNORE, true)
	scroll.gui_input.connect(_on_main_scroll_gui_input)
	popup.popup_hide.connect(_on_menu_hide.bind(popup, scroll))

# 为具体乐器子菜单配置触摸滚动（与 TouchScrollOptionButton 机制一致）
func _setup_submenu_scroll(submenu: PopupMenu) -> void:
	# 阻止选中后自动关闭：滚动拖拽松手不应误选中（由 _on_submenu_item_selected 手动控制关闭）
	submenu.hide_on_item_selection = false
	var scroll := _find_scroll_container(submenu)
	if scroll == null:
		return
	# 事件穿透到 ScrollContainer 实现原生触摸拖拽
	_set_mouse_filter_recursive(scroll, Control.MOUSE_FILTER_PASS, true)
	scroll.gui_input.connect(_on_menu_scroll_gui_input.bind(submenu))
	submenu.popup_hide.connect(_on_menu_hide.bind(submenu, scroll))

func _on_menu_scroll_gui_input(event: InputEvent, popup: PopupMenu) -> void:
	# 新一轮按下开始时重置拖拽标志：上一次"拖拽滚动但未选中项"的标记不应残留到后续点击，
	# 否则后续点击都会被误判成拖拽松手而无法选中（表现为按钮无效但 hover 正常）。
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		_drag_flags[popup] = false
	elif event is InputEventScreenDrag:
		_drag_flags[popup] = true
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_drag_flags[popup] = true

# 主菜单拖拽检测：有拖拽位移时标记 _main_dragging，_on_submenu_about_to_popup 据此跳过复位
func _on_main_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_main_dragging = true
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_main_dragging = true

# 子菜单弹出时复位大类菜单 ScrollContainer 的拖拽跟随状态。
# 松手弹出子菜单后，主菜单可能收不到松开事件导致 drag_touching 卡住，一直跟随鼠标滚动；
# set_v_scroll(get_v_scroll()) 内部会 _cancel_drag() 停止跟随。
# 仅"点击展开子菜单"（非拖拽）时复位：拖拽滚动中悬浮切到其它大类也会触发弹出，此时复位会中断拖拽。
func _on_submenu_about_to_popup() -> void:
	if _main_scroll and not _main_dragging:
		_main_scroll.set_v_scroll(_main_scroll.get_v_scroll())

# 弹窗关闭时清除拖拽标志 + 重置 ScrollContainer 卡住的拖拽状态
func _on_menu_hide(popup: PopupMenu, scroll: ScrollContainer) -> void:
	_drag_flags.erase(popup)
	if popup == instruments_btn.get_popup():
		_main_dragging = false
	scroll.set_v_scroll(scroll.get_v_scroll())

func _find_scroll_container(node: Node) -> ScrollContainer:
	for child in node.get_children(true):
		if child is ScrollContainer:
			return child
		var found := _find_scroll_container(child)
		if found:
			return found
	return null

func _set_mouse_filter_recursive(node: Node, filter: int, skip_root: bool = false) -> void:
	if not skip_root and node is Control:
		node.mouse_filter = filter
	for child in node.get_children(true):
		_set_mouse_filter_recursive(child, filter, false)

# 选中某大类下的具体乐器，更新按钮显示并通知父节点应用
func _on_submenu_item_selected(id: int, category: int) -> void:
	var list: Array = _category_items.get(category, [])
	if id < 0 or id >= list.size():
		return
	var sub := _find_submenu(category)
	# 拖拽滚动后松手：不选中、不关闭（与 TouchScrollOptionButton 一致）
	if sub != null and _drag_flags.get(sub, false):
		return
	var display: String = list[id]
	current_instrument = display
	_current_display_name = display
	instruments_btn.text = display
	# 勾选切换到当前大类
	var popup := instruments_btn.get_popup()
	for i in popup.item_count:
		popup.set_item_checked(i, false)
	var cat_idx := popup.get_item_index(category)
	if cat_idx >= 0:
		popup.set_item_checked(cat_idx, true)
	# hide_on_item_selection=false，需手动关闭子菜单
	if sub != null:
		sub.hide()
	if parent_node and parent_node.has_method("_on_track_instrument_changed"):
		var info := InstrumentCategory.parse_display_name(display)
		parent_node._on_track_instrument_changed(
			track_index,
			track_channel,
			info.get("bank", 0),
			info.get("program", 0),
			info.get("name", ""))

# 由外部设置当前显示的乐器并高亮对应大类（默认显示使用中的乐器，与原来 OptionButton 一致）
func set_current_instrument(category: int, display_name: String) -> void:
	instruments_btn.text = display_name
	current_instrument = display_name
	_current_display_name = display_name
	# 大类高亮通过勾选标记体现（PopupMenu 无 select，用 set_item_checked）
	var popup := instruments_btn.get_popup()
	var idx := popup.get_item_index(category)
	if idx >= 0:
		popup.set_item_checked(idx, true)

# 外部（SoundFont 变更等）更新本轨道的乐器选项并重建两级菜单，保持当前乐器选中
func refresh_instrument_options(regular: Array, drum: Array) -> void:
	if track_channel == 9 and not drum.is_empty():
		instrument_options = drum
	elif not regular.is_empty():
		instrument_options = regular

	_build_category_items()
	_build_instrument_menus()
	_refresh_current_highlight()

# 重建后重新应用当前乐器的显示与对应大类高亮
func _refresh_current_highlight() -> void:
	if _current_display_name.is_empty():
		_current_display_name = instruments_btn.text
	if _current_display_name.is_empty():
		return
	var info := InstrumentCategory.parse_display_name(_current_display_name)
	set_current_instrument(
		InstrumentCategory.get_category(info.get("bank", 0), info.get("program", 0)),
		_current_display_name)

func _on_mute_toggled(is_pressed: bool):
	# 注意：MidiData的修改由TrackView._on_track_mute_toggled通过MidiPlaybackManager处理
	# 这里仅负责UI状态更新
	mute_btn.texture_normal.region = Rect2(0, 240, 80, 80) if is_pressed else Rect2(0, 160, 80, 80)

func _on_solo_toggled(is_pressed: bool):
	solo_btn.texture_normal.region = Rect2(80, 160, 80, 80) if is_pressed else Rect2(80, 240, 80, 80)

func _on_enable_toggled(toggle_on: bool):
	if midi_data:
		midi_data.set_track_channel_enabled(track_index, track_channel, toggle_on)
	enable_btn_text.text = "已启用" if toggle_on else "已禁用"

	note_display.note_color = color_normal if toggle_on else color_dark
	note_display.update_color()
