extends HBoxContainer

class_name ParticleAdjust

@onready var _particle_preview: Panel = $ParticlePreview
@onready var _title_label: Label = $VBoxC/Title
@onready var _particle_type_btn: OptionButton = $VBoxC/OptionButton
@onready var _particle_scaling_edit: LineEdit = $VBoxC/OtherOptions/ValueLineEdit/LineEdit

# ===== 粒子设置页 =====
## 粒子 preset 选项（索引 0=None，之后动态从 ParticleMGR 读取粒子包）
## 与 SettingGroupsData 中 spark_preset 的 options 语义一致（0=无，1 起对应粒子包）
var _particle_presets: Array[String] = ["None"]
## 粒子预览场景（精灵图序列帧批绘节点）
var _particle_scene: PackedScene = preload("res://UI/Views/PlayView/particle_player.tscn")
## 常驻批绘节点（预览粒子全部由单个 Node2D 统一绘制）
var _particle_drawer: Node2D = null
## 预览循环定时器
var _particle_preview_timer: Timer = null
## 粒子预览自动播放间隔（秒）
const _PARTICLE_PREVIEW_INTERVAL: float = 1.8
## 缩放值防抖定时器（连续输入时只保存 + 预览一次，避免逐字符写盘/重复实例化）
var _scaling_debounce_timer: Timer = null
const _SCALING_DEBOUNCE_SEC := 0.4

## 当前正在编辑的判定类型（Perfect / Great / Good / Bad）
## 由 PopupWindow.show_particle_adjust 传入，决定读写哪个 spark 配置字段
var _judge_type: String = "Perfect"

func _ready() -> void:
	_particle_type_btn.item_selected.connect(_on_particle_preset_selected)
	_particle_scaling_edit.text_changed.connect(_on_particle_scaling_changed)
	# 常驻单个批绘节点，预览粒子由它统一绘制
	_particle_drawer = _particle_scene.instantiate()
	_particle_preview.add_child(_particle_drawer)
	_init_particle_preview()
	_init_scaling_debounce()

## 初始化缩放防抖定时器（one-shot，连续输入只触发一次保存 + 预览）
func _init_scaling_debounce() -> void:
	_scaling_debounce_timer = Timer.new()
	_scaling_debounce_timer.one_shot = true
	_scaling_debounce_timer.wait_time = _SCALING_DEBOUNCE_SEC
	_scaling_debounce_timer.timeout.connect(_apply_scaling_debounced)
	add_child(_scaling_debounce_timer)

## 初始化粒子预览循环定时器（粒子由常驻批绘节点统一绘制，定时触发 spawn）
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
	# 刷新粒子样式选项（动态从 ParticleMGR 读取，支持外部导入的粒子包）
	_refresh_presets()
	# 选中当前配置值
	var preset_key := "%s_spark_preset" % judge_type.to_lower()
	var current_preset: int = ConfigManager.instance.get_int("Lane", preset_key, 0)
	_particle_type_btn.selected = clampi(current_preset, 0, _particle_presets.size() - 1)
	# 显示当前缩放值（临时断开信号避免回环）
	var scaling_key := "%s_spark_scaling" % judge_type.to_lower()
	var current_scaling: int = ConfigManager.instance.get_int("Lane", scaling_key, 100)
	_particle_scaling_edit.text_changed.disconnect(_on_particle_scaling_changed)
	_particle_scaling_edit.text = str(current_scaling)
	_particle_scaling_edit.text_changed.connect(_on_particle_scaling_changed)

## 刷新粒子包选项列表（索引 0=None，1 起按 ParticleMGR 扫描顺序：内置在前，用户在后）
func _refresh_presets() -> void:
	_particle_presets = ["None"]
	for pack_key in ParticleMGR.get_particle_list():
		_particle_presets.append(pack_key)
	# 同步到 OptionButton 的显示项
	_particle_type_btn.clear()
	for pack_name in _particle_presets:
		_particle_type_btn.add_item(pack_name)

## 播放一次预览粒子（在 ParticlePreview 中心，使用当前选中的 preset 和缩放值）
## 由常驻批绘节点直接 spawn，粒子内部 _process/_draw 统一推进绘制
func _play_preview_particle() -> void:
	if not is_visible_in_tree():
		return
	# preset=0 (None) 时不播放
	var preset_idx: int = _particle_type_btn.selected
	if preset_idx == 0:
		return
	var scaling_str := _particle_scaling_edit.text
	var scaling: int = int(scaling_str) if scaling_str.is_valid_int() else 100
	var pack_key: String = _particle_presets[preset_idx]
	# 单节点批绘：直接 spawn，粒子由内部 _process/_draw 统一推进绘制
	# Node2D 在 Control 下的 position 以左上角为原点，Panel size=500x500 → 中心 250,250
	_particle_drawer.spawn(pack_key, _judge_type, _particle_preview.size / 2.0, scaling)

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

## 缩放值修改：重启防抖定时器，停顿后统一保存 + 播放预览
func _on_particle_scaling_changed(_new_text: String) -> void:
	_scaling_debounce_timer.start()

## 防抖触发：将当前缩放值保存到对应判定类型的配置字段并播放一次预览
func _apply_scaling_debounced() -> void:
	if not _particle_scaling_edit.text.is_valid_int():
		return
	var value := int(_particle_scaling_edit.text)
	var scaling_key := "%s_spark_scaling" % _judge_type.to_lower()
	ConfigManager.instance.set_value_and_notify("Lane", scaling_key, value)
	# 弹窗已关闭时不再重复播放预览（配置保存本身无副作用）
	if is_visible_in_tree():
		_play_preview_particle()

## 返回当前粒子设置（供 PopupWindow.show_particle_adjust 返回）
func get_result() -> Dictionary:
	return {
		"judge_type": _judge_type,
		"preset": _particle_type_btn.selected,
		"preset_name": _particle_presets[_particle_type_btn.selected],
		"scaling": int(_particle_scaling_edit.text) if _particle_scaling_edit.text.is_valid_int() else 100,
	}
