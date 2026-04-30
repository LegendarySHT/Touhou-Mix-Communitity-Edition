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

const _MELTY_AUDIO_OUTPUT_KEY := "melty_audio_output_backend"  # 保留以兼容旧配置

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
	return "fmod"  # 始终使用FMOD后端

func should_use_fmod_audio_output() -> bool:
	return has_runtime_fmod()  # 始终使用FMOD后端

func has_melty_audio_output_preference() -> bool:
	return true  # 始终使用FMOD后端

func get_melty_audio_buffer_length_seconds() -> float:
	return 0.025
