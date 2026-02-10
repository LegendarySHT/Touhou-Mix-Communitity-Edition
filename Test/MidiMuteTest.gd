## MIDI 静音功能测试脚本
## 验证 MidiPlayer 的 set_track_channel_mute() 实现
extends Node

var midi_player: MidiPlayer
var midi_playback_manager: MidiPlaybackManager

func _ready() -> void:
	print("[MidiMuteTest] Starting MIDI Mute functionality test...")
	
	midi_playback_manager = MidiPlaybackManager.instance
	if midi_playback_manager == null:
		push_error("[MidiMuteTest] MidiPlaybackManager not initialized")
		return
	
	# 创建一个测试 MidiPlayer 实例
	midi_player = MidiPlayer.new()
	add_child(midi_player)
	
	# 检查接口方法是否存在
	if midi_player.has_method("set_track_channel_mute"):
		print("[MidiMuteTest] ✓ MidiPlayer.set_track_channel_mute() method exists")
	else:
		push_error("[MidiMuteTest] ✗ MidiPlayer.set_track_channel_mute() method NOT found")
	
	# 检查 MidiPlaybackInterface 中是否定义了接口
	var interface = MidiPlaybackInterface.new()
	if interface.has_method("set_track_channel_mute"):
		print("[MidiMuteTest] ✓ MidiPlaybackInterface.set_track_channel_mute() interface exists")
	else:
		push_error("[MidiMuteTest] ✗ MidiPlaybackInterface.set_track_channel_mute() interface NOT found")
	
	# 测试调用（不加载 MIDI，只测试方法存在）
	print("[MidiMuteTest] Testing method signature...")
	try_call_mute_method()
	
	print("[MidiMuteTest] Test completed!")

## 尝试调用静音方法
func try_call_mute_method() -> void:
	# 由于没有实际加载 MIDI，这会输出警告，但证明方法存在
	print("[MidiMuteTest] Attempting to call set_track_channel_mute(0, 0, true)...")
	midi_player.set_track_channel_mute(0, 0, true)
	print("[MidiMuteTest] Method call completed")
