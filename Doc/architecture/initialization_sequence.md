# 核心系统初始化顺序

## 入口

初始化由 `Main._initialize_core_systems()` 统一执行。

## 顺序（必须保持）

```text
1.  GameLogger.instance
2.  ConfigManager.instance
2.5 ConfigManager.clear_cache() + load_and_set_current()
3.  FileSystemManager.new() + initialize_directory_structure()
4.  EventBus.instance
5.  UIStateManager.instance
6.  AnimationManager.instance
7.  SortingEngine.instance
8.  DataManager.instance
9.  GameplayManager.new()
9.5 ScoreCalculator.new()
10. AudioManager.new()
11. MidiPlaybackManager.new()
12. KeySequenceManager.new()
13. _init_ui() -> _connect_signals() -> _load_configuration() -> _load_midi_data()
```

## 关键依赖关系

### 配置先行
- `ConfigManager` 必须先完成 `load_and_set_current()`
- 否则后续管理器读取到的可能是空配置或旧值

### 文件系统先于数据加载
- `DataManager.load_all_midis_async()` 依赖 `FileSystemManager` 资源索引
- `_load_midi_data()` 内会等待 `resources_scanned` 就绪（含超时兜底）

### 先管理器后 UI
- `_init_ui()` 在所有核心管理器就位后执行
- 防止 View 在 `_ready()` 提前读取空状态

## 已连接的核心信号

`Main._connect_signals()`：
- `DataManager.data_loaded -> _on_data_loaded`
- `UIStateManager.state_changed -> _on_state_changed`
- `EventBus.error_occurred -> _on_error_occurred`
- `EventBus.settings_changed -> _on_settings_changed`
- `EventBus.config_changed -> _on_config_changed`

## 常见问题

### 1. 数据加载为空
优先检查：
- `FileSystemManager.resources_scanned` 是否完成
- `charts_index` 是否有条目

### 2. 设置不生效
优先检查：
- 是否执行了 `ConfigManager.load_and_set_current()`
- 是否发出了 `EventBus.settings_changed` / `config_changed`

### 3. UI 状态异常
优先检查：
- 是否统一使用 `UIStateManager.instance.change_state()`
- 是否在 View 中重复修改状态历史
