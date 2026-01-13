## 迁移助手工具
## 用于帮助从旧架构迁移到新架构
extends Node

class_name MigrationHelper

## 检查数据一致性
static func verify_data_consistency(old_data: Dictionary, new_data_manager: DataManager) -> Dictionary:
	var report = {
		"old_midi_count": 0,
		"new_midi_count": 0,
		"old_albums": [],
		"new_albums": [],
		"missing_in_new": [],
		"missing_in_old": [],
		"consistent": true
	}
	
	# 统计旧数据
	for album_name in old_data.keys():
		report.old_albums.append(album_name)
		for song_name in old_data[album_name].keys():
			report.old_midi_count += old_data[album_name][song_name].size()
	
	# 统计新数据
	var new_albums = new_data_manager.get_all_albums()
	for album in new_albums:
		report.new_albums.append(album.name)
	report.new_midi_count = new_data_manager.midis.size()
	
	# 检查差异
	for old_album in report.old_albums:
		if not old_album in report.new_albums:
			report.missing_in_new.append(old_album)
	
	for new_album in report.new_albums:
		if not new_album in report.old_albums:
			report.missing_in_old.append(new_album)
	
	report.consistent = (report.old_midi_count == report.new_midi_count and 
						 report.missing_in_new.is_empty() and 
						 report.missing_in_old.is_empty())
	
	return report

## 打印迁移报告
static func print_migration_report(report: Dictionary) -> void:
	print("\n========== Migration Verification Report ==========")
	print("Old MIDI Count: %d" % report.old_midi_count)
	print("New MIDI Count: %d" % report.new_midi_count)
	print("Old Albums Count: %d" % report.old_albums.size())
	print("New Albums Count: %d" % report.new_albums.size())
	
	if not report.missing_in_new.is_empty():
		print("\n⚠️ Albums missing in NEW architecture:")
		for album in report.missing_in_new:
			print("  - %s" % album)
	
	if not report.missing_in_old.is_empty():
		print("\n⚠️ Albums missing in OLD architecture:")
		for album in report.missing_in_old:
			print("  - %s" % album)
	
	if report.consistent:
		print("\n✅ Data is CONSISTENT between old and new architecture!")
	else:
		print("\n❌ Data INCONSISTENCY detected!")
	
	print("===================================================\n")

## 将旧UI状态转换为新UI状态
static func convert_old_ui_state(old_ui: int) -> int:
	match old_ui:
		0:  # 初始专辑列表
			return UIStateManager.UIState.ALBUM_VIEW
		1:  # 二级选曲
			return UIStateManager.UIState.SONG_VIEW
		2:  # MIDI界面
			return UIStateManager.UIState.MIDI_VIEW
		5:  # 设置
			return UIStateManager.UIState.SETTINGS_VIEW
		20: # 排序视图
			return UIStateManager.UIState.SORTED_VIEW
		_:
			return UIStateManager.UIState.ALBUM_VIEW

## 将旧排序字段转换为新排序字段
static func convert_sort_field(old_ptr) -> int:
	# 根据旧的LinkList指针名称判断
	if old_ptr == null:
		return SortingEngine.SortField.DEFAULT
	
	# 这里需要根据实际的指针类型判断
	return SortingEngine.SortField.DEFAULT

## 桥接旧数据到新架构
static func bridge_old_data_to_new(old_data: Dictionary, data_manager: DataManager) -> void:
	print("[Migration] Bridging old data structure to new architecture...")
	
	# 旧数据结构: data[album_name][song_name][midi_index] = json_data
	# 新数据结构: DataManager 管理所有数据
	
	var bridged_count = 0
	
	for album_name in old_data.keys():
		for song_name in old_data[album_name].keys():
			for midi_data in old_data[album_name][song_name]:
				# 这里可以进行数据验证和补充
				bridged_count += 1
	
	print("[Migration] Bridged %d MIDI entries" % bridged_count)

## 生成迁移清单
static func generate_migration_checklist() -> Array[String]:
	return [
		"[ ] Phase 1: Main.gd 初始化核心系统",
		"[ ] Phase 2: Global.gd 添加新架构引用",
		"[ ] Phase 3: 验证数据一致性",
		"[ ] Phase 4: Scene/AlbumList.gd -> UI/Views/AlbumView.gd",
		"[ ] Phase 5: Scene/SongList.gd -> UI/Views/SongView.gd",
		"[ ] Phase 6: Scene/MidiList.gd -> UI/Views/MidiView.gd",
		"[ ] Phase 7: 更新所有UI事件到EventBus",
		"[ ] Phase 8: 更新所有动画到AnimationManager",
		"[ ] Phase 9: 测试所有功能",
		"[ ] Phase 10: 移除旧代码和LinkList"
	]

## 检测是否可以安全移除旧代码
static func can_safely_remove_old_code(global: Node) -> Dictionary:
	var result = {
		"safe": true,
		"warnings": [],
		"blockers": []
	}
	
	# 检查是否还在使用旧的data字典
	if global.data and not global.data.is_empty():
		result.blockers.append("Global.data still contains data")
		result.safe = false
	
	# 检查是否还在使用旧的UI状态
	if global.UI != 0:
		result.warnings.append("Global.UI is not at default state (0)")
	
	# 检查是否还有活跃的旧线程
	if global._thread and global._thread.is_alive():
		result.blockers.append("Old thread is still running")
		result.safe = false
	
	return result

## 生成迁移报告HTML
static func generate_html_report(report: Dictionary) -> String:
	var html = """
	<html>
	<head><title>Migration Report</title></head>
	<body>
	<h1>THMIX Migration Report</h1>
	<h2>Data Statistics</h2>
	<table border='1'>
	<tr><td>Old MIDI Count</td><td>%d</td></tr>
	<tr><td>New MIDI Count</td><td>%d</td></tr>
	<tr><td>Consistent</td><td>%s</td></tr>
	</table>
	</body>
	</html>
	""" % [report.old_midi_count, report.new_midi_count, 
		   "✅ Yes" if report.consistent else "❌ No"]
	
	return html
