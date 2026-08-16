extends Control

## 通用倾斜布局同步：
## 挂在作倾斜的 Node2D 下的 Control(C) 上，自动跟随上层最近的 Control 容器尺寸，
## 并补偿 skew 切变使视觉对齐，避免每次为倾斜手动写布局同步。
## 树结构约定：self 的父节点是作倾斜的 Node2D，Node2D 的父（或更上层）是参照 Control。

## 是否同步宽度
@export var sync_width: bool = true
## 是否同步高度
@export var sync_height: bool = true
## 是否补偿 skew 切变（让倾斜后的视觉右边缘对齐参照容器右边缘）
@export var skew_compensate: bool = true

## 参照 Control（自动探测，可能为空时回退到 viewport 尺寸）
var _ref_control: Control

func _ready() -> void:
	_ref_control = _find_ref_control()
	if _ref_control:
		_ref_control.resized.connect(_sync)
	_sync()

## 向上查找参照 Control：先取父 Node2D 的父，若非 Control 则继续上溯
func _find_ref_control() -> Control:
	var p := get_parent()
	if p is Node2D:
		p = p.get_parent()
	while p and not (p is Control):
		p = p.get_parent()
	return p as Control

## 读取倾斜角度（弧度）：取父 Node2D 的 skew
func _get_skew_angle() -> float:
	var p := get_parent()
	if p is Node2D:
		return p.skew
	return 0.0

func _sync() -> void:
	var ref_size := _ref_control.size if _ref_control else get_viewport().get_visible_rect().size
	var angle := _get_skew_angle()
	var tan_a := tan(angle)
	var cos_a := cos(angle)
	# 切变导致的水平偏移量（按参照高度计算）
	var margin := ref_size.y * tan_a if skew_compensate else 0.0

	var new_pos := position
	var new_size := size
	if sync_width:
		new_size.x = ref_size.x - margin
		new_pos.x = margin
	if sync_height:
		new_size.y = ref_size.y / cos_a if cos_a != 0.0 else ref_size.y
	position = new_pos
	size = new_size
