## 配置管理系统重构验证清单

**重构日期**: 2026-02-12  
**重构范围**: 配置管理系统单例化、配置变更通知机制、热重载支持  
**联系人**: GitHub Copilot

### ✅ 编译期检查

- [ ] 打开 Godot Editor，加载项目
- [ ] 检查脚本编译是否成功（Output 面版无错误）
- [ ] ConfigManager.gd 编译无误
- [ ] ConfigLoader.gd 代理正常工作
- [ ] EventBus 新增 config_changed 信号
- [ ] Main.gd 初始化流程无误

---

### ✅ 单元测试

运行 `Test/ConfigManagerTest.gd`：

```
在编辑器中运行此脚本，查看输出面板
```

**预期结果**：
- [ ] ✓ Singleton Initialization - PASS
- [ ] ✓ Config Loading and Caching - PASS
- [ ] ✓ Config Saving - PASS
- [ ] ✓ Path Constants - PASS
- [ ] ✓ Priority Rules - PASS
- [ ] ✓ Config Change Notification - PASS

---

### ✅ 功能测验证

#### 1. 配置加载

**执行步骤**：
1. 启动游戏
2. 在 Output 面板观察日志

**验证项**：
- [ ] ConfigManager.instance 初始化成功
- [ ] 默认配置文件加载完成
- [ ] 配置项被正确读取（lane_count, master_volume 等）
- [ ] 日志显示"Configuration loaded successfully"

**预期错误**（如果出现则需修复）：
- ❌ "ConfigManager.instance returned null"
- ❌ "Failed to load config.ini"
- ❌ "Config key not found"

---

#### 2. 单例缓存验证

**执行步骤**：
1. 启动游戏
2. 多次读取配置
3. 开启性能监视器（Editor > Window > Toggle Developer Console）

**验证项**：
- [ ] 同一配置文件只被解析一次（查看日志输出次数）
- [ ] 多个 Manager 可以共享配置（无需重复解析）
- [ ] 内存占用不会因为重复加载而增加

**测试代码**（在 Main.gd _ready() 中临时添加）：
```gdscript
print("=== Cache Test ===")
var mgr = ConfigManager.instance
var config1 = mgr.load_config(ConfigManager.DEFAULT_CONFIG_PATH)
var config2 = mgr.load_config(ConfigManager.DEFAULT_CONFIG_PATH)
print("Same instance: %s" % (config1 == config2))
print("===")
```

---

#### 3. 配置变更通知

**执行步骤**：
1. 启动游戏
2. 进入 SettingView
3. 修改任意配置（如音量）
4. 保存并关闭

**验证项**：
- [ ] SettingView 保存配置无错误
- [ ] 其他 Manager 接收到配置变更信号
- [ ] AudioManager 自动调整音量
- [ ] 日志显示"config_changed"信号发送

**预期行为**：
- 修改主音量 → 游戏音量立即改变
- 修改 MIDI 后端 → 播放manager 重新初始化
- 修改键盘数量 → NotesRenderer 判定窗口更新

---

#### 4. 热重载测试

**执行步骤**：
1. 启动游戏，进入 PlayView
2. 打开 user://files/settings.ini（用文本编辑器）
3. 修改 master_volume 值
4. 在游戏中调用重新加载（或修改其他配置项）
5. 观察变化

**验证项**：
- [ ] 配置变更被正确读取
- [ ] Manager 自动适应新值
- [ ] 不需要重启游戏即可生效

---

#### 5. 向后兼容性

**执行步骤**：
1. 检查项目中是否还有使用 ConfigLoader.new() 的代码
2. 验证这些代码是否仍能正常工作

**验证项**：
- [ ] 所有 ConfigLoader 弃用警告已显示
- [ ] 代码功能仍然正常
- [ ] 未来可以安全地移除 ConfigLoader

**检查命令**（在编辑器搜索窗口中）：
```
ConfigLoader.new
```

应该返回空结果或只有向后兼容代码。

---

#### 6. SettingView 集成测试

**执行步骤**：
1. 加载游戏
2. 进入 SettingView（按左上角按钮进入设置）
3. 修改多个配置项：
   - Audio → Master Volume = 50
   - Audio → Music Volume = 70
   - Gameplay → MIDI Backend = MeltySynth
   - Lane → Lane Count = 8
4. 退出 SettingView

**验证项**：
- [ ] 配置成功保存到 user://files/settings.ini
- [ ] EventBus 发送 config_changed 信号
- [ ] 相关 Manager 自动应用新配置
- [ ] 日志显示所有变更

**验证文件**：
检查 user://files/settings.ini 中修改的值：
```ini
[Audio]
master_volume = 50
music_volume = 70

[Gameplay]
midi_backend = meltysynth

[Lane]
lane_count = 8
```

---

#### 7. TrackView JSON 保存测试

**执行步骤**：
1. 进入 TrackView（选择一首 MIDI）
2. 修改 MIDI 配置（调整音量等）
3. 保存并退出

**验证项**：
- [ ] ConfigManager 用于保存 JSON 文件
- [ ] user://files/Charts/{chart_id}/info.json 被更新
- [ ] JSON 内容包含运行时配置

---

#### 8. 键位生成器配置变更

**执行步骤**：
1. 启动游戏
2. 进入 PlayView
3. 修改配置文件中的 Lane → lane_count = 8
4. 重新加载或重新进入游戏

**验证项**：
- [ ] NotesRenderer 收到配置变更通知
- [ ] 键位生成器使用新的 lane_count
- [ ] 谱面正确显示 8 条轨道（如果适用）

---

### 🔴 问题排查

如果出现问题，按以下顺序检查：

1. **配置文件找不到**
   - [ ] 检查 ConfigManager.DEFAULT_CONFIG_PATH 是否正确
   - [ ] 检查 res://Resources/Config/config.ini 是否存在
   - [ ] 检查文件权限

2. **单例初始化失败**
   - [ ] ConfigManager.instance 返回 null？
   - [ ] 检查 _init() 构造函数
   - [ ] 查看是否多次创建实例

3. **配置变更不生效**
   - [ ] 检查 EventBus.config_changed 信号是否连接
   - [ ] 检查 Manager._on_config_changed() 是否实现
   - [ ] 查看日志是否有错误消息

4. **性能问题**
   - [ ] 配置是否被重复加载？
   - [ ] 缓存是否生效？
   - [ ] 是否有死循环配置变更？

---

### 📊 性能基准

**预期性能指标**：

| 指标 | 目标 | 实际 |
|------|------|------|
| 配置加载时间（首次） | < 50ms | ___ |
| 配置加载时间（缓存） | < 1ms | ___ |
| 配置保存时间 | < 100ms | ___ |
| EventBus 信号延迟 | < 5ms | ___ |
| 内存占用（单个配置） | < 200KB | ___ |

---

### ✨ 完成清单

- [ ] 所有编译检查通过
- [ ] 所有单元测试通过
- [ ] 所有功能验证完成
- [ ] 没有性能回归
- [ ] 文档已更新
- [ ] 代码审查通过（如适用）

---

**验证完成时间**: _______________  
**验证人员**: _______________  
**验证状态**: ☐ 通过 ☐ 需要修复

---

## 附录：快速诊断命令

```gdscript
# 在 Godot 脚本编辑器中运行以检查配置管理器状态
@onready var mgr = ConfigManager.instance

func test_config_status():
    if mgr == null:
        print("❌ ERROR: ConfigManager.instance is null")
        return
    
    print("✓ ConfigManager.instance initialized")
    
    # 检查缓存
    print("Cached configs: %d" % mgr.configs.size())
    
    # 检查路径常量
    print("DEFAULT_CONFIG_PATH: %s" % ConfigManager.DEFAULT_CONFIG_PATH)
    print("USER_CONFIG_PATH: %s" % ConfigManager.USER_CONFIG_PATH)
    
    # 检查 EventBus 信号
    if EventBus.instance:
        print("✓ EventBus.instance initialized")
        print("config_changed signal: %s" % EventBus.instance.config_changed)
    else:
        print("❌ EventBus.instance is null")
```

---

**最后更新**: 2026-02-12  
**版本**: 1.0
