# Channel 级别区分 - 快速参考和测试指南

**目的**: 协助开发者理解、测试和维护Channel级别的UI区分功能

---

## 🚀 快速开始

### 基本概念

在TrackView中，**不再按Track创建UI**，而是按**(Track, Channel)对**创建:

```
原理：
  Track 0: [Note(ch=0), Note(ch=0), Note(ch=1), Note(ch=1), ...]
                ↓
  分解为：
  - TrackView_Item[0] → Track 0, Channel 0 (notes with ch=0)
  - TrackView_Item[1] → Track 0, Channel 1 (notes with ch=1)
  - ...
  
排序规则：先Channel↑, 再Track↑
  Channel 0 track 0, 1, 2, ...
  Channel 1 track 0, 1, 2, ...
  Channel 2 track 0, 1, 2, ...
```

---

## 🔍 核心代码位置

### 1. 数据模型查询

```gdscript
# MidiData.gd - 两个新方法

# 查询(track, channel)是否启用
if MidiData.instance.is_track_channel_selected(track_idx=0, channel=0):
    print("Track 0 Channel 0 is enabled")

# 设置(track, channel)的启用状态
MidiData.instance.set_track_channel_enabled(
    track_idx=0,
    channel=0, 
    enabled=true
)
```

**文件**: [Core/Models/MidiData.gd](../../Core/Models/MidiData.gd) 第 162-180 行

### 2. UI项创建和排序

```gdscript
# TrackView.gd - _create_track_views() 的3步算法

# 第1步：聚合channels
var track_channel_groups: Dictionary[int, Array[int]] = {}
for note in All_Notes:
    if not track_channel_groups.has(note.track_index):
        track_channel_groups[note.track_index] = []
    if note.channel not in track_channel_groups[note.track_index]:
        track_channel_groups[note.track_index].append(note.channel)

# 第2步：排序生成pairs
var track_channel_pairs = []
for track_idx in track_channel_groups.keys():
    var channels = track_channel_groups[track_idx]
    channels.sort()  # channel升序
    for ch in channels:
        track_channel_pairs.append({
            "track": track_idx,
            "channel": ch,
            "notes": filter_notes_for_pair(track_idx, ch)
        })

# 第3步：按(channel asc, track asc)排序
track_channel_pairs.sort_custom(func(a, b):
    if a["channel"] != b["channel"]:
        return a["channel"] < b["channel"]
    return a["track"] < b["track"]
)
```

**文件**: [UI/Views/TrackView/TrackView.gd](../../UI/Views/TrackView/TrackView.gd) 第 147-187 行

### 3. UI项设置

```gdscript
# TrackView.gd - 创建MidiTrack UI时

var track_scene = create_and_add_item(track_name, "MidiTrack") as MidiTrack

# 注意新参数：channel 和 current_midi_data
track_scene.setup_track(
    self,                    # parent
    track_idx,               # 轨道索引
    track_name,              # 轨道名
    instrument_options,      # 乐器列表
    channel,                 # ⭐ 新增：channel号
    current_midi_data        # ⭐ 新增：MidiData引用
)

# 初始化该(track, channel)对的notes显示
_init_track_note_displayer(
    track_scene,
    track_idx,
    channel,                 # ⭐ 新增
    pair_notes               # 该对的notes
)
```

**文件**: [UI/Views/TrackView/TrackView.gd](../../UI/Views/TrackView/TrackView.gd) 第 198-201 行

### 4. 状态同步

```gdscript
# NoteDisplayer.gd - 新增方法

func sync_from_midi_data(midi_data: MidiData) -> void:
    enable_tracks.clear()
    for track_idx in midi_data.selected_track_configs.keys():
        enable_tracks.append(track_idx)
    
    # 根据(track, channel)状态调整显示
    for note_rect in active_notes:
        var track_idx = note_rect.get_meta("track_index")
        var channel = note_rect.get_meta("channel")
        
        var is_enabled = midi_data.is_track_channel_selected(track_idx, channel)
        note_rect.self_modulate.a = 1.0 if is_enabled else 0.0
```

**文件**: [UI/Views/TrackView/noteDisplayer.gd](../../UI/Views/TrackView/noteDisplayer.gd) 第 263-280 行

---

## 🧪 测试清单

### 测试1: 基本加载验证

**步骤**:
1. 在Godot编辑器中打开Main场景
2. 选择一个包含多个通道的MIDI文件
3. 进入TrackView

**预期结果**:
```
✅ 不同通道的notes在UI中呈现为独立的track项
✅ 每个项的track名称相同，但代表不同的channel
✅ 没有报错
```

**验证方法**: 
- 打开控制台，检查"_create_track_views"的输出
- 数visual track项数量应 > notes所属unique (track,ch)对数

### 测试2: 排序验证 (Channel优先)

**步骤**:
1. 加载一个包含以下notes的MIDI:
   ```
   Track 0, Channel 1
   Track 1, Channel 0
   Track 0, Channel 0
   Track 2, Channel 0
   ```

**预期UI顺序**:
```
✅ Track 0, Channel 0
✅ Track 1, Channel 0
✅ Track 2, Channel 0
✅ Track 0, Channel 1
```

**验证方法**: 检查TrackView中list_items的顺序

### 测试3: 启用/禁用功能

**步骤**:
1. 加载MIDI进TrackView
2. 找到"Track 0, Channel 1"的UI项
3. 点击其enable按钮禁用它

**预期结果**:
```
✅ MidiData.selected_track_configs[0] 中移除 1
✅ master_note_displayer中该(track,ch)的notes变为半透明(alpha=0)
✅ 其他(track,ch)的notes保持正常显示
```

**验证方法**:
```gdscript
# 在Godot debugger中
print(MidiData.instance.selected_track_configs)
# 应输出: {0: [0, 2, 3], 1: [0], ...}  (没有[0][1])
```

### 测试4: 互不影响验证

**步骤**:
1. 加载MIDI进TrackView
2. 禁用"Track 0, Channel 0"
3. 再禁用"Track 0, Channel 1"

**预期结果**:
```
✅ Track 0的两个channel都禁用了
✅ 但Track 1的notes仍显示
✅ MidiData中: {0: [其他ch], 1: [0], ...}
```

### 测试5: 回放同步

**步骤**:
1. 加载MIDI进TrackView
2. 禁用一个(track,ch)对
3. 进入PlayView播放

**预期结果**:
```
✅ GameplayManager加载的notes也反映禁用状态
✅ 播放时，被禁用的(track,ch)的notes不显示判定框
```

---

## 🐛 常见问题与解决

### Q1: Track名重复，无法区分

**当前行为**: 同一Track的多个Channel显示相同track名  
**原因**: 设计意图，channel号显示预留  
**解决方案**: 后续调用 `MidiTrack.set_channel_label(channel)` 时添加channel显示

**临时调试方法**:
```gdscript
# 在TrackView._create_track_views()中修改track_name
var track_name = "%s (Ch%d)" % [track_name_map.get(track_idx), channel]
track_scene.setup_track(..., track_name, ...)
```

### Q2: 音符显示错乱

**症状**: Notes未按预期显示或隐藏  
**常见原因**: 
- NoteDisplayer.enable_tracks未同步
- Note.channel元数据未正确设置

**调试步骤**:
```gdscript
# 检查note元数据
for note_rect in master_note_displayer.active_notes:
    var track = note_rect.get_meta("track_index")
    var ch = note_rect.get_meta("channel")
    var enabled = MidiData.instance.is_track_channel_selected(track, ch)
    print("Note(track=%d, ch=%d): enabled=%s" % [track, ch, enabled])
```

### Q3: 状态变化不同步

**症状**: 点击enable按钮后音符显示不变  
**原因**: sync_from_midi_data()未被调用  
**解决方案**: 检查TrackView._on_track_enable_toggled()中是否调用了master_note_displayer.sync_from_midi_data()

---

## 📊 数据流调试

### 打印当前状态

```gdscript
# 在任何地方检查状态
var midi_data = MidiData.instance
print("=== Track-Channel Config ===")
for track_idx in midi_data.selected_track_configs.keys():
    var channels = midi_data.selected_track_configs[track_idx]
    print("Track %d: Channels %s" % [track_idx, channels])

print("=== All Notes ===")
for note in TrackView.All_Notes:
    var is_en = midi_data.is_track_channel_selected(note.track_index, note.channel)
    print("Note(track=%d, ch=%d): %s" % [note.track_index, note.channel, "ENABLED" if is_en else "DISABLED"])
```

### 追踪enable/disable流程

在以下位置添加打印:

1. **MidiTrack._on_enable_toggled()** - 打印按钮状态
2. **TrackView._on_track_enable_toggled()** - 打印(track,ch)对和MidiData更新
3. **master_note_displayer.sync_from_midi_data()** - 打印enable_tracks和note过滤结果
4. **noteDisplayer.update()** - 打印每个note的显示/隐藏决策

---

## 🔧 常见修改点

### 添加Channel显示

```gdscript
# 在 MidiTrack.setup_track() 后添加
track_scene.set_channel_label(channel)
```

### 添加Channel号到轨道名

```gdscript
# TrackView._create_track_views() 中
var display_name = track_name if channel == 0 else "%s (Ch%d)" % [track_name, channel]
var track_scene = create_and_add_item(display_name, "MidiTrack") as MidiTrack
```

### 特殊处理鼓轨

```gdscript
# 在任何需要区分鼓轨的地方
if channel == 9:  # MIDI鼓轨总是channel 9
    print("Drum track detected!")
    # 特殊处理...
```

---

## 🎯 后续功能扩展点

### 1. UI完善 (实现set_channel_label)

在MidiTrack中:
```gdscript
func set_channel_label(channel_num: int) -> void:
    # 当前为空实现
    # TODO: 在UI中显示channel号
    print("Channel label should show: %d" % channel_num)
```

### 2. 音频播放同步

MidiPlaybackManager已支持新格式:
```gdscript
var selected = []
for track_idx in midi_data.selected_track_configs.keys():
    for ch in midi_data.selected_track_configs[track_idx]:
        selected.append({"track": track_idx, "channel": ch})

MidiPlaybackManager.instance.set_selected_tracks(selected)
```

### 3. Solo/Mute 扩展

数据模型已支持，只需在MidiData中添加:
```gdscript
var muted_track_channels: Dictionary[int, Array[int]] = {}
var solo_track_channels: Dictionary[int, Array[int]] = {}

func is_track_channel_muted(track, ch) -> bool:
    return muted_track_channels.has(track) and ch in muted_track_channels[track]
```

---

**文档最后更新**: 2026-01-30  
**适用版本**: Godot 4.5, THMIX CE

