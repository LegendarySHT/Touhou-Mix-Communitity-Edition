# Touhou Mix 社区版 - AI 编程助手指南

**项目**: Godot 4.5 节奏游戏（GDScript）  
**状态**: 核心架构完成；UI/MIDI 系统已集成  
**更新**: 2026-01-26

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
- `MidiPlaybackManager.instance` - MIDI 文件加载与音符解析
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

## ⚠️ 常见陷阱与修复

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 获取到空数据 | View._ready() 时数据还未加载 | 监听 `data_loaded_complete` 信号后再查询 |
| MIDI 加载失败 | FileSystemManager 未初始化完成 | Main._load_midi_data() 等待 resources_scanned = true |
| 状态混乱 | 多处直接修改 UI 可见性 | 统一用 UIStateManager.change_state() |
| Tween 卡顿 | 直接创建 Tween 未管理 | 使用 AnimationManager.animate_*() |
| MIDI 未找到 | FileSystemManager 扫描失败 | 检查 user://files/Charts/ 目录权限 |

## 📁 文件导航速查

| 任务 | 查看文件 | 关键方法 |
|------|---------|---------|
| 初始化流程 | [Main.gd](../Main.gd) | _initialize_core_systems() |
| 全局事件 | [Core/EventBus.gd](../Core/EventBus.gd) | 20+ signals |
| 数据查询 | [Core/DataManager.gd](../Core/DataManager.gd) | get_all_albums(), get_midis_by_song() |
| 文件索引 | [Core/FileSystemManager.gd](../Core/FileSystemManager.gd) | charts_index, get_charts_index() |
| MIDI 播放 | [Game/MidiPlaybackManager.gd](../Game/MidiPlaybackManager.gd) | load_midi(), get_track_infos() |
| 排序搜索 | [Core/SortingEngine.gd](../Core/SortingEngine.gd) | get_sorted_midis(), search_midis() |
| 标准 View | [UI/Views/MidiView/MidiView.gd](../UI/Views/MidiView/MidiView.gd) | BaseScrollList 继承示例 |
| 动画库 | [UI/Animations/AnimationManager.gd](../UI/Animations/AnimationManager.gd) | 15+ 预设动画 |

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

**最后更新**: 2026-01-26  
**Godot 版本**: 4.5 | **主要语言**: GDScript
