## 谱面格式迁移验证脚本
## 用于验证新格式谱面加载是否正常工作
extends Node

var test_results = {
	"filesystem_init": false,
	"charts_scanned": 0,
	"charts_indexed": 0,
	"data_loaded": 0,
	"errors": []
}

func _ready():
	print("\n=== Chart Format Migration Verification ===\n")
	
	# 等待一帧，确保所有单例初始化
	await get_tree().process_frame
	
	test_filesystem_manager()
	await get_tree().process_frame
	
	test_data_manager()
	await get_tree().process_frame
	
	print_results()

func test_filesystem_manager():
	print("[Test] FileSystemManager Verification")
	print("=".repeat(50))
	
	var fs_mgr = FileSystemManager.instance
	if fs_mgr == null:
		test_results["errors"].append("FileSystemManager instance not found")
		print("[FAIL] FileSystemManager instance not found!")
		return
	
	print("[PASS] FileSystemManager instance found")
	test_results["filesystem_init"] = true
	
	# 检查目录
	print("\n[Test] Directory Structure:")
	print("  Charts Dir: %s" % fs_mgr.get_charts_directory())
	
	# 检查索引
	var charts_index = fs_mgr.get_charts_index()
	test_results["charts_indexed"] = charts_index.size()
	
	print("\n[Test] Charts Index:")
	print("  Total charts indexed: %d" % charts_index.size())
	
	if charts_index.is_empty():
		test_results["errors"].append("No charts found in index")
		print("[WARN] No charts in index - may indicate initialization issue")
		return
	
	# 验证第一个谱面
	var first_chart_id = charts_index.keys()[0]
	var first_metadata = charts_index[first_chart_id]
	
	print("\n[Test] First Chart Sample:")
	print("  Folder: %s" % first_metadata.get("folder_name", "N/A"))
	print("  ID: %s" % first_metadata.get("id", "N/A"))
	print("  JSON Path: %s" % first_metadata.get("json_path", "N/A"))
	print("  Complete: %s" % first_metadata.get("is_complete", false))
	print("  Path: %s" % first_metadata.get("path", "N/A"))
	
	# 检查 data 字段
	if first_metadata.has("data"):
		var data_keys = first_metadata.get("data", {}).keys()
		print("  Data Keys: %s" % str(data_keys))
	else:
		print("  Data Keys: N/A")
	
	# 检查必需字段
	var required_fields = ["id", "data", "path", "folder_name"]
	var missing_fields = []
	
	for field in required_fields:
		if not first_metadata.has(field):
			missing_fields.append(field)
	
	if missing_fields.is_empty():
		print("[PASS] All required fields present in metadata")
	else:
		print("[WARN] Missing fields: %s" % missing_fields)
		test_results["errors"].append("Missing fields in metadata: %s" % missing_fields)

func test_data_manager():
	print("\n[Test] DataManager Verification")
	print("=".repeat(50))
	
	var data_mgr = DataManager.instance
	if data_mgr == null:
		test_results["errors"].append("DataManager instance not found")
		print("[FAIL] DataManager instance not found!")
		return
	
	print("[PASS] DataManager instance found")
	
	# 等待数据加载完成
	print("\n[Test] Waiting for data to load...")
	await data_mgr.data_loaded
	
	print("[PASS] Data loaded signal received")
	
	# 检查统计信息
	var stats = data_mgr.get_statistics()
	test_results["data_loaded"] = stats["total_midis"]
	
	print("\n[Test] Data Statistics:")
	print("  Total Albums: %d" % stats["total_albums"])
	print("  Total Songs: %d" % stats["total_songs"])
	print("  Total MIDIs: %d" % stats["total_midis"])
	print("  Approved: %d" % stats["approved_count"])
	print("  Pending: %d" % stats["pending_count"])
	print("  Included: %d" % stats["included_count"])
	print("  Dead: %d" % stats["dead_count"])
	
	if stats["total_midis"] == 0:
		test_results["errors"].append("No MIDI data loaded")
		print("[FAIL] No MIDI data loaded!")
		return
	
	print("[PASS] MIDI data loaded successfully")
	
	# 检查第一个MIDI
	var all_midis = data_mgr.get_all_midis()
	if not all_midis.is_empty():
		var first_midi = all_midis[0]
		print("\n[Test] First MIDI Sample:")
		print("  ID: %s" % first_midi.id)
		print("  Name: %s" % first_midi.name)
		print("  Status: %s" % first_midi.status)
		print("[PASS] MIDI object created successfully")
	else:
		test_results["errors"].append("Cannot get MIDI data")
		print("[FAIL] Cannot retrieve MIDI data")

func print_results():
	print("\n" + "=".repeat(50))
	print("VERIFICATION RESULTS")
	print("=".repeat(50))
	
	print("\n✓ Tests Passed:")
	print("  • FileSystemManager initialized: %s" % test_results["filesystem_init"])
	print("  • Charts indexed: %d" % test_results["charts_indexed"])
	print("  • Data loaded (MIDIs): %d" % test_results["data_loaded"])
	
	if test_results["errors"].is_empty():
		print("\n✓ ALL TESTS PASSED!")
		print("\nChart format migration successful:")
		print("  - FileSystemManager correctly loaded %d charts" % test_results["charts_indexed"])
		print("  - DataManager successfully processed %d MIDIs" % test_results["data_loaded"])
		print("  - New format working as expected")
	else:
		print("\n✗ ERRORS FOUND:")
		for error in test_results["errors"]:
			print("  • %s" % error)
		print("\nPlease check the log files for more details.")
	
	print("\n" + "=".repeat(50))
	print("End of Verification")
	print("=".repeat(50) + "\n")
