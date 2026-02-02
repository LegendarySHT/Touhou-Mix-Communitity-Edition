# MIDI持久化快速参考

**完成日期:** 2026年1月30日  
**状态:** ✅ 完成并编译无错误

---

## 🎯 5分钟快速了解

### 用户角度 - 它是如何工作的

1. **加载MIDI** → 系统自动从JSON恢复上次的音量和设置
2. **修改音量** → 拖动滑块，实时播放效果
3. **退出TrackView** → 系统自动保存所有设置到JSON文件
4. **再次加载** → 看到之前保存的音量

### 开发者角度 - 核心流程

```gdscript
# 加载时 (MidiData.from_json)
var runtime_config = json_data.get("_runtime", {})
midi_volume = runtime_config.get("midi_volume", 100)

# 退出时 (TrackView._save_midi_config)
var config = current_midi_data.export_runtime_config()
ConfigLoader.save_json_file(json_path, {"_runtime": config}, true)

# 显示时 (TrackView._restore_midi_config)
midi_vol_slider.value = current_midi_data.midi_volume
```

---

## 📋 新增API速查表

### MidiData.gd

```gdscript
# 字段
midi_volume: int = 100      # MIDI音量 (0-100)
vocal_volume: int = 100     # 人声音量 (0-100)

# 方法
export_runtime_config() -> Dictionary
    返回: {
        "midi_volume": int,
        "vocal_volume": int,
        "selected_track_indices": Array,
        "track_channel_mute_state": Dictionary,
        "use_soundfont": String,
        "saved_at": int
    }
```

### ConfigLoader.gd

```gdscript
# 加载JSON
load_json_file(file_path: String) -> Dictionary

# 保存JSON（默认启用合并）
save_json_file(file_path: String, data: Dictionary, 
               merge_existing: bool = true) -> bool
```

### FileSystemManager.gd

```gdscript
# 获取谱面JSON路径
get_chart_json_path(chart_id: String) -> String
    返回: "user://files/Charts/[folder]/[chart_id].json"
```

### TrackView.gd

```gdscript
# 保存配置（退出时自动调用）
_save_midi_config() -> void

# 恢复配置（加载时自动调用）
_restore_midi_config() -> void
```

---

## 🔄 数据流

### 保存流程
```
user modifies slider
      ↓
value_changed signal
      ↓
(real-time playback updated by MidiPlaybackManager)
      ↓
user exits TrackView
      ↓
_on_ui_state_changed() fired
      ↓
_save_midi_config() called
      ↓
current_midi_data.midi_volume = slider.value
      ↓
export_runtime_config() → Dictionary
      ↓
ConfigLoader.save_json_file(json_path, {"_runtime": config}, merge=true)
      ↓
JSON file saved (original fields preserved)
```

### 加载流程
```
user selects MIDI
      ↓
DataManager.load_all_midis_async()
      ↓
MidiData.from_json(json)
      ↓
reads "_runtime" object from JSON
      ↓
midi_volume = runtime_config.get("midi_volume", 100)
      ↓
TrackView._load_midi() called
      ↓
_restore_midi_config() called
      ↓
midi_vol_slider.value = current_midi_data.midi_volume
      ↓
user sees saved volume
```

---

## ✅ 测试场景

### 场景1: 首次加载MIDI（无_runtime）

```gdscript
# JSON内容
{
  "id": "chart123",
  "name": "My Chart",
  ...metadata...
  # 注意：没有 "_runtime" 对象
}

# from_json执行
runtime_config = json.get("_runtime", {})  # 返回 {}
midi_volume = runtime_config.get("midi_volume", 100)  # 使用默认值100

# 结果：UI显示100%
```

### 场景2: 修改后保存

```gdscript
# 用户修改
midi_vol_slider.value = 60

# 退出时
current_midi_data.midi_volume = 60
export_runtime_config() returns:
{
  "midi_volume": 60,
  "vocal_volume": 100,
  "selected_track_indices": [0, 1],
  ...
}

save_json_file(path, {"_runtime": {...}}, true)

# JSON文件变为
{
  "id": "chart123",
  "name": "My Chart",
  ...metadata...,
  "_runtime": {
    "midi_volume": 60,
    ...
  }
}
```

### 场景3: 再次加载MIDI

```gdscript
# JSON现在包含_runtime
runtime_config = json.get("_runtime", {})  # 返回 {...}
midi_volume = runtime_config.get("midi_volume", 100)  # 读取60

# 恢复
midi_vol_slider.value = 60

# 结果：UI显示60%（保存的值）
```

---

## 🐛 错误处理

### 如果JSON路径获取失败

```gdscript
var json_path = FileSystemManager.instance.get_chart_json_path(midi_id)
if json_path.is_empty():
    push_error("Failed to locate JSON file for MIDI: %s" % midi_id)
    return  # 配置不保存，但游戏继续运行
```

### 如果JSON保存失败

```gdscript
if not config_loader.save_json_file(json_path, data_to_save, true):
    push_error("Failed to save MIDI config")
    return  # 配置丢失，但游戏继续运行
```

### 如果merge失败

```gdscript
# merge=true时，如果读取现有JSON失败，将使用新数据覆盖
# （这是安全的回退行为）
```

---

## 📊 JSON合并示例

### 原始JSON
```json
{
  "id": "abc123",
  "name": "Chart Name",
  "artist": "Artist Name",
  "bpm": 120,
  "duration": 240
}
```

### 保存数据
```json
{
  "_runtime": {
    "midi_volume": 60,
    "vocal_volume": 100
  }
}
```

### 合并后结果（merge=true）
```json
{
  "id": "abc123",
  "name": "Chart Name",
  "artist": "Artist Name",
  "bpm": 120,
  "duration": 240,
  "_runtime": {
    "midi_volume": 60,
    "vocal_volume": 100
  }
}
```

✅ **原有字段全部保留！**

---

## 🎮 使用示例

### 在TrackView中获取已保存的配置

```gdscript
if current_midi_data:
    var saved_volume = current_midi_data.midi_volume
    var saved_tracks = current_midi_data.selected_track_indices
    var saved_mute = current_midi_data.track_channel_mute_state
```

### 导出用户配置备份

```gdscript
var config = current_midi_data.export_runtime_config()
var json_str = JSON.stringify(config)
# 可以保存到文件或发送到服务器
```

### 手动保存配置（不等待退出）

```gdscript
func manual_save_config() -> void:
    if current_midi_data:
        # 更新字段
        current_midi_data.midi_volume = int(midi_vol_slider.value)
        
        # 获取路径
        var json_path = FileSystemManager.instance.get_chart_json_path(
            current_midi_data.id
        )
        
        # 保存
        var config_loader = ConfigLoader.new()
        config_loader.save_json_file(json_path, 
            {"_runtime": current_midi_data.export_runtime_config()}, true)
```

---

## 🔐 安全特性

✅ **非破坏性** - 原有JSON字段不会被删除  
✅ **幂等性** - 多次保存相同数据结果相同  
✅ **容错性** - 配置丢失时使用默认值继续运行  
✅ **类型检查** - 从JSON恢复时验证数据类型  
✅ **时间戳** - saved_at记录最后保存时间  

---

## 📝 日志输出

### 成功保存
```
[TrackView] Successfully saved MIDI config to: user://files/Charts/abc123_song/abc123.json
```

### 成功恢复
```
[TrackView] Restored MIDI config: midi_volume=60, vocal_volume=100
```

### 错误
```
[TrackView] Failed to save MIDI config to: ...
ERROR: Failed to locate JSON file for MIDI: ...
```

---

## 🚀 后续增强建议

### 短期
- [ ] 添加用户提示"配置已保存"
- [ ] 添加"重置为默认"按钮
- [ ] 添加快速保存按钮（无需退出）

### 中期
- [ ] 多配置预设切换
- [ ] 配置导出/导入功能
- [ ] 配置版本历史

### 长期
- [ ] 云端同步配置
- [ ] 社区配置分享
- [ ] 自动备份机制

---

## 📞 常见问题

**Q: 配置保存到哪里？**  
A: 每个谱面对应的JSON文件中，位置：`user://files/Charts/[folder_name]/[chart_id].json`

**Q: 如果我删除了_runtime对象会怎样？**  
A: 下次加载时使用默认值（100% 音量等），不会报错

**Q: 不同谱面的配置是否独立？**  
A: 是的，每个谱面的JSON文件包含自己的_runtime对象

**Q: 如果JSON文件损坏了会怎样？**  
A: 配置无法加载，使用默认值，游戏继续运行

**Q: 可以禁用自动保存吗？**  
A: 可以，注释掉TrackView._on_ui_state_changed中的_save_midi_config()调用

---

## ✨ 完成度

| 功能 | 状态 |
|------|------|
| MidiData扩展 | ✅ 完成 |
| JSON I/O方法 | ✅ 完成 |
| 路径解析 | ✅ 完成 |
| 自动保存/恢复 | ✅ 完成 |
| 错误处理 | ✅ 完成 |
| 日志记录 | ✅ 完成 |
| 编译验证 | ✅ 无错误 |
| 文档 | ✅ 完成 |

---

**系统已就绪！** 🎉

用户的MIDI配置现在会自动保存和恢复。

