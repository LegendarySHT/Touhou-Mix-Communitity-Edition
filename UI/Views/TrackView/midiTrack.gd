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
@onready var instruments_option_btn: OptionButton = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/InstrumentBtn

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

	# 仅在setup_track未预填充时填充OptionButton
	if instruments_option_btn.item_count == 0:
		instruments_option_btn.clear()
		for i in instrument_options:
			instruments_option_btn.add_item(i)

	print("[MidiTrack] Track %d initialized with %d instrument options" % [track_index, instruments_option_btn.item_count])

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

func _connect_signals():
	enable_btn.toggled.connect(_on_enable_toggled)
	mute_btn.toggled.connect(_on_mute_toggled)
	solo_btn.toggled.connect(_on_solo_toggled)

	volume_slider.value_changed.connect(
		func(value):
			volume_label.text = "%.2fdB" % linear_to_db(value)
			current_volume = value
	)
	instruments_option_btn.item_selected.connect(
		func(index):
			current_instrument = instrument_options[index]
	)

	if not parent_node:
		print("轨道 %d 初始化失败: 无父节点" % track_index)
		return

	if parent_node.has_method("_on_track_enable_toggled"):
		enable_btn.toggled.connect(parent_node._on_track_enable_toggled.bind(track_index, track_channel))
	if parent_node.has_method("_on_track_mute_toggled"):
		mute_btn.toggled.connect(parent_node._on_track_mute_toggled.bind(track_index, track_channel))
	if parent_node.has_method("_on_track_solo_toggled"):
		solo_btn.toggled.connect(parent_node._on_track_solo_toggled.bind(track_index, track_channel))
	if parent_node.has_method("_on_track_volume_changed"):
		volume_slider.value_changed.connect(parent_node._on_track_volume_changed.bind(track_index, track_channel))
	if parent_node.has_method("_on_track_instrument_changed"):
		instruments_option_btn.item_selected.connect(parent_node._on_track_instrument_changed.bind(track_index, track_channel))
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
	if channel == 9:
		# Channel 9 是鼓轨道，只显示鼓组乐器
		if "drum_instruments" in parent and not parent.drum_instruments.is_empty():
			instrument_options = parent.drum_instruments.duplicate()
			print("[MidiTrack] Track %d Channel %d: 使用鼓组乐器列表 (%d 个)" % [index, channel, instrument_options.size()])
		else:
			instrument_options = instruments.duplicate()  # fallback
	else:
		# 普通 channel，只显示常规乐器
		if "regular_instruments" in parent and not parent.regular_instruments.is_empty():
			instrument_options = parent.regular_instruments.duplicate()
			print("[MidiTrack] Track %d Channel %d: 使用常规乐器列表 (%d 个)" % [index, channel, instrument_options.size()])
		else:
			instrument_options = instruments.duplicate()  # fallback


	# 提前填充OptionButton（使用get_node因@onready在_ready之前未初始化）
	if is_inside_tree():
		var btn = get_node_or_null("HBoxC/MC/HBoxC/MC/ControlPanel/GridC/InstrumentBtn") as OptionButton
		if btn:
			btn.clear()
			for option_text in instrument_options:
				btn.add_item(option_text)
	_init_fin.emit()

func _on_mute_toggled(is_pressed: bool):
	# 注意：MidiData的修改由TrackView._on_track_mute_toggled通过MidiPlaybackManager处理
	# 这里仅负责UI状态更新
	mute_btn.modulate = Color(1, 0.5, 0.5, 1) if is_pressed else Color(1, 1, 1, 1)

func _on_solo_toggled(is_pressed: bool):
	solo_btn.modulate = Color(1, 1, 0.5, 1) if is_pressed else Color(1, 1, 1, 1)

func _on_enable_toggled(toggle_on: bool):
	if midi_data:
		midi_data.set_track_channel_enabled(track_index, track_channel, toggle_on)
	enable_btn_text.text = "已启用" if toggle_on else "已禁用"

	note_display.note_color = color_normal if toggle_on else color_dark
	note_display.update_color()
