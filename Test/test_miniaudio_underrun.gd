## miniaudio underrun 测试节点
## 挂载到场景中运行, 用于验证 miniaudio 后端播放复杂 MIDI 时的 underrun 情况
## 同时测量实际音频延迟 (设备延迟 + RingBuffer 延迟)
## 测试 MIDI: Resources/Charts/ffee74125fd2020afe0a987c3cd30d45_竹取飞翔〜Lunatic Princess/ffee74125fd2020afe0a987c3cd30d45.mid
extends Node

## 测试配置
const MIDI_PATH := "res://Resources/Charts/ffee74125fd2020afe0a987c3cd30d45_竹取飞翔〜Lunatic Princess/ffee74125fd2020afe0a987c3cd30d45.mid"
const SOUNDFONT_PATH := "res://Resources/Soundfont/GeneralUser-GS.sf2"
const TEST_DURATION_SEC := 30.0  # 每个缓冲区配置的测试时长
const BUFFER_FRAMES_OPTIONS := [256, 512, 1024]  # 测试不同缓冲区大小

var _player: Node = null
var _test_start_ms: float = 0.0
var _current_test_index: int = 0
var _is_testing: bool = false

## 延迟统计 (每个测试配置独立采集)
var _latency_samples: Array = []  # 每秒采样的延迟值 (ms)
var _latency_min: float = 0.0
var _latency_max: float = 0.0
var _latency_sum: float = 0.0
var _latency_count: int = 0
## 汇总: 每个缓冲区配置的延迟结果 { buffer_frames: {min, max, avg} }
var _latency_summary: Dictionary = {}

func _ready() -> void:
	print("====================================================")
	print("[miniaudio Underrun Test] 开始测试")
	print("====================================================")
	print("MIDI: ", MIDI_PATH)
	print("SoundFont: ", SOUNDFONT_PATH)
	print("测试时长: ", TEST_DURATION_SEC, " 秒/缓冲区配置")
	print("")

	# 创建 MeltySynthPlayer 实例 (通过 .tscn 实例化以确保 C# 类正确加载)
	var player_scene := load("res://CSharp/MeltySynthPlayer.tscn") as PackedScene
	if player_scene == null:
		push_error("[Test] 无法加载 MeltySynthPlayer.tscn")
		get_tree().quit(1)
		return

	_player = player_scene.instantiate()
	add_child(_player)

	# 等待一帧让 _Ready 执行
	await get_tree().process_frame

	# 直接获取 C# 后端节点 (.tscn 中 wrapper 的 meltysynth_player export 未设置)
	# wrapper 的所有方法都转发到这个子节点
	_player = _player.get_node("CSharpBackend")
	if _player == null:
		push_error("[Test] 无法获取 CSharpBackend 子节点")
		get_tree().quit(1)
		return

	print("[Test] 已获取 CSharpBackend 节点: ", _player)

	# 设置 SoundFont (会触发 EnsureAudioInitialized 和合成器创建)
	_player.call("set_soundfont", SOUNDFONT_PATH)
	await get_tree().process_frame

	# 依次测试每种缓冲区大小
	for i in range(BUFFER_FRAMES_OPTIONS.size()):
		_current_test_index = i
		var buffer_frames: int = BUFFER_FRAMES_OPTIONS[i]
		print("\n[Test %d/%d] 缓冲区 = %d 帧 (%.1f ms)" % [
			i + 1, BUFFER_FRAMES_OPTIONS.size(),
			buffer_frames, buffer_frames * 1000.0 / 48000.0
		])
		await _run_single_test(buffer_frames)

	# 输出汇总
	_print_summary()

	# 清理
	_player.call("stop")
	await get_tree().process_frame
	_player.queue_free()
	print("\n[Test] 测试完成, 退出")
	get_tree().quit(0)

func _run_single_test(buffer_frames: int) -> void:
	# 设置 miniaudio 后端
	_player.call("SetAudioBackend", 1)  # 1 = miniaudio
	await get_tree().process_frame

	# 设置缓冲区大小
	_player.call("SetAudioBufferFrames", buffer_frames)
	await get_tree().process_frame

	# 切换后端后重新设置 SoundFont (会触发 EnsureAudioInitialized 和合成器重建)
	_player.call("set_soundfont", SOUNDFONT_PATH)
	await get_tree().process_frame

	# 加载 MIDI
	var loaded: bool = _player.call("load_midi", MIDI_PATH)
	if not loaded:
		push_error("[Test] MIDI 加载失败")
		return
	await get_tree().process_frame

	# 开始播放
	_player.call("play")
	_test_start_ms = Time.get_ticks_msec()
	_is_testing = true

	print("[Test] 播放开始, 等待 ", TEST_DURATION_SEC, " 秒...")

	# 重置延迟统计
	_latency_samples.clear()
	_latency_min = 999999.0
	_latency_max = 0.0
	_latency_sum = 0.0
	_latency_count = 0

	# 监控播放
	var elapsed: float = 0.0
	var last_underrun_check := 0
	var last_latency_sec := -1
	while elapsed < TEST_DURATION_SEC:
		await get_tree().process_frame
		elapsed = (Time.get_ticks_msec() - _test_start_ms) / 1000.0

		var elapsed_int := int(elapsed)

		# 每秒采样一次音频延迟
		if elapsed_int > 0 and elapsed_int != last_latency_sec:
			last_latency_sec = elapsed_int
			var latency_ms: float = _player.call("GetAudioLatencyMs")
			_latency_samples.append(latency_ms)
			if latency_ms < _latency_min:
				_latency_min = latency_ms
			if latency_ms > _latency_max:
				_latency_max = latency_ms
			_latency_sum += latency_ms
			_latency_count += 1
			# 输出延迟分解 (前 5 秒 + 每 5 秒)
			if elapsed_int <= 5 or elapsed_int % 5 == 0:
				var breakdown: Dictionary = _player.call("GetAudioLatencyBreakdown")
				print("[Test] 第 %d 秒 | 总延迟 %.2f ms (设备 %.2f + RingBuffer %.2f) | period=%dx%d" % [
					elapsed_int, latency_ms,
					breakdown.get("device_ms", 0.0),
					breakdown.get("ring_ms", 0.0),
					breakdown.get("actual_period", 0),
					breakdown.get("actual_period_count", 0)
				])

		# 每 5 秒输出一次状态
		if elapsed_int > 0 and elapsed_int % 5 == 0 and elapsed_int != last_underrun_check:
			last_underrun_check = elapsed_int
			print("[Test] 已运行 %d/%d 秒" % [elapsed_int, int(TEST_DURATION_SEC)])

	_is_testing = false

	# 停止播放
	_player.call("stop")
	await get_tree().process_frame

	# 记录此配置的延迟汇总
	var avg_latency: float = 0.0
	if _latency_count > 0:
		avg_latency = _latency_sum / _latency_count
	_latency_summary[buffer_frames] = {
		"min": _latency_min,
		"max": _latency_max,
		"avg": avg_latency,
		"samples": _latency_count
	}
	print("[Test] 测试完成 (buffer=%d) | 延迟 min=%.2f max=%.2f avg=%.2f ms" % [
		buffer_frames, _latency_min, _latency_max, avg_latency
	])

func _print_summary() -> void:
	print("\n====================================================")
	print("[测试汇总]")
	print("====================================================")

	# ---- 延迟汇总 ----
	print("\n--- 音频延迟汇总 (设备延迟 + RingBuffer 延迟) ---")
	print("缓冲区帧数 | 理论延迟 | 实测 min | 实测 max | 实测 avg | 采样数")
	print("-----------|----------|----------|----------|----------|------")
	for bf in BUFFER_FRAMES_OPTIONS:
		var theoretical_ms: float = bf * 1000.0 / 48000.0
		if _latency_summary.has(bf):
			var d: Dictionary = _latency_summary[bf]
			print("%10d | %6.1fms | %6.1fms | %6.1fms | %6.1fms | %d" % [
				bf, theoretical_ms, d["min"], d["max"], d["avg"], d["samples"]
			])
		else:
			print("%10d | %6.1fms |     N/A  |     N/A  |     N/A  | 0" % [bf, theoretical_ms])
	print("")
	print("说明:")
	print("  - 理论延迟 = buffer_frames / 48000 × 1000 (仅缓冲区, 不含设备/RingBuffer)")
	print("  - 实测延迟 = 设备延迟 periodSize×(count-0.5) + RingBuffer 可读帧 / 采样率")
	print("  - WASAPI 独占模式: period 可设到 128 (≈2.67ms), 绕过 Windows 音频引擎")
	print("  - WASAPI 共享模式: period 被强制为 480 (≈10ms), 不可控")
	print("  - RingBuffer 容量 = effectivePeriod × 3, 延迟守护阈值 = 1.0×period")
	print("  - 优化目标: ≤ 10ms (periodSize=128 独占模式: 设备 4ms + RingBuffer 2.67ms)")

	# ---- underrun 汇总 ----
	print("\n--- Underrun 诊断 ---")
	print("注意: underrun 详细次数请查看上方 C# 日志输出")
	print("      日志格式: [MeltySynthPlayer][miniaudio] Underrun #N (read=X/Y, rbFill=Z, rbCap=C, decode=D)")
	print("")
	print("诊断要点:")
	print("  1. rbFill=0 持续出现 → 渲染线程未填充 RingBuffer (严重)")
	print("  2. rbFill < period → RingBuffer 容量不足或生产跟不上消耗")
	print("  3. 偶发 underrun → 边界情况, 可通过增大缓冲区改善")
	print("  4. underrun 数量随缓冲区增大而减少 → 正常行为")
	print("  5. Pre-fill 日志显示预填充是否成功 (目标 50% 容量)")
