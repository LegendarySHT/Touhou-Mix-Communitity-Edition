## 接口：定义MIDI后端应实现的public API
class_name MidiPlaybackInterface

extends Node

## ===================== 基本控制 =====================

## 加载MIDI文件
func load_midi(_file_path: String) -> bool:
	push_error("load_midi not implemented")
	return false

## 播放
func play() -> void:
	push_error("play not implemented")

## 暂停
func pause() -> void:
	push_error("pause not implemented")

## 恢复播放
func resume() -> void:
	push_error("resume not implemented")

## 停止
func stop() -> void:
	push_error("stop not implemented")

## 跳转到指定位置（毫秒）
func seek(_position_ms: float) -> void:
	push_error("seek not implemented")

## ===================== 配置相关 =====================

## 设置音源文件
func set_soundfont(_soundfont_path: String) -> bool:
	push_error("set_soundfont not implemented")
	return false

## 设置主音量（dB）
func set_volume_db(_volume_db: float) -> void:
	push_error("set_volume_db not implemented")

## 获取主音量（dB）
func get_volume_db() -> float:
	push_error("get_volume_db not implemented")
	return 0.0

## 设置特定轨道通道的音量（线性值，0.0-1.0）
func set_track_channel_volume(_track_index: int, _channel: int, _volume_linear: float) -> void:
	push_error("set_track_channel_volume not implemented")

## 获取特定轨道通道的音量
func get_track_channel_volume(_track_index: int, _channel: int) -> float:
	push_error("get_track_channel_volume not implemented")
	return 1.0

## 设置轨道通道的乐器
func set_track_channel_instrument(_track_index: int, _channel: int, _bank: int, _program: int) -> void:
	push_error("set_track_channel_instrument not implemented")

## 获取轨道通道的乐器
func get_track_channel_instrument(_track_index: int, _channel: int) -> Dictionary:
	push_error("get_track_channel_instrument not implemented")
	return {"bank": 0, "program": 0}

## ===================== 状态查询 =====================

## 获取当前播放位置（毫秒）
func get_position_ms() -> float:
	push_error("get_position_ms not implemented")
	return 0.0

## 获取音频回调已渲染的原始播放位置（毫秒）
## 与 get_position_ms() 不同，此时钟不做设备延迟补偿
func get_raw_position_ms() -> float:
	push_error("get_raw_position_ms not implemented")
	return get_position_ms()

## 获取总时长（毫秒）
func get_duration_ms() -> float:
	push_error("get_duration_ms not implemented")
	return 0.0

## 检查是否正在播放
func is_playing() -> bool:
	push_error("is_playing not implemented")
	return false

## ===================== 高级功能 =====================

## 设置静音状态
func set_track_channel_mute(_track_index: int, _channel: int, _muted: bool) -> void:
	push_error("set_track_channel_mute not implemented")

## 手动触发Note On
func trigger_note_on(_pitch: int, _velocity: int, _channel: int, _track_index: int = 0) -> void:
	push_error("trigger_note_on not implemented")

## 批量触发Note On（演奏模式一次判定单次跨语言调用）
func trigger_notes_on(_events: Array) -> void:
	push_error("trigger_notes_on not implemented")

## 预热手动音符触发路径（无声音；可选传入 (track,channel) 乐器表）
func warmup_manual_path(_track_channel_instruments: Dictionary = {}) -> void:
	push_error("warmup_manual_path not implemented")

## 手动触发Note Off
func trigger_note_off(_pitch: int, _velocity: int, _channel: int, _track_index: int = 0) -> void:
	push_error("trigger_note_off not implemented")

## 获取可用乐器列表
func get_presets_list() -> Array:
	push_error("get_presets_list not implemented")
	return []

## 获取乐器名称
func get_preset_name(_program: int, _bank: int = 0) -> String:
	push_error("get_preset_name not implemented")
	return ""

## 设置手动控制的note列表（格式：{channel: {pitch: true}}）
func set_manually_controlled_notes(_manually_controlled: Dictionary) -> void:
	push_error("set_manually_controlled_notes not implemented")

## ===================== 信号 =====================

@warning_ignore("unused_signal")
signal finished
@warning_ignore("unused_signal")
signal soundfont_changed(soundfont_path: String)
