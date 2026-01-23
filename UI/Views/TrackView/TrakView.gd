extends ScrollContainer

@onready var total_note: NoteDisplayer = $VBox/TotalView/VBoxC/flowArea
@onready var current_time: Label = $VBox/TotalView/VBoxC/playArea/currentTime
@onready var progress_bar: HSlider = $VBox/TotalView/VBoxC/playArea/progressBar
@onready var total_time: Label = $VBox/TotalView/VBoxC/playArea/totalTime

# 导入人声按钮，存在人声时变为切换启用状态？
@onready var vocal_btn: TextureButton = $VBox/VolumeView/HBoxC/VBoxC2/VocalBtn
@onready var latency_edit: LineEdit = $VBox/VolumeView/HBoxC/VBoxC2/HBoxContainer/Latency
@onready var midi_vol_btn: TextureButton = $VBox/VolumeView/HBoxC/GridC/midiVolIcon
@onready var midi_vol_slider: HSlider = $VBox/VolumeView/HBoxC/GridC/midiVolSlider
@onready var midi_vol_label: Label = $VBox/VolumeView/HBoxC/GridC/midiVolLabel
@onready var volcal_vol_btn: TextureButton = $VBox/VolumeView/HBoxC/GridC/vocalVolIcon
@onready var vocal_vol_slider: HSlider = $VBox/VolumeView/HBoxC/GridC/vocalVolSlider
@onready var vocal_vol_label: Label = $VBox/VolumeView/HBoxC/GridC/vocalVolLabel

# 底部填充，增加新项时需要把这个移到底部
@onready var bottom: MarginContainer = $VBox/PaddingBottom
