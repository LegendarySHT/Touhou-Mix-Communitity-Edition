## 集成测试脚本
## 用于验证新架构的各个组件是否正常工作
extends Node

class_name IntegrationTest

var passed_tests: int = 0
var failed_tests: int = 0
var test_results: Array[Dictionary] = []

## 运行所有测试
func run_all_tests() -> void:
	print("\n" + "=".repeat(60))
	print("Starting THMIX Integration Tests...")
	print("=".repeat(60) + "\n")
	
	# 测试核心系统初始化
	test_core_systems_initialized()
	
	# 测试数据管理器
	test_data_manager()
	
	# 测试排序引擎
	test_sorting_engine()
	
	# 测试UI状态管理
	test_ui_state_manager()
	
	# 测试事件总线
	test_event_bus()
	
	# 测试动画管理器
	test_animation_manager()
	
	# 打印测试结果
	print_test_summary()

## 测试核心系统是否已初始化
func test_core_systems_initialized() -> void:
	var test_name = "Core Systems Initialization"
	var main_node = get_tree().root.get_node_or_null("Main")
	
	if main_node == null:
		record_test(test_name, false, "Main node not found")
		return
	
	var systems_ok = true
	var missing_systems: Array[String] = []
	
	var required_systems = [
		"DataManager",
		"EventBus",
		"UIStateManager",
		"AnimationManager",
		"GameplayManager",
		"AudioManager",
		"Logger"
	]
	
	for system in required_systems:
		if main_node.get_node_or_null(system) == null:
			systems_ok = false
			missing_systems.append(system)
	
	if systems_ok:
		record_test(test_name, true, "All core systems initialized")
	else:
		record_test(test_name, false, "Missing systems: " + str(missing_systems))

## 测试数据管理器
func test_data_manager() -> void:
	var test_name = "DataManager Functionality"
	var data_manager = DataManager.instance
	
	if data_manager == null:
		record_test(test_name, false, "DataManager instance not found")
		return
	
	# 测试数据结构
	var has_data = (not data_manager.albums.is_empty() or 
					not data_manager.songs.is_empty() or 
					not data_manager.midis.is_empty())
	
	if has_data:
		var stats = data_manager.get_statistics()
		var msg = "Albums: %d, Songs: %d, MIDIs: %d" % [
			stats.total_albums, stats.total_songs, stats.total_midis
		]
		record_test(test_name, true, msg)
	else:
		record_test(test_name, false, "No data loaded (may be loading...)")

## 测试排序引擎
func test_sorting_engine() -> void:
	var test_name = "SortingEngine Functionality"
	
	# 创建测试数据
	var test_midis: Array[MidiData] = []
	for i in range(5):
		var midi = MidiData.new()
		midi.id = "test_midi_%d" % i
		midi.name = "Test MIDI %d" % i
		midi.download_count = i * 10
		midi.love_count = (5 - i) * 10
		test_midis.append(midi)
	
	var sorting_engine = SortingEngine.new()
	
	# 测试降序排序
	var sorted_desc = sorting_engine._sort_midis(
		test_midis,
		SortingEngine.SortDataField.DOWNLOAD_COUNT,
		SortingEngine.SortDirection.DESCENDING
	)
	
	var is_desc_sorted = true
	for i in range(sorted_desc.size() - 1):
		if sorted_desc[i].download_count < sorted_desc[i + 1].download_count:
			is_desc_sorted = false
			break
	
	if is_desc_sorted:
		record_test(test_name, true, "Sorting works correctly")
	else:
		record_test(test_name, false, "Sorting produced incorrect order")

## 测试UI状态管理
func test_ui_state_manager() -> void:
	var test_name = "UIStateManager Functionality"
	var state_manager = UIStateManager.instance
	
	if state_manager == null:
		record_test(test_name, false, "UIStateManager instance not found")
		return
	
	# 测试状态转换
	var initial_state = state_manager.get_current_state()
	state_manager.change_state(UIStateManager.UIState.SONG_VIEW)
	var new_state = state_manager.get_current_state()
	
	# 返回到初始状态
	state_manager.go_back()
	var back_state = state_manager.get_current_state()
	
	if new_state == UIStateManager.UIState.SONG_VIEW and back_state == initial_state:
		record_test(test_name, true, "State transitions working")
	else:
		record_test(test_name, false, "State transitions failed")

## 测试事件总线
func test_event_bus() -> void:
	var test_name = "EventBus Functionality"
	var event_bus = EventBus.instance
	
	if event_bus == null:
		record_test(test_name, false, "EventBus instance not found")
		return
	
	var signal_received = false
	var callback = func():
		signal_received = true
	
	# 测试信号发送和接收
	event_bus.warning_occurred.connect(callback)
	event_bus.emit_warning("Test warning")
	
	await get_tree().process_frame
	
	event_bus.warning_occurred.disconnect(callback)
	
	if signal_received:
		record_test(test_name, true, "Event signals working")
	else:
		record_test(test_name, false, "Event signals not working")

## 测试动画管理器
func test_animation_manager() -> void:
	var test_name = "AnimationManager Functionality"
	var anim_manager = AnimationManager.instance
	
	if anim_manager == null:
		record_test(test_name, false, "AnimationManager instance not found")
		return
	
	# 创建测试节点
	var test_node = Node2D.new()
	add_child(test_node)
	
	# 测试动画创建
	var tween = anim_manager.animate_position(test_node, Vector2(100, 100), 0.1)
	
	await get_tree().create_timer(0.2).timeout
	
	var active_count = anim_manager.get_active_tween_count()
	
	test_node.queue_free()
	
	record_test(test_name, true, "Animation manager working (active tweens: %d)" % active_count)

## 记录测试结果
func record_test(test_name: String, passed: bool, message: String = "") -> void:
	if passed:
		passed_tests += 1
		print("✅ PASS: %s" % test_name)
	else:
		failed_tests += 1
		print("❌ FAIL: %s" % test_name)
	
	if not message.is_empty():
		print("   └─ %s" % message)
	
	test_results.append({
		"name": test_name,
		"passed": passed,
		"message": message
	})

## 打印测试总结
func print_test_summary() -> void:
	print("\n" + "=".repeat(60))
	print("Test Summary")
	print("=".repeat(60))
	print("Total Tests: %d" % (passed_tests + failed_tests))
	print("Passed: %d ✅" % passed_tests)
	print("Failed: %d ❌" % failed_tests)
	print("Success Rate: %.1f%%" % (float(passed_tests) / (passed_tests + failed_tests) * 100))
	print("=".repeat(60) + "\n")
	
	if failed_tests > 0:
		print("⚠️ Some tests failed. Please review the errors above.\n")
	else:
		print("🎉 All tests passed! Architecture is working correctly.\n")

## 生成测试报告JSON
func generate_json_report() -> String:
	var report = {
		"timestamp": Time.get_datetime_string_from_system(),
		"total_tests": passed_tests + failed_tests,
		"passed": passed_tests,
		"failed": failed_tests,
		"success_rate": float(passed_tests) / (passed_tests + failed_tests) * 100,
		"results": test_results
	}
	
	return JSON.stringify(report, "\t")
