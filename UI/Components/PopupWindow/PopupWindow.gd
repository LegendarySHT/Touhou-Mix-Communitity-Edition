extends PopupPanel

class_name PopupWindow

static var instance: PopupWindow

@onready var style: PanelContainer = $Style
@onready var tab_c: TabContainer = $TabC
@onready var content: Label = $TabC/Default/VBoxC/Content/Label
@onready var option_btn: OptionButton = $TabC/Default/VBoxC/Content/OptionButton
@onready var cancel_btn: Button = $TabC/Default/VBoxC/Btns/Cancel
@onready var confirm_btn: Button = $TabC/Default/VBoxC/Btns/Confirm

@onready var ani: AnimationManager = AniMGR

## 背景遮罩（同级节点 PopupWindowBG）
var _bg: ColorRect

signal window_close

var confirm: bool = false

func _ready() -> void:
	instance = self
	# 按钮信号改为代码连接
	cancel_btn.pressed.connect(_on_cancel_pressed)
	confirm_btn.pressed.connect(_on_confirm_pressed)
	# 监听内置 popup 生命周期信号
	about_to_popup.connect(func() -> void: _window_popup_animate(true))
	# 点击窗口外部时 Godot 会自动隐藏 popup 并发出 popup_hide，此处兜底处理
	popup_hide.connect(func() -> void: _window_popup_animate(false))
	# PopupWindowBG 是同级节点（背景遮罩）
	_bg = get_parent().get_node_or_null("PopupWindowBG")

func _on_cancel_pressed() -> void:
	confirm = false
	hide()

func _on_confirm_pressed() -> void:
	confirm = true
	hide()

func _window_popup_animate(is_popup: bool) -> Tween:
	var popup_tween : Tween = null
	if is_popup:
		# 窗口内容
		for nd in get_children():
			nd.offset_transform_scale = Vector2.ZERO if is_popup else Vector2.ONE
			ani.animate_offset_scale(nd, Vector2.ZERO if not is_popup else Vector2.ONE, 0.4, "popup_%s_scale" % nd.name)

		# 背景
		popup_tween = ani.animate_fade_in(_bg, 0.3, "popup_bg_fade")
	else:
		popup_tween = ani.animate_fade_out(_bg, 0.3, "popup_bg_fade")
		popup_tween.finished.connect(func() -> void: window_close.emit())
	return popup_tween

# 用默认窗口显示消息或者选择内容
func set_message(message: String, cancel_visible: bool = false, option_visible: bool = false) -> void:
	size = Vector2(800, 550)
	tab_c.current_tab = 0
	content.text = message
	cancel_btn.modulate.a = 0 if not cancel_visible else 1
	option_btn.visible = option_visible
	popup()  # 内置 popup() → 触发 about_to_popup → 播放进入动画
