extends Panel

class_name MidiTrack

@onready var note_display: NoteDisplayer = $HBoxC/MC/HBoxC/MC/flowArea

# 写着轨道编号的按钮（我也没想到有什么用）
@onready var track_btn: Button = $HBoxC/Panel/TrackBtn
# 切换轨道启用状态的按钮
@onready var enable_btn: Button = $HBoxC/MC/HBoxC/enableBtn

@onready var mute_btn: TextureButton = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/MuteBtn
@onready var solo_btn: TextureButton = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/SoloBtn
@onready var volume_slider: HSlider = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/Volume/Slider
@onready var volume_label: Label = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/Volume/Label
@onready var instruments_option_btn: OptionButton = $HBoxC/MC/HBoxC/MC/ControlPanel/GridC/InstrumentBtn

# 轨道属性
var track_index: int = -1
var track_name: String = ""
var is_enabled: bool = true
var is_muted: bool = false
var is_solo: bool = false

func _ready():
	# 设置按钮的初始状态
	_update_enable_button()
	_update_mute_button()
	_update_solo_button()
	
	# 连接按钮信号
	mute_btn.toggled.connect(_on_mute_toggled)
	solo_btn.toggled.connect(_on_solo_toggled)

func _on_mute_toggled(is_pressed: bool):
	is_muted = is_pressed
	_update_mute_button()

func _on_solo_toggled(is_pressed: bool):
	is_solo = is_pressed
	_update_solo_button()

func _update_enable_button():
	enable_btn.text = "✓" if is_enabled else "✗"
	enable_btn.modulate = Color(1, 1, 1, 1) if is_enabled else Color(1, 1, 1, 0.5)

func _update_mute_button():
	mute_btn.modulate = Color(1, 0.5, 0.5, 1) if is_muted else Color(1, 1, 1, 1)

func _update_solo_button():
	solo_btn.modulate = Color(1, 1, 0.5, 1) if is_solo else Color(1, 1, 1, 1)
