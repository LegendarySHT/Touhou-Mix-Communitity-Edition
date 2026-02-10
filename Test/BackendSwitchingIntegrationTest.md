# MIDI 后端切换集成测试计划

## 🎯 测试目的
验证四个阶段的修复（信号监听+初始化验证+完整清理+竞态条件防护）全部生效，后端切换100%成功。

## 📋 测试前提条件
- [ ] 项目已编译
- [ ] 两个 MIDI 文件已加载 (以便验证播放)
- [ ] 控制台即时日志开启
- [ ] 游戏窗口和控制台同时可见

## 🔧 测试场景

### 场景1: 基础切换 ✔️
**预期**: MidiPlayer ↔ MeltySynth 可正常切换

1. 启动游戏
2. 打开 SettingView 选项
3. 在 MIDI后端中:
   - 选择 "MidiPlayer" 
   - 点击返回/确定
4. **验证清单**:
   - [ ] 日志显示: `Switched to MidiPlayer MIDI backend`
   - [ ] 没有错误日志
   - [ ] 返回后能正常播放MIDI

5. 重复打开 SettingView, 选择 "MeltySynth"
6. **验证清单**:
   - [ ] 日志显示: `Switched to MeltySynth MIDI backend`
   - [ ] 没有随后的 "Cleaning up ... before switching to" 错误回退日志
   - [ ] 返回后能正常播放MIDI

**预期日志示例**:
```
[EventBus] settings_changed signal emitted...
[MidiPlaybackManager] Settings changed, checking midi_backend...
[MidiPlaybackManager] MIDI backend changed from 'addons' to 'meltysynth'
[MidiPlaybackManager] Cleaning up addons backend...
[MidiPlaybackManager] Initializing MeltySynth backend...
[MidiPlaybackManager] MeltySynth backend initialized successfully
[MidiPlaybackManager] Switched to MeltySynth MIDI backend
```

### 场景2: 重复同一后端 ✔️
**预期**: 选择相同后端时，应检测到无需切换

1. 当前后端是 MidiPlayer
2. 打开 SettingView，选择 MidiPlayer (同一个)
3. **验证清单**:
   - [ ] 日志显示: `Backend already set to 'addons', no switch needed`
   - [ ] 没有初始化日志
   - [ ] 后台没有任何操作

### 场景3: 快速多次切换 🔄
**预期**: 频繁切换时，第二次切换应被拦截，等待完成后恢复正常

1. 启动游戏
2. **第一次**: 打开 SettingView, 选择 MeltySynth, 立即点返回
3. **快速切换** (在前面的切换完成前):
   - 立即重新打开 SettingView
   - 选择 MidiPlayer
4. **验证清单**:
   - [ ] 日志显示: `Backend switch already in progress, ignoring redundant set_backend() call`
   - [ ] 没有出现两个后端同时活跃的迹象
   - [ ] 继续等待, 最终后端回到 MeltySynth (因为被拦截, 第二次未生效)

5. 等待 3 秒钟，确保第一次切换完成
6. **重试切换**: 再次打开 SettingView, 选择 MidiPlayer
7. **验证清单**:
   - [ ] 这次切换成功 (不被拦截)
   - [ ] 日志显示完整初始化日志

### 场景4: 在MIDI播放中切换 ▶️
**预期**: 播放中切换后端，应停止→清理→切换→继续

1. 在 MidiView 中选择一个 MIDI 文件, 进入 TrackView
2. 选择轨道开始播放 MIDI (MidiPlayer 后端)
3. **播放进行中** (音乐正在继续):
   - 打开 SettingView
   - 切换到 MeltySynth
   - 点返回
4. **预期行为**:
   - [ ] 播放立即停止
   - [ ] 清理 MidiPlayer 后端
   - [ ] 初始化 MeltySynth
   - [ ] 用新后端重新加载 MIDI
   - [ ] MIDI 暂停 (不自动继续)

5. **再次切换回 MidiPlayer**:
   - 在SettingView选择MidiPlayer
6. **验证清单**:
   - [ ] 同样的流程: 停止→清理→初始化→加载
   - [ ] 没有音频混淆或重复

### 场景5: 异常处理 ⚠️
**预期**: 初始化失败时，应正确回退到另一个后端

1. 修改 MeltySynth 初始化代码使其失败 (仅用于测试):
   ```gdscript
   # 在 _initialize_meltysynth_backend() 中临时添加:
   GameLogger.instance.error("Test failure", "MidiPlaybackManager")
   return false  # 强制失败
   ```

2. 启动游戏，尝试切换到 MeltySynth
3. **验证清单**:
   - [ ] 日志显示初始化失败: `MeltySynth initialization failed`
   - [ ] 自动回退: `Falling back to 'addons' backend`
   - [ ] 后端最终设置为 MidiPlayer
   - [ ] MIDI 仍可正常播放

4. **还原测试代码** (删除上面的测试代码)

## 📊 结果统计

### 通过条件
所有场景都通过 = ✅ 修复成功

### 部分失败原因分析
| 场景 | 失败症状 | 可能原因 |
|------|---------|--------|
| 场景1 | 切换失败，回退到MidiPlayer | 初始化失败，检查MeltySynth文件路径 |
| 场景1 | "Cleaning up...before switching to" 异常出现 | Main.gd 中的 midi_backend 处理未被注释掉 |
| 场景3 | 没有看到 "already in progress" 日志 | backend_switching 标志未生效，检查代码修改 |
| 场景4 | 两个后端同时播放声音 | _cleanup_old_backend() 失败，检查scene tree移除 |
| 场景5 | 未能回退到MidiPlayer | set_backend() 的fallback逻辑未实现 |

## 🐛 调试技巧

### 启用详细日志
```gdscript
# 在 GameLogger._print_log() 中临时降低日志级别:
if true:  # 强制打印所有日志
    print(formatted_log)
```

### 监控后端状态
在任何suspected问题时，检查:
```gdscript
# 在游戏运行时临时添加快捷键:
if Input.is_action_just_pressed("debug_key"):
    var mgr = MidiPlaybackManager.instance
    print("Current backend: ", mgr.midi_backend)
    print("Is switching: ", mgr.backend_switching)
    print("MIDI loaded: ", mgr.is_midi_loaded)
```

### 确认文件修改
```bash
# 检查 Main.gd 中 midi_backend 处理是否被注释:
grep -n "midi_backend" Main.gd  
# 应该看到被注释的行（以 # 开头）

# 检查 MidiPlaybackManager.gd 中是否有 backend_switching:
grep -n "backend_switching" MidiPlaybackManager.gd
# 应该看到至少 10+ 处引用
```

## 📝 测试报告模板

```
测试日期: ____
游戏版本: ____
MeltySynth版本: ____

场景1 (基础切换): ☐PASS ☐FAIL
  - 问题: ___________
  - 日志参考: ___________

场景2 (重复同一后端): ☐PASS ☐FAIL
  - 问题: ___________

场景3 (快速多次切换): ☐PASS ☐FAIL
  - 问题: ___________

场景4 (播放中切换): ☐PASS ☐FAIL
  - 问题: ___________

场景5 (异常处理): ☐PASS ☐FAIL
  - 问题: ___________

总体评分: ___ / 5

备注:
```

---

**测试关键词**: 无竞态条件，100% 切换成功，完整日志  
**预期结果**: 全部场景通过 ✅
