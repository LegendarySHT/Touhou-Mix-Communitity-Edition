# DataManager 加载问题修复说明

**修复日期:** 2026年1月21日  
**问题:** DataManager 无法读取从新谱面格式加载的数据

## 问题描述

迁移到新的谱面格式后，运行测试显示：
- ✅ FileSystemManager 成功扫描了 396 个谱面
- ❌ DataManager 加载了 0 个 MIDI 数据

## 根本原因

在 `DataManager._load_midis_thread()` 中使用了 `await` 语句，但该方法在**线程上下文**中运行，线程中**不能使用 await**！这导致：

1. 线程执行到 `await` 时挂起
2. 异步等待永远无法完成
3. 数据加载被阻塞，导致 0 MIDI 被加载

此外，Main.gd 中的 `_load_midi_data()` 没有等待 FileSystemManager 的资源扫描完成，可能导致数据不可用。

## 修复方案

### 1. **修改 DataManager._load_midis_thread()** 

**文件:** [Core/DataManager.gd](../Core/DataManager.gd) 第 56-87 行

**变更：**
- ❌ 移除 `await FileSystemManager.instance.initialization_complete`
- ✅ 改用轮询等待：使用 `OS.delay_msec(100)` 和 `while` 循环
- ✅ 添加超时机制（最多等待 10 秒）
- ✅ 添加进度日志（每 100 个谱面打印一次）
- ✅ 添加空检查（处理谱面索引为空的情况）

```gdscript
# 旧代码（有问题）：
await FileSystemManager.instance.initialization_complete

# 新代码（正确）：
var timeout = 0
while not FileSystemManager.instance.is_initialized and timeout < 100:
    OS.delay_msec(100)
    timeout += 1
```

### 2. **修改 DataManager._process_new_format_chart()**

**文件:** [Core/DataManager.gd](../Core/DataManager.gd) 第 105-130 行

**变更：**
- ✅ 添加更详细的错误日志
- ✅ 添加 folder_name 参数检查
- ✅ 添加验证步骤确保 MIDI 对象正确创建
- ✅ 验证 midi.id 是否被正确设置

### 3. **修改 Main.gd 初始化流程**

**文件:** [Main.gd](../Main.gd) 第 165-174 行

**变更：**
- ✅ 在 `_load_midi_data()` 中添加等待机制
- ✅ 确保在 FileSystemManager 资源准备完毕后再启动 DataManager 加载
- ✅ 添加详细的日志记录

```gdscript
# 旧代码：
func _load_midi_data() -> void:
    logger.info("Starting MIDI data load...", "Main")
    data_manager.load_all_midis_async()

# 新代码：
func _load_midi_data() -> void:
    logger.info("Starting MIDI data load...", "Main")
    
    # 等待 FileSystemManager 资源准备完毕
    if filesystem_manager and not filesystem_manager.is_initialized:
        logger.info("Waiting for FileSystemManager to complete resource scanning...", "Main")
        await filesystem_manager.resources_ready
    
    logger.info("FileSystemManager resources ready, starting MIDI load...", "Main")
    data_manager.load_all_midis_async()
```

## 修复验证

修复后的初始化流程：

```
Main._initialize_core_systems()
  ├─ FileSystemManager.initialize_directory_structure()
  │  ├─ 创建目录结构
  │  └─ 后台线程复制默认资源和扫描
  │
  └─ FileSystemManager 资源扫描完成
     └─ 发送 resources_ready 信号
        └─ Main._load_midi_data()
           └─ DataManager.load_all_midis_async()
              └─ 线程轮询等待 FileSystemManager.is_initialized
                 └─ 获取谱面索引并加载数据
```

## 关键改进

| 方面 | 修复前 | 修复后 |
|------|--------|--------|
| 线程上下文 | ❌ 使用 await | ✅ 轮询等待 |
| 同步机制 | ❌ 无 | ✅ 资源准备完全 |
| 错误处理 | ❌ 最少 | ✅ 详细日志 |
| 超时管理 | ❌ 无 | ✅ 10 秒超时 |
| 进度报告 | ❌ 无 | ✅ 每 100 个谱面 |

## 测试方法

运行迁移测试脚本验证修复：

```bash
# 在 Godot 编辑器中
# 1. 添加 Utilities/ChartMigrationTest.gd 到场景
# 2. 运行游戏
# 3. 查看控制台输出，应该显示：
#    ✓ FileSystemManager initialized: true
#    ✓ Charts indexed: 396+
#    ✓ Data loaded (MIDIs): 396+
```

## 预期结果

修复后：
- ✅ FileSystemManager 扫描 396 个谱面
- ✅ DataManager 加载 396 个 MIDI 数据
- ✅ 所有专辑、歌曲、MIDI 统计数据正确
- ✅ 无数据加载错误日志

## 相关文件修改

1. [Core/DataManager.gd](../Core/DataManager.gd)
   - `_load_midis_thread()` - 移除 await，添加轮询
   - `_process_new_format_chart()` - 增强错误处理

2. [Main.gd](../Main.gd)
   - `_load_midi_data()` - 添加初始化等待

3. [Utilities/ChartMigrationTest.gd](../Utilities/ChartMigrationTest.gd)
   - 改进测试输出，显示更多调试信息

4. [Utilities/QuickDebug.gd](../Utilities/QuickDebug.gd) - 新文件
   - 快速调试脚本，用于检查加载流程

## 教训

✅ **线程安全** - 避免在线程中使用 await  
✅ **同步机制** - 使用轮询或信号等待条件  
✅ **初始化顺序** - 确保依赖项先初始化  
✅ **日志记录** - 添加详细日志便于调试  
✅ **错误处理** - 提前检查和验证数据  

---

**修复完成！** ✅

系统现在应该能够正确加载所有 396+ 个谱面数据。

