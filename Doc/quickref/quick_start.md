# 快速上手（开发者）

## 5 分钟了解项目

1. 看 `Main.gd` 的 `_initialize_core_systems()`（初始化入口）
2. 看 `Core/EventBus.gd`（全局信号）
3. 看 `Core/DataManager.gd` + `Core/FileSystemManager.gd`（数据与资源）
4. 看 `Game/MidiPlaybackManager.gd`（播放后端）
5. 看 `UI/Views/MidiView/`（典型 UI 消费方式）

## 最小调试路径

1. 启动项目
2. 观察日志是否出现 `Core Systems Initialized`
3. 确认 `charts_index` 条目数大于 0
4. 确认收到 `EventBus.data_loaded_complete`

## 常用调用

```gdscript
# 数据
var albums = DataManager.instance.get_all_albums()
var songs = DataManager.instance.get_songs_by_album(album_id)
var midis = DataManager.instance.get_midis_by_song(song_id)

# 状态切换
UIStateManager.instance.change_state(UIStateManager.UIState.MIDI_VIEW)

# 后端切换
MidiPlaybackManager.instance.set_backend("meltysynth")

# 配置读取
var lane_count = ConfigManager.instance.get_int("Lane", "lane_count", 12)
```

## 新增 View 的最低要求

- `_ready()` 中连接必要信号（如 `data_loaded_complete` / `config_changed`）
- 不在 `_ready()` 直接假设数据已可用
- 通过 `UIStateManager` 管理页面切换，不直接改全局状态

## 下一步阅读

- `../architecture/architecture_overview.md`
- `../architecture/initialization_sequence.md`
- `developer_cheatsheet.md`
