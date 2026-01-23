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
