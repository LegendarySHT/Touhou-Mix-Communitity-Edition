## 方案2快速验证脚本
## 使用方法：将此代码临时添加到任何 _ready() 函数中进行测试
## 功能：打印所有相关的接口调用日志

extends Node

## 快速验证所有方案2的接口是否可用
func _verify_solution2_implementation() -> void:
	print("\n========== 方案2实现验证 ==========\n")
	
	# 验证 MidiData 的 track_channel_mute_state 字段
	var test_midi = MidiData.new()
	if test_midi.has_meta("track_channel_mute_state") or "track_channel_mute_state" in test_midi:
		print("✅ MidiData.track_channel_mute_state 字段存在")
	else:
		print("❌ MidiData.track_channel_mute_state 字段不存在")
	
	# 验证 MidiData 的新方法
	var methods_to_check = [
		"set_track_channel_mute",
		"get_track_channel_mute",
		"clear_all_mutes"
	]
	
	for method_name in methods_to_check:
		if test_midi.has_method(method_name):
			print("✅ MidiData.%s() 方法存在" % method_name)
		else:
			print("❌ MidiData.%s() 方法不存在" % method_name)
	
	# 验证 MidiPlaybackManager 的新方法
	var midi_mgr = MidiPlaybackManager.instance
	if midi_mgr != null:
		var midi_mgr_methods = [
			"set_track_channel_mute",
			"is_track_channel_muted",
			"_stop_channel_notes",
			"unmute_all_channels"
		]
		
		for method_name in midi_mgr_methods:
			if midi_mgr.has_method(method_name):
				print("✅ MidiPlaybackManager.%s() 方法存在" % method_name)
			else:
				print("❌ MidiPlaybackManager.%s() 方法不存在" % method_name)
		
		# 验证新信号
		if midi_mgr.has_signal("channel_mute_state_changed"):
			print("✅ MidiPlaybackManager.channel_mute_state_changed 信号存在")
		else:
			print("❌ MidiPlaybackManager.channel_mute_state_changed 信号不存在")
	else:
		print("❌ MidiPlaybackManager 实例不存在")
	
	print("\n========== 验证完成 ==========\n")

## 测试 set_track_channel_mute() 的实时效果
func test_real_time_mute() -> void:
	print("\n========== 实时静音测试开始 ==========\n")
	
	var midi_mgr = MidiPlaybackManager.instance
	if midi_mgr == null or midi_mgr.current_midi_data == null:
		print("❌ 未加载MIDI，无法测试")
		return
	
	print("当前MIDI: %s" % midi_mgr.current_midi_data.name)
	print("当前状态: %s" % ("播放中" if midi_mgr.is_playing else "停止"))
	
	# 测试静音
	print("\n--- 测试 Channel 0 静音 ---")
	midi_mgr.set_track_channel_mute(0, 0, true)
	
	# 检查状态
	var is_muted = midi_mgr.is_track_channel_muted(0, 0)
	print("Channel 0 静音状态: %s" % ("已静音" if is_muted else "未静音"))
	
	# 测试取消静音
	print("\n--- 测试 Channel 0 取消静音 ---")
	midi_mgr.set_track_channel_mute(0, 0, false)
	
	is_muted = midi_mgr.is_track_channel_muted(0, 0)
	print("Channel 0 静音状态: %s" % ("已静音" if is_muted else "未静音"))
	
	print("\n========== 实时静音测试完成 ==========\n")

## 打印当前的 mute 状态
func print_mute_state() -> void:
	var midi_mgr = MidiPlaybackManager.instance
	if midi_mgr == null or midi_mgr.current_midi_data == null:
		print("未加载MIDI")
		return
	
	var mute_state = midi_mgr.current_midi_data.track_channel_mute_state
	
	if mute_state.is_empty():
		print("没有静音的轨道")
		return
	
	print("\n========== 当前静音状态 ==========")
	for track_idx in mute_state.keys():
		for channel in mute_state[track_idx].keys():
			var is_muted = mute_state[track_idx][channel]
			print("Track %d Channel %d: %s" % [track_idx, channel, "已静音" if is_muted else "未静音"])
	print("================================\n")

## 连接信号以监听静音事件
func connect_mute_signal_monitoring() -> void:
	var midi_mgr = MidiPlaybackManager.instance
	if midi_mgr == null:
		return
	
	if not midi_mgr.channel_mute_state_changed.is_connected(Callable(self, "_on_channel_mute_changed")):
		midi_mgr.channel_mute_state_changed.connect(Callable(self, "_on_channel_mute_changed"))
		print("✅ 已连接 channel_mute_state_changed 信号监听")

func _on_channel_mute_changed(track_index: int, channel: int, muted: bool) -> void:
	print("[信号] Track %d Channel %d: %s" % [track_index, channel, "已静音" if muted else "已取消静音"])
