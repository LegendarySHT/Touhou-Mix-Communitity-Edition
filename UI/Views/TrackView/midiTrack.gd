extends Panel

class_name MidiTrack

@onready var note_display: NoteDisplayer = $HBoxC/MC/HBoxC/MC/flowArea

# 写着"Track"的按钮（我也没想到有什么用）
@onready var track_btn: Button = $HBoxC/Panel/TrackBtn
# 轨道编号
@onready var track_num: Label = $HBoxC/Panel/TrackNum
# 切换轨道启用状态的按钮
@onready var enable_btn: Button = $HBoxC/MC/HBoxC/enableBtn

@onready var mute_btn: TextureButton = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/MuteBtn
@onready var solo_btn: TextureButton = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/SoloBtn
@onready var volume_slider: HSlider = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/Volume/Slider
@onready var volume_label: Label = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/Volume/Label
@onready var instruments_option_btn: OptionButton = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/InstrumentBtn

# 轨道属性
var track_index: int = -1
var is_enabled: bool = true
var is_muted: bool = false
var is_solo: bool = false
var current_volume: float = 1.0
var current_instrument: String = ""

var instrument_options: Array = []


# 父节点
var parent_node: Node = null

func _ready():
	# 连接按钮信号
	_connect_signals()

	track_num.text = str(track_index)
	if not instrument_options:
		if not parent_node:
			push_error("轨道 %d 初始化失败: 无父节点" % track_index)
			return
		instrument_options = parent_node.instrument_options
	if not instrument_options:
		push_error("轨道 %d 初始化失败: 无可用乐器选项" % track_index)
		return
	for i in instrument_options:
		instruments_option_btn.add_item(i)

	if is_enabled:
		enable_btn.button_pressed = true

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
		enable_btn.toggled.connect(parent_node._on_track_enable_toggled.bind(track_index))
	if parent_node.has_method("_on_track_mute_toggled"):
		mute_btn.toggled.connect(parent_node._on_track_mute_toggled.bind(track_index))
	if parent_node.has_method("_on_track_solo_toggled"):
		solo_btn.toggled.connect(parent_node._on_track_solo_toggled.bind(track_index))
	if parent_node.has_method("_on_track_volume_changed"):
		volume_slider.value_changed.connect(parent_node._on_track_volume_changed.bind(track_index))
	if parent_node.has_method("_on_track_instrument_changed"):
		instruments_option_btn.item_selected.connect(parent_node._on_track_instrument_changed.bind(track_index))

# 提供父节点及轨道信息，自动连接信号 乐器选项不提供时从传入的父节点获取
func setup_track(parent: Node, index: int, track_name: String, instruments: Array = []):
	parent_node = parent
	track_index = index
	name = track_name
	instrument_options = instruments

func _on_mute_toggled(is_pressed: bool):
	is_muted = is_pressed
	mute_btn.modulate = Color(1, 0.5, 0.5, 1) if is_muted else Color(1, 1, 1, 1)

func _on_solo_toggled(is_pressed: bool):
	is_solo = is_pressed
	solo_btn.modulate = Color(1, 1, 0.5, 1) if is_solo else Color(1, 1, 1, 1)

func _on_enable_toggled(toggle_on: bool):
	is_enabled = toggle_on
	enable_btn.text = "已启用" if toggle_on else "已禁用"
