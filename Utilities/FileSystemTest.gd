## 文件系统管理器测试脚本
## 用于验证 FileSystemManager 的功能
extends Node

func _ready():
	print("=== FileSystem Manager Test ===")
	
	# 等待一帧，确保所有单例都已初始化
	await get_tree().process_frame
	
	# 测试文件系统管理器
	test_filesystem_manager()

func test_filesystem_manager():
	print("\n[Test] Testing FileSystemManager...")
	
	var fs_mgr = FileSystemManager.instance
	if fs_mgr == null:
		print("[FAIL] FileSystemManager instance not found!")
		return
	
	print("[PASS] FileSystemManager instance found")
	
	# 测试目录路径
	print("\n[Test] Directory Paths:")
	print("  User Path: %s" % ProjectSettings.globalize_path("user://"))
	print("  Charts: %s" % fs_mgr.get_charts_directory())
	print("  Skins: %s" % fs_mgr.SKINS_DIR)
	print("  Soundfont: %s" % fs_mgr.SOUNDFONT_DIR)
	print("  Background: %s" % fs_mgr.BACKGROUND_DIR)
	print("  Logs: %s" % fs_mgr.get_logs_directory())
	print("  Settings: %s" % fs_mgr.get_settings_directory())
	
	# 连接信号
	fs_mgr.resource_scan_completed.connect(_on_resource_scan_completed)
	fs_mgr.resources_ready.connect(_on_resources_ready)
	fs_mgr.resource_error.connect(_on_resource_error)
	
	print("\n[Test] Signals connected, waiting for resource scan...")

func _on_resource_scan_completed(resource_type: String, count: int):
	print("[Signal] Resource scan completed: %s - %d items" % [resource_type, count])

func _on_resources_ready():
	print("[Signal] All resources ready!")
	
	var fs_mgr = FileSystemManager.instance
	
	# 输出资源索引
	print("\n[Test] Resource Indexes:")
	print("  Charts: %d" % fs_mgr.get_charts_index().size())
	print("  Skins: %d" % fs_mgr.get_skins_index().size())
	print("  Soundfonts: %d" % fs_mgr.get_soundfonts_index().size())
	print("  Backgrounds: %d" % fs_mgr.get_backgrounds_index().size())
	
	# 列出前几个谱面
	var charts = fs_mgr.get_charts_index()
	if charts.size() > 0:
		print("\n[Test] Sample Charts (first 3):")
		var count = 0
		for chart_id in charts.keys():
			if count >= 3:
				break
			var metadata = charts[chart_id]
			print("  - %s: complete=%s" % [chart_id, metadata.get("is_complete", false)])
			count += 1
	
	print("\n=== FileSystem Manager Test Complete ===")

func _on_resource_error(error_message: String):
	print("[ERROR] %s" % error_message)
