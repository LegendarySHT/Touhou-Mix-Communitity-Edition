# Manager 单例模式指南

## 目标

统一所有管理器访问方式，避免路径硬编码、重复实例和初始化时序问题。

## 三种初始化路径

### 1) Autoload 注册（`project.godot`）
示例：`DataManager`、`EventBus`、`SortingEngine`、`UIStateManager`、`AnimationManager`、`GameLogger`

特征：
- 在 `_ready()` 中设置 `instance = self`
- 全局可直接访问 `ClassName.instance`

### 2) `Main.gd` 手动 `new() + add_child()`
示例：`FileSystemManager`、`GameplayManager`、`ScoreCalculator`、`AudioManager`、`MidiPlaybackManager`、`KeySequenceManager`

特征：
- 在 `Main._initialize_core_systems()` 按顺序创建
- `_ready()` 后建立 `instance`

### 3) 懒加载 getter（唯一例外）
示例：`ConfigManager`

特征：
- 通过 `ConfigManager.instance` 首次访问时创建
- 非 Autoload、非 Main 手动挂载

## 标准访问方式

```gdscript
var data_mgr = DataManager.instance
if data_mgr:
    var albums = data_mgr.get_all_albums()

UIStateManager.instance.change_state(UIStateManager.UIState.SONG_VIEW)
```

## 禁止用法

```gdscript
# 不要这样做
var mgr = get_node("/root/Main/DataManager")
```

原因：
- 路径脆弱，场景结构变更后容易失效
- 运行时耦合高，不利于维护与测试

## 初始化安全建议

1. 在 `_ready()` 或数据就绪信号后访问依赖管理器。
2. 可能为空的单例先判空再调用。
3. 若依赖配置，优先确保 `ConfigManager.load_and_set_current()` 已执行。

## 与 EventBus 的配合

管理器之间不直接串改内部状态，跨模块优先通过信号：

```gdscript
EventBus.instance.config_changed.connect(_on_config_changed)
EventBus.instance.data_loaded_complete.connect(_on_data_ready)
```

## 自检清单

- [ ] 是否全部使用 `ClassName.instance`
- [ ] 是否移除了 `/root/...` 路径访问
- [ ] 是否在初始化时序正确后再调用
- [ ] 是否用 `EventBus` 处理跨模块事件
