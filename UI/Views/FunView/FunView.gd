extends Control

const VIDEO_PATH := "res://Resources/Video/Never Gonna Give You Up.mp4"
const VIDEO_BASE_PATH := "res://Resources/Video/Never Gonna Give You Up"
const INTRO_BLACK_HOLD_SECONDS := 2.0

const ENTER_BUTTON_COLOR_A := Color(0.98, 0.41, 0.26, 1.0)
const ENTER_BUTTON_COLOR_B := Color(0.18, 0.74, 0.99, 1.0)
const ENTER_FONT_COLOR_A := Color(0.08, 0.07, 0.07, 1.0)
const ENTER_FONT_COLOR_B := Color(1.0, 0.98, 0.94, 1.0)

@onready var background_panel: ColorRect = $ColorRect
@onready var black_overlay: ColorRect = $BlackOverlay
@onready var video_player: VideoStreamPlayer = $VideoStreamPlayer
@onready var enter_button: Button = $EnterButton
@onready var back_button: Button = $BackButton

var _intro_tween: Tween
var _enter_color_tween: Tween
var _back_spin_tween: Tween
var _is_exiting: bool = false
var _video_started: bool = false

func _ready() -> void:
	enter_button.visible = false
	enter_button.disabled = false
	back_button.visible = false
	_setup_back_button_style()
	video_player.visible = false
	video_player.stop()

	black_overlay.visible = true
	black_overlay.modulate = Color(1, 1, 1, 1)

	enter_button.pressed.connect(_on_enter_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)

	_play_intro_sequence()

func _play_intro_sequence() -> void:
	await get_tree().create_timer(INTRO_BLACK_HOLD_SECONDS).timeout
	if _is_exiting or not is_inside_tree():
		return

	_intro_tween = create_tween()
	_intro_tween.tween_property(black_overlay, "modulate:a", 0.0, 0.5)
	await _intro_tween.finished
	if _is_exiting or not is_inside_tree():
		return

	black_overlay.visible = false

	await get_tree().create_timer(1.0).timeout
	if _is_exiting or not is_inside_tree():
		return

	enter_button.visible = true
	_start_enter_button_color_cycle()

func _start_enter_button_color_cycle() -> void:
	_set_enter_color_mix(0.0)
	_kill_tween(_enter_color_tween)
	_enter_color_tween = create_tween().set_loops()
	_enter_color_tween.tween_method(Callable(self, "_set_enter_color_mix"), 0.0, 1.0, 0.6)
	_enter_color_tween.tween_method(Callable(self, "_set_enter_color_mix"), 1.0, 0.0, 0.6)

func _set_enter_color_mix(weight: float) -> void:
	var button_color := ENTER_BUTTON_COLOR_A.lerp(ENTER_BUTTON_COLOR_B, weight)
	var font_color := ENTER_FONT_COLOR_A.lerp(ENTER_FONT_COLOR_B, weight)
	enter_button.modulate = button_color
	enter_button.add_theme_color_override("font_color", font_color)
	enter_button.add_theme_color_override("font_hover_color", font_color)
	enter_button.add_theme_color_override("font_pressed_color", font_color)

func _on_enter_button_pressed() -> void:
	if _video_started or _is_exiting:
		return
	_video_started = true

	enter_button.disabled = true
	enter_button.visible = false
	_kill_tween(_enter_color_tween)

	video_player.visible = true
	video_player.play()

	await get_tree().create_timer(1.0).timeout
	if _is_exiting or not is_inside_tree():
		return

	back_button.visible = true
	_start_back_button_spin()


func _start_back_button_spin() -> void:
	_kill_tween(_back_spin_tween)
	back_button.rotation = 0.0
	_back_spin_tween = create_tween().set_loops()
	_back_spin_tween.tween_property(back_button, "rotation", TAU, 1.2).from(0.0)

func _setup_back_button_style() -> void:
	back_button.flat = false
	back_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	back_button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	back_button.add_theme_color_override("font_pressed_color", Color(1, 0.96, 0.75, 1))
	back_button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	back_button.add_theme_constant_override("outline_size", 4)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.93, 0.21, 0.21, 0.95)
	normal_style.corner_radius_top_left = 20
	normal_style.corner_radius_top_right = 20
	normal_style.corner_radius_bottom_right = 20
	normal_style.corner_radius_bottom_left = 20
	normal_style.border_width_left = 3
	normal_style.border_width_top = 3
	normal_style.border_width_right = 3
	normal_style.border_width_bottom = 3
	normal_style.border_color = Color(1, 0.92, 0.66, 1)
	normal_style.shadow_size = 10
	normal_style.shadow_color = Color(0, 0, 0, 0.35)

	var hover_style := normal_style.duplicate()
	hover_style.bg_color = Color(1.0, 0.33, 0.24, 1)

	var pressed_style := normal_style.duplicate()
	pressed_style.bg_color = Color(0.72, 0.1, 0.1, 1)

	back_button.add_theme_stylebox_override("normal", normal_style)
	back_button.add_theme_stylebox_override("hover", hover_style)
	back_button.add_theme_stylebox_override("focus", hover_style)
	back_button.add_theme_stylebox_override("pressed", pressed_style)

func _on_back_button_pressed() -> void:
	if _is_exiting:
		return
	_is_exiting = true

	video_player.stop()
	video_player.visible = false

	_stop_all_tweens()
	visible = false
	queue_free()

func _stop_all_tweens() -> void:
	_kill_tween(_intro_tween)
	_kill_tween(_enter_color_tween)
	_kill_tween(_back_spin_tween)

func _kill_tween(tween: Tween) -> void:
	if tween and is_instance_valid(tween):
		tween.kill()

func _exit_tree() -> void:
	_stop_all_tweens()
	if is_instance_valid(video_player):
		video_player.stop()
