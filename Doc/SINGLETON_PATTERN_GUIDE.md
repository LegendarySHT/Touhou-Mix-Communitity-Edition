# Manager 单例模式统一指南

## 概述

本指南说明THMIX项目中Manager类的单例模式统一方案，确保所有Manager类都使用一致的访问方式。

**更新日期:** 2026年1月13日  
**版本:** 1.1 (单例模式统一版)

## 目标

✅ 统一所有Manager类的单例访问方式  
✅ 提高代码一致性和可读性  
✅ 简化测试代码和业务逻辑  
✅ 避免节点树查询的复杂性

## Manager 类列表

### 已实现单例模式的Manager类

#### 1. DataManager ✅
**文件:** `Core/DataManager.gd`  
**访问方式:**
```gdscript
var data_mgr = DataManager.instance
if data_mgr:
    var albums = data_mgr.get_all_albums()
```

#### 2. EventBus ✅
**文件:** `Core/EventBus.gd`  
**访问方式:**
```gdscript
var bus = EventBus.instance
if bus:
    bus.album_selected.connect(_on_album_selected)
```

#### 3. UIStateManager ✅ (已统一)
**文件:** `Core/UIStateManager.gd`  
**访问方式:**
```gdscript
var state_mgr = UIStateManager.instance
if state_mgr:
    state_mgr.change_state(UIStateManager.UIState.SONG_VIEW)
```

#### 4. AnimationManager ✅ (已统一)
**文件:** `UI/Animations/AnimationManager.gd`  
**访问方式:**
```gdscript
var anim_mgr = AnimationManager.instance
if anim_mgr:
    anim_mgr.animate_fade_in(node, 0.3)
```

#### 5. GameplayManager ✅ (已统一)
**文件:** `Game/GameplayManager.gd`  
**访问方式:**
```gdscript
var gameplay_mgr = GameplayManager.instance
if gameplay_mgr:
    gameplay_mgr.start_game(midi_data)
```

#### 6. AudioManager ✅ (已统一)
**文件:** `Game/AudioManager.gd`  
**访问方式:**
```gdscript
var audio_mgr = AudioManager.instance
if audio_mgr:
    audio_mgr.play_bgm(audio_stream)
```

## 单例模式实现

### 标准实现模板

每个Manager类都应该包含以下代码：

```gdscript
class_name YourManagerName

## 单例实例
static var instance: YourManagerName

func _ready() -> void:
    if instance == null:
        instance = self
    else:
        queue_free()
    add_to_group("singleton")
```

### 实现说明

1. **静态instance属性**
   - 用于全局访问单例实例
   - 类型声明确保类型安全
   - 允许编辑器自动补全

2. **_ready()初始化**
   - 检查instance是否已存在
   - 如果是首次创建，赋值给instance
   - 如果已存在，删除重复实例
   - 添加到"singleton"组便于管理

3. **单例组("singleton")**
   - 便于查找所有单例
   - 便于统一管理生命周期
   - 便于调试

## 访问模式

### ✅ 推荐方式（统一模式）

```gdscript
# 直接通过instance访问
var manager = ManagerClassName.instance
if manager:
    manager.do_something()
```

**优点:**
- 统一一致
- 代码简洁
- 性能最优
- 编辑器支持补全

### ❌ 不推荐方式（旧模式 - 已弃用）

```gdscript
# 通过节点树查询获取
var manager = get_node("/root/Main/ManagerName")
manager.do_something()

# 或
var main = get_node("/root/Main")
var manager = main.get_node_or_null("ManagerName")
```

**为什么不推荐:**
- 路径硬编码易出错
- 性能低于直接访问
- 节点树依赖性强
- 代码复用性差

## 完整使用示例

### 访问数据

```gdscript
# ✅ 推荐
var data = DataManager.instance.get_all_albums()

# ❌ 避免
var data = get_node("/root/Main/DataManager").get_all_albums()
```

### 监听事件

```gdscript
# ✅ 推荐
if EventBus.instance:
    EventBus.instance.album_selected.connect(_on_album_selected)

# ❌ 避免
get_node("/root/Main/EventBus").album_selected.connect(_on_album_selected)
```

### 改变UI状态

```gdscript
# ✅ 推荐
UIStateManager.instance.change_state(UIStateManager.UIState.SONG_VIEW)

# ❌ 避免
get_node("/root/Main/UIStateManager").change_state(UIStateManager.UIState.SONG_VIEW)
```

### 播放动画

```gdscript
# ✅ 推荐
AnimationManager.instance.animate_fade_in(button, 0.3)

# ❌ 避免
get_node("/root/Main/AnimationManager").animate_fade_in(button, 0.3)
```

### 开始游戏

```gdscript
# ✅ 推荐
GameplayManager.instance.start_game(midi_data)

# ❌ 避免
get_node("/root/Main/GameplayManager").start_game(midi_data)
```

### 播放音频

```gdscript
# ✅ 推荐
AudioManager.instance.play_bgm(music_stream)

# ❌ 避免
get_node("/root/Main/AudioManager").play_bgm(music_stream)
```

## 安全访问模式

当需要检查Manager是否存在时，使用以下模式：

```gdscript
# 安全的nil检查
var manager = ManagerClassName.instance
if manager == null:
    push_error("Manager not initialized")
    return

manager.do_something()

# 或者使用三元操作符
if manager:
    manager.do_something()
```

## 初始化顺序

所有Manager在Main._ready()中按以下顺序初始化：

1. **GameLogger** - 日志系统
2. **ConfigLoader** - 配置加载
3. **EventBus** - 事件总线
4. **UIStateManager** - UI状态
5. **AnimationManager** - 动画系统
6. **DataManager** - 数据管理
7. **SortingEngine** - 排序引擎
8. **GameplayManager** - 游戏管理
9. **AudioManager** - 音频系统

**初始化顺序很重要** - 后续系统可能依赖前序系统。

## 测试中的使用

### 单元测试

```gdscript
func test_my_feature() -> void:
    # 直接访问单例
    var data_mgr = DataManager.instance
    assert_not_null(data_mgr)
    
    var albums = data_mgr.get_all_albums()
    assert_greater_than(albums.size(), 0)
```

### 集成测试

```gdscript
func test_system_integration() -> void:
    # 检查所有单例是否初始化
    assert_not_null(DataManager.instance)
    assert_not_null(EventBus.instance)
    assert_not_null(UIStateManager.instance)
    assert_not_null(AnimationManager.instance)
    assert_not_null(GameplayManager.instance)
    assert_not_null(AudioManager.instance)
```

## 常见问题

### Q: 为什么使用单例？
A: 单例确保只有一个实例，便于全局访问，避免创建多个浪费资源。

### Q: 如果instance为null怎么办？
A: 使用`if manager == null`检查，或在_ready()确保正确初始化顺序。

### Q: 可以在_ready()前访问Manager吗？
A: 不推荐。确保访问时节点树已初始化（通常在_ready()之后）。

### Q: 如何调试单例问题？
A: 在Main._ready()中添加日志，或在autoload中检查单例状态。

### Q: 单例会内存泄漏吗？
A: 不会。单例属于Main节点，Main销毁时单例自动释放。

## 最佳实践

✅ **DO:**
- 使用`ManagerName.instance`访问
- 总是检查null: `if manager:`
- 在Main._ready()中统一初始化
- 记录Manager状态变化
- 使用单例来共享全局状态

❌ **DON'T:**
- 硬编码节点路径
- 重复创建Manager实例
- 在_ready()之前访问Manager
- 在Manager之间创建复杂依赖
- 直接修改instance属性

## 迁移指南

如果现有代码使用了节点树查询方式，以下是迁移步骤：

### 1. 识别旧代码
```gdscript
# 旧代码示例
var manager = get_node("/root/Main/ManagerName")
```

### 2. 替换为单例方式
```gdscript
# 新代码
var manager = ManagerName.instance
```

### 3. 测试
运行相关功能测试确保工作正常

### 4. 提交
提交迁移代码并记录变更

## 相关文件

- [Core/DataManager.gd](../Core/DataManager.gd) - 数据管理单例
- [Core/EventBus.gd](../Core/EventBus.gd) - 事件总线单例
- [Core/UIStateManager.gd](../Core/UIStateManager.gd) - UI状态单例
- [UI/Animations/AnimationManager.gd](../UI/Animations/AnimationManager.gd) - 动画单例
- [Game/GameplayManager.gd](../Game/GameplayManager.gd) - 游戏管理单例
- [Game/AudioManager.gd](../Game/AudioManager.gd) - 音频单例
- [Main.gd](../Main.gd) - 单例初始化入口

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0 | 2026-01-13 | 初版 - DataManager和EventBus支持单例 |
| 1.1 | 2026-01-13 | 统一版 - 所有Manager支持单例模式 |

---

**最后更新:** 2026年1月13日  
**维护者:** THMIX开发团队
