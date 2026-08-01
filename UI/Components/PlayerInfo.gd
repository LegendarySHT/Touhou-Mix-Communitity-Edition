extends Control

# ========== 状态 ==========
# LOGGED_OUT: 未登录，InfoPanel 缩右 + 显示"点击此处注册"提示
# LOGGED_IN:  已登录，InfoPanel 复位 + 隐藏提示
# EXPANDED:   面板展开（登录/注册），ExpandInfoPanel 淡入并放大，InfoPanel 淡出，遮罩淡入
enum State { LOGGED_OUT, LOGGED_IN, EXPANDED }

# ========== 常量 ==========
# InfoPanel 的 skew（与 ExpandInfoPanel 共享同一 StyleBoxFlat_bg4s2）
const SKEW_LOGGED_OUT := 0.55
const SKEW_LOGGED_IN := 0.268
# 未登录时 InfoPanel 向右偏移
const OFFSET_LOGGED_OUT_X := 490.0
# Tip 宽度：未登录容纳提示文字，已登录仅作间距
const TIP_WIDTH_LOGGED_OUT := 100.0
const TIP_WIDTH_LOGGED_IN := 20.0
# ExpandInfoPanel 收起/展开的 offset_left/offset_top
# 右下锚定 (anchor 1,1,1,1)，offset_right=50 / offset_bottom=5 固定
# 收起: offset_left=-800, offset_top=-195  → size 850×200
# 展开: offset_left=-1000, offset_top=-1075 → size 1050×1080
const COLLAPSE_OFFSET := Vector2(-800, -195)
const EXPAND_OFFSET := Vector2(-1000, -1075)
const ANIM_DURATION := 0.35

# ========== 节点 ==========
@onready var info_panel: PanelContainer = $InfoPanel
@onready var info_panel_style: StyleBoxFlat = info_panel.get_theme_stylebox("panel")
@onready var tip: Control = $InfoPanel/HBoxContainer/Tip
@onready var tip_label: Label = $InfoPanel/HBoxContainer/Tip/Label
@onready var expand_panel: Button = $ExpandInfoPanel
@onready var expand_content: VBoxContainer = $ExpandInfoPanel/VBoxC
@onready var shader_overlay: ColorRect = $ExpandPanelShader
@onready var shortcut_menu = get_node_or_null("/root/Main/skew/C/ShortCutMenu")
@onready var rb_btn = get_node_or_null("/root/Main/RB_Btn")

# ========== 运行时 ==========
var _state: State = State.LOGGED_OUT
var _tween: Tween = null
# 展开期间的登录结果，由登录逻辑通过 set_login_result 设置；收起时据此回到对应状态
var _login_result: bool = false
# 展开前 RB_Btn 的显示状态，收起时恢复
var _saved_rb_stat = -1

func _ready() -> void:
	_apply_state_instant(State.LOGGED_OUT)
	expand_panel.pressed.connect(_on_expand_panel_pressed)
	if shader_overlay:
		shader_overlay.gui_input.connect(_on_shader_overlay_gui_input)

# ========== 状态应用 ==========

## 瞬时应用状态（无动画，用于初始化）
func _apply_state_instant(s: State) -> void:
	_state = s
	match s:
		State.LOGGED_OUT:
			info_panel.offset_transform_position = Vector2(OFFSET_LOGGED_OUT_X, 0)
			info_panel_style.skew = Vector2(SKEW_LOGGED_OUT, 0)
			tip.custom_minimum_size.x = TIP_WIDTH_LOGGED_OUT
			tip_label.visible = true
			# ExpandInfoPanel 透明但可见，作为点击层；VBoxC 隐藏防止子控件（LineEdit）拦截点击
			expand_panel.modulate.a = 0.0
			expand_panel.visible = true
			expand_panel.offset_left = COLLAPSE_OFFSET.x
			expand_panel.offset_top = COLLAPSE_OFFSET.y
			expand_panel.offset_transform_position = Vector2(OFFSET_LOGGED_OUT_X, 0)
			expand_content.visible = false
			# InfoPanel 可见；遮罩隐藏
			info_panel.modulate.a = 1.0
			if shader_overlay:
				shader_overlay.visible = false
				shader_overlay.modulate.a = 0.0
		State.LOGGED_IN:
			info_panel.offset_transform_position = Vector2.ZERO
			info_panel_style.skew = Vector2(SKEW_LOGGED_IN, 0)
			tip.custom_minimum_size.x = TIP_WIDTH_LOGGED_IN
			tip_label.visible = false
			expand_panel.modulate.a = 0.0
			expand_panel.visible = false
			expand_panel.offset_transform_position = Vector2.ZERO
			info_panel.modulate.a = 1.0
			if shader_overlay:
				shader_overlay.visible = false
				shader_overlay.modulate.a = 0.0
		State.EXPANDED:
			expand_panel.modulate.a = 1.0
			expand_panel.offset_left = EXPAND_OFFSET.x
			expand_panel.offset_top = EXPAND_OFFSET.y
			expand_panel.offset_transform_position = Vector2.ZERO
			expand_content.visible = true
			info_panel.modulate.a = 0.0
			if shader_overlay:
				shader_overlay.visible = true
				shader_overlay.modulate.a = 1.0

## 动画切换到新状态
func _animate_to_state(s: State) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)

	match s:
		State.LOGGED_OUT:
			_tween.tween_property(info_panel, "offset_transform_position", Vector2(OFFSET_LOGGED_OUT_X, 0), ANIM_DURATION)
			_tween.tween_property(info_panel_style, "skew", Vector2(SKEW_LOGGED_OUT, 0), ANIM_DURATION)
			_tween.tween_property(tip, "custom_minimum_size:x", TIP_WIDTH_LOGGED_OUT, ANIM_DURATION)
			tip_label.visible = true
			# InfoPanel 淡入
			_tween.tween_property(info_panel, "modulate:a", 1.0, ANIM_DURATION)
			# ExpandInfoPanel 淡出 + 缩回
			_tween.tween_property(expand_panel, "modulate:a", 0.0, ANIM_DURATION)
			_tween.tween_property(expand_panel, "offset_left", COLLAPSE_OFFSET.x, ANIM_DURATION)
			_tween.tween_property(expand_panel, "offset_top", COLLAPSE_OFFSET.y, ANIM_DURATION)
			_tween.tween_property(expand_panel, "offset_transform_position", Vector2(OFFSET_LOGGED_OUT_X, 0), ANIM_DURATION)
			# 淡出完成后隐藏 VBoxC，防止子控件拦截后续点击
			_tween.chain().tween_callback(func() -> void:
				if _state == State.LOGGED_OUT:
					expand_content.visible = false
			)
			# 遮罩淡出 + 隐藏
			if shader_overlay:
				_tween.tween_property(shader_overlay, "modulate:a", 0.0, ANIM_DURATION)
				_tween.chain().tween_callback(func() -> void:
					if _state == State.LOGGED_OUT and shader_overlay:
						shader_overlay.visible = false
				)
			_play_shortcut_menu_enter()
			_setup_rb_btn_for_expanded(false)
		State.LOGGED_IN:
			_tween.tween_property(info_panel, "offset_transform_position", Vector2.ZERO, ANIM_DURATION)
			_tween.tween_property(info_panel_style, "skew", Vector2(SKEW_LOGGED_IN, 0), ANIM_DURATION)
			_tween.tween_property(tip, "custom_minimum_size:x", TIP_WIDTH_LOGGED_IN, ANIM_DURATION)
			tip_label.visible = false
			# InfoPanel 淡入
			_tween.tween_property(info_panel, "modulate:a", 1.0, ANIM_DURATION)
			# ExpandInfoPanel 淡出 + 缩回
			_tween.tween_property(expand_panel, "modulate:a", 0.0, ANIM_DURATION)
			_tween.tween_property(expand_panel, "offset_left", COLLAPSE_OFFSET.x, ANIM_DURATION)
			_tween.tween_property(expand_panel, "offset_top", COLLAPSE_OFFSET.y, ANIM_DURATION)
			_tween.tween_property(expand_panel, "offset_transform_position", Vector2.ZERO, ANIM_DURATION)

			# 遮罩淡出 + 隐藏
			if shader_overlay:
				_tween.tween_property(shader_overlay, "modulate:a", 0.0, ANIM_DURATION)
				_tween.chain().tween_callback(func() -> void:
					if _state == State.LOGGED_IN and shader_overlay:
						shader_overlay.visible = false
				)
			_play_shortcut_menu_enter()
			_setup_rb_btn_for_expanded(false)
		State.EXPANDED:
			# 立即显示 VBoxC（跟着 modulate.a 一起淡入）
			expand_content.visible = true
			# ExpandInfoPanel 淡入 + 展开
			_tween.tween_property(expand_panel, "modulate:a", 1.0, ANIM_DURATION)
			_tween.tween_property(expand_panel, "offset_left", EXPAND_OFFSET.x, ANIM_DURATION)
			_tween.tween_property(expand_panel, "offset_top", EXPAND_OFFSET.y, ANIM_DURATION)
			_tween.tween_property(expand_panel, "offset_transform_position", Vector2.ZERO, ANIM_DURATION)
			# InfoPanel 淡出
			_tween.tween_property(info_panel, "modulate:a", 0.0, ANIM_DURATION)
			# 遮罩淡入
			if shader_overlay:
				shader_overlay.visible = true
				_tween.tween_property(shader_overlay, "modulate:a", 1.0, ANIM_DURATION)
			_play_shortcut_menu_exit()
			_setup_rb_btn_for_expanded(true)
	_state = s

# ========== ShortCutMenu 联动 ==========

## ShortCutMenu 退场（仅当它当前可见）
func _play_shortcut_menu_exit() -> void:
	if shortcut_menu and shortcut_menu.visible and shortcut_menu.has_method("play_transition_animation"):
		shortcut_menu.play_transition_animation(true)

## ShortCutMenu 入场（仅当它当前不可见）
func _play_shortcut_menu_enter() -> void:
	if shortcut_menu and not shortcut_menu.visible and shortcut_menu.has_method("play_transition_animation"):
		shortcut_menu.play_transition_animation(false)

# ========== RB_Btn 联动 ==========

## 展开/收起时切换 RB_Btn 的显示状态与点击行为
## expanded=true: 保存当前状态，切到 BACK_BTN 图标，点击收起面板
## expanded=false: 恢复 RB_Btn 到展开前的状态
func _setup_rb_btn_for_expanded(expanded: bool) -> void:
	if not rb_btn:
		return
	if expanded:
		_saved_rb_stat = rb_btn._current_stat
		rb_btn.pressed_override = Callable(self, "_collapse")
		rb_btn.switch_display(rb_btn.ShowStat.BACK_BTN)
	else:
		rb_btn.pressed_override = Callable()
		if _saved_rb_stat >= 0:
			rb_btn.switch_display(_saved_rb_stat)
			_saved_rb_stat = -1

# ========== 点击逻辑 ==========

## ExpandInfoPanel 点击（Button.pressed，释放时触发）
## LOGGED_OUT → 展开面板；EXPANDED 状态点击内部不做任何事
func _on_expand_panel_pressed() -> void:
	if _state == State.LOGGED_OUT:
		_login_result = false
		_animate_to_state(State.EXPANDED)

## 遮罩点击：展开状态下点击遮罩 → 收起面板
func _on_shader_overlay_gui_input(event: InputEvent) -> void:
	if _state != State.EXPANDED:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_collapse()

## 收起面板：根据 _login_result 回到 LOGGED_IN 或 LOGGED_OUT
func _collapse() -> void:
	var target_state := State.LOGGED_IN if _login_result else State.LOGGED_OUT
	_animate_to_state(target_state)

# ========== 公共 API ==========

## 登录逻辑调用：标记展开期间的登录结果，收起时据此决定回到哪个状态
func set_login_result(success: bool) -> void:
	_login_result = success

## 强制切到已登录状态（供登录成功后外部直接调用）
func set_logged_in() -> void:
	_login_result = true
	if _state == State.EXPANDED:
		_collapse()
	else:
		_animate_to_state(State.LOGGED_IN)
