extends Button

class_name KeySequenceItem

## 单个键位项的数据
## 注意：属性名用 key_code 而非 key，避免与 Key 枚举类型同名导致跨类访问解析失败
var key_code: Key = Key.KEY_NONE
var display_name: String = ""
var item_index: int = -1

## 选中信号（被点击时触发，由父容器监听并切换右侧详情面板）
signal item_selected(item: KeySequenceItem)
## 拖拽开始信号
signal drag_started(item: KeySequenceItem)
## 拖拽过程中悬停在某个 item 上时触发（用于刷新 InsertPlace 位置）
signal drag_over(target: KeySequenceItem, at_pos: Vector2)
## 拖拽释放到目标 item 上时触发
signal drop_received(target: KeySequenceItem, dragged: KeySequenceItem)
## 拖拽结束（无论是否成功 drop）— 用于兜底隐藏 InsertPlace
signal drag_ended(source: KeySequenceItem)

func _ready() -> void:
	# button_group 已在 tscn 中设置（互斥单选）；pressed 仅在从未选中→选中时触发
	pressed.connect(_on_pressed)

## 写入数据并刷新文本
func set_data(k: Key, _name: String, idx: int) -> void:
	key_code = k
	display_name = _name
	item_index = idx
	refresh_text()

## 刷新按钮显示文本：自定义名称优先，否则用按键默认名；按键未设置时显示"未设置"
func refresh_text() -> void:
	if key_code == Key.KEY_NONE:
		text = "未设置"
		return
	if not display_name.is_empty():
		text = display_name
	else:
		text = OS.get_keycode_string(key_code)

# ===== 拖拽 =====

func _get_drag_data(_at_pos: Vector2) -> Variant:
	# 创建预览 Label 跟随光标
	var preview := Label.new()
	preview.text = text
	preview.add_theme_font_size_override("font_size", 32)
	preview.add_theme_color_override("font_color", Color.WHITE)
	preview.modulate.a = 0.8
	set_drag_preview(preview)
	drag_started.emit(self)
	return self

func _can_drop_data(at_pos: Vector2, data: Variant) -> bool:
	var can = data is KeySequenceItem and data != self
	if can:
		drag_over.emit(self, at_pos)
	return can

func _drop_data(_at_pos: Vector2, data: Variant) -> void:
	if data is KeySequenceItem and data != self:
		drop_received.emit(self, data)

func _notification(what: int) -> void:
	# 拖拽结束（释放或取消）时由引擎发送给源控件
	if what == NOTIFICATION_DRAG_END:
		drag_ended.emit(self)

# ===== 内部 =====

func _on_pressed() -> void:
	item_selected.emit(self)
