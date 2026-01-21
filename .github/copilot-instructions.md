# Touhou Mix 社区版 - AI 编程助手指南

**项目**: GDScript/Godot 4.5 节奏游戏  
**状态**: 第 1 阶段完成；UI/事件系统迁移进行中

## 架构概览

该项目采用 **分层管理器模式**，分为 4 层：

1. **Core/** (数据与业务逻辑层)
   - `DataManager`：单例，管理专辑/歌曲/MIDI 数据树
   - `EventBus`：全局信号分发器（约 20 个事件）
   - `UIStateManager`：带导航历史的状态机
   - `SortingEngine`：6 种排序类型 + 过滤/搜索
   - 数据模型：`AlbumData`、`SongData`、`MidiData`（数据类）

2. **Game/** (游戏逻辑层)
   - `GameplayManager`、`AudioManager`、`ScoreCalculator`、`NotesRenderer`
   - 全部遵循单例模式，通过 `ClassName.instance` 访问

3. **UI/** (界面层)
   - `AnimationManager`：基于补间动画的管理器（15+ 动画预设）
   - `Components/`：基础类（如 `ListItemBase`、`BaseScrollList`）
   - `Views/`：具体的 UI 视图（迁移中）
   - `midis_info/*.json`：MIDI 元数据文件
   - 主题/皮肤配置
var data = DataManager.instance
var bus = EventBus.instance
### 数据查询
使用 `DataManager` 进行一致性数据访问：
    midis, 
    SortingEngine.SortField.DOWNLOAD_COUNT,
)
```
不要本地实现排序；请使用 `filter_and_sort()` 和 `search_midis()`。

### 动画
使用 `AnimationManager`（不要直接使用补间动画）：
AnimationManager.instance.animate_fade_in(node, 0.2)
AnimationManager.instance.animate_bounce(node, start, end, 0.5)
```
预设动画：`fade_in/out`、`pulse`、`bounce`、`menu_expand/collapse`、`scale`、`position`。
### UI 状态切换
通过 `UIStateManager` 管理，支持返回导航：
```gdscript
UIStateManager.instance.change_state(UIStateManager.UIState.SONG_VIEW)
UIStateManager.instance.go_back()  # 撤销上一个状态
## 文件组织规则

- **数据模型**：存放于 `Core/Models/`，仅包含最少逻辑

## 开发工作流

### 数据加载
数据在 `Main.gd` 中 **异步加载**：
```gdscript
data_manager.data_loaded.connect(_on_data_loaded)
data_manager.load_all_midis_async()  # 非阻塞
```
等待 `data_loaded` 信号后再查询 UI 数据。

### 配置
通过 `ConfigLoader` 访问：
```gdscript
var config = ConfigLoader.new()
var settings = config.load_config("res://Resources/Config/config.ini")
var value = settings["section"]["key"]
```
支持 INI 格式并缓存。

### 日志
使用 `GameLogger` 进行调试：
```gdscript
logger.info("Message", "ComponentName")  # 基于标签的日志
logger.warning("Warn msg", "Tag")
### 测试
- `Utilities/IntegrationTest.gd`：完整系统验证
## 常见问题

5. **Godot 4.5 语法**：使用 `func_name() -> ReturnType` 类型提示；类型检查优先使用 `is` 而非 `==`

✅ EventBus 含 20+ 信号  
🔄 第 2 阶段：UI 视图迁移（albumNote → AlbumView 等）  
查看 `Doc/MIGRATION_PROGRESS.md` 获取详细迁移进度。
## 关键文件参考

- **架构文档**: [Doc/ARCHITECTURE_OVERVIEW.md](../Doc/ARCHITECTURE_OVERVIEW.md)
- **快速参考**: [Doc/DEVELOPER_CHEATSHEET.md](../Doc/DEVELOPER_CHEATSHEET.md)
- **单例指南**: [Doc/SINGLETON_PATTERN_GUIDE.md](../Doc/SINGLETON_PATTERN_GUIDE.md)
- **主场景初始化**: [Main.gd](../Main.gd)
- **事件信号**: [Core/EventBus.gd](../Core/EventBus.gd)
- **数据访问**: [Core/DataManager.gd](../Core/DataManager.gd)

---

**最后更新**: 2026-01-14  
**Godot 版本**: 4.5  
**主要语言**: GDScript
