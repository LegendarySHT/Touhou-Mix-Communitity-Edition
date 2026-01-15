## 音频管理器
## 负责音乐播放、音效等音频相关的功能
extends Node

class_name AudioManager

## 单例实例
static var instance: AudioManager

## 背景音乐播放器
@onready var bgm_player: AudioStreamPlayer = AudioStreamPlayer.new()

## 音效播放器池
var sfx_players: Array[AudioStreamPlayer] = []

## 是否启用音频
var audio_enabled: bool = true

## 主音量（0-100）
var master_volume: float = 80.0

## 音乐音量（0-100）
var music_volume: float = 80.0

## 音效音量（0-100）
var sfx_volume: float = 80.0

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
	add_to_group("singleton")
	
	# 初始化背景音乐播放器
	add_child(bgm_player)
	bgm_player.bus = "Music"
	
	# 初始化音效播放器池（预创建10个）
	for i in range(10):
		var player = AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		sfx_players.append(player)

## 播放背景音乐
func play_bgm(audio_stream: AudioStream, loop: bool = true) -> void:
	if not audio_enabled or audio_stream == null:
		return
	
	bgm_player.stream = audio_stream
	bgm_player.bus_layout_override = "Music"
	bgm_player.play()
	
	if not loop:
		bgm_player.finished.connect(func() -> void:
			bgm_player.stop()
		)

## 停止背景音乐
func stop_bgm(fade_duration: float = 0.0) -> void:
	if fade_duration > 0:
		var tween = create_tween()
		tween.tween_property(bgm_player, "volume_db", -80, fade_duration)
		tween.tween_callback(bgm_player.stop)
	else:
		bgm_player.stop()

## 暂停背景音乐
func pause_bgm() -> void:
	bgm_player.stream_paused = true

## 恢复背景音乐
func resume_bgm() -> void:
	bgm_player.stream_paused = false

## 播放音效
func play_sfx(audio_stream: AudioStream, volume: float = 1.0) -> void:
	if not audio_enabled or audio_stream == null:
		return
	
	# 查找空闲的音效播放器
	var player: AudioStreamPlayer = null
	for sfx_player in sfx_players:
		if not sfx_player.playing:
			player = sfx_player
			break
	
	# 如果所有播放器都在使用，创建新的
	if player == null:
		player = AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		sfx_players.append(player)
	
	player.stream = audio_stream
	player.volume_db = linear_to_db(volume)
	master_volume = clamp(volume, 0.0, 100.0)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), 
							 master_volume == 0)

## 设置主音量
func set_master_volume(volume: float) -> void:
	master_volume = clamp(volume, 0.0, 100.0)
	var db = linear_to_db(master_volume / 100.0)
	var bus_idx = AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, db)

## 设置音乐音量
func set_music_volume(volume: float) -> void:
	music_volume = clamp(volume, 0.0, 100.0)
	var db = linear_to_db(music_volume / 100.0)
	var bus_idx = AudioServer.get_bus_index("Music")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, db)
	else:
		# 如果 Music 总线不存在，使用 Master 总线
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)

## 设置音效音量
func set_sfx_volume(volume: float) -> void:
	sfx_volume = clamp(volume, 0.0, 100.0)
	var db = linear_to_db(sfx_volume / 100.0)
	var bus_idx = AudioServer.get_bus_index("SFX")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, db)
	else:
		# 如果 SFX 总线不存在，使用 Master 总线
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)

## 启用/禁用音频
func set_audio_enabled(enabled: bool) -> void:
	audio_enabled = enabled

## 获取背景音乐播放位置（秒）
func get_bgm_position() -> float:
	if bgm_player.playing:
		return bgm_player.get_playback_position()
	return 0.0

## 获取背景音乐时长（秒）
func get_bgm_duration() -> float:
	if bgm_player.stream:
		return bgm_player.stream.get_length()
	return 0.0

## 获取背景音乐是否在播放
func is_bgm_playing() -> bool:
	return bgm_player.playing
