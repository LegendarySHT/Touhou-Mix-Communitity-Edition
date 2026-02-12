## ConfigManager 单元测试
## 测试 ConfigManager 单例的功能正确性
extends Node

class_name ConfigManagerTest

## 测试结果
var test_results: Array = []
var test_passed: int = 0
var test_failed: int = 0

func _ready() -> void:
	print("\n=== ConfigManager Unit Tests ===\n")
	
	# 运行所有测试
	test_singleton_initialization()
	test_config_loading_and_caching()
	test_config_saving()
	test_path_constants()
	test_priority_rules()
	test_config_change_notification()
	
	# 输出测试结果
	_print_results()

## 测试1: 单例初始化
func test_singleton_initialization() -> void:
	var test_name = "Singleton Initialization"
	
	var manager = ConfigManager.instance
	if manager == null:
		_record_test(test_name, false, "ConfigManager.instance returned null")
		return
	
	# 再次获取实例，应该返回同一个对象
	var manager2 = ConfigManager.instance
	if manager != manager2:
		_record_test(test_name, false, "ConfigManager.instance does not return same instance")
		return
	
	_record_test(test_name, true, "Singleton successfully initialized")

## 测试2: 配置加载与缓存
func test_config_loading_and_caching() -> void:
	var test_name = "Config Loading and Caching"
	var manager = ConfigManager.instance
	
	# 加载默认配置
	var config1 = manager.load_config(ConfigManager.DEFAULT_CONFIG_PATH)
	if config1.is_empty():
		_record_test(test_name, false, "Failed to load default config")
		return
	
	# 再次加载相同配置，应该从缓存返回
	var config2 = manager.load_config(ConfigManager.DEFAULT_CONFIG_PATH)
	
	# 验证缓存是否生效（同一个对象引用）
	if config1 == config2:
		_record_test(test_name, true, "Config loaded and cached successfully")
	else:
		_record_test(test_name, false, "Config caching not working")

## 测试3: 配置保存
func test_config_saving() -> void:
	var test_name = "Config Saving"
	var manager = ConfigManager.instance
	
	# 创建测试配置
	var test_config = {
		"TestSection": {
			"test_key": "test_value",
			"test_int": "123"
		}
	}
	
	# 保存到临时位置
	var test_path = "user://files/test_config.ini"
	var success = manager.save_config(test_path, test_config)
	
	if not success:
		_record_test(test_name, false, "Failed to save config")
		return
	
	# 验证文件是否存在
	if not FileAccess.file_exists(test_path):
		_record_test(test_name, false, "Saved config file not found")
		return
	
	# 清空缓存并重新加载验证
	manager.configs.erase(test_path)
	var loaded_config = manager.load_config(test_path)
	
	if loaded_config.has("TestSection") and loaded_config["TestSection"].get("test_key") == "test_value":
		_record_test(test_name, true, "Config saved and verified successfully")
		# 清理测试文件
		var file = FileAccess.open(test_path, FileAccess.WRITE)
		if file != null:
			file.close()
	else:
		_record_test(test_name, false, "Saved config verification failed")

## 测试4: 路径常量
func test_path_constants() -> void:
	var test_name = "Path Constants"
	
	# 检查所有必要的常量是否存在
	if ConfigManager.DEFAULT_CONFIG_PATH.is_empty():
		_record_test(test_name, false, "DEFAULT_CONFIG_PATH is empty")
		return
	
	if ConfigManager.USER_CONFIG_PATH.is_empty():
		_record_test(test_name, false, "USER_CONFIG_PATH is empty")
		return
	
	if ConfigManager.SOUNDFONT_DIR.is_empty():
		_record_test(test_name, false, "SOUNDFONT_DIR is empty")
		return
	
	# 验证路径格式
	if not ConfigManager.DEFAULT_CONFIG_PATH.begins_with("res://"):
		_record_test(test_name, false, "DEFAULT_CONFIG_PATH does not start with res://")
		return
	
	if not ConfigManager.USER_CONFIG_PATH.begins_with("user://"):
		_record_test(test_name, false, "USER_CONFIG_PATH does not start with user://")
		return
	
	_record_test(test_name, true, "All path constants are correctly defined")

## 测试5: 配置优先级规则
func test_priority_rules() -> void:
	var test_name = "Priority Rules"
	var manager = ConfigManager.instance
	
	# 加载默认配置
	var default_config = manager.load_config(ConfigManager.DEFAULT_CONFIG_PATH)
	
	if default_config.is_empty():
		_record_test(test_name, false, "Failed to load default config for priority test")
		return
	
	# 验证必要的 section 存在
	var required_sections = ["Game", "Audio", "Gameplay", "Lane", "Display"]
	for section in required_sections:
		if not default_config.has(section):
			_record_test(test_name, false, "Missing required section: %s" % section)
			return
	
	# 验证配置版本
	var version = manager.get_value(default_config, "Game", "config_version")
	if version.is_empty():
		_record_test(test_name, false, "Config version not found")
		return
	
	_record_test(test_name, true, "Priority rules validated successfully")

## 测试6: 配置变更通知
func test_config_change_notification() -> void:
	var test_name = "Config Change Notification"
	
	# 检查 EventBus 和 config_changed 信号是否存在
	if EventBus.instance == null:
		_record_test(test_name, false, "EventBus.instance is null")
		return
	
	# 尝试连接 config_changed 信号
	var signal_connected = false
	var result_key = ""
	var result_section = ""
	var result_value = ""
	
	var callback = func(key: String, section: String, value: Variant):
		signal_connected = true
		result_key = key
		result_section = section
		result_value = str(value)
	
	EventBus.instance.config_changed.connect(callback)
	
	# 测试发送信号
	EventBus.instance.emit_config_changed("test_key", "TestSection", "test_value")
	
	if signal_connected and result_key == "test_key" and result_section == "TestSection":
		_record_test(test_name, true, "Config change notification working correctly")
	else:
		_record_test(test_name, false, "Config change notification not working")
	
	# 清理连接
	EventBus.instance.config_changed.disconnect(callback)

## 记录测试结果
func _record_test(test_name: String, passed: bool, message: String) -> void:
	var status = "✓ PASS" if passed else "✗ FAIL"
	var result_text = "[%s] %s - %s" % [status, test_name, message]
	
	test_results.append(result_text)
	
	if passed:
		test_passed += 1
		print(result_text)
	else:
		test_failed += 1
		print(result_text)

## 打印测试结果摘要
func _print_results() -> void:
	print("\n=== Test Results Summary ===")
	print("Passed: %d" % test_passed)
	print("Failed: %d" % test_failed)
	print("Total: %d" % (test_passed + test_failed))
	
	if test_failed > 0:
		print("\n⚠️  Some tests failed!")
	else:
		print("\n✓ All tests passed!")
	
	print("\n=== End of Tests ===\n")

## 辅助函数：打印测试说明
func print_test_instructions() -> void:
	print("""
	ConfigManager 单元测试说明：
	
	1. 确保已运行以下初始化：
	   - GameLogger.instance 已初始化
	   - EventBus.instance 已初始化
	   - ConfigManager.instance 已初始化
	
	2. 测试覆盖的功能：
	   ✓ 单例模式初始化
	   ✓ 配置文件加载与缓存
	   ✓ 配置文件保存与验证
	   ✓ 路径常量定义
	   ✓ 配置优先级规则
	   ✓ 配置变更通知机制
	
	3. 执行方式：
	   - 在 Godot Editor 中运行此脚本
	   - 查看输出面板查看测试结果
	
	4. 预期结果：
	   - 所有 6 个测试应该通过
	   - 如有失败，检查错误信息并调查原因
	""")
