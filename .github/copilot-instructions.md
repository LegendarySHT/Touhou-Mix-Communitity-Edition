# Touhou Mix 社区版 - AI 编程助手指南

**项目**: Godot 4.5 节奏游戏（GDScript）  
**状态**: 核心架构完成；UI/MIDI/GameplayManager 系统全部集成  
**更新**: 2026-02-02  
**核心完成度**: 80% - 框架完成，UI 界面 & 游戏逻辑待完善

## ⚡ 5 分钟快速概览

**分层架构**: Core（数据）→ Game（业务）→ UI（视图）  
**通信方式**: 单例 Manager 直接调用 + EventBus 信号  
**数据流向**: FileSystemManager → DataManager → SortingEngine → UI Views  
**初始化顺序很关键** - Main._ready() 遵循严格的 13 步初始化（见 Main.gd）

## 🏗️ 关键架构模式

### 单例 Manager 模式（统一访问）
所有 Manager 都是单例，通过 `ClassName.instance` 访问：
```gdscript
# ✅ 正确方式
var data = DataManager.instance
var midi_player = MidiPlaybackManager.instance
var ui_state = UIStateManager.instance

# ❌ 错误 - 不要硬编码路径
var manager = get_node("/root/Main/DataManager")
```

**关键 Manager**:
- `DataManager.instance` - 访问专辑/歌曲/MIDI 树（albums/songs/midis 字典）
- `EventBus.instance` - 发送/监听全局信号
- `FileSystemManager.instance` - 谱面索引与资源扫描
- `MidiPlaybackManager.instance` - MIDI 文件加载与轨道选择
- `KeySequenceManager.instance` - Note 分类与键位生成
- `GameplayManager.instance` - 游戏状态与流程控制
- `NotesRenderer.instance` - 键位判定与渲染框架
- `ScoreCalculator.instance` - 分数计算与等级评定
- `UIStateManager.instance` - UI 状态机与导航历史
- `AnimationManager.instance` - 所有 Tween 管理

### 数据加载工作流（关键：FileSystemManager → DataManager）
```gdscript
# Main._ready() 的初始化顺序
1. FileSystemManager.initialize_directory_structure()  # 后台线程：创建 user:// 目录，复制默认谱面
2. DataManager.instance 创建（等待下一步）
3. Main._load_midi_data()
   ├─ 等待 FileSystemManager.resources_scanned = true  # 最多等 300 帧
   └─ 调用 DataManager.load_all_midis_async()
      └─ 线程轮询: 等 FileSystemManager.is_initialized
         └─ 获取 charts_index，逐个创建 MidiData 对象
4. data_loaded 信号 → UI 开始显示数据
```

**错误原因**: 若 UI 代码在 DataManager 加载前查询数据，会获取空结果。始终监听 `data_loaded` 或 `EventBus.data_loaded_complete`。

### MIDI 数据结构与索引
```gdscript
# FileSystemManager 维护的索引
charts_index: Dictionary  # { chart_id: { "folder_name", "data": {...json...} } }

# DataManager 构建的树结构
albums: Dictionary[String, AlbumData]        # Album ID → 专辑对象
songs: Dictionary[String, SongData]          # Song ID → 歌曲对象
midis: Dictionary[String, MidiData]          # MIDI ID → 谱面对象
midi_tree: Dictionary                        # AlbumID → SongID → [MidiID]

# 查询示例
var album = DataManager.instance.get_album_by_id(album_id)
var songs = DataManager.instance.get_songs_by_album(album_id)
var midis = DataManager.instance.get_midis_by_song(song_id)
```

### 游戏流程与 MIDI 整合（关键：GameplayManager → KeySequenceManager）
```gdscript
# 完整流程：用户选择 MIDI → 游戏加载 → Note 分类 → 键位生成 → 游戏进行
1. 用户选择 MIDI，MidiView 发出信号
2. EventBus.start_game_with.emit(midi_data)
3. GameplayManager.start_game(midi_data)
   ├─ 设置 LOADING 状态
   ├─ MidiPlaybackManager.load_midi(midi) - 加载 MIDI 文件
   │  ├─ FileSystemManager 定位 MIDI 文件路径
   │  ├─ MidiParser.load_and_parse_midi() 解析音符
   │  └─ 返回 parsed_notes 列表
   ├─ KeySequenceManager.classify_sequences() - 分类 Note
   │  ├─ 从选中轨道提取 GameSequences（玩家操作）
   │  └─ 剩余轨道作为 BackgroundSequences（伴奏）
   ├─ KeySequenceManager.generate_keys() - 生成键位
   │  ├─ 根据 MIDI pitch 计算屏幕 X 位置
   │  └─ 分配每个 GameSequence 唯一的 key_id
   └─ 设置 PLAYING 状态，开始游戏
```

### 关键游戏 Manager（新增）
```gdscript
# GameplayManager - 游戏流程控制（单例）
var state = GameplayManager.instance.current_state  # 获取游戏状态
GameplayManager.instance.start_game(midi_data)      # 启动游戏（自动触发加载→分类→生成→播放）
GameplayManager.instance.game_time_updated.connect(fn) # 监听时间更新
GameplayManager.instance.set_game_state(GameState.PAUSED)  # 暂停游戏

# KeySequenceManager - Note 分类与键位映射（单例）
var game_keys = KeySequenceManager.instance.game_sequences    # 玩家需操作的键列表
var bg_notes = KeySequenceManager.instance.background_sequences  # 背景伴奏列表
KeySequenceManager.instance.judge_key(key_id, hit_time_ms, judge_windows)  # 判定键位

# NotesRenderer - 谱面渲染与显示（单例）
NotesRenderer.instance.update_position(current_time_ms)  # 更新当前播放位置
var visible_keys = NotesRenderer.instance.get_visible_keys()  # 获取当前应显示的键

# ScoreCalculator - 分数计算（单例）
ScoreCalculator.instance.record_judge(JudgeGrade.PERFECT)  # 记录判定结果
var score_data = ScoreCalculator.instance.get_score_data()  # 获取最终分数数据
```

## 🔄 常见工作流

### 流程 1: 用户选择 MIDI，进入播放界面
```gdscript
# TrackView 监听进入信号
EventBus.instance.enter_track_view_with.connect(_load_midi)

# 加载 MIDI 到播放器
func _load_midi(midi: MidiData) -> void:
    MidiPlaybackManager.instance.load_midi(midi)  # 返回 bool
    # MidiPlaybackManager 内部：
    # 1. FileSystemManager 定位 MIDI 文件路径
    # 2. MidiParser.load_and_parse_midi() 解析，返回 parsed_notes
    # 3. KeySequenceManager 分类音符（game/background）
    # 4. 发出 midi_loaded 信号
```

### 流程 2: 排序和搜索 MIDI
```gdscript
# 不要在 View 中排序；使用 SortingEngine
var sorted = SortingEngine.instance.get_sorted_midis(
    all_midis,
    SortingEngine.SortField.DOWNLOAD_COUNT,
    SortingEngine.SortDirection.DESCENDING
)

# 搜索示例
var results = SortingEngine.instance.search_midis(all_midis, "Lost Word")
```

### 流程 3: UI 视图的标准结构
```gdscript
# Views/SomeView.gd 应该继承 BaseScrollList
extends BaseScrollList
class_name SomeView

@onready var data_manager = DataManager.instance
@onready var event_bus = EventBus.instance

func _ready() -> void:
    # 1. 等待数据加载完成
    event_bus.data_loaded_complete.connect(_on_data_ready)
    
    # 2. 连接选择事件
    event_bus.midi_selected.connect(_on_midi_selected)
    
    # 3. 初始化列表
    super._ready()

func _on_data_ready() -> void:
    # 现在可以安全地查询 DataManager
    var items = data_manager.get_all_albums()
    for item in items:
        create_and_add_item(item.id, "type_name")
```

### 流程 4: 游戏启动与 Note 判定（新）
```gdscript
# 用户点击"开始游戏"
func _on_start_game_btn_pressed() -> void:
    var midi = current_midi_selection
    EventBus.instance.start_game_with.emit(midi)
    UIStateManager.instance.change_state(UIStateManager.UIState.PLAY_VIEW)

# GameplayManager 自动处理整个流程
func _on_start_game(midi: MidiData) -> void:
    GameplayManager.instance.start_game(midi)  # 加载→分类→生成→开始

# 在 GameplayView 中处理判定
func _process(_delta) -> void:
    var position_ms = GameplayManager.instance.game_time * 1000
    NotesRenderer.instance.update_position(position_ms)
    
    # 用户击键时
    if Input.is_action_pressed("key_1"):
        var result = NotesRenderer.instance.judge_note_at_key(key_id, position_ms)
        ScoreCalculator.instance.record_judge(result)
```

## ⚠️ 常见陷阱与修复

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 获取到空数据 | View._ready() 时数据还未加载 | 监听 `data_loaded_complete` 信号后再查询 |
| MIDI 加载失败 | FileSystemManager 未初始化完成 | Main._load_midi_data() 等待 resources_scanned = true |
| 状态混乱 | 多处直接修改 UI 可见性 | 统一用 UIStateManager.change_state() |
| Tween 卡顿 | 直接创建 Tween 未管理 | 使用 AnimationManager.animate_*() |
| MIDI 未找到 | FileSystemManager 扫描失败 | 检查 user://files/Charts/ 目录权限 |
| 动画闪烁 | 页面切换时 UI 元素未同步 | AnimationManager 内部自动处理退场→进场，不要手动控制 |
| Note 时间错误 | 混淆 tick 和毫秒单位 | 使用 MidiPlaybackManager.get_position_ms() 统一获取毫秒 |
| 判定窗口漂移 | BPM 时间线计算错误 | MidiParser 已自动处理 BPM 变化，无需手工调整 |

## 📁 文件导航速查

| 任务 | 查看文件 | 关键方法 |
|------|---------|---------|
| 初始化流程 | [Main.gd](../Main.gd) | _initialize_core_systems() - 13步初始化顺序 |
| 全局事件 | [Core/EventBus.gd](../Core/EventBus.gd) | 20+ 信号，emit_*() 便利函数 |
| 数据查询 | [Core/DataManager.gd](../Core/DataManager.gd) | get_all_albums(), get_midis_by_song(), load_all_midis_async() |
| 文件索引 | [Core/FileSystemManager.gd](../Core/FileSystemManager.gd) | charts_index, get_charts_index(), initialize_directory_structure() |
| UI状态 | [Core/UIStateManager.gd](../Core/UIStateManager.gd) | change_state(), UIState 枚举，state_changed 信号 |
| 排序搜索 | [Core/SortingEngine.gd](../Core/SortingEngine.gd) | get_sorted_midis(), search_midis(), 线程安全排序 |
| MIDI 播放 | [Game/MidiPlaybackManager.gd](../Game/MidiPlaybackManager.gd) | load_midi(), play(), set_soundfont(), classify_notes() |
| 键位管理 | [Game/KeySequenceManager.gd](../Game/KeySequenceManager.gd) | classify_sequences(), generate_keys(), GameSequence/BackgroundSequence |
| 游戏管理 | [Game/GameplayManager.gd](../Game/GameplayManager.gd) | start_game(), pause_game(), resume_game(), GameState 枚举 |
| 分数计算 | [Game/ScoreCalculator.gd](../Game/ScoreCalculator.gd) | record_judge(), calculate_grade(), get_score_data() |
| 谱面渲染 | [Game/NotesRenderer.gd](../Game/NotesRenderer.gd) | update_position(), get_visible_keys(), judge_windows 配置 |
| 标准 View | [UI/Views/MidiView/MidiView.gd](../UI/Views/MidiView/MidiView.gd) | BaseScrollList 继承示例，数据加载模式 |
| 动画库 | [UI/Animations/AnimationManager.gd](../UI/Animations/AnimationManager.gd) | animate_*() 系列（15+预设），_create_tween() 管理 |
| MIDI 解析 | [Utilities/MidiParser.gd](../Utilities/MidiParser.gd) | load_and_parse_midi(), Note/AutoPlayNote/ManualControlNote 类 |
| 配置加载 | [Utilities/ConfigLoader.gd](../Utilities/ConfigLoader.gd) | load_config(), get_value()，支持 ini 格式 |
| 日志系统 | [Utilities/Logger.gd](../Utilities/Logger.gd) | GameLogger.instance.info/warning/error()，标签式日志 |

## 🛠️ 实用代码片段

### 对象构建（新格式支持两种 JSON）
```gdscript
# MidiData.from_json() 支持两种格式：
# 格式1：嵌套 song/album 对象 → _process_nested_format()
# 格式2：扁平字段（sourceAlbumName 等）→ _process_flat_format()

# 不要手动构建 MidiData；让 DataManager 处理
var midi = MidiData.new()
midi.from_json(json_data)  # 自动识别格式
```

### 连接 EventBus 信号的标准做法
```gdscript
func _ready() -> void:
    if EventBus.instance == null:
        push_error("EventBus not initialized")
        return
    
    EventBus.instance.data_loaded_complete.connect(_on_data_loaded)
    EventBus.instance.midi_selected.connect(_on_midi_selected)

func _exit_tree() -> void:
    # 可选：自动断开（通过 CONNECT_ONE_SHOT 限制）
    # 或使用 disconnected_once 模式
    pass
```

### 日志记录（基于组件标签）
```gdscript
GameLogger.instance.info("User selected MIDI: %s" % midi.id, "MidiView")
GameLogger.instance.warning("MIDI not found", "DataManager")
GameLogger.instance.error("File access denied", "FileSystemManager")
```

### 动画最佳实践（AnimationManager）
```gdscript
# ✅ 正确：使用 AnimationManager 管理所有动画
AnimationManager.instance.animate_position(node, target_pos, 0.3, "node_move")
AnimationManager.instance.animate_fade_in(node, 0.5, "node_fade")

# ❌ 错误：直接创建 Tween 会导致无法管理
var tween = create_tween()  # 无法统一管理！

# 序列动画
var seq = AnimationManager.instance.create_sequence("combo")
seq.tween_property(node1, "modulate:a", 0.0, 0.2)
seq.tween_property(node2, "position", Vector2(0, 100), 0.3)
```

### MIDI 时间单位转换
```gdscript
# MidiPlaybackManager 中的时间单位需要注意：
# - position: tick 单位（MIDI tick，NOT 毫秒）
# - position_ms: 毫秒（使用 BPM 时间线计算）
# - get_position_ms(): 推荐方法，获取毫秒值

var midi_mgr = MidiPlaybackManager.instance
var ms_pos = midi_mgr.get_position_ms()  # 毫秒
var tick_pos = midi_mgr.position  # tick单位

# 寻找位置时使用毫秒
midi_mgr.seek(1000.0)  # 参数为毫秒
```

## 🎯 最佳实践

✅ **DO**:
- 通过 Manager.instance 访问单例
- 监听 EventBus 信号进行跨模块通信
- 在 UI 中继承 BaseScrollList/ListItemBase
- 使用 AnimationManager 进行所有动画
- 在 View._ready() 中连接数据加载信号

❌ **DON'T**:
- 硬编码节点路径（get_node("/root/...")）
- 在 _ready() 之前访问 Manager 实例
- 直接修改其他 Manager 的数据
- 使用 create_tween() 而不经过 AnimationManager
- 在 _process/_physics_process 中频繁排序大数据

## 📚 深入文档

- [Doc/ARCHITECTURE_OVERVIEW.md](../Doc/ARCHITECTURE_OVERVIEW.md) - 完整架构可视化
- [Doc/DEVELOPER_CHEATSHEET.md](../Doc/DEVELOPER_CHEATSHEET.md) - 常用代码速查
- [Doc/SINGLETON_PATTERN_GUIDE.md](../Doc/SINGLETON_PATTERN_GUIDE.md) - 单例详解
- [Doc/DATAMANAGER_LOADING_FIX.md](../Doc/DATAMANAGER_LOADING_FIX.md) - 数据加载修复
- [Doc/MIDI_PLAYBACK_IMPLEMENTATION.md](../Doc/MIDI_PLAYBACK_IMPLEMENTATION.md) - MIDI 系统集成

---

**最后更新**: 2026-02-02  
**Godot 版本**: 4.5 | **主要语言**: GDScript
