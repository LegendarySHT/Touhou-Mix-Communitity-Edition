## 快速测试启动脚本
## 附加到任意节点运行此脚本来快速测试新架构
extends Node

func _ready() -> void:
	# 等待一帧确保所有系统初始化
	await get_tree().process_frame
	
	print("\n" + "=".repeat(70))
	print("🚀 THMIX 新架构快速测试")
	print("=".repeat(70) + "\n")
	
	# 1. 检查核心系统
	print("📋 Step 1: 检查核心系统...")
	check_core_systems()
	
	# 2. 测试数据管理器
	print("\n📊 Step 2: 测试数据管理器...")
	await test_data_manager()
	
	# 3. 测试事件总线
	print("\n📡 Step 3: 测试事件总线...")
	test_event_bus()
	
	# 4. 测试状态管理
	print("\n🎛️ Step 4: 测试状态管理...")
	test_state_manager()
	
	# 5. 测试动画管理
	print("\n🎬 Step 5: 测试动画管理...")
	test_animation_manager()
	
	# 6. 运行完整集成测试（可选）
	print("\n🧪 Step 6: 运行集成测试...")
	# run_integration_tests()
	
	print("\n" + "=".repeat(70))
	print("✅ 快速测试完成!")
	print("=".repeat(70) + "\n")
	
	print("💡 提示:")
	print("  - 查看控制台输出了解详细信息")
	print("  - 查看日志文件: user://logs/game.log")
	print("  - 运行 IntegrationTest 进行完整测试")
	print("  - 查看 MIGRATION_PROGRESS.md 了解迁移进度\n")

## 检查核心系统
func check_core_systems() -> void:
	var main = get_node("/root/Main")
	
	if not main:
		print("  ❌ Main 节点未找到")
		return
	
	var systems = {
		"DataManager": main.get_node_or_null("DataManager"),
		"EventBus": main.get_node_or_null("EventBus"),
		"UIStateManager": main.get_node_or_null("UIStateManager"),
		"AnimationManager": main.get_node_or_null("AnimationManager"),
		"GameplayManager": main.get_node_or_null("GameplayManager"),
		"AudioManager": main.get_node_or_null("AudioManager"),
		"Logger": main.get_node_or_null("Logger"),
		"ConfigLoader": main.get_node_or_null("ConfigLoader")
	}
	
	var all_ok = true
	for system_name in systems.keys():
		if systems[system_name]:
			print("  ✅ %s - OK" % system_name)
		else:
			print("  ❌ %s - 未找到" % system_name)
			all_ok = false
	
	if all_ok:
		print("\n  🎉 所有核心系统已正确初始化!")
	else:
		print("\n  ⚠️ 部分系统未初始化，请检查 Main.gd")

## 测试数据管理器
func test_data_manager() -> void:
	var data_manager = DataManager.instance
	
	if not data_manager:
		print("  ❌ DataManager 实例未找到")
		return
	
	print("  ⏳ 等待数据加载...")
	
	# 等待数据加载（最多等待5秒）
	var wait_time = 0.0
	var max_wait = 5.0
	while data_manager.is_loading and wait_time < max_wait:
		await get_tree().create_timer(0.1).timeout
		wait_time += 0.1
	
	if data_manager.is_loading:
		print("  ⚠️ 数据仍在加载中...")
		return
	
	# 获取统计信息
	var stats = data_manager.get_statistics()
	
	print("  📈 数据统计:")
	print("     - 专辑数: %d" % stats.total_albums)
	print("     - 歌曲数: %d" % stats.total_songs)
	print("     - MIDI数: %d" % stats.total_midis)
	print("     - 待审核: %d" % stats.pending_count)
	print("     - 已批准: %d" % stats.approved_count)
	print("     - 已收录: %d" % stats.included_count)
	
	if stats.total_midis > 0:
		print("\n  ✅ 数据加载成功!")
		
		# 测试数据查询
		var albums = data_manager.get_all_albums()
		if not albums.is_empty():
			var first_album = albums[0]
			print("  📀 示例专辑: %s (ID: %s)" % [first_album.name, first_album.id])
			
			var songs = data_manager.get_songs_by_album(first_album.id)
			print("     └─ 包含 %d 首歌曲" % songs.size())
	else:
		print("\n  ⚠️ 未加载到数据，可能路径配置有误")

## 测试事件总线
func test_event_bus() -> void:
	var event_bus = EventBus.instance
	
	if not event_bus:
		print("  ❌ EventBus 实例未找到")
		return
	
	var signal_received = false
	
	# 测试信号
	var callback = func(msg: String):
		signal_received = true
		print("  📬 收到警告信号: %s" % msg)
	
	event_bus.warning_occurred.connect(callback)
	event_bus.emit_warning("这是一个测试警告")
	
	await get_tree().process_frame
	
	event_bus.warning_occurred.disconnect(callback)
	
	if signal_received:
		print("  ✅ EventBus 工作正常!")
	else:
		print("  ❌ EventBus 信号未接收到")

## 测试状态管理
func test_state_manager() -> void:
	var state_manager = UIStateManager.instance
	
	if not state_manager:
		print("  ❌ UIStateManager 实例未找到")
		return
	
	var initial_state = state_manager.get_current_state()
	print("  📍 当前状态: %s" % state_manager.get_state_name(initial_state))
	
	# 测试状态转换
	print("  🔄 测试状态转换...")
	state_manager.change_state(UIStateManager.UIState.SONG_VIEW)
	print("     └─ 转换到: %s" % state_manager.get_state_name(
		state_manager.get_current_state()))
	
	state_manager.change_state(UIStateManager.UIState.MIDI_VIEW)
	print("     └─ 转换到: %s" % state_manager.get_state_name(
		state_manager.get_current_state()))
	
	# 测试返回
	print("  ⬅️ 测试返回...")
	state_manager.go_back()
	print("     └─ 返回到: %s" % state_manager.get_state_name(
		state_manager.get_current_state()))
	
	# 恢复初始状态
	while state_manager.go_back():
		pass
	
	print("  ✅ UIStateManager 工作正常!")

## 测试动画管理
func test_animation_manager() -> void:
	var anim_manager = AnimationManager.instance
	
	if not anim_manager:
		print("  ❌ AnimationManager 实例未找到")
		return
	
	print("  🎬 创建测试动画...")
	
	# 创建测试节点
	var test_node = Control.new()
	add_child(test_node)
	
	# 测试几种动画
	anim_manager.animate_fade_in(test_node, 0.1)
	await get_tree().create_timer(0.15).timeout
	
	anim_manager.animate_fade_out(test_node, 0.1)
	await get_tree().create_timer(0.15).timeout
	
	var active_count = anim_manager.get_active_tween_count()
	print("  📊 活跃动画数: %d" % active_count)
	
	test_node.queue_free()
	
	print("  ✅ AnimationManager 工作正常!")

## 运行完整集成测试
func run_integration_tests() -> void:
	var test_runner = IntegrationTest.new()
	add_child(test_runner)
	test_runner.run_all_tests()
	await get_tree().create_timer(1.0).timeout
	test_runner.queue_free()
