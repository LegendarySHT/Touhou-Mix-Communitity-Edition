# 音符可视化集成说明

**完成日期**: 2026年1月27日  
**集成状态**: ✅ 完成

---

## 📋 功能概述

已成功将 `noteDisplayer.gd` 音符可视化组件集成到 TrackView 中，用于 MIDI 预览时的实时音符显示。

## 🎯 集成要点

### 1. 数据流向

```
MidiPlaybackManager
    ↓ (load_midi)
current_notes (Array[MidiParser.NoteEvent])
    ↓ (转换格式)
NoteDisplayer.NoteEvent
    ↓ (init_displayer)
noteDisplayer 组件
    ↓ (_process)
实时渲染和位置更新
```

### 2. 组件结构

#### TrackView 主视图
- **master_note_displayer**: 显示所有音符的总览视图
- **多个 midiTrack**: 每个轨道都有自己的 note_display

#### NoteDisplayer 组件
- 接收 NoteEvent 数组
- 根据 current_tick 实时渲染音符位置
- 支持音符回退和前进
- 自动管理可见音符

### 3. 关键修改

#### TrackView.gd (TrakView.gd)

**新增属性**:
```gdscript
var current_tick: int = 0  # 当前播放位置（tick）
```

**新增方法**:
```gdscript
# 初始化主音符显示器（显示所有音符）
func _init_master_note_displayer() -> void

# 初始化轨道音符显示器（按轨道过滤）
func _init_track_note_displayer(track_scene: MidiTrack, track_index: int) -> void

# 转换音符格式
func _convert_notes_to_display_format(midi_notes: Array) -> Array[NoteDisplayer.NoteEvent]
```

**修改方法**:
```gdscript
func _load_midi(midi: MidiData):
    # 添加了初始化 master_note_displayer 的调用
    _init_master_note_displayer()

func _create_track_views():
    # 为每个轨道初始化音符显示
    _init_track_note_displayer(track_scene, track_info.index)

func _process(delta: float):
    # 更新 current_tick 以驱动音符显示
    current_tick = int(midi_playback_manager.position)
```

#### MidiPlaybackManager.gd

**新增方法**:
```gdscript
func set_vocal_volume_db(volume_db: float) -> void
    # 占位符方法，供 TrackView 调用
```

### 4. 音符格式转换

```gdscript
# MidiParser.NoteEvent → NoteDisplayer.NoteEvent
MidiParser.NoteEvent:
    - pitch: int
    - velocity: int  
    - start_tick: int
    - duration: int
    - track_index: int
    - channel: int

转换为 ↓

NoteDisplayer.NoteEvent:
    - pitch: int
    - velocity: int
    - start_tick: int
    - duration: int
    - track_index: int
    - channel: int
```

两者字段完全一致，只是类定义不同。

---

## 🚀 使用方式

### 用户操作流程

1. 在 MidiView 中选择一个 MIDI 谱面
2. 点击"进入轨道视图"按钮
3. TrackView 加载后自动显示：
   - **顶部**: master_note_displayer 显示所有音符的总览
   - **每个轨道**: 显示该轨道的音符
4. 点击"播放预览"按钮
5. 音符会随着播放实时滚动显示

### 音符显示特性

- **实时滚动**: 音符随播放位置移动
- **颜色编码**: 根据音高自动着色（HSV 色轮）
- **多车道显示**: 按轨道号分配到不同车道
- **进度追踪**: 显示已通过/总音符数
- **回退支持**: 拖动进度条回退时自动重新渲染

---

## 📊 性能优化

### 已实现的优化

1. **可见性剔除**: 只渲染当前视野内的音符
2. **增量生成**: 按需生成即将进入视野的音符
3. **自动清理**: 离开视野的音符自动销毁
4. **批量操作**: 回退时批量重建音符

### 配置参数

```gdscript
# noteDisplayer.gd
var scale_factor: float = 0.5   # tick 到像素的缩放因子
var lane_count: int = 12        # 车道数量（小窗口）/ 24（大窗口）
```

---

## 🔧 开发者备注

### 已知限制

1. **音符宽度**: 当前 duration 很短的音符可能显示为细线
2. **车道分配**: 简单按 track_index % lane_count 分配，可能重叠
3. **缩放固定**: scale_factor 当前硬编码，未来可改为动态调整

### 扩展方向

1. **自定义皮肤**: 支持加载自定义音符样式
2. **性能模式**: 超大 MIDI 文件的优化渲染
3. **判定线**: 添加视觉判定线指示
4. **音符预览**: 鼠标悬停显示音符详情
5. **轨道过滤**: UI 控制显示/隐藏特定轨道

---

## ✅ 测试清单

- [x] MIDI 加载时正确初始化 master_note_displayer
- [x] 每个轨道正确显示自己的音符
- [x] 播放时音符实时滚动
- [x] 拖动进度条时音符正确回退/前进
- [x] 音符颜色根据音高正确显示
- [x] 已通过音符计数正确更新
- [x] 窗口大小改变时车道数正确调整

---

## 📚 相关文件

| 文件 | 作用 |
|------|------|
| [UI/Views/TrackView/TrakView.gd](../UI/Views/TrackView/TrakView.gd) | TrackView 主逻辑 |
| [UI/Views/TrackView/noteDisplayer.gd](../UI/Views/TrackView/noteDisplayer.gd) | 音符可视化组件 |
| [UI/Views/TrackView/midiTrack.gd](../UI/Views/TrackView/midiTrack.gd) | 单个轨道视图 |
| [Game/MidiPlaybackManager.gd](../Game/MidiPlaybackManager.gd) | MIDI 播放管理 |
| [Utilities/MidiParser.gd](../Utilities/MidiParser.gd) | MIDI 解析工具 |

---

## 🎓 技术细节

### current_tick 更新机制

```gdscript
# TrackView._process()
func _process(delta: float):
    if is_previewing and midi_playback_manager:
        # position 属性直接以 tick 为单位
        current_tick = int(midi_playback_manager.position)

# noteDisplayer._process()
func _process(_delta):
    var ct = master_node.current_tick  # 获取父节点的 current_tick
    # 基于 ct 计算音符位置
    var x = area_width - (end_tick - ct) * scale_factor
```

### 音符生成条件

```gdscript
# 视野右边界
var view_right_bound = ct + area_width / scale_factor

# 生成即将进入视野的音符
while current_idx < current_notes.size() and 
      current_notes[current_idx].start_tick < view_right_bound:
    _create_note(current_notes[current_idx])
    current_idx += 1
```

---

**集成完成！** 🎉

现在 TrackView 具备完整的 MIDI 音符可视化功能，可用于谱面预览和调试。
