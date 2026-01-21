## 快速调试脚本
## 用于快速检查和显示加载过程中的关键信息
extends Node

func _ready():
	print("\n=== Quick Debug Check ===\n")
	
	await get_tree().process_frame
	
	# 检查 FileSystemManager
	var fs = FileSystemManager.instance
	if fs:
		print("[FileSystemManager]")
		print("  Initialized: %s" % fs.is_initialized)
		var charts = fs.get_charts_index()
		print("  Charts indexed: %d" % charts.size())
		
		if not charts.is_empty():
			var first_key = charts.keys()[0]
			var first_meta = charts[first_key]
			print("\n  First Chart:")
			print("    Key: %s" % first_key)
			print("    ID: %s" % first_meta.get("id", "MISSING"))
			print("    Data: %s" % ("Present" if first_meta.has("data") else "MISSING"))
			if first_meta.has("data"):
				print("    Data Type: %s" % typeof(first_meta["data"]))
				print("    Data Keys: %s" % str(first_meta["data"].keys()))
				if first_meta["data"].has("_id"):
					print("    Data._id: %s" % first_meta["data"]["_id"])
	else:
		print("[ERROR] FileSystemManager not found")
	
	# 检查 DataManager
	await get_tree().process_frame
	var dm = DataManager.instance
	if dm:
		print("\n[DataManager]")
		print("  Is Loading: %s" % dm.is_loading)
		
		# 连接信号
		if not dm.data_loaded.is_connected(_on_data_loaded):
			dm.data_loaded.connect(_on_data_loaded)
		
		print("  Waiting for data to load...")
	else:
		print("[ERROR] DataManager not found")

func _on_data_loaded():
	var dm = DataManager.instance
	var stats = dm.get_statistics()
	
	print("\n[Data Loaded]")
	print("  Total MIDIs: %d" % stats["total_midis"])
	print("  Total Albums: %d" % stats["total_albums"])
	print("  Total Songs: %d" % stats["total_songs"])
	
	if stats["total_midis"] > 0:
		var all_midis = dm.get_all_midis()
		var first = all_midis[0]
		print("\n  First MIDI:")
		print("    ID: %s" % first.id)
		print("    Name: %s" % first.name)
		print("    Status: %s" % first.status)
	else:
		print("\n  [WARN] No MIDIs loaded!")
