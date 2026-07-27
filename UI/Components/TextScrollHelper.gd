## 文字滚动工具
## 用于长文本超出显示区域时的来回滚动效果（marquee）。
##
## 用法（在消费方脚本顶部声明）：
##   const TextScrollHelper = preload("res://UI/Components/TextScrollHelper.gd")
##   var state: TextScrollHelper.State = null
##   state = TextScrollHelper.setup(label, clip_container, full_text, state)
##   # 尺寸/字体变化后再次调用 setup 即可重算
##   # 退出/隐藏时调用 TextScrollHelper.stop(state)
##
## 结构要求：Label 必须作为某个 clip_contents=true 的 Control 子节点, 布局使用锚点布局并选择整个矩形的锚点预设即可
extends RefCounted

## 滚动一段的时长
const SCROLL_DURATION := 3.0
## 滚动到端点后的停留时长
const PAUSE_DURATION := 1.0


## 滚动状态（RefCounted，随持有者释放）
class State extends RefCounted:
	var tween: Tween = null
	var label: Label = null
	var clip: Control = null
	var full_text: String = ""
	var _resized_callable: Callable


## 启动或重新计算滚动。
## - 传入 prev_state 可复用并清理旧动画
## - 不修改 Label 的 horizontal_alignment / vertical_alignment，保留 tscn 原值
## - 溢出时通过 position:x 实现来回滚动；非溢出时仅 kill 旧 tween
static func setup(label: Label, clip_container: Control, full_text: String,
		prev_state: State = null) -> State:
	var state: State = prev_state if prev_state != null else State.new()
	if state.tween != null and is_instance_valid(state.tween):
		state.tween.kill()
	state.label = label
	state.clip = clip_container
	state.full_text = full_text
	state.tween = null

	# 重置 Label 位置
	label.offset_transform_position.x = 0.0

	# 获取容器宽度（未布局时回退到 custom_minimum_size 或经验值）
	var box_width := clip_container.size.x
	if box_width <= 10.0:
		box_width = max(clip_container.custom_minimum_size.x, 200.0)

	# 文字高度：用字体实际行高，避免垂直裁剪
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")

	# 测量文字宽度
	var text_width := font.get_string_size(
		full_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x

	# 容器尺寸变化时重新计算滚动（仅首次连接，防止重复累积）
	if not (state._resized_callable.is_valid() and clip_container.resized.is_connected(state._resized_callable)):
		var _cb := func():
			refresh(state)
		state._resized_callable = _cb
		clip_container.resized.connect(_cb)

	# 文字未溢出：不滚动
	if text_width <= box_width:
		return state

	# 启用 offset_transform 并左对齐
	label.offset_transform_enabled = true
	label.grow_horizontal = Control.GROW_DIRECTION_END

	# 文字溢出：来回滚动
	var max_offset := text_width - box_width + 20.0  # 额外留点空隙
	var tween := label.create_tween().set_loops()
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "offset_transform_position:x", -max_offset, SCROLL_DURATION)
	tween.tween_interval(PAUSE_DURATION)
	tween.tween_property(label, "offset_transform_position:x", 0.0, SCROLL_DURATION)
	tween.tween_interval(PAUSE_DURATION)
	state.tween = tween
	return state


## 停止滚动并重置 Label 位置
static func stop(state: State) -> void:
	if state == null:
		return
	if state._resized_callable.is_valid() and is_instance_valid(state.clip) and state.clip.resized.is_connected(state._resized_callable):
		state.clip.resized.disconnect(state._resized_callable)
	if state.tween != null and is_instance_valid(state.tween):
		state.tween.kill()
		state.tween = null
	if state.label != null and is_instance_valid(state.label):
		state.label.offset_transform_position.x = 0.0


## 使用 state 中缓存的 full_text 重新计算并启动
static func refresh(state: State) -> State:
	if state == null or state.label == null or state.clip == null:
		return state
	return setup(state.label, state.clip, state.full_text, state)
