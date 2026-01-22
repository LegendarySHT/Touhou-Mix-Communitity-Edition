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

## 列表项的按钮
var button: Button

## 选中动画相关
var _enable_ani: bool = false
var _item_btn: Button
var pulse_tween: Tween
var press_tween: Tween

var _mouse_press: bool = false
var _mouse_press_pos:Vector2 = Vector2.ZERO

signal btn_toggled(toggled_on: bool)
signal btn_confirmed

## 初始化函数
func enable_selected_animation(btn: Button) -> void:
	init_btn(btn)
	_enable_ani = true

func init_btn(btn: Button) -> void:
	_item_btn = btn
	# 连接按钮信号
	_item_btn.button_down.connect(_on_button_down)
	_item_btn.button_up.connect(_on_button_up)
	_item_btn.toggled.connect(_on_toggled)

func _on_button_down():
	_mouse_press_pos = get_global_mouse_position()
	_mouse_press = true
	if not _enable_ani:
		return

	# 按下效果
	if press_tween:
		press_tween.kill()
	if pulse_tween:
		pulse_tween.kill()

	press_tween = create_tween()
	press_tween.tween_property(self, "scale", Vector2(0.96, 0.96), 0.07).set_ease(Tween.EASE_OUT)

func _on_button_up():
	if not _enable_ani:
		return

	# 松开弹起效果
	if press_tween:
		press_tween.kill()
	
	press_tween = create_tween()
	press_tween.tween_property(self, "scale", Vector2(1.03, 1.03), 0.06).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	
	press_tween.tween_property(self, "scale", Vector2(0.98, 0.98), 0.34).set_ease(Tween.EASE_IN_OUT)

	press_tween.finished.connect(func ():
		if not is_selected:
			_pulse_animation(false)
	)

func _on_toggled(toggled_on: bool):
	# 切换选中状态
	var dis = get_global_mouse_position().distance_to(_mouse_press_pos)
	var final: bool = false
	if dis < 30 or not _mouse_press:
		final = toggled_on
	
	btn_toggled.emit(final)
	if _enable_ani:
		await get_tree().create_timer(0.4).timeout
		# if toggled_on == final:
		print("btn idx ", _item_btn.get_meta("index"),final)
		_pulse_animation(final)
			# await get_tree().create_timer(0.4).timeout
		# else:
		# 	print("branch 2 %d" % _item_btn.get_meta("index"))
		# 	_pulse_animation(is_selected)

	_mouse_press_pos = Vector2.ZERO
	_mouse_press = false
	
func _pulse_animation(enable: bool):
	if pulse_tween:
		pulse_tween.kill()
		pulse_tween = null
	
	if enable:
		pulse_tween = create_tween()
		pulse_tween.set_loops()
		
		# 柔和的脉冲
		pulse_tween.tween_property(self, "scale", Vector2(1.01, 1.01), 0.8).set_ease(Tween.EASE_IN_OUT)
		
		pulse_tween.tween_property(self, "scale", Vector2(0.99, 0.99), 0.8).set_ease(Tween.EASE_IN_OUT)
	else:
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_IN_OUT)

# ## 虚函数：初始化列表项
func initialize(id: String, type: String) -> void:
	item_id = id
	item_type = type

# ## 虚函数：设置选中状态
# func set_selected(selected: bool) -> void:
# 	is_selected = selected
# 	if selected:
# 		_on_selected()
# 		self.selected.emit(item_id)
# 	else:
# 		_on_deselected()
# 		self.deselected.emit(item_id)

# ## 虚函数：设置悬停状态
# func set_hovered(hovered: bool) -> void:
# 	is_hovered = hovered
# 	if hovered:
# 		_on_hovered()
# 		self.hovered.emit(item_id)
# 	else:
# 		_on_unhovered()
# 		unhovered.emit()

# ## 虚函数：当被选中时调用
# func _on_selected() -> void:
# 	pass

# ## 虚函数：当被取消选中时调用
# func _on_deselected() -> void:
# 	pass

# ## 虚函数：当被悬停时调用
# func _on_hovered() -> void:
# 	pass

# ## 虚函数：当取消悬停时调用
# func _on_unhovered() -> void:
# 	pass

# ## 虚函数：更新视觉效果（在选中/悬停状态改变时调用）
# func update_appearance() -> void:
# 	pass

# ## 获取列表项ID
# func get_item_id() -> String:
# 	return item_id

# ## 获取列表项类型
# func get_item_type() -> String:
# 	return item_type
