# ✅ MIDI 后端切换修复 - 快速检查清单

运行此清单以确认所有修改都已正确应用。

## 🔍 验证修改

### 1️⃣ 检查 MidiPlaybackManager.gd 中的 backend_switching 标志

```bash
# 预期: 至少 10 处引用
grep -c "backend_switching" Game/MidiPlaybackManager.gd
```
✅ **检查点**: 结果应该是 `10`

### 2️⃣ 检查 backend_switching 标志初始化

在 MidiPlaybackManager.gd 第 30-40 行附近应该有：
```gdscript
var backend_switching: bool = false
```

✅ **检查点**: 这行必须存在

### 3️⃣ 检查 set_backend() 开头的拦截器

在 MidiPlaybackManager.gd `set_backend()` 函数开头应该有：
```gdscript
if backend_switching:
    print("[MidiPlaybackManager] Backend switch already in progress, ignoring redundant set_backend() call")
    return false
```

✅ **检查点**: 必须在 `func set_backend()` 的前 5 行内

### 4️⃣ 检查所有 return 前都重置标志

在 MidiPlaybackManager.gd `set_backend()` 中应该有多个：
```gdscript
backend_switching = false
return true  # 或 false
```

✅ **检查点**: 应该有至少 7-8 处这样的重置

### 5️⃣ 检查 Main.gd 中 midi_backend 处理被注释

在 Main.gd `_reload_all_settings()` 中，lines 281-289 应该被注释：
```gdscript
# NOTE: midi_backend 的处理由 MidiPlaybackManager._on_settings_changed() 专门负责
# 不要在这里重复处理，避免竞态条件导致后端切换失败
# if midi_playback_manager and gameplay_section.has("midi_backend"):
#     ...
```

✅ **检查点**: 这些行必须被 `#` 注释掉

### 6️⃣ 检查 EventBus 信号监听

在 MidiPlaybackManager.gd `_ready()` 中应该有：
```gdscript
EventBus.instance.settings_changed.connect(_on_settings_changed)
```

✅ **检查点**: 这行必须存在

### 7️⃣ 检查 _on_settings_changed() 函数存在

在 MidiPlaybackManager.gd 中应该有函数：
```gdscript
func _on_settings_changed(_key: String, _value: Variant) -> void:
    # 检测后端变更...
```

✅ **检查点**: 函数必须存在且包含 set_backend() 调用

### 8️⃣ 检查 _cleanup_old_backend() 函数存在

在 MidiPlaybackManager.gd 中应该有函数：
```gdscript
func _cleanup_old_backend(backend_type: String) -> void:
    # 停止播放、断开信号、移除节点、释放内存
```

✅ **检查点**: 函数必须存在，且包含 free() 调用（不是 queue_free()）

---

## 🧪 快速测试

### 测试 1: 基础功能
```
1. 启动游戏
2. 打开 SettingView
3. 在 MIDI后端选择 "MeltySynth" (第二个选项)
4. 点击返回
5. 检查日志输出:
   ✓ 应该看到 "Switched to MeltySynth MIDI backend"
   ✗ 不应该看到 "Cleaning up ... before switching to" (异常回退)
```

### 测试 2: 快速切换拦截
```
1. 从 MidiPlayer 切换到 MeltySynth (完整切换)
2. 立即打开 SettingView，再次尝试切换到 MidiPlayer
3. 快速点击返回，不等待 MeltySynth 初始化完成
4. 检查日志:
   ✓ 应该看到 "Backend switch already in progress"
   💡 这是正确行为，说明互斥锁有效
```

---

## 📊 修改验证脚本

若你使用 Git，可以查看修改的文件：
```bash
# 查看 MidiPlaybackManager.gd 的修改
git diff Game/MidiPlaybackManager.gd

# 查看 Main.gd 的修改  
git diff Main.gd

# 统计修改行数
git diff --stat
```

---

## ⚠️ 常见问题

### 问题: grep 找不到 backend_switching
**解决**: 
- 确认文件已保存
- 确认在正确的文件路径: `Game/MidiPlaybackManager.gd`
- 重新打开文件或强制刷新编辑器

### 问题: Main.gd 中仍看到 midi_backend 代码（未注释）
**解决**:
- 从行 281-289 再次选中代码
- 使用 Ctrl+/ 进行注释
- 保存文件 (Ctrl+S)

### 问题: 日志中没有看到任何 backend_switching 相关的日志
**解决**:
- 检查是否有 `print("[MidiPlaybackManager]...")`  语句
- 确认 GameLogger 已启用
- 尝试在 set_backend() 开头手动添加 print 调试

---

## ✨ 修改完成后

完成所有验证后，你可以：
1. 自信地运行集成测试 ([BackendSwitchingIntegrationTest.md](BackendSwitchingIntegrationTest.md))
2. 提交这些修改到版本控制
3. 标记为 MIDI 后端切换功能完成

---

**快速检查用时**: 5-10 分钟  
**检查项目总数**: 8 项  
**预期通过率**: 100% ✅

