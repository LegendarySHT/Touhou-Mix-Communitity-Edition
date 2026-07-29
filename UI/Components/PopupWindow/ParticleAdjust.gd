extends HBoxContainer

class_name ParticleAdjust

@onready var _particle_preview: Panel = $ParticlePreview
@onready var _title_label: Label = $VBoxC/Title
@onready var _particle_type_btn: OptionButton = $VBoxC/OptionButton
@onready var _particle_scaling_edit: LineEdit = $VBoxC/OtherOptions/ValueLineEdit/LineEdit

# ===== 粒子设置页 =====
## 粒子 preset 选项（与 SettingGroupsData 中 spark_preset 的 options 一致）
## 索引 0=None 关闭，1=Block 方块；之后扩展新粒子效果时在此追加
const _PARTICLE_PRESETS: Array[String] = ["None", "Block"]
## 预览时使用的判定类型（仅用于触发 particle_square.play，展示粒子样式本身）
const _PARTICLE_PREVIEW_TYPE: String = "Perfect"
## 粒子预览场景
var _particle_scene: PackedScene = preload("res://UI/Views/PlayView/particleSquare.tscn")
## 预览循环定时器
var _particle_preview_timer: Timer = null
## 粒子预览自动播放间隔（秒）
const _PARTICLE_PREVIEW_INTERVAL: float = 1.8

## 当前正在编辑的判定类型（Perfect / Great / Good / Bad）
## 由 PopupWindow.show_particle_adjust 传入，决定读写哪个 spark 配置字段
var _judge_type: String = "Perfect"

func _ready() -> void:
	_particle_type_btn.item_selected.connect(_on_particle_preset_selected)
	_particle_scaling_edit.text_changed.connect(_on_particle_scaling_changed)
	_init_particle_preview()

## 初始化粒子预览循环定时器（实际粒子实例在每次播放时 instantiate）
func _init_particle_preview() -> void:
	_particle_preview_timer = Timer.new()
	_particle_preview_timer.wait_time = _PARTICLE_PREVIEW_INTERVAL
	_particle_preview_timer.timeout.connect(_play_preview_particle)
	add_child(_particle_preview_timer)

## 由 PopupWindow.show_particle_adjust 调用：填充选项 + 选中当前配置值
## judge_type: Perfect / Great / Good / Bad，决定读写哪个 spark 配置字段
func init_adjust(judge_type: String = "Perfect") -> void:
	_judge_type = judge_type
	# 更新窗口标题
	_title_label.text = "%s 特效设定" % judge_type
	# 填充粒子样式选项（None/Block/...）
	_particle_type_btn.clear()
	for _name in _PARTICLE_PRESETS:
		_particle_type_btn.add_item(_name)
	# 选中当前配置值
	var preset_key := "%s_spark_preset" % judge_type.to_lower()
	var current_preset: int = ConfigManager.instance.get_int("Lane", preset_key, 0)
	_particle_type_btn.selected = clampi(current_preset, 0, _PARTICLE_PRESETS.size() - 1)
	# 显示当前缩放值（临时断开信号避免回环）
	var scaling_key := "%s_spark_scaling" % judge_type.to_lower()
	var current_scaling: int = ConfigManager.instance.get_int("Lane", scaling_key, 50)
	_particle_scaling_edit.text_changed.disconnect(_on_particle_scaling_changed)
	_particle_scaling_edit.text = str(current_scaling)
	_particle_scaling_edit.text_changed.connect(_on_particle_scaling_changed)

## 播放一次预览粒子（在 ParticlePreview 中心，使用当前选中的 preset 和缩放值）
## 每次播放都 instantiate 新实例，避免 CONNECT_ONE_SHOT 重复连接冲突（与 FlowArea 对象池一致的做法）
func _play_preview_particle() -> void:
	if not is_visible_in_tree():
		return
	# preset=0 (None) 时不播放
	var preset_idx: int = _particle_type_btn.selected
	if preset_idx == 0:
		return
	var scaling_str := _particle_scaling_edit.text
	var scaling: int = int(scaling_str) if scaling_str.is_valid_int() else 50
	# 每次播放创建新实例，播完后通过 particle_done 信号自动回收
	var ptc: Node2D = _particle_scene.instantiate()
	_particle_preview.add_child(ptc)
	# Node2D 在 Control 下的 position 以左上角为原点，Panel size=500x500 → 中心 250,250
	ptc.position = _particle_preview.size / 2.0
	ptc.set_particle_scale(scaling)
	# 用 Perfect 类型触发 play（仅展示粒子样式本身，不区分判定类型）
	ptc.play(_PARTICLE_PREVIEW_TYPE)
	# 播放完成后自动 queue_free
	ptc.particle_done.connect(func() -> void:
		if is_instance_valid(ptc):
			ptc.queue_free()
	)

## 启动粒子预览循环
func start_preview() -> void:
	if _particle_preview_timer:
		_particle_preview_timer.start()
	# 立即播放一次
	_play_preview_particle()

## 停止粒子预览循环
func stop_preview() -> void:
	if _particle_preview_timer and not _particle_preview_timer.is_stopped():
		_particle_preview_timer.stop()

## 切换粒子样式：即时保存到对应判定类型的配置字段并播放一次预览
func _on_particle_preset_selected(_index: int) -> void:
	# preset 配置对应 Lane 段的 {judge_type_lower}_spark_preset 字段
	var preset_value: int = _particle_type_btn.selected
	var preset_key := "%s_spark_preset" % _judge_type.to_lower()
	ConfigManager.instance.set_value_and_notify("Lane", preset_key, preset_value)
	_play_preview_particle()

## 缩放值修改：即时保存到对应判定类型的配置字段并播放一次预览
func _on_particle_scaling_changed(new_text: String) -> void:
	if not new_text.is_valid_int():
		return
	var value := int(new_text)
	var scaling_key := "%s_spark_scaling" % _judge_type.to_lower()
	ConfigManager.instance.set_value_and_notify("Lane", scaling_key, value)
	_play_preview_particle()

## 返回当前粒子设置（供 PopupWindow.show_particle_adjust 返回）
func get_result() -> Dictionary:
	return {
		"judge_type": _judge_type,
		"preset": _particle_type_btn.selected,
		"preset_name": _PARTICLE_PRESETS[_particle_type_btn.selected],
		"scaling": int(_particle_scaling_edit.text) if _particle_scaling_edit.text.is_valid_int() else 0,
	}
