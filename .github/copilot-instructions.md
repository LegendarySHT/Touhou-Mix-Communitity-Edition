# Touhou Mix 社区版 - AI 编程助手指南

**项目**: Godot 4.5 节奏游戏（GDScript）  
**状态**: 核心架构完成；UI/MIDI/GameplayManager 系统全部集成  
**更新**: 2026-02-12 (v2)  
**核心完成度**: 85% - 框架完成，TrackView 编辑系统集成，配置管理系统完全重构（用户配置优先）

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
- `ConfigManager.instance` - 统一配置管理（单例，已单例化）✨
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
# Main._ready() 的初始化顺序（13步）
1. GameLogger.instance - 日志系统
2. ConfigManager.instance - 配置管理（新增：已单例化）
3. FileSystemManager - 文件系统初始化
   ├─ initialize_directory_structure() - 后台线程创建 user:// 目录
   └─ 并行复制默认谱面到 user://files/Charts/
4. EventBus.instance - 全局事件总线
5. UIStateManager.instance - UI 状态机
6. AnimationManager.instance - 动画管理
7. SortingEngine.instance - 排序引擎
8. DataManager.instance - 数据管理
9. GameplayManager - 游戏管理
10. AudioManager - 音频管理
11. MidiPlaybackManager - MIDI 播放
12. KeySequenceManager - 键序列管理
13. Main 调用 _load_midi_data()
    ├─ 等待 FileSystemManager.resources_scanned = true（最多等 300 帧）
    ├─ 调用 DataManager.load_all_midis_async()
    │  └─ 后台线程轮询：等 FileSystemManager.is_initialized
    │     └─ 获取 charts_index，逐个创建 MidiData 对象
    └─ 数据加载完成，发出 data_loaded 信号
```

**核心要点**:
- FileSystemManager 必须在 DataManager 之前初始化（数据依赖）
- `load_all_midis_async()` 在后台线程运行，不阻塞 UI
- 监听 `EventBus.data_loaded_complete` 确保数据就绪
- 所有 Manager 都是单例，通过 `ClassName.instance` 访问

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

### MIDI 后端系统（addons vs MeltySynth）
本项目支持两种 MIDI 播放后端，两者都实现 `IMidiPlaybackInterface` 接口：
- **addons 后端** - Godot 4.5 自带 MIDI 插件（占用 CPU 较高）
- **MeltySynth** - C# 高性能后端（编译版本提供）

```gdscript
# 后端选择（在 ConfigLoader 中配置）
var backend = ConfigLoader.instance.get_value("midi", "midi_backend")  # "addons" 或 "meltysynth"

# 动态切换后端（重新初始化播放器）
MidiPlaybackManager.instance.set_backend("meltysynth")
# ⚠️ 注意：backend_switching 锁防止在播放中切换导致音频中断

# 两个后端的音源加载都通过统一接口
MidiPlaybackManager.instance.set_soundfont(soundfont_path)  # 自动适配两个后端
```

**关键配置文件**:
- [Resources/Config/config.ini](../Resources/Config/config.ini) - MidiPlaybackManager 配置，channel/track 静音等
- [CSharp/MeltySynthPlayer.cs](../CSharp/MeltySynthPlayer.cs) - C# 后端实现

### 数据持久化模式
MIDI 编辑后的数据通过 JSON 持久化到 user:// 目录：
```gdscript
# TrackView 编辑完成后保存
TrackView.save_midi_to_json()
  ├─ FileSystemManager.get_json_file_path(chart_id) - 定位 JSON 路径
  ├─ MidiData.to_json() - 序列化数据
  └─ 写入 user://files/Charts/{chart_folder}/info.json

# 下次启动时 DataManager 自动重新加载
DataManager.load_all_midis_async()
  └─ FileSystemManager.get_charts_index() - 读取更新后的 JSON
```

### 关键游戏 Manager（新增）
```gdscript
# GameplayManager - 游戏流程控制（单例）
var state = GameplayManager.instance.current_state  # GameState 枚举
var game_time = GameplayManager.instance.game_time  # 秒为单位
GameplayManager.instance.start_game(midi_data)      # 启动游戏流程
GameplayManager.instance.set_game_state(GameState.PAUSED)  # 改变状态

# MidiPlaybackManager - MIDI 加载与播放（单例）
var loaded = MidiPlaybackManager.instance.load_midi(midi_data)  # 加载并解析
MidiPlaybackManager.instance.play()  # 播放
var position_ms = MidiPlaybackManager.instance.get_position_ms()  # 获取毫秒位置

# KeySequenceManager - Note 分类与键位映射（单例）
var game_keys = KeySequenceManager.instance.game_sequences    # 玩家需操作的键列表
var bg_notes = KeySequenceManager.instance.background_sequences  # 背景伴奏列表
KeySequenceManager.instance.classify_sequences(midi_data, notes)  # 分类
KeySequenceManager.instance.generate_keys()  # 生成键位映射

# NotesRenderer - 谱面渲染与判定（单例）
NotesRenderer.instance.load_chart(midi_data)  # 加载谱面
NotesRenderer.instance.update_position(current_time_ms)  # 更新当前位置
var visible = NotesRenderer.instance.get_visible_keys()  # 获取当前可视键

# ScoreCalculator - 分数计算（单例）
ScoreCalculator.instance.record_judge(JudgeGrade.PERFECT)  # 记录判定
var score_data = ScoreCalculator.instance.get_score_data()  # 获取最终分数
```

**游戏启动完整流程**：
```gdscript
# 1. 用户选择 MIDI，MidiView 发出信号
EventBus.instance.start_game_with.emit(midi_data)

# 2. GameplayManager.start_game() 处理整个加载流程
GameplayManager.instance.start_game(midi_data)
  ├─ set_game_state(LOADING)
  ├─ MidiPlaybackManager.load_midi(midi) - 加载并解析 MIDI
  ├─ KeySequenceManager.classify_sequences() - 分类 Note
  ├─ KeySequenceManager.generate_keys() - 生成键位映射
  ├─ NotesRenderer.load_chart(midi) - 初始化谱面渲染
  └─ set_game_state(PLAYING) - 开始游戏

# 3. GameView 监听游戏时间更新
GameplayManager.instance.game_time_updated.connect(func(time, duration):
    NotesRenderer.instance.update_position(time * 1000)  # 转换为毫秒
)
```

## 🔄 常见工作流

### 流程 1: 用户选择 MIDI，进入不同视图
```gdscript
# 方案 A：进入 TrackView（编辑谱面）
var midi = midi_list.get_selection()
EventBus.instance.enter_track_view_with.emit(midi)
UIStateManager.instance.change_state(UIStateManager.UIState.TRACK_VIEW)

# 方案 B：进入 PlayView（开始游戏）
var midi = midi_list.get_selection()
EventBus.instance.start_game_with.emit(midi)
UIStateManager.instance.change_state(UIStateManager.UIState.PLAY_VIEW)
GameplayManager.instance.start_game(midi)  # 自动处理加载、分类、键位生成
```

### 流程 2: TrackView 特殊模式
```gdscript
# TrackView 支持编辑模式，与普通游戏流程不同
# 导入音轨（人声、伴奏等）
TrackView.import_vocal_file(file_path)  # 保存到 MIDI 数据，持久化到 JSON

# 选择游戏轨道（改变哪个 track 作为玩家操作的对象）
TrackView.set_game_track(track_index)  # → MidiPlaybackManager 更新选择
# 返回 GameSequence（玩家操作）+ BackgroundSequence（伴奏）

# 保存修改
TrackView.save_midi_to_json()  # → FileSystemManager 定位文件路径，更新 JSON
```

### 流程 3: 排序和搜索 MIDI
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

### 流程 4: UI 视图的标准结构
```gdscript
# Views/SomeView.gd 应该继承 Control 或 BaseScrollList
extends Control
class_name SomeView

@onready var data_manager = DataManager.instance
@onready var event_bus = EventBus.instance
@onready var config_manager = ConfigManager.instance

func _ready() -> void:
    # 1. 等待数据加载完成
    event_bus.data_loaded_complete.connect(_on_data_ready)
    
    # 2. 连接选择事件（信号驱动）
    event_bus.midi_selected.connect(_on_midi_selected)
    
    # 3. 监听配置变更（新增）
    event_bus.config_changed.connect(_on_config_changed)
    
    # 4. 初始化 UI

func _on_config_changed(key: String, section: String, value: Variant) -> void:
    # 处理配置变更，例如：
    if section == "Audio" and key == "master_volume":
        _update_volume_ui(int(value))
```
    event_bus.midi_selected.connect(_on_midi_selected)
    
    # 3. 初始化 UI

func _on_data_ready() -> void:
    # 现在可以安全地查询 DataManager
    var items = data_manager.get_all_albums()
    for item in items:
        add_item_to_list(item)
```

### 流程 5: MIDI 时间单位转换
```gdscript
# 重要：MidiPlaybackManager 使用两种时间单位
var position_tick = MidiPlaybackManager.instance.position  # tick 单位（MIDI 标准）
var position_ms = MidiPlaybackManager.instance.get_position_ms()  # 毫秒（推荐）

# GameplayManager 使用秒为单位
var game_time_sec = GameplayManager.instance.game_time  # 秒

# NotesRenderer/KeySequenceManager 使用毫秒
NotesRenderer.instance.update_position(game_time_sec * 1000)  # 转换！
KeySequenceManager.instance.judge_note_at_key(key_id, position_ms)  # 毫秒
```

## ⚠️ 常见陷阱与修复

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 获取到空数据 | View._ready() 时数据还未加载 | 监听 `EventBus.data_loaded_complete` 信号后再查询 |
| 时间不同步 | 混淆 tick/毫秒/秒三种单位 | GameplayManager:秒 ← NotesRenderer:毫秒 ← MidiPlaybackManager:tick（需转换）|
| MIDI 加载失败 | FileSystemManager 未初始化完成 | Main._load_midi_data() 等待 resources_scanned = true |
| 谱面显示错误 | TrackView 改变游戏轨道后未重新生成键位 | 调用 KeySequenceManager.generate_keys() 后更新 NotesRenderer |
| 状态混乱 | 多处直接修改 UI 可见性 | 统一用 UIStateManager.change_state() 控制转换 |
| Tween 卡顿 | 直接创建 Tween 未管理生命周期 | 使用 AnimationManager.animate_*() |
| 静音无效 | 混淆轨道静音与通道静音（MIDI 中 16 通道/轨道） | MidiPlaybackManager.set_track_mute() vs set_channel_mute() |
| 音源切换失败 | 后端切换时 SoundFont 参数未同步 | 检查 MidiPlaybackManager.backend_switching 锁 |
| 配置读取重复 | 每次都创建 ConfigLoader.new() 实例 | 使用 ConfigManager.instance 单例，自动缓存 |
| 配置变更无效 | 其他 Manager 不知道配置已修改 | 监听 EventBus.config_changed 信号并热重载配置 |

### 单例初始化顺序的关键
- **错误**: Manager 在其依赖还未初始化时被访问（.instance 返回 null）
- **正确**: Main._initialize_core_systems() 遵循 13 步顺序，FileSystemManager → DataManager
- **检查**: Main.gd 行 46-126 的初始化逻辑

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
| 标准 View | [UI/Views/MidiView/MidiView.gd](../UI/Views/MidiView/MidiView.gd) | 使用 EventBus 信号驱动的 View 示例 |
| UI组件基类 | [UI/Components/BaseScrollList.gd](../UI/Components/BaseScrollList.gd) | 继承此类用于列表 UI，load_*() 加载数据 |
| 动画库 | [UI/Animations/AnimationManager.gd](../UI/Animations/AnimationManager.gd) | animate_*() 系列（15+预设），_create_tween() 管理 |
| MIDI 解析 | [Utilities/MidiParser.gd](../Utilities/MidiParser.gd) | load_and_parse_midi(), Note/AutoPlayNote/ManualControlNote 类 |
| 配置加载 | [Utilities/ConfigManager.gd](../Utilities/ConfigManager.gd) | load_config(), save_config(), set_value_and_notify()，单例管理 ✨ |
| 配置加载（弃用） | [Utilities/ConfigLoader.gd](../Utilities/ConfigLoader.gd) | 已弃用，为向后兼容的代理，请使用 ConfigManager |
| 日志系统 | [Utilities/Logger.gd](../Utilities/Logger.gd) | GameLogger.instance.info/warning/error()，标签式日志 |
| TrackView 编辑 | [UI/Views/TrackView/TrackView.gd](../UI/Views/TrackView/TrackView.gd) | 专用 MIDI 编辑、轨道导入、持久化 |

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

### 配置管理（新增 - ConfigManager 单例，用户配置优先）
```gdscript
# ✅ 正确：使用 ConfigManager.instance 访问
var config_manager = ConfigManager.instance

# 初始化时加载（优先用户配置，默认配置补充缺失部分）
config_manager.load_and_set_current()

# 简化用法：读取当前活跃配置（无需传入config参数）
var lane_count = config_manager.get_int("Lane", "lane_count", 12)
var is_fullscreen = config_manager.get_bool("Display", "fullscreen", true)

# 保存配置并触发通知
config_manager.set_value_and_notify("Lane", "lane_count", 16)

# 重新加载配置（用户配置优先，默认配置补充）
config_manager.reload_config()

# 检查并迁移配置版本（新增部分从默认配置中恢复）
config_manager.check_and_migrate()

# 监听配置变更
if EventBus.instance:
    EventBus.instance.config_changed.connect(func(key, section, value):
        print("配置变更: [%s] %s = %s" % [section, key, value])
    )

# ❌ 错误：不要重复创建实例
var loader1 = ConfigLoader.new()  # 每次创建都会重新解析文件
var loader2 = ConfigLoader.new()

# ⚠️ 配置策略说明
# - USER_CONFIG_PATH (user://files/settings.ini) - 用户和游戏内修改的配置，优先加载
# - DEFAULT_CONFIG_PATH (res://Resources/Config/config.ini) - 默认配置，用于补充缺失部分和版本迁移
# - 游戏内所有配置读取都基于合并后的_current_config
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
- [Doc/quickref/TRACKVIEW_QUICK_REFERENCE.md](../Doc/quickref/TRACKVIEW_QUICK_REFERENCE.md) - TrackView 快速参考
- [Doc/quickref/MIDI_BACKEND_QUICK_REFERENCE.md](../Doc/quickref/MIDI_BACKEND_QUICK_REFERENCE.md) - MIDI 后端选择
- [Doc/quickref/quick_start.md](../Doc/quickref/quick_start.md) - 快速开始指南

---

**最后更新**: 2026-02-10  
**Godot 版本**: 4.5 | **主要语言**: GDScript
