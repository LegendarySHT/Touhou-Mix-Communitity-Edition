# 架构总览

> 适用版本：THMIX Community Edition（Godot 4.6）

## 分层结构

项目采用三层结构：

1. `Core/`：数据模型、索引、排序、状态与事件
2. `Game/`：MIDI 播放、打歌流程、按键序列、计分
3. `UI/`：视图与组件（通过 `EventBus` / `UIStateManager` 协作）

跨层通信的原则：
- 全局管理器统一通过 `ClassName.instance` 访问
- 跨模块通知优先用 `EventBus` 信号
- UI 切换统一经 `UIStateManager.instance.change_state()`

## 核心管理器

### Core 层
- `DataManager`：加载并组织 `albums/songs/midis`
- `FileSystemManager`：初始化 `user://files` 目录并扫描资源
- `SortingEngine`：排序、筛选、搜索
- `UIStateManager`：UI 状态机与历史栈
- `EventBus`：全局事件总线

### Game 层
- `GameplayManager`：游戏流程、状态与时间推进
- `ScoreCalculator`：判定、准确率、评级
- `AudioManager`：全局音量与音频通道
- `MidiPlaybackManager`：MIDI 后端（addons / meltysynth）与音源管理
- `KeySequenceManager`：按键序列分类与可视化输入数据

### Utilities
- `ConfigManager`：懒加载单例，统一 INI 读取/写入与通知
- `PathHelper`：跨平台路径（桌面/Android）
- `GameLogger`：统一日志输出

## 数据主链路

```text
FileSystemManager.initialize_directory_structure()
  -> 扫描 Charts/Soundfont/Skins/BackgroundImage
  -> 更新 charts_index 与资源索引

DataManager.load_all_midis_async()
  -> 读取 charts_index
  -> 构建 AlbumData / SongData / MidiData
  -> 发出 data_loaded

Main._on_data_loaded()
  -> EventBus.data_loaded_complete
  -> 各 View 开始绑定和渲染
```

## UI 状态枚举（`UIStateManager`）

```gdscript
enum UIState {
    NONE = -1,
    ALBUM_VIEW = 0,
    SONG_VIEW = 1,
    MIDI_VIEW = 2,
    TRACK_VIEW = 21,
    SORTED_VIEW = 3,
    STORE_VIEW = 4,
    SETTINGS_VIEW = 5,
    PLAY_VIEW = 6,
    SCORE_VIEW = 61,
}
```

## 关键约束

- 不要在业务代码中使用 `get_node("/root/..." )` 访问管理器。
- `ConfigManager` 是唯一懒加载单例特例，其他 Manager 按初始化流程就位。
- `DataManager.load_all_midis_async()` 前必须保证 `FileSystemManager` 资源扫描已完成或超时兜底。
- 与播放时间有关的模块要明确单位（tick / ms / 秒），避免混用。

## 关联文档

- `singleton_pattern_guide.md`
- `initialization_sequence.md`
- `../features/midi_playback_implementation.md`
