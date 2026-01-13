## UI列表项的基类
## 所有列表项（专辑、歌曲、MIDI）都应继承此类
extends Control

class_name ListItemBase

## 列表项所代表的数据ID
var item_id: String = ""

## 列表项类型（"album"、"song"、"midi"等）
var item_type: String = ""

## 是否被选中
var is_selected: bool = false

## 是否被悬停
var is_hovered: bool = false

## 选中状态改变信号
signal selected(item_id: String)
signal deselected(item_id: String)
signal hovered(item_id: String)
signal unhovered

## 虚函数：初始化列表项
func initialize(id: String, type: String) -> void:
	item_id = id
	item_type = type

## 虚函数：设置选中状态
func set_selected(selected: bool) -> void:
	is_selected = selected
	if selected:
		_on_selected()
		self.selected.emit(item_id)
	else:
		_on_deselected()
		self.deselected.emit(item_id)

## 虚函数：设置悬停状态
func set_hovered(hovered: bool) -> void:
	is_hovered = hovered
	if hovered:
		_on_hovered()
		self.hovered.emit(item_id)
	else:
		_on_unhovered()
		unhovered.emit()

## 虚函数：当被选中时调用
func _on_selected() -> void:
	pass

## 虚函数：当被取消选中时调用
func _on_deselected() -> void:
	pass

## 虚函数：当被悬停时调用
func _on_hovered() -> void:
	pass

## 虚函数：当取消悬停时调用
func _on_unhovered() -> void:
	pass

## 虚函数：更新视觉效果（在选中/悬停状态改变时调用）
func update_appearance() -> void:
	pass

## 获取列表项ID
func get_item_id() -> String:
	return item_id

## 获取列表项类型
func get_item_type() -> String:
	return item_type
