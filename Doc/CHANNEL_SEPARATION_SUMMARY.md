# TrackView Channel 级别区分实施总结

**完成日期**: 2026-01-30  
**Godot版本**: 4.5  
**状态**: ✅ 实施完成

---

## 📋 实施概览

本次实施将TrackView从按Track创建UI修改为按**(Track, Channel)组合**创建独立的UI项，按**先Channel后Track**的顺序排列，同时最小化对系统其他部分的影响。

---

## 🔧 修改的文件列表

### 1. **Core/Models/MidiData.gd** ✅
**修改内容**:
- 添加字段 `selected_track_configs: Dictionary[int, Array[int]]` - 存储(track_idx → [ch0, ch1, ...])配置
- 添加方法 `is_track_channel_selected(track_idx, channel) -> bool` - 检查是否选中
- 添加方法 `set_track_channel_enabled(track_idx, channel, enabled)` - 设置启用状态

**影响**:
- 保留原有 `selected_track_indices` 用于向后兼容
- 新增channel级别的状态管理

### 2. **UI/Views/TrackView/MidiTrack.gd** ✅
**修改内容**:
- ❌ 删除本地属性: `is_enabled`, `is_muted`, `is_solo`
- ✅ 添加属性: `track_channel: int` 和 `midi_data: MidiData`
- ✅ 修改 `setup_track()` 方法，添加 `channel` 和 `midi_data_ref` 参数
- ✅ 修改按钮回调 `_on_enable_toggled()` 等，调用 `midi_data.set_track_channel_enabled()`
- ✅ 添加预留接口 `set_channel_label()` 用于后续UI完善

**影响**:
- UI状态现在从MidiData读取而非本地属性
- 支持同一track的不同channel独立的启用/禁用

### 3. **UI/Views/TrackView/TrackView.gd** ✅
**修改内容**:
- ✅ 重写 `_create_track_views()` - 三步聚合和排序
  1. 聚合所有notes中每个track的unique channels
  2. 按(channel asc, track asc)排序track-channel对
  3. 为每个对创建MidiTrack UI项
- ✅ 修改 `_on_track_enable_toggled()` - 调用MidiData的set_track_channel_enabled
- ✅ 修改 `_on_track_mute_toggled()` - 同上
- ✅ 修改 `_update_master_note_displayer()` - 从selected_track_configs过滤
- ✅ 修改 `_init_master_note_displayer()` - 初始化selected_track_configs，默认全选
- ✅ 修改 `_init_track_note_displayer()` - 添加channel参数

**影响**:
- TrackView现在管理channel级别的音符区分
- 状态变化自动同步到MidiData

### 4. **UI/Views/TrackView/NoteDisplayer.gd** ✅
**修改内容**:
- ✅ 修改 `_create_note()` - 添加 `note_rect.set_meta("channel", note.channel)`
- ✅ 添加方法 `sync_from_midi_data(midi_data)` - 从MidiData同步启用状态
- ✅ 更新 `toggle_track()` - 保留向后兼容

**影响**:
- 音符现在包含channel元数据
- 可根据(track, channel)对过滤音符显示

### 5. **Game/MidiPlaybackManager.gd** ✅
**修改内容**:
- ✅ 修改 `set_selected_tracks()` - 兼容新格式 `Array[Dictionary]` 和旧格式 `Array[int]`
  - 新格式: `[{"track": int, "channel": int}, ...]`
  - 旧格式: `[int, int, ...]` 仅保留track信息
- 调用 `midi_data.set_track_channel_enabled()` 更新配置

**影响**:
- 向后兼容旧代码使用Array[int]调用
- 支持新的Array[Dictionary]格式

### 6. **Game/AudioManager.gd** ✅
**修改内容**:
- ✅ 修改 `set_midi_tracks()` 参数类型 - 接收 `tracks_data` 而非 `Array[int]`
- 改为调用 `MidiPlaybackManager.set_selected_tracks(tracks_data)`

**影响**:
- 支持新格式数据传递

---

## 📊 数据结构变更

### selected_track_configs 格式

```gdscript
# 新数据结构
selected_track_configs: Dictionary[int, Array[int]] = {
    0: [0, 1, 2],     # Track 0 的通道 0, 1, 2 被选中
    1: [0],           # Track 1 的通道 0 被选中
    2: [3, 9]         # Track 2 的通道 3, 9 被选中
}
```

### (Track, Channel) 创建顺序

按以下规则排序:

```
第1步：按channel升序排列 (0, 1, 2, ..., 15)
第2步：同一channel内按track升序排列

示例结果:
- Track 0, Channel 0
- Track 1, Channel 0
- Track 2, Channel 0
- Track 0, Channel 1
- Track 1, Channel 1
- ...
```

---

## 🎯 关键特性

✅ **Channel级别区分**
- 同一Track的不同Channel创建独立的MidiTrack UI项

✅ **灵活的排序**
- 先按Channel升序，再按Track升序
- 便于查看同一通道的所有轨道

✅ **向后兼容**
- 旧代码使用 `Array[int]` 仍然有效
- `selected_track_indices` 字段保留
- MidiPlaybackManager 自动适配新旧格式

✅ **UI状态管理**
- MidiData中央管理所有(track, channel)的启用状态
- MidiTrack从MidiData读取状态而非本地属性
- 状态变化自动同步

✅ **预留扩展接口**
- MidiTrack.`set_channel_label()` - 后续在UI中显示channel号
- 当前不显示channel信息，仅留接口供后续使用

---

## 🔄 工作流程

### 加载MIDI

```
1. TrackView._load_midi(midi)
2. All_Notes 转换完成，包含track_index和channel信息
3. _init_master_note_displayer()
   - 初始化 selected_track_configs (默认全选所有track-channel对)
   - 初始化master_note_displayer显示所有音符
4. _create_track_views()
   - 第1步：聚合 track → channels 映射
   - 第2步：按(channel, track)排序生成列表
   - 第3步：为每个对创建MidiTrack UI + 初始化其NoteDisplayer
```

### 启用/禁用Track-Channel

```
1. 用户点击MidiTrack的enable_btn
2. MidiTrack._on_enable_toggled()
3. midi_data.set_track_channel_enabled(track_idx, channel, enabled)
4. TrackView._on_track_enable_toggled()
5. master_note_displayer.sync_from_midi_data()
   - 重建enable_tracks列表
   - 根据(track, channel)状态调整音符显示
```

---

## 📝 使用示例

### 查询(track, channel)的启用状态

```gdscript
if midi_data.is_track_channel_selected(track_idx, channel):
    print("Track %d Channel %d is enabled" % [track_idx, channel])
```

### 设置(track, channel)的启用状态

```gdscript
midi_data.set_track_channel_enabled(track_idx, channel, true)   # 启用
midi_data.set_track_channel_enabled(track_idx, channel, false)  # 禁用
```

### MidiPlaybackManager适配新格式

```gdscript
# 新格式
var tracks_config = [
    {"track": 0, "channel": 0},
    {"track": 0, "channel": 1},
    {"track": 1, "channel": 0}
]
MidiPlaybackManager.instance.set_selected_tracks(tracks_config)

# 旧格式（向后兼容）
MidiPlaybackManager.instance.set_selected_tracks([0, 1])  # 仅track索引
```

---

## ⚠️ 已知限制

1. **UI显示** - Channel号暂未在UI中显示，仅留接口供后续完善
2. **鼓轨特殊处理** - 第10通道未做特殊标记，可后续扩展
3. **独奏功能** - Solo逻辑暂未实现channel级别

---

## ✅ 验证清单

- [x] MidiData 新增 selected_track_configs 和相关方法
- [x] MidiTrack 删除本地状态属性，添加 channel 和 midi_data 参数
- [x] TrackView._create_track_views() 实现 3 步聚合和排序
- [x] TrackView 状态管理调用 MidiData 的新方法
- [x] NoteDisplayer 添加 channel 元数据和 sync_from_midi_data()
- [x] MidiPlaybackManager.set_selected_tracks() 兼容新旧格式
- [x] AudioManager.set_midi_tracks() 改为接收 tracks_data

---

## 🚀 后续完善方向

1. **UI完善**
   - 在MidiTrack中显示Channel号：调用 `set_channel_label(channel)`
   - 同一Track的多个Channel在UI中的分组显示

2. **功能完善**
   - 实现Channel级别的独奏(Solo)
   - 添加鼓轨(Channel 10)的特殊标记

3. **优化**
   - 性能优化：缓存track-channel对的创建
   - 大规模数据的分页加载

---

**实施完成！** ✅

所有文件已修改，功能架构就位。系统已支持Channel级别的音符区分和灵活的启用/禁用管理。

