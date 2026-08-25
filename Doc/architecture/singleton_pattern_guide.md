# Manager 单例模式指南

> 适用版本：THMIX Community Edition（Godot 4.7.1 Mono）

## 目标

统一所有管理器访问方式，避免路径硬编码、重复实例和初始化时序问题。

## 四种初始化路径

### 1) Autoload 注册（`project.godot`）

| 别名 | 类 | 层 |
|---|---|---|
| `DataMGR` | DataManager | Core |
| `EvtBus` | EventBus | Core |
| `SortEngine` | SortingEngine | Core |
| `UiStatMGR` | UIStateManager | Core |
| `SkinMGR` | SkinManager | Core |
| `AniMGR` | AnimationManager | UI |
| `ThemeMGR` | ThemeManager | UI |
| `GLogger` | GameLogger | Utilities |

特征：
- 引擎启动时自动实例化
- `_ready()` 中 `add_to_group("singleton")`
- 全局通过别名（`DataMGR`、`EvtBus` 等）或 `ClassName.instance` 访问

### 2) `Main.gd` 手动 `new() + add_child()`

| 类 | 说明 |
|---|---|
| `FileSystemManager` | 含 `static var instance`，`_ready()` 中赋值 |
| `ScoreCalculator` | 含 `static var instance`（如有） |
| `AudioManager` | 含 `static var instance`（如有） |
| `MidiPlaybackManager` | 含 `static var instance`（如有） |
| `KeySequenceManager` | 含 `static var instance`（如有） |
| `NetManager` | 在线连接和 HTTP 请求 |
| `AuthManager` | 登录态与鉴权请求 |
| `ScoreManager` | 本地成绩与成绩上传 |
| `CommunityManager` | MIDI 评价、评论、点赞与公开计数缓存 |

特征：
- 在 `Main._initialize_core_systems()` 按顺序创建
- 子节点 `_ready()` 后建立 `instance`

### 3) 懒加载 getter（唯一例外）

- `ConfigManager`：通过 `ConfigManager.instance` 首次访问时创建，非 autoload、非 Main 手动挂载

### 4) 纯静态工具类

- `PathHelper`：无实例，全部静态方法

## 标准访问方式

```gdscript
# autoload 别名（推荐，更简短）
var albums = DataMGR.albums
UiStatMGR.change_state(UIStateManager.UIState.SONG_VIEW)
GLogger.info("msg", "Tag")

# 或通过 ClassName.instance（等价）
var data_mgr = DataManager.instance
if data_mgr:
    var albums = data_mgr.get_all_albums()

# 配置（懒加载，必须用 .instance）
ConfigManager.instance.get_int("Lane", "lane_count", 12)
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
3. 若依赖配置，优先确保 `ConfigManager.load_and_set_current()` 已执行（在 `Main._initialize_core_systems()` 第 2.5 步）。

## 与 EventBus 的配合

管理器之间不直接串改内部状态，跨模块优先通过信号：

```gdscript
EvtBus.config_changed.connect(_on_config_changed)
EvtBus.data_loaded_complete.connect(_on_data_ready)
```

## 自检清单

- [ ] 是否全部使用 autoload 别名或 `ClassName.instance`
- [ ] 是否移除了 `/root/...` 路径访问
- [ ] 是否在初始化时序正确后再调用
- [ ] 是否用 `EventBus` 处理跨模块事件

## 关联文档

- `architecture_overview.md`
- `initialization_sequence.md`
