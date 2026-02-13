extends ColorRect

class_name PopupWindow

static var instance: PopupWindow

@onready var window: Panel = $Window
@onready var content: Label = $Window/VBoxC/Content/Label
@onready var option_btn: OptionButton = $Window/VBoxC/Content/OptionButton

@onready var cancel_btn: Button = $Window/VBoxC/Btns/Cancel
@onready var confirm_btn: Button = $Window/VBoxC/Btns/Confirm

@onready var ani: AnimationManager = AnimationManager.instance

signal window_close

var confirm: bool = false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_cancel_pressed()
			accept_event()

func _ready() -> void:
	instance = self

func _on_cancel_pressed() -> void:
	confirm = false
	close()

func _on_confirm_pressed() -> void:
	confirm = true
	close()
	
func set_message(message: String):
	content.text = message
	option_btn.visible = false

	cancel_btn.modulate.a = 0
	popup()

func show_del_selection():
	content.text = "请选择要删除的内容"
	option_btn.visible = true

	cancel_btn.modulate.a = 1
	popup()

func close():
	ani.animate_fade_out(self, 0.4, "menu_bg_fade")
	ani.animate_scale(window, Vector2.ZERO, 0.25, "window_scale")
	window_close.emit()

func popup():
	ani.animate_fade_in(self, 0.8, "menu_bg_fade")
	window.scale = Vector2.ZERO
	ani.animate_scale(window, Vector2.ONE, 0.5, "window_scale")
