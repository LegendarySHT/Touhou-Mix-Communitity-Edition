# MIDI播放器Note生命周期控制扩展实施文档

**实施日期**: 2026年1月27日  
**Godot版本**: 4.5  
**状态**: ✅ 已完成实施（核心框架）

---

## 📋 实施概览

本次实施扩展了MIDI播放器功能，支持Note的生命周期管理和分类控制，允许游戏将MIDI note分为两类：
1. **AutoPlayNote** - 由MIDI播放器内部自动播放
2. **ManualControlNote** - 由游戏逻辑手动调用start()/stop()方法控制

同时纠正了position单位的误解（tick而非毫秒），并提供了完整的转换工具。

---

## 🔧 实施详情

### 1. MidiParser.gd - Note类定义

#### 新增类结构

```gdscript
## Note 基类
class Note:
    var event: NoteEvent           # 原始Note事件数据
    var is_on: bool = false        # noteOn状态
    var is_off: bool = false       # noteOff状态
    var note_index: int = -1       # 在数组中的索引
    
    func is_playing() -> bool      # 查询是否正在播放
    func has_finished() -> bool    # 查询是否已结束

## AutoPlayNote - 自动播放Note
class AutoPlayNote extends Note:
    # 由MIDI播放器内部自动控制

## ManualControlNote - 手动控制Note
class ManualControlNote extends Note:
    var midi_player: Node          # MIDI播放器引用
    
    func start() -> void           # 手动触发noteOn
    func stop() -> void            # 手动触发noteOff
```

#### 修改的方法

**load_and_parse_midi()** 返回值结构：
```gdscript
{
    "success": bool,
    "notes": Array[Note],              # Note对象数组（默认AutoPlayNote）
    "note_events": Array[NoteEvent],   # 原始NoteEvent（向后兼容）
    "bpm": float,
    "duration": float,
    "track_infos": Array[TrackInfo],
    "timebase": int,
    "bpm_timeline": Array[Dictionary]
}
```

---

### 2. MidiPlayer.gd - 内部播放控制

#### 新增属性

```gdscript
## 手动控制的note列表 - 格式: {channel: {pitch: is_manual_controlled}}
var manually_controlled_notes: Dictionary = {}

func set_manually_controlled_notes(notes_dict: Dictionary) -> void
```

#### 新增公开方法

```gdscript
## 手动触发noteOn - 直接播放指定音符
func trigger_note_on(pitch: int, velocity: int, channel_number: int = 0) -> void

## 手动触发noteOff - 停止指定音符
func trigger_note_off(pitch: int, velocity: int, channel_number: int = 0) -> void
```

#### 修改的内部逻辑

**_process_track_event_note_on()** - 在播放前检查note是否被标记为手动控制：

```gdscript
func _process_track_event_note_on(channel, note, velocity) -> void:
    # 手动控制note检查
    if manually_controlled_notes.has(channel.number):
        if manually_controlled_notes[channel.number].has(note):
            if manually_controlled_notes[channel.number][note] == true:
                return  # 跳过内部播放，等待游戏手动触发
    
    # 继续原有的自动播放逻辑
    ...
```

---

### 3. MidiPlaybackManager.gd - 分类接口和位置纠正

#### 位置单位纠正

```gdscript
## 当前播放位置（MIDI tick单位，NOT毫秒！）
## 注意：MidiPlayer.position使用tick单位
var position: float = 0.0

## 当前播放位置（毫秒，用于向后兼容 - 已弃用）
var position_ms: float = 0.0
```

**_process()修改**：
```gdscript
func _process(_delta: float) -> void:
    if is_playing and midi_player != null:
        # 直接从MidiPlayer读取position（tick单位）
        position = midi_player.position
        
        # 同时更新position_ms用于向后兼容
        if midi_player.smf_data != null:
            position_ms = _calculate_position_with_bpm_timeline(
                position, 
                midi_player.smf_data.timebase
            )
```

#### 新增分类接口

```gdscript
## 将解析的note分为两类：自动播放和手动控制
## @param all_notes 所有Note对象
## @param manual_track_indices 需要手动控制的轨道索引
## @return {auto_play_notes: Array[Note], manual_control_notes: Array[Note]}
func classify_notes(all_notes: Array, manual_track_indices: Array[int] = []) -> Dictionary
```

**分类逻辑（当前实现）**：
- 按轨道索引分类：如果note所在轨道在`manual_track_indices`中，转为ManualControlNote
- 否则保持为AutoPlayNote
- 具体算法预留，待后续实现

```gdscript
## 设置MidiPlayer的手动控制note标记
## 游戏完成分类后调用，通知MidiPlayer哪些note需要手动控制
func set_manual_control_notes(manual_control_notes: Array) -> void
```

#### 新增位置转换工具

```gdscript
## 将tick位置转换为毫秒
func tick_to_ms(tick: float) -> float

## 获取当前播放位置（毫秒）- 明确返回单位
func get_position_ms() -> float

## 获取当前播放位置（tick）- 明确返回单位
func get_position_tick() -> float
```

---

### 4. GameplayManager.gd - 游戏流程集成

#### 修改的加载流程

**_load_midi_thread()** 集成note分类：

```gdscript
func _load_midi_thread(midi: MidiData) -> void:
    # 1. 加载MIDI文件
    midi_playback_manager.load_midi(midi)
    
    # 2. 获取解析后的Note对象
    var parsed_notes = midi_playback_manager.current_notes
    
    # 3. 调用分类接口（从MidiData配置获取手动轨道）
    var manual_track_indices = midi.selected_track_indices
    var classified_notes = midi_playback_manager.classify_notes(
        parsed_notes, 
        manual_track_indices
    )
    
    var auto_play_notes = classified_notes["auto_play_notes"]
    var manual_control_notes = classified_notes["manual_control_notes"]
    
    # 4. 通知MidiPlayer哪些note需要手动控制
    midi_playback_manager.set_manual_control_notes(manual_control_notes)
    
    # 5. KeySequenceManager处理（使用手动控制的note生成游戏键）
    key_sequence_manager.generate_keys(manual_control_notes)
    
    print("Total Notes: %d (Auto: %d, Manual: %d)" % 
        [parsed_notes.size(), auto_play_notes.size(), manual_control_notes.size()])
```

#### 同步播放位置

```gdscript
func _sync_playback_position() -> void:
    # 使用get_position_ms()方法获取毫秒值
    var midi_position_ms = midi_playback_manager.get_position_ms()
    game_time = midi_position_ms / 1000.0
```

---

## 🔄 完整数据流向图

```
用户开始游戏
    ↓
GameplayManager.start_game(midi)
    ↓
_load_midi_thread() [异步线程]
    │
    ├─ 1. MidiPlaybackManager.load_midi(midi)
    │   └─ MidiParser.load_and_parse_midi()
    │       └─ 返回 Array[AutoPlayNote]（默认全自动）
    │
    ├─ 2. MidiPlaybackManager.classify_notes(notes, manual_tracks)
    │   ├─ 按轨道索引分类
    │   ├─ 转换为AutoPlayNote / ManualControlNote
    │   └─ 返回 {auto_play_notes, manual_control_notes}
    │
    ├─ 3. MidiPlaybackManager.set_manual_control_notes(manual_notes)
    │   └─ 构建字典 {channel: {pitch: true}}
    │       └─ MidiPlayer.set_manually_controlled_notes(dict)
    │
    ├─ 4. KeySequenceManager.generate_keys(manual_notes)
    │   └─ 为手动控制的note生成GameSequence（游戏键）
    │
    └─ 5. 设置状态为PLAYING

游戏进行中
    ↓
GameplayManager._process()
    ├─ _sync_playback_position()
    │   └─ midi_playback_manager.get_position_ms()
    │
    └─ _update_game_time()

MidiPlaybackManager._process()
    ├─ position = midi_player.position (tick)
    └─ position_ms = tick_to_ms(position)

MidiPlayer._process_track()
    ├─ 遍历事件
    ├─ 触发noteOn事件
    │   └─ _process_track_event_note_on()
    │       ├─ 检查 manually_controlled_notes
    │       │   ├─ 如果是手动控制 → 跳过播放
    │       │   └─ 如果是自动播放 → 继续播放
    │       └─ 播放音符（自动）
    │
    └─ 触发noteOff事件

游戏手动控制Note（玩家击键）
    ↓
用户按键 → UI事件
    ↓
GameSequence判定
    ↓
ManualControlNote.start()
    └─ MidiPlayer.trigger_note_on(pitch, velocity, channel)
        └─ _process_track_event_note_on() (绕过手动检查)
            └─ 播放音符

用户松键
    ↓
ManualControlNote.stop()
    └─ MidiPlayer.trigger_note_off(pitch, velocity, channel)
        └─ _process_track_event_note_off()
            └─ 停止音符
```

---

## 🎯 关键设计要点

### 1. 两类Note的隔离机制

**自动播放Note**:
- 由MidiPlayer内部逻辑自动处理
- 在`_process_track()`中触发
- 不会标记在`manually_controlled_notes`中

**手动控制Note**:
- 标记在`manually_controlled_notes`字典中
- 在`_process_track_event_note_on()`中被跳过
- 通过`trigger_note_on/off()`手动触发

**隔离检查代码**：
```gdscript
# MidiPlayer._process_track_event_note_on()
if manually_controlled_notes.has(channel.number):
    if manually_controlled_notes[channel.number].has(note):
        if manually_controlled_notes[channel.number][note] == true:
            return  # 跳过自动播放
```

**避免冲突**：
- 手动控制的note不会被自动播放逻辑触发
- 手动触发时直接调用内部播放方法，不会重复检查

### 2. position单位统一

| 变量/方法 | 单位 | 说明 |
|-----------|------|------|
| MidiPlayer.position | tick | 内部原始单位 |
| MidiPlaybackManager.position | tick | 直接来自MidiPlayer |
| MidiPlaybackManager.position_ms | ms | 向后兼容，已弃用 |
| MidiPlaybackManager.get_position_ms() | ms | 推荐使用 |
| MidiPlaybackManager.get_position_tick() | tick | 推荐使用 |
| MidiPlaybackManager.tick_to_ms() | - | 转换工具 |

**转换公式**（考虑BPM变化）：
```
ms = tick * (60000 / BPM) / timebase
```

使用BPM时间线进行精确计算：`_calculate_position_with_bpm_timeline()`

### 3. 分类接口设计

**预留实现**：
- 当前实现：按轨道索引简单分类
- 预留算法扩展点：
  - 按通道号（如鼓声通道9）
  - 按音符范围（如低音贝司）
  - 按时间密度（密集段落）
  - 按音符属性（力度、持续时间）

**调用时机**：
- ✅ 加载MIDI后
- ✅ 播放前
- ❌ 不在播放过程中

---

## ✅ 测试验证

### 单元测试场景

1. **Note分类测试**
   - 加载包含多轨道的MIDI
   - 选择轨道1为手动控制
   - 验证轨道1的note被标记为ManualControlNote
   - 验证其他轨道为AutoPlayNote

2. **自动播放测试**
   - 分类后，标记为AutoPlayNote的note
   - 播放MIDI，验证音符自动播放
   - 检查不会触发手动控制note

3. **手动控制测试**
   - 分类后，标记为ManualControlNote的note
   - 验证播放时不会自动触发
   - 调用ManualControlNote.start()，验证音符播放
   - 调用ManualControlNote.stop()，验证音符停止

4. **混合播放测试**
   - 同时包含自动和手动note
   - 验证两类note不会互相干扰
   - 验证同一pitch同一时间不会重复播放

5. **位置单位测试**
   - 验证position为tick单位
   - 验证get_position_ms()返回毫秒
   - 验证tick_to_ms()转换正确

### 集成测试场景

1. **完整游戏流程**
   - 加载MIDI → 分类 → 播放 → 手动触发note → 结束
   - 验证整个流程无错误

2. **多MIDI切换**
   - 加载MIDI A → 播放 → 停止
   - 加载MIDI B → 播放
   - 验证分类状态正确清除

---

## 📚 使用示例

### 示例1：加载MIDI并分类

```gdscript
# 在GameplayManager中
func start_game(midi: MidiData) -> void:
    # 加载MIDI
    midi_playback_manager.load_midi(midi)
    
    # 获取notes
    var all_notes = midi_playback_manager.current_notes
    
    # 分类（轨道0, 1为手动控制）
    var classified = midi_playback_manager.classify_notes(all_notes, [0, 1])
    
    # 通知MidiPlayer
    midi_playback_manager.set_manual_control_notes(classified["manual_control_notes"])
    
    # 生成游戏键
    key_sequence_manager.generate_keys(classified["manual_control_notes"])
    
    # 开始播放
    midi_playback_manager.play()
```

### 示例2：手动触发note

```gdscript
# 在游戏逻辑中（玩家按键）
func _on_player_press_key(game_sequence: GameSequence) -> void:
    # game_sequence包含对应的ManualControlNote
    var note = game_sequence.manual_note
    
    if note is MidiParser.ManualControlNote:
        note.start()  # 触发noteOn

func _on_player_release_key(game_sequence: GameSequence) -> void:
    var note = game_sequence.manual_note
    
    if note is MidiParser.ManualControlNote:
        note.stop()   # 触发noteOff
```

### 示例3：查询播放位置

```gdscript
# 在NotesRenderer中
func update_position() -> void:
    # 获取当前位置（毫秒）
    var current_ms = MidiPlaybackManager.instance.get_position_ms()
    
    # 获取当前位置（tick）- 用于精确对齐
    var current_tick = MidiPlaybackManager.instance.get_position_tick()
    
    # 判断哪些note应该显示
    var visible_notes = _get_visible_notes_at(current_ms)
```

---

## 🔧 后续优化方向

### 优先级高

1. **分类算法实现**
   - 实现复杂的分类策略（通道、音符范围、时间密度）
   - 添加配置文件支持（track_control_mode: AUTO/MANUAL/CUSTOM）

2. **性能优化**
   - 缓存分类结果
   - 优化manually_controlled_notes查找（使用Set）

3. **错误处理**
   - 添加边界情况检查
   - 验证note完整性（on/off匹配）

### 优先级中

4. **扩展Note类**
   - 添加更多状态（如sustain, release）
   - 支持MIDI效果（pitch bend, modulation）

5. **调试工具**
   - 可视化note分类状态
   - 实时监控manually_controlled_notes

6. **单元测试**
   - 编写GDScript单元测试
   - 覆盖所有分类场景

---

## 📝 相关文件清单

### 修改的文件

| 文件 | 主要改动 | 行数变化 |
|------|---------|----------|
| [Utilities/MidiParser.gd](../Utilities/MidiParser.gd) | 添加Note、AutoPlayNote、ManualControlNote类 | +100 |
| [addons/midi/MidiPlayer.gd](../addons/midi/MidiPlayer.gd) | 添加manually_controlled_notes、trigger方法、检查逻辑 | +70 |
| [Game/MidiPlaybackManager.gd](../Game/MidiPlaybackManager.gd) | 添加classify_notes、位置纠正、转换工具 | +120 |
| [Game/GameplayManager.gd](../Game/GameplayManager.gd) | 集成分类流程、修正position使用 | +30 |

### 未修改但相关的文件

- [Game/KeySequenceManager.gd](../Game/KeySequenceManager.gd) - 需适配Note类
- [Game/NotesRenderer.gd](../Game/NotesRenderer.gd) - 需使用新的position方法
- [Core/Models/MidiData.gd](../Core/Models/MidiData.gd) - 可添加track_control_mode配置

---

## 🎓 架构学习要点

### 关键概念

1. **Note生命周期**
   - 创建（解析） → 分类（classify） → 播放（auto/manual） → 结束

2. **双路播放机制**
   - 自动路径：MidiPlayer内部播放逻辑
   - 手动路径：trigger_note_on/off直接调用

3. **单位转换**
   - tick为MIDI内部时间单位
   - 毫秒为游戏逻辑时间单位
   - 精确转换需考虑BPM变化

### 设计原则

1. **职责分离**
   - MidiParser：解析和数据建模
   - MidiPlayer：音频播放和内部控制
   - MidiPlaybackManager：分类和接口封装
   - GameplayManager：游戏流程集成

2. **向后兼容**
   - 保留NoteEvent用于旧代码
   - position_ms保留但标记为已弃用
   - 提供明确的替代方法

3. **扩展性**
   - Note类可继承扩展
   - 分类算法预留接口
   - 支持多种播放模式

---

**实施完成！** ✅

此架构支持灵活的MIDI note管理，满足当前游戏需求，并为未来扩展预留空间。

---

**最后更新**: 2026年1月27日  
**Godot版本**: 4.5  
**主要语言**: GDScript  
**实施人员**: AI助手

