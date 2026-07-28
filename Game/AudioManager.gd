## 音频管理器
## 负责人声播放（BGM/SFX/MIDI 转发已移除，MIDI 由 MidiPlaybackManager 直接管理）
extends Node

class_name AudioManager

## 单例实例
static var instance: AudioManager

## 人声播放器
var vocal_player: AudioStreamPlayer

## 人声播放状态标志
var vocal_is_playing: bool = false

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
	add_to_group("singleton")

	# 初始化人声播放器
	vocal_player = AudioStreamPlayer.new()
	vocal_player.bus = "Music"
	add_child(vocal_player)

## ========== 人声相关方法 ==========

## 播放人声音频，支持毫秒偏移
func play_vocal(audio_stream: AudioStream, offset_ms: float = 0.0) -> void:
	if audio_stream == null or vocal_player == null:
		return

	vocal_player.stream = audio_stream
	vocal_player.play(offset_ms / 1000.0)  # 转换为秒
	vocal_is_playing = true

## 停止人声播放
func stop_vocal() -> void:
	if vocal_player != null:
		vocal_player.stop()
		vocal_is_playing = false

## 通过设置stream_paused来暂停/恢复人声
func set_vocal_playing(is_playing: bool) -> void:
	if vocal_player != null:
		vocal_player.stream_paused = not is_playing
		vocal_is_playing = is_playing

## 获取人声播放进度（毫秒）
func get_vocal_position() -> float:
	if vocal_player != null and vocal_player.playing:
		return vocal_player.get_playback_position() * 1000.0  # 转换为毫秒
	return 0.0

## 跳转人声播放进度（毫秒）
func seek_vocal(position_ms: float) -> void:
	if vocal_player != null and vocal_player.stream != null:
		var position_sec = clamp(position_ms / 1000.0, 0.0, vocal_player.stream.get_length())
		vocal_player.seek(position_sec)

## 设置人声音量（dB）
func set_vocal_volume_db(volume_db: float) -> void:
	if vocal_player != null:
		vocal_player.volume_db = volume_db

## 检查人声是否正在播放
func is_vocal_playing() -> bool:
	return vocal_is_playing and vocal_player != null and vocal_player.playing
