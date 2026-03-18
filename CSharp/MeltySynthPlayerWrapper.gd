## MeltySynthPlayer 的 GDScript 包装
## 将 C# 对象包装为 GDScript MidiPlaybackInterface 接口
extends MidiPlaybackInterface
class_name MeltySynthPlayerWrapper

@export var meltysynth_player: Node

func _ready() -> void:
	# 尽管 meltysynth_player 是 C# 对象，我们可以通过 call() 和方法名称与之交互
	pass

## 加载 MIDI 文件
func load_midi(file_path: String) -> bool:
	if meltysynth_player == null:
		return false
	return meltysynth_player.call("load_midi", file_path)

## 播放
func play() -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("play")

## 暂停
func pause() -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("pause")

## 恢复
func resume() -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("resume")

## 停止
func stop() -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("stop")

## 寻找位置（毫秒）
func seek(position_ms: float) -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("seek", position_ms)

## 获取当前位置（毫秒）
func get_position_ms() -> float:
	if meltysynth_player == null:
		return 0.0
	return meltysynth_player.call("get_position_ms")

## 获取总长度（毫秒）
func get_duration_ms() -> float:
	if meltysynth_player == null:
		return 0.0
	return meltysynth_player.call("get_duration_ms")

## 设置音量（dB）
func set_volume_db(db: float) -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("set_volume_db", db)

## 设置音频总线
func set_bus(bus_name: String) -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("set_bus", bus_name)

## 设置音色库
func set_soundfont(path: String) -> bool:
	if meltysynth_player == null:
		return false
	meltysynth_player.call("set_soundfont", path)
	return true

## 设置轨道/通道的音量
func set_track_channel_volume(track_index: int, channel: int, volume: float) -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("set_track_channel_volume", track_index, channel, volume)

## 设置轨道/通道的静音状态
func set_track_channel_mute(track_index: int, channel: int, muted: bool) -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("set_track_channel_mute", track_index, channel, muted)

## 设置轨道/通道的乐器
func set_track_channel_instrument(track_index: int, channel: int, bank: int, program: int) -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("set_track_channel_instrument", track_index, channel, bank, program)

## 获取音色预设列表
func get_presets_list() -> Array:
	if meltysynth_player == null:
		return []
	var result = meltysynth_player.call("get_presets_list")
	if result is PackedStringArray:
		return Array(result)
	return result if result is Array else []

## 获取指定索引的音色预设名称
func get_preset_name(program: int, bank: int = 0) -> String:
	if meltysynth_player == null:
		return ""
	return meltysynth_player.call("get_preset_name", program, bank)

## 触发按键（Note On）
func trigger_note_on(pitch: int, velocity: int, channel: int) -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("trigger_note_on", pitch, velocity, channel)

## 释放按键（Note Off）
func trigger_note_off(pitch: int, velocity: int, channel: int) -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("trigger_note_off", pitch, velocity, channel)

## 获取轨道/通道的音量
func get_track_channel_volume(track_index: int, channel: int) -> float:
	if meltysynth_player == null:
		return 1.0
	var result = meltysynth_player.call("get_track_channel_volume", track_index, channel)
	return result if result is float else 1.0

## 获取轨道/通道的乐器信息（C# 后端不维护此信息，返回空值让上层处理）
func get_track_channel_instrument(track_index: int, channel: int) -> Dictionary:
	# MeltySynth C# 后端不维护 MIDI 文件的乐器映射
	# 这个信息由 MidiPlaybackManager 维护
	# 此处返回空字典会导致上层使用默认值或 MIDI 原始配置
	return {}

## 获取当前位置（tick 单位）
func get_position_tick() -> float:
	if meltysynth_player == null:
		return 0.0
	var result = meltysynth_player.call("get_position_tick")
	return result if result is float else 0.0

## 检查是否正在播放
func is_playing() -> bool:
	if meltysynth_player == null:
		return false
	var result = meltysynth_player.call("is_playing")
	return result if result is bool else false

## 设置手动控制的 note 列表
func set_manually_controlled_notes(manually_controlled: Dictionary) -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("set_manually_controlled_notes", manually_controlled)

## 设置循环播放
func set_loop(enabled: bool) -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("set_loop", enabled)

## 获取循环播放状态
func get_loop() -> bool:
	if meltysynth_player == null:
		return false
	var result = meltysynth_player.call("get_loop")
	return result if result is bool else false

## 设置是否启用系统时钟模式
func set_use_system_stopwatch(enabled: bool) -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("set_use_system_stopwatch", enabled)

## 获取系统时钟模式状态
func get_use_system_stopwatch() -> bool:
	if meltysynth_player == null:
		return false
	var result = meltysynth_player.call("get_use_system_stopwatch")
	return result if result is bool else false

## 跳转到指定位置（毫秒）
func seek_ms(position_ms: float) -> void:
	if meltysynth_player == null:
		return
	meltysynth_player.call("seek_ms", position_ms)
