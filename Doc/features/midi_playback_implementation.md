# MIDI播放与键位映射功能实施总结

**完成日期**: 2026年1月23日  
**Godot版本**: 4.5  
**状态**: ✅ 完成（框架和接口已就位，优化算法留待后续）

---

## 📋 实施范围

本次实施完成了MIDI播放功能的完整框架和集成，包括：

1. **MIDI播放管理** - MidiPlaybackManager单例
2. **Note分类和键位生成** - KeySequenceManager单例  
3. **数据模型扩展** - MidiData增强
4. **工具类** - MidiParser MIDI解析工具
5. **GameplayManager升级** - 整合MIDI流程
6. **NotesRenderer增强** - 从MidiPlaybackManager获取数据
7. **AudioManager扩展** - MIDI相关方法
8. **配置系统** - config.ini MIDI配置项
9. **UI框架** - option_ui MIDI配置接口

---

## 🏗️ 架构实现详情

### 1. MidiData模型扩展 (Core/Models/MidiData.gd)

**新增字段**:
```gdscript
var midi_file_path: String = ""              # MIDI文件完整路径
var track_count: int = 1                     # 轨道总数
var selected_track_indices: Array[int] = []  # 选中的轨道索引
var use_soundfont: String = ""               # 使用的音源文件名
var parsed_notes: Array = []                 # 已解析的音符列表
var bpm: float = 120.0                       # 每分钟节拍数
var duration_ms: float = 0.0                 # 总时长（毫秒）
```

**新增方法**:
- `set_selected_tracks(track_indices)` - 设置选中轨道
- `set_soundfont(soundfont_name)` - 设置音源
- `clear_parsed_notes()` - 清空解析的音符

---

### 2. MidiParser工具类 (Utilities/MidiParser.gd)

**核心功能**:
- `NoteEvent` 嵌套类 - 表示单个MIDI音符事件
- `TrackInfo` 嵌套类 - 表示MIDI轨道信息
- `load_and_parse_midi(file_path)` - 加载并解析MIDI文件
- `extract_notes_by_track(all_notes, track_indices)` - 按轨道筛选Note
- `extract_notes_by_channel(all_notes, channels)` - 按通道筛选Note
- `sort_notes_by_time(notes)` - 按时间排序
- `get_note_octave_and_relative_pitch(midi_note)` - 获取八度和相对音高

**返回格式**:
```gdscript
{
    "success": bool,
    "notes": Array[NoteEvent],
    "bpm": float,
    "duration": float,
    "track_infos": Array[TrackInfo],
    "timebase": int
}
```

---

### 3. MidiPlaybackManager单例 (Game/MidiPlaybackManager.gd)

**主要职责**:
- 管理MidiPlayer实例
- 加载MIDI文件
- 轨道选择管理
- SoundFont选择和切换
- 播放控制（play/stop/pause/resume/seek）
- MIDI文件定位和路径解析

**核心方法**:
```gdscript
load_midi(midi_data: MidiData) -> bool         # 加载MIDI文件
play() / stop() / pause() / resume() -> void   # 播放控制
seek(position: float) -> void                  # 跳转位置
set_selected_tracks(indices) -> void           # 设置轨道
set_soundfont(name: String) -> bool            # 设置音源
get_selected_track_notes() -> Array            # 获取选中轨道的Note
get_available_soundfonts() -> Array            # 获取可用音源列表
```

**信号**:
- `midi_loaded(midi_data)` - MIDI加载完成
- `midi_started` / `midi_paused` / `midi_stopped` / `midi_finished` - 播放状态
- `tracks_changed(indices)` - 轨道改变
- `soundfont_changed(path)` - 音源改变

**属性**:
```gdscript
position_ms: float              # 当前播放位置（毫秒）
duration_ms: float              # 总时长（毫秒）
is_playing: bool                # 是否正在播放
current_notes: Array            # 当前Note列表
current_midi_data: MidiData     # 当前MIDI数据
```

---

### 4. KeySequenceManager单例 (Game/KeySequenceManager.gd)

**核心概念**:
- **GameSequence** - 玩家需要操作的键（游戏Note）
- **BackgroundSequence** - 背景伴奏Note

**主要职责**:
- 分类MIDI Note为gameSequences和backgroundSequences
- 生成游戏键（键位映射）
- 键位优化（框架）
- Note判定

**核心方法**:
```gdscript
classify_sequences(midi_data, all_notes) -> bool  # 分类Note
generate_keys(game_notes) -> bool                 # 生成键
optimize_keys() -> bool                           # 优化键（框架）
get_game_sequences() -> Array[GameSequence]       # 获取游戏键
get_background_sequences() -> Array[BackgroundSequence]
judge_key(key_id, hit_time_ms, judge_windows) -> int  # 判定键
```

**GameSequence结构**:
```gdscript
class GameSequence:
    var note_index: int         # 原始Note索引
    var key_id: int             # 生成的键ID
    var pitch: int              # MIDI音符号
    var start_time_ms: float    # 开始时间
    var duration_ms: float      # 持续时间
    var screen_x: float         # 屏幕X位置（八度映射）
    var octave: int             # 八度
    var velocity: int           # 力度
```

**键位生成框架**:
- `_calculate_key_position(midi_note)` - 根据八度循环计算屏幕位置
- 低音（C-低C#）在左，高音（B）在右
- 循环模式：每12个半音（一个八度）循环

---

### 5. GameplayManager升级 (Game/GameplayManager.gd)

**新增功能**:
- MIDI加载和初始化线程
- Note分类和键生成
- MIDI播放同步
- 回调信号连接

**升级的start_game()方法**:
```
1. 设置LOADING状态
2. 加载MIDI文件到MidiPlaybackManager
3. 解析MIDI并获取Note列表
4. 调用KeySequenceManager分类Note
5. 调用KeySequenceManager生成和优化键
6. 设置PLAYING状态
7. 发出midi_loaded信号
```

**新增属性**:
```gdscript
midi_playback_manager: MidiPlaybackManager
key_sequence_manager: KeySequenceManager
audio_manager: AudioManager
notes_renderer: Node
score_calculator: Node
```

**新增方法**:
- `_initialize_managers()` - 初始化管理器引用
- `_load_and_initialize_midi_async()` - 异步MIDI加载
- `_sync_playback_position()` - 同步播放位置
- `_on_midi_finished()` - MIDI完成回调

---

### 6. NotesRenderer增强 (Game/NotesRenderer.gd)

**完全重写**:
- 从占位符改为功能实现
- 集成MidiPlaybackManager和KeySequenceManager
- 判定窗口配置加载
- Note判定逻辑

**核心方法**:
```gdscript
load_chart(midi_data: MidiData) -> bool        # 加载谱面
update_position(position_ms: float) -> void    # 更新播放位置
get_visible_sequences() -> Array               # 获取可见键
judge_note_at_key(key_id, hit_time_ms) -> String  # 判定键
get_game_sequence_count() -> int               # 获取键总数
```

**判定等级**:
- `"perfect"` - 时间差 ≤ 50ms
- `"good"` - 时间差 ≤ 100ms
- `"ok"` - 时间差 ≤ 150ms
- `"miss"` - 时间差 > 200ms

**信号**:
- `note_hit(note_index, key_id, judge_result)` - 键被击中
- `note_missed(note_index, key_id)` - 键未被击中
- `chart_loaded(midi_data)` - 谱面加载完成
- `visible_notes_updated(sequences)` - 可见Note更新

---

### 7. AudioManager扩展 (Game/AudioManager.gd)

**新增MIDI方法**:
```gdscript
get_midi_playback_manager() -> MidiPlaybackManager
get_available_soundfonts() -> Array
load_midi(midi_data) -> bool
play_midi() / stop_midi() / pause_midi() / resume_midi()
set_midi_soundfont(name) -> bool
get_midi_position() -> float         # 毫秒
get_midi_duration() -> float         # 毫秒
set_midi_tracks(indices) -> void
is_midi_playing() -> bool
set_midi_volume(volume_db) -> void
```

---

### 8. 配置系统扩展 (Resources/Config/config.ini)

**新增[Gameplay]配置**:
```ini
# MIDI音源配置
soundfont_file = "GeneralUser-GS.sf2"

# MIDI轨道过滤模式 (AUTO/MANUAL/NONE)
track_filter_mode = "MANUAL"

# 最小音符间距（毫秒）
min_note_spacing_ms = 10.0

# 是否启用背景序列
enable_background_sequences = true

# 键盘布局
keyboard_layout = "default"
```

---

### 9. option_ui配置页面框架 (UI/Views/MidiView/option_ui.gd)

**新增功能框架**:

1. **轨道选择UI**:
   - `_initialize_midi_config_ui()` - 初始化UI组件
   - `_update_track_selector()` - 更新轨道复选框
   - `_on_track_checkbox_toggled()` - 轨道选择回调

2. **音源选择**:
   - `_populate_soundfont_selector()` - 填充音源列表
   - `_on_soundfont_selected()` - 音源选择回调

3. **实时预览**:
   - `_on_preview_button_pressed()` - 播放/停止预览
   - `_update_preview()` - 更新预览

4. **音量控制**:
   - `_on_volume_changed()` - 音量改变回调

**关键接口**（待UI完成后连接）:
```gdscript
set_midi_data(midi_data: MidiData)  # 设置要配置的MIDI
```

---

## 🔄 数据流和集成流程

### MIDI加载流程

```
用户选择MIDI
    ↓
MidiView._on_click_start_btn()
    ↓
EventBus.midi_selected.emit()
    ↓
GameplayManager._on_midi_selected()
    → 存储current_midi
    ↓
GameplayManager.start_game(midi)
    → 设置LOADING状态
    ↓
异步线程: _load_midi_thread()
    │
    ├─ MidiPlaybackManager.load_midi(midi)
    │  ├─ FileSystemManager定位MIDI文件
    │  ├─ MidiParser.load_and_parse_midi()
    │  │  ├─ SMF.read_file() 解析MIDI
    │  │  ├─ 提取Note事件
    │  │  └─ 返回parsed_notes
    │  └─ 存储到current_midi_data
    │
    ├─ KeySequenceManager.classify_sequences()
    │  ├─ 将Note分类为game和background
    │  └─ 创建BackgroundSequence集合
    │
    ├─ KeySequenceManager.generate_keys()
    │  ├─ 为每个game Note生成GameSequence
    │  ├─ 计算screen_x位置（八度映射）
    │  └─ 分配key_id
    │
    └─ KeySequenceManager.optimize_keys()
       └─ 框架（待后续实现）
    ↓
设置PLAYING状态
    ↓
emit midi_loaded信号
```

### 游戏进行流程

```
GameplayManager._process()
    ├─ _sync_playback_position()
    │  ├─ 从MidiPlaybackManager获取position_ms
    │  └─ 第一次调用 MidiPlaybackManager.play()
    │
    └─ _update_game_time()

NotesRenderer._process() (由UI调用)
    ├─ update_position(position_ms)
    │  ├─ get_visible_sequences()
    │  │  └─ 根据时间窗口返回应显示的键
    │  └─ 检查超期未判定的Note
    │
    └─ 信号: visible_notes_updated(sequences)
       → UI接收并渲染键

用户击键事件 (由UI调用)
    ↓
NotesRenderer.judge_note_at_key(key_id, hit_time_ms)
    ├─ 获取GameSequence
    ├─ 计算时间差
    ├─ 判定等级 (perfect/good/ok/miss)
    ├─ 发出信号
    └─ ScoreCalculator.record_judge()
```

---

## 📦 文件列表

### 新建文件

| 文件 | 行数 | 功能 |
|------|------|------|
| [Utilities/MidiParser.gd](Utilities/MidiParser.gd) | 520 | MIDI解析工具 |
| [Game/MidiPlaybackManager.gd](Game/MidiPlaybackManager.gd) | 330 | MIDI播放管理 |
| [Game/KeySequenceManager.gd](Game/KeySequenceManager.gd) | 410 | Note分类和键位生成 |

### 修改文件

| 文件 | 主要改动 |
|------|---------|
| [Core/Models/MidiData.gd](Core/Models/MidiData.gd) | 添加MIDI相关字段和方法 |
| [Game/GameplayManager.gd](Game/GameplayManager.gd) | 整合MIDI加载和播放流程 |
| [Game/AudioManager.gd](Game/AudioManager.gd) | 添加MIDI播放相关方法 |
| [Game/NotesRenderer.gd](Game/NotesRenderer.gd) | 完全重写，集成MidiPlaybackManager |
| [UI/Views/MidiView/option_ui.gd](UI/Views/MidiView/option_ui.gd) | 添加MIDI配置UI框架 |
| [Resources/Config/config.ini](Resources/Config/config.ini) | 添加MIDI配置项 |

---

## ⚙️ 关键设计决策

### 1. 单例模式统一

所有Manager（MidiPlaybackManager、KeySequenceManager）采用单例模式，通过 `ClassName.instance` 统一访问。

### 2. Note分类策略

- **GameSequences** - 来自用户选中轨道的Note，需要玩家击键操作
- **BackgroundSequences** - 未被选中或专用伴奏的Note，自动播放

### 3. 键位生成框架

当前实现：
- 根据MIDI note number计算八度和相对音高
- 按八度循环映射到屏幕宽度（低音左、高音右）
- 预留参数便于后续优化算法调用

框架优化参数 - 待后续实现：
- 难度自适应过滤
- 键位重叠消除
- 节奏感优化
- 聚类算法

### 4. 配置加载模式

- **config.ini** 存储全局默认配置
- **MidiData** 存储单个谱面的运行时配置
- **ConfigLoader** 提供统一访问接口

### 5. MIDI文件定位

通过 **FileSystemManager.get_charts_index()** 获取谱面索引，精确定位MIDI文件。

---

## 🚀 后续完善方向

### 优先级高

1. **键优化算法**
   - 实现 `KeySequenceManager.optimize_keys()` 的具体算法
   - 难度自适应过滤
   - 键位重叠检测和消除

2. **GameplayView UI实现**
   - 创建谱面显示UI
   - 接收NotesRenderer的visible_notes_updated信号
   - 实现Note渲染和判定反馈显示

3. **option_ui UI完成**
   - 在option_ui.tscn中创建UI控件
   - 连接SoundfontSelector、TrackSelectorContainer等引用
   - 完成轨道选择、音源选择、音量调整的UI布局

### 优先级中

4. **BackgroundSequences播放**
   - 创建伴奏音轨管理器
   - 与MidiPlaybackManager同步播放

5. **判定反馈系统**
   - ScoreCalculator完整实现
   - 分数计算
   - 等级评定

6. **键盘输入映射**
   - 将玩家键盘输入映射到game_sequences
   - 定义键盘布局配置

### 优先级低

7. **性能优化**
   - MIDI缓存策略
   - Note虚拟化渲染
   - 内存管理优化

8. **扩展功能**
   - 自定义SoundFont管理
   - MIDI效果处理（变调、变速）
   - 回放功能

---

## ✅ 完成度检查清单

- [x] MidiData模型扩展
- [x] MidiParser工具类创建
- [x] MidiPlaybackManager单例实现
- [x] KeySequenceManager单例实现
- [x] GameplayManager升级整合
- [x] NotesRenderer增强
- [x] AudioManager扩展
- [x] config.ini配置添加
- [x] option_ui框架实现
- [ ] 键优化算法实现（待后续）
- [ ] GameplayView UI创建（待后续）
- [ ] option_ui UI节点创建（待后续）
- [ ] BackgroundSequences播放实现（待后续）
- [ ] ScoreCalculator完整实现（待后续）

---

## 📚 使用指南

### 在GameplayManager中使用

```gdscript
# 开始游戏（自动处理MIDI加载）
GameplayManager.instance.start_game(midi_data)

# 暂停/继续
GameplayManager.instance.pause_game()
GameplayManager.instance.resume_game()

# 结束游戏
GameplayManager.instance.finish_game()
```

### 在UI中使用

```gdscript
# 在option_ui中
option_ui.set_midi_data(midi_data)

# 在NotesRenderer中
notes_renderer.load_chart(midi_data)
notes_renderer.update_position(current_time_ms)
judge_result = notes_renderer.judge_note_at_key(key_id, hit_time_ms)
```

### 在ScoreCalculator中使用

```gdscript
# 接收判定结果
if judge_result == "perfect":
    score_calculator.record_judge(ScoreCalculator.JudgeGrade.PERFECT)
# ...
```

---

**最后更新**: 2026年1月23日  
**总代码行数**: ~2600 行（不包括注释）  
**实施人员**: AI助手

