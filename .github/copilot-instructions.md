# Touhou Mix 社区版 - AI 编程助手指南

**项目**: Godot 4.6 节奏游戏（GDScript + C# 可选后端）  
**更新**: 2026-02-28 (v3)

## 架构概览

三层分层架构：`Core/`（数据模型与索引）→ `Game/`（MIDI 播放与游戏逻辑）→ `UI/`（视图与组件）  
跨模块通信：单例 `Manager.instance` 直接调用 + `EventBus` 信号解耦  
数据流：`FileSystemManager` → `DataManager` → `SortingEngine` → UI Views

### 单例模式 — 三种初始化路径

| 初始化方式 | Manager | 说明 |
|---|---|---|
| **Autoload**（project.godot 注册） | DataManager, EventBus, SortingEngine, UIStateManager, AnimationManager, GameLogger | `_ready()` 中 `instance = self` |
| **Main.gd `new()` + `add_child()`** | FileSystemManager, GameplayManager, ScoreCalculator, AudioManager, MidiPlaybackManager, KeySequenceManager | Main.gd 手动创建，`_ready()` 中 `instance = self` |
| **Lazy getter（唯一例外）** | ConfigManager | `static var instance` 通过 getter 自动懒创建，无需 autoload |

所有 Manager 统一通过 `ClassName.instance` 访问，**禁止** `get_node("/root/...")` 硬编码路径。

### 初始化顺序（Main._initialize_core_systems）

严格顺序，不可打乱（依赖链：FileSystemManager → DataManager → UI）：
```
1. GameLogger → 2. ConfigManager（+load_and_set_current）→ 3. FileSystemManager（+initialize_directory_structure）
→ 4. EventBus → 5. UIStateManager → 6. AnimationManager → 7. SortingEngine → 8. DataManager
→ 9. GameplayManager → 9.5. ScoreCalculator → 10. AudioManager → 11. MidiPlaybackManager → 12. KeySequenceManager
→ _init_ui() → _connect_signals() → _load_configuration() → _load_midi_data()
```
`_load_midi_data()` 等待 `FileSystemManager.is_initialized` 后调用 `DataManager.load_all_midis_async()`。

### UIState 枚举（UIStateManager）

```gdscript
enum UIState { NONE=-1, ALBUM_VIEW=0, SONG_VIEW=1, MIDI_VIEW=2, TRACK_VIEW=21,
               SORTED_VIEW=3, STORE_VIEW=4, SETTINGS_VIEW=5, PLAY_VIEW=6, SCORE_VIEW=61 }
```
视图切换统一使用 `UIStateManager.instance.change_state()`，对应 `UI/Views/` 下的 9 个视图目录。

## 关键数据结构

```gdscript
# DataManager 树结构
albums: Dictionary[String, AlbumData]   # Core/Models/AlbumData.gd (extends Resource)
songs: Dictionary[String, SongData]     # Core/Models/SongData.gd
midis: Dictionary[String, MidiData]     # Core/Models/MidiData.gd — 最复杂，含运行时配置

# FileSystemManager 索引
charts_index: Dictionary  # { folder_name: { "data": {...json} } }
```
`MidiData` 含 `track_channel_volume_config`、`solo_pairs`、`vocal_file_path`、`export_runtime_config()` 等运行时字段，JSON 中通过 `_runtime` 对象持久化。

## MIDI 播放后端

两套后端实现 `MidiPlaybackInterface`（GDScript 基类，见 `Game/MidiPlaybackInterfaces.gd`）：
- **addons** — `addons/midi/MidiPlayer.gd`（纯 GDScript）
- **MeltySynth** — `CSharp/MeltySynthPlayer.cs`（C# 高性能，通过 `MeltySynthPlayerWrapper.gd` 桥接）

```gdscript
MidiPlaybackManager.instance.set_backend("meltysynth")  # 动态切换，有 backend_switching 锁
MidiPlaybackManager.instance.set_soundfont(name)        # 统一接口
```

### 时间单位（关键陷阱）

| 系统 | 单位 | 访问方法 |
|---|---|---|
| MidiPlaybackManager | tick / 毫秒 | `.position`（tick）/ `.get_position_ms()`（推荐） |
| GameplayManager | 秒 | `.game_time` |
| NotesRenderer / KeySequenceManager | 毫秒 | `update_position(game_time * 1000)` |

## 配置管理

```gdscript
# 唯一入口：ConfigManager.instance（lazy 单例）
ConfigManager.instance.get_int("Lane", "lane_count", 12)
ConfigManager.instance.set_value_and_notify("Lane", "lane_count", 16)  # 自动发 EventBus.config_changed
```
- 用户配置 `user://files/settings.ini` 优先，默认配置 `res://Resources/Config/config.ini` 补充缺失
- `SettingsMapper`（`Utilities/SettingsMapper.gd`）负责 SettingView UI 控件 ID ↔ INI section/key 映射（~70 项）
- `PathHelper`（`Utilities/PathHelper.gd`）纯静态工具类，处理 Android vs 桌面路径差异

## 代码约定

### 新建 View 标准模板
```gdscript
extends Control
class_name SomeView

func _ready() -> void:
    EventBus.instance.data_loaded_complete.connect(_on_data_ready)
    EventBus.instance.config_changed.connect(_on_config_changed)

func _on_data_ready() -> void:
    var items = DataManager.instance.albums  # 直接访问字典属性
```

### DO / DON'T

| ✅ DO | ❌ DON'T |
|---|---|
| `Manager.instance` 访问单例 | `get_node("/root/...")` 硬编码路径 |
| `EventBus` 信号跨模块通信 | 直接修改其他 Manager 数据 |
| `AnimationManager.animate_*()` 管理 Tween | `create_tween()` 无管理创建 |
| `SortingEngine` 排序/搜索 | View 中自行排序大数据 |
| `GameLogger.instance.info(msg, "Tag")` 日志 | `print()` 裸打印 |
| 等 `data_loaded_complete` 后查数据 | `_ready()` 中直接查 DataManager |

### 分数评级体系

`ScoreCalculator` 使用 `Judgment { PERFECT, GREAT, GOOD, BAD, MISS }` 和 16 级评级：Ω, SSS, SS, S, A+, A, A-, B+, B, B-, C+, C, C-, D+, D, D-。核心方法：`record_judgment()`、`get_snapshot()`、`get_accuracy()`。

## 文件导航

| 关注点 | 关键文件 |
|---|---|
| 初始化入口 | `Main.gd` — `_initialize_core_systems()` |
| 全局信号（~17个） | `Core/EventBus.gd` |
| 数据模型 | `Core/Models/{AlbumData,SongData,MidiData}.gd` |
| 文件索引 & 路径 | `Core/FileSystemManager.gd` + `Utilities/PathHelper.gd` |
| MIDI 播放 | `Game/MidiPlaybackManager.gd`（1570行，核心） |
| 游戏流程 | `Game/GameplayManager.gd` — `start_game()`, GameState 枚举 |
| 配置系统 | `Utilities/ConfigManager.gd` + `Utilities/SettingsMapper.gd` |
| UI 组件基类 | `UI/Components/BaseScrollList.gd`（ScrollContainer）+ `ListItemBase.gd` |
| 视图模板 | `UI/Views/MidiView/` — EventBus 信号驱动的典型 View |
| MIDI 后端接口 | `Game/MidiPlaybackInterfaces.gd` + `CSharp/MeltySynthPlayer.cs` |
| 测试 | `Test/` — extends Node, `_ready()` 自动运行，`_record_test()` 记录结果 |

详细文档见 `Doc/quickref/` 目录下的快速参考指南。

---
**Godot 版本**: 4.6 | **语言**: GDScript（主）+ C#（MeltySynth 后端）
