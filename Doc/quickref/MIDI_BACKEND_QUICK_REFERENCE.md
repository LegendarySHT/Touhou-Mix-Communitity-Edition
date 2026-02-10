# MIDI后端动态切换 - 快速参考

## 📋 改动概览

### 问题
用户在SettingView选择MIDI后端（Addon或MeltySynth）后，退出时**设置无法生效**。

### 解决方案
添加EventBus信号监听，使MidiPlaybackManager能**动态响应设置变更**而无需重启游戏。

---

## 🔧 改动详情

### 1️⃣ MidiPlaybackManager._ready()
```gdscript
# 监听设置改变信号（用于动态切换MIDI后端和音源）
if EventBus.instance:
    EventBus.instance.settings_changed.connect(_on_settings_changed)
```
**作用**：在初始化时连接信号，使MidiPlaybackManager能随后响应设置变更。

### 2️⃣ MidiPlaybackManager._on_settings_changed()
```gdscript
func _on_settings_changed(setting_name: String, value: Variant) -> void:
    # 处理MIDI后端改变
    if setting_name == "*" or setting_name == "midi_backend":
        # 1. 重新读取配置
        _load_backend_from_config()
        # 2. 检查是否实际改变了
        if midi_backend != old_backend:
            # 3. 停止播放
            stop()
            # 4. 重新初始化后端
            _initialize_backend()
            # 5. 重新加载MIDI（如果有的话）
            load_midi(current_midi_data)
```
**作用**：接收EventBus信号，执行后端切换逻辑。

### 3️⃣ SettingView.save_config_to_file() <增强>
添加详细的日志记录：
```gdscript
print("[SettingView] midi_backend raw value from UI: %s (type: %s)" % [raw_value, typeof(raw_value)])
print("[SettingView] Converting midi_backend index %d to '%s'" % [index, converted])
# ... 后续保存和验证
```
**作用**：便于调试配置保存过程。

---

## 🔄 工作流程

```
SettingView → 选择后端 → 退出
                    ↓
        SettingView.save_config_to_file()
            ↓
        保存到user://files/settings.ini
            ↓
        EventBus.settings_changed("*", null)
            ↓
        ┌─────────────────────────┐
        │   Main._on_settings...  │ ←← 重新加载所有配置
        │   MidiPlaybackManager   │ ←← 动态切换后端
        │   ._on_settings...      │
        └─────────────────────────┘
            ↓
        MIDI后端已切换 ✓
```

---

## ✅ 验证清单

- [ ] 开启游戏，查看初始化日志中的后端选择
- [ ] 打开SettingView，切换MIDI后端  
- [ ] 退出SettingView，观察控制台日志
- [ ] 确认日志显示 `MIDI backend changed from ... to ...`
- [ ] 验证user://files/settings.ini中的midi_backend值已更新
- [ ] 如果之前加载过MIDI，验证新后端能正确播放
- [ ] 尝试多次切换，确保稳定性

---

## 📊 关键日志输出

### 成功的后端切换应包含：
```
[SettingView] Converting midi_backend index 1 to 'meltysynth'
[SettingView] About to save config. Gameplay section: {midi_backend: meltysynth}
[SettingView] Saved 5 settings to: user://files/settings.ini
[SettingView] Verification: midi_backend in saved file = 'meltysynth'
[MidiPlaybackManager] Settings changed event: setting_name='*'
[MidiPlaybackManager] MIDI backend changed from 'addons' to 'meltysynth' (triggered by settings)
[MidiPlaybackManager] Stopping playback before backend switch
[MidiPlaybackManager] Reinitializing backend: meltysynth
[MidiPlaybackManager] MeltySynth C# backend initialized via wrapper
```

### 后端未改变时：
```
[MidiPlaybackManager] Backend unchanged (still: 'addons')
```

---

## 🐛 常见问题

| 问题 | 可能原因 | 检查方法 |
|------|--------|--------|
| 后端未切换 | EventBus信号未发出 | 查看AnimationManager日志 |
| 后端未切换 | MidiPlaybackManager未监听信号 | 查看MidiPlaybackManager._ready()是否执行 |
| MIDI加载失败 | 新后端初始化失败 | 查看是否有"Failed to initialize"错误 |
| 频繁切换卡顿 | 正在重新初始化后端 | 切换后等待1-2秒 |

---

## 📁 涉及文件

| 文件 | 修改行数 | 说明 |
|------|--------|------|
| Game/MidiPlaybackManager.gd | 95-170 | 添加信号监听和处理函数 |
| UI/Views/SettingView/SettingView.gd | 140-205 | 增强日志记录 |
| Doc/MIDI_BACKEND_SETTING_FIX.md | NEW | 完整功能文档 |

---

## 🎯 核心逻辑

**关键原理**：动态切换无需重启是因为：
1. ✅ 后端初始化独立于游戏流程
2. ✅ MidiData可重新加载到新后端
3. ✅ 配置实时保存，程序实时读取
4. ✅ EventBus信号实时传递设置变更

---

**修复完成日期**: 2025年2月10日  
**测试状态**: 等待测试验证
