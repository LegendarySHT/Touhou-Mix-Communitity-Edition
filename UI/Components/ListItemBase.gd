## UI列表项的基类
## 所有列表项（专辑、歌曲、MIDI）都应继承此类
extends Control

class_name ListItemBase

## 列表项所代表的数据ID
var item_id: String = ""

## 列表项的索引
var item_index: int = -1

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

var _pass_focus: bool = false

var parent_node: Node = null

signal btn_toggled(toggled_on: bool)
signal btn_confirmed(index: int)

## 初始化函数
func enable_selected_animation(btn: Button, parent) -> void:
	init_btn(btn, parent)
	_enable_ani = true

func init_btn(btn: Button, parent) -> void:
	if _item_btn:
		return

	_item_btn = btn
	parent_node = parent
	
	# 连接按钮信号
	_item_btn.button_down.connect(_on_button_down)
	_item_btn.button_up.connect(_on_button_up)
	_item_btn.toggled.connect(_on_toggled)

	if parent.has_method("on_item_button_confirmed"):
		btn_confirmed.connect(parent.on_item_button_confirmed)
	if has_method("on_item_button_toggled"):
		btn_toggled.connect(self.on_item_button_toggled)

	# 自动选择聚焦的项
	button.focus_entered.connect(_on_focus_entered)

func _on_focus_entered():
	if _pass_focus:
		_pass_focus = false
		return

	# 方向键聚焦时需要触发按钮
	await get_tree().process_frame
	if not button.button_pressed and _mouse_press_pos == Vector2.ZERO:
		parent_node.select_item(item_index)

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
		_pulse_animation(is_selected)
	)

func _on_toggled(toggled_on: bool):
	# 切换选中状态
	var dis = get_global_mouse_position().distance_to(_mouse_press_pos)
	var final: bool = false
	if dis < 30 or not _mouse_press:
		final = toggled_on

	var temp = is_selected
	is_selected = final
	_pass_focus = final
	await get_tree().process_frame
	if is_selected and self != get_viewport().gui_get_focus_owner():
		button.grab_focus()
	_mouse_press_pos = Vector2.ZERO
	_mouse_press = false

	if final and temp:
		btn_confirmed.emit(item_index)
	else:
		btn_toggled.emit(final)

	if _enable_ani:
		await get_tree().create_timer(0.4).timeout
		_pulse_animation(final)
	

	
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

# 虚函数：初始化列表项
func initialize(id: String, type: String) -> void:
	item_id = id
	item_type = type
