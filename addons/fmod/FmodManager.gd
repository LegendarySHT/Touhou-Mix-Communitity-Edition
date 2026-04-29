@tool
extends Node

var performance_display: PerformancesDisplay

const _LOW_LEVEL_AUDIO_METHODS := [
	"create_sound",
	"create_stream",
	"create_dsp",
	"create_dsp_by_type",
	"create_channel_group",
	"play_sound"
]

const _MELTY_AUDIO_OUTPUT_KEY := "melty_audio_output_backend"

func _ready():
	process_mode = PROCESS_MODE_ALWAYS
	performance_display = PerformancesDisplay.new()
	add_child(performance_display)

func _exit_tree() -> void:
	remove_child(performance_display)
	performance_display.free()

func _process(delta):
	FmodServer.update()
	
func _notification(what):
	FmodServer.notification(what)

func has_runtime_fmod() -> bool:
	return ClassDB.class_exists(&"FmodServer")

func has_low_level_audio_api() -> bool:
	if not has_runtime_fmod():
		return false

	for method_name in _LOW_LEVEL_AUDIO_METHODS:
		if ClassDB.class_has_method(&"FmodServer", method_name):
			return true
	return false

func has_studio_event_api() -> bool:
	if not has_runtime_fmod():
		return false
	return ClassDB.class_has_method(&"FmodServer", &"create_event_instance_with_guid")

func get_melty_audio_output_backend() -> String:
	var config_manager = ConfigManager.instance
	if config_manager == null:
		return "auto"

	var backend = str(config_manager.get_value("Gameplay", _MELTY_AUDIO_OUTPUT_KEY, "auto")).to_lower().strip_edges()
	if backend != "auto" and backend != "godot" and backend != "fmod":
		return "auto"
	return backend

func should_use_fmod_audio_output() -> bool:
	var backend = get_melty_audio_output_backend()
	if backend == "godot":
		return false

	if backend == "fmod":
		return has_low_level_audio_api()

	return has_low_level_audio_api()

func has_melty_audio_output_preference() -> bool:
	return get_melty_audio_output_backend() != "godot"

func get_melty_audio_buffer_length_seconds() -> float:
	var config_manager = ConfigManager.instance
	if config_manager == null:
		return 0.1

	var preset = config_manager.get_int("Gameplay", "melty_audio_preset", 1)
	match preset:
		0:
			return 0.01
		1:
			return 0.025
		2:
			return 0.1
		3:
			return 0.025
		_:
			return 0.025
