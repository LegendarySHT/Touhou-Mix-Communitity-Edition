# 开发者备忘单

快速参考指南，用于日常开发工作。

---

## 🔧 常用命令和代码片段

### 获取管理器实例

```gdscript
# 数据管理
var data = DataManager.instance

# 事件总线
var events = EventBus.instance

# UI状态
var state = UIStateManager.instance

# 动画管理
var animator = AnimationManager.instance

# 游戏管理
var gameplay = GameplayManager.instance
```

### 数据查询常用操作

```gdscript
# 获取所有专辑
var albums = DataManager.instance.get_all_albums()

# 按专辑ID获取歌曲
var songs = DataManager.instance.get_songs_by_album(album_id)

# 按歌曲ID获取MIDI
var midis = DataManager.instance.get_midis_by_song(song_id)

# 按MIDI ID获取单个谱面
var midi = DataManager.instance.get_midi_by_id(midi_id)

# 按状态过滤
var approved = DataManager.instance.get_midis_by_status("APPROVED")

# 获取统计
var stats = DataManager.instance.get_statistics()
```

### 排序和过滤常用操作

```gdscript
var engine = SortingEngine.instance

# 按下载数降序排序
var sorted = engine.get_sorted_midis(
    midis,
    SortingEngine.SortField.DOWNLOAD_COUNT,
    SortingEngine.SortDirection.DESCENDING
)

# 按状态过滤并排序
var result = engine.filter_and_sort(
    midis,
    "APPROVED",
    SortingEngine.SortField.TRIAL_COUNT,
    SortingEngine.SortDirection.DESCENDING
)

# 搜索
var search_results = engine.search_midis(midis, "Lost Word")
```

### 动画常用操作

```gdscript
var animator = AnimationManager.instance

# 基础动画
animator.animate_position(node, Vector2(100, 50), 0.3)
animator.animate_scale(node, Vector2(1.2, 1.2), 0.3)
animator.animate_modulate(node, Color.RED, 0.3)

# 淡入淡出
animator.animate_fade_in(panel, 0.2)
animator.animate_fade_out(panel, 0.2)

# 菜单动画
animator.animate_menu_expand(menu, 200.0, 0.3)
animator.animate_menu_collapse(menu, 0.3)

# 特殊动画
animator.animate_pulse(button, 0.9, 1.0, 0.2)
animator.animate_bounce(node, start_pos, end_pos, 0.5)

# 序列动画
var tween = animator.create_sequence("my_sequence")
tween.tween_property(node1, "position", Vector2(100, 100), 0.3)
tween.tween_property(node2, "position", Vector2(200, 200), 0.3)
tween.tween_callback(func(): print("Done!"))

# 延迟执行
animator.delay_call(my_function, 1.0)
```

### 事件发送和监听

```gdscript
# 监听数据加载
EventBus.data_loaded_complete.connect(_on_data_loaded)

# 监听选择事件
EventBus.album_selected.connect(_on_album_selected)
EventBus.song_selected.connect(_on_song_selected)
EventBus.midi_selected.connect(_on_midi_selected)

# 监听导航事件
EventBus.navigate_back.connect(_on_navigate_back)
EventBus.navigate_to_album_view.connect(_on_album_view)

# 监听排序事件
EventBus.sort_field_changed.connect(_on_sort_changed)
EventBus.status_filter_changed.connect(_on_filter_changed)

# 发出事件
EventBus.emit_album_selected(album_id, album_data)
EventBus.emit_song_selected(song_id, song_data)
EventBus.emit_midi_selected(midi_id, midi_data)
```

### UI状态管理

```gdscript
var state_mgr = UIStateManager.instance

# 改变状态
state_mgr.change_state(UIStateManager.UIState.ALBUM_VIEW)
state_mgr.change_state(UIStateManager.UIState.SONG_VIEW)
state_mgr.change_state(UIStateManager.UIState.MIDI_VIEW)

# 返回上一状态
state_mgr.go_back()

# 检查当前状态
if state_mgr.is_in_state(UIStateManager.UIState.ALBUM_VIEW):
    print("In album view")

# 监听状态改变
state_mgr.state_changed.connect(_on_state_changed)
state_mgr.state_entering.connect(_on_state_entering)
state_mgr.state_exiting.connect(_on_state_exiting)

# 打印状态信息
state_mgr.print_state_info()
```

---

## 📝 创建新组件的模板

### 创建新的列表视图

```gdscript
# UI/Views/MyListView.gd
extends BaseScrollList
class_name MyListView

func _ready() -> void:
    container = $VBoxContainer
    item_size = 100.0
    item_spacing = 10.0
    enable_snap = true
    
    EventBus.data_loaded_complete.connect(_on_data_loaded)
    item_focused.connect(_on_item_focused)

func _on_data_loaded() -> void:
    var items = _get_items()
    for item_data in items:
        var item = create_and_add_item(item_data.id, "my_type")
        _initialize_item(item, item_data)

func _initialize_item(item: ListItemBase, data) -> void:
    # 自定义初始化逻辑
    pass

func _on_item_focused(item_id: String) -> void:
    # 处理选择
    EventBus.emit_item_selected(item_id)

func _get_items() -> Array:
    # 返回要显示的数据
    return []
```

### 创建新的列表项

```gdscript
# UI/Components/MyListItem.gd
extends ListItemBase
class_name MyListItem

@onready var label = $Label
@onready var icon = $Icon

func _on_selected() -> void:
    # 选中时的效果
    modulate = Color.YELLOW
    scale = Vector2(1.05, 1.05)

func _on_deselected() -> void:
    # 取消选中时的效果
    modulate = Color.WHITE
    scale = Vector2(1.0, 1.0)

func _on_hovered() -> void:
    modulate = Color.LIGHT_GRAY

func _on_unhovered() -> void:
    if not is_selected:
        modulate = Color.WHITE

func update_appearance() -> void:
    # 更新视觉
    label.text = item_id
```

### 创建新的游戏管理器

```gdscript
# Game/MyManager.gd
extends Node
class_name MyManager

signal my_signal(data)

var data: Dictionary = {}

func _ready() -> void:
    add_to_group("game_logic")
    
    # 监听事件
    EventBus.my_event.connect(_on_my_event)

func do_something() -> void:
    # 实现逻辑
    my_signal.emit(data)

func _on_my_event() -> void:
    # 处理事件
    pass
```

---

## 🎨 常用UI颜色和样式

根据 default_theme.ini：

```gdscript
# 主色
Color.ORANGE  # #FF6B00

# 背景
Color(0.1, 0.1, 0.18)  # 深灰蓝 #1A1A2E

# 文字
Color.WHITE           # 主文字
Color(0.8, 0.8, 0.8) # 副文字

# 状态
Color(0.16, 0.13, 0.24)  # 悬停 #2A2A4E
Color(1.0, 0.55, 0.0)    # 选中 #FF8C00

# 强调
Color.YELLOW  # 强调 #FFD60A
Color.RED     # 错误 #D62828
Color.GREEN   # 成功 #07BC0C
```

---

## 🔍 调试命令

### 打印调试信息

```gdscript
# 打印UI状态
UIStateManager.instance.print_state_info()

# 打印数据统计
var stats = DataManager.instance.get_statistics()
print(stats)

# 打印活跃动画
var count = AnimationManager.instance.get_active_tween_count()
print("Active tweens: %d" % count)

# 打印日志
Logger.instance.debug("Debug message")
Logger.instance.info("Info message")
Logger.instance.warning("Warning message")
Logger.instance.error("Error message")
```

### 性能测试

```gdscript
# 测试排序性能
var start = Time.get_ticks_msec()
var sorted = SortingEngine.instance.get_sorted_midis(midis)
var elapsed = Time.get_ticks_msec() - start
print("Sort time: %d ms" % elapsed)

# 监控内存
var mem = OS.get_static_memory_usage()
print("Memory: %.2f MB" % (mem / 1024.0 / 1024.0))

# 监控FPS
print("FPS: %d" % Engine.get_frames_per_second())
```

---

## 🛠️ 常见任务

### 任务1: 添加新的排序方式

1. 在 `SortingEngine.gd` 的 `SortField` 枚举中添加新字段
2. 在 `_compare_midis()` 中添加对应的 `match` 分支
3. 在 `_compare_*()` 辅助函数中实现比较逻辑

```gdscript
# SortingEngine.gd
enum SortField {
    # ... 现有的
    ACCURACY,  # 新增：按准确率排序
}

match current_sort_field:
    SortField.ACCURACY:
        result = _compare_float(midi_a.avg_accuracy, midi_b.avg_accuracy)
```

### 任务2: 添加新的UI状态

1. 在 `UIStateManager.gd` 的 `UIState` 枚举中添加
2. 在 `get_state_name()` 中添加对应的字符串

```gdscript
# UIStateManager.gd
enum UIState {
    # ... 现有的
    REPLAY_VIEW = 60  # 新增：回放页面
}

func get_state_name(state: UIState) -> String:
    match state:
        UIState.REPLAY_VIEW:
            return "REPLAY_VIEW"
```

### 任务3: 添加新的全局事件

1. 在 `EventBus.gd` 中定义新信号
2. 创建便利函数（可选）

```gdscript
# EventBus.gd
signal replay_started(midi_id: String)
signal replay_finished

# 便利函数
func emit_replay_started(midi_id: String) -> void:
    replay_started.emit(midi_id)
```

### 任务4: 创建新的配置节点

1. 在 `Resources/` 下创建对应的INI文件
2. 使用 `ConfigLoader` 加载

```gdscript
var loader = ConfigLoader.new()
var config = loader.load_config("res://Resources/MyConfig/settings.ini")
var value = loader.get_value(config, "section", "key")
```

---

## ⚡ 快速修复

### 问题: 数据加载缓慢

**原因**: JSON文件过多  
**解决方案**:
- 使用异步加载：`DataManager.load_all_midis_async()`
- 实现分页加载
- 缓存已加载的数据

### 问题: 内存泄漏

**原因**: Tween未正确清理  
**解决方案**:
- 使用 `AnimationManager` 而不是直接 `create_tween()`
- 在 `_exit_tree()` 中清理资源
- 使用 `CONNECT_ONE_SHOT` 连接一次性信号

### 问题: UI状态混乱

**原因**: 多处同时改变UI  
**解决方案**:
- 统一通过 `UIStateManager.change_state()` 改变状态
- 所有导航都通过 `EventBus` 事件
- 避免直接修改节点可见性

### 问题: 动画卡顿

**原因**: Tween过多或冲突  
**解决方案**:
- 使用 Tween ID 替换旧动画
- 使用 `parallel()` 并行执行
- 检查活跃Tween数量

---

## 📚 重要文件快速定位

| 需要修改 | 文件 | 行数 |
|---------|------|------|
| 数据模型 | Core/Models/*.gd | 15-40 |
| 排序逻辑 | Core/SortingEngine.gd | 50-100 |
| UI状态 | Core/UIStateManager.gd | 20-40 |
| 全局事件 | Core/EventBus.gd | 10-30 |
| UI组件 | UI/Components/*.gd | 30-70 |
| 动画 | UI/Animations/AnimationManager.gd | 60-150 |
| 游戏逻辑 | Game/*.gd | 50-150 |
| 配置 | Resources/Config/config.ini | 各节 |

---

## 🎯 最佳实践

✅ **DO**
- 使用 EventBus 进行模块间通信
- 通过 DataManager 访问数据
- 用 UIStateManager 管理UI状态
- 用 AnimationManager 处理动画
- 在 GDScript 中使用类型注解

❌ **DON'T**
- 直接修改其他模块的数据
- 硬编码节点路径
- 创建多个Tween管理器
- 使用全局变量跨模块通信
- 在 _process() 中频繁排序大数据

---

## 🎓 学习资源速查

| 想学习 | 查看文件 |
|--------|---------|
| 整体架构 | README.md |
| 快速上手 | QUICK_START.md |
| 详细说明 | REFACTOR_SUMMARY.md |
| 代码结构 | ARCHITECTURE_OVERVIEW.md |
| 代码注释 | 各个 .gd 文件的注释 |

---

## 📞 常见错误信息

| 错误 | 原因 | 解决 |
|-----|------|------|
| `Attempt to call function on null object` | 管理器未初始化 | 确保在 Main._ready() 中创建 |
| `Signal not connected` | EventBus信号未监听 | 检查 EventBus 中的信号定义 |
| `Invalid animation tween` | Tween被kill | 使用 AnimationManager 替代 |
| `File not found` | 配置文件路径错 | 使用绝对路径或 res:// |

---

**开发愉快！** 🚀

定期查阅此备忘单以加快开发效率。
