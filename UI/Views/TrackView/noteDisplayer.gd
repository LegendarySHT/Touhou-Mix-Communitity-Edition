extends HBoxContainer

class_name NoteDisplayer

@onready var flow_area: Panel = $noteFlowArea # 显示音符的区域
@onready var note_count_passed: Label = $noteTotal/VBoxC/passedNote # 显示已通过的音符数量
@onready var note_count_total: Label = $noteTotal/VBoxC/totalNote   # 显示总音符数量

# midi track独有的控制节点
@onready var mute_btn: TextureButton = $noteFlowArea/HBoxC/ControlPanel/GridC/MuteBtn
@onready var solo_btn: TextureButton = $noteFlowArea/HBoxC/ControlPanel/GridC/SoloBtn
@onready var volume_slider: Slider = $noteFlowArea/HBoxC/ControlPanel/GridC/Volume/Slider
@onready var volume_label: Label = $noteFlowArea/HBoxC/ControlPanel/GridC/Volume/Label
@onready var instrument_btn: OptionButton = $noteFlowArea/HBoxC/ControlPanel/GridC/InstrumentBtn
