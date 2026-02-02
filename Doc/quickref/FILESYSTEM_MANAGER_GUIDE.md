# 文件系统管理器使用指南

**创建日期:** 2026年1月20日  
**版本:** 1.0

## 概述

FileSystemManager 是 THMIX 项目的文件系统管理核心，负责管理 `user://` 目录下的所有游戏资源，包括谱面、皮肤、音源、背景图、日志和设置。

## 目录结构

游戏启动时会在 `user://` 目录下创建以下结构：

```
user://
├── BackgroundImage/          # 背景图片
│   └── *.jpg, *.png
│
├── Charts/                   # 谱面资源
│   ├── *.json                # 兼容旧格式：单个 JSON 文件
│   └── example_chart/        # 新格式：谱面文件夹
│       ├── example_chart.json    # 谱面元数据
│       ├── example_chart.mid     # MIDI 文件
│       ├── example_chart.ogg     # 音频文件
│       └── example_chart.jpg     # 封面（可选）
│
├── Logs/                     # 游戏日志
│   └── game_YYYY-MM-DD.log   # 按日期命名的日志文件
│
├── Skins/                    # 自定义皮肤
│   └── SkinName/             # 一个皮肤一个文件夹
│       ├── instant.png       # 瞬时音符
│       ├── short.png         # 短音符
│       ├── long-f.png        # 长音符前端
│       ├── long-t.png        # 长音符尾部
│       └── long-b.png        # 长音符主体
│
├── Settings/                 # 玩家设置
│   └── (设置文件，格式待定)
│
└── Soundfont/               # 音源文件
    └── *.sf2                # SoundFont 2 文件
```

## 初始化流程

### 自动初始化

FileSystemManager 在 `Main.gd` 中自动初始化，流程如下：

1. **创建目录结构** - 检查并创建所有必需目录
2. **复制默认资源** - 如果目录为空，从 `res://Resources/` 复制默认内容
3. **扫描资源** - 索引所有可用资源
4. **发送就绪信号** - 通知其他系统资源已准备完毕

### 初始化顺序

在 `Main._initialize_core_systems()` 中：

```gdscript
1. GameLogger          # 日志系统
2. ConfigLoader        # 配置加载
3. FileSystemManager   # 文件系统（本模块）
4. EventBus            # 事件总线
5. UIStateManager      # UI状态
...
```

## 使用方式

### 访问单例

```gdscript
var fs_mgr = FileSystemManager.instance
if fs_mgr:
    # 使用文件系统管理器
    pass
```

### 获取目录路径

```gdscript
# 获取各个目录的路径
var charts_dir = FileSystemManager.instance.get_charts_directory()
var logs_dir = FileSystemManager.instance.get_logs_directory()
var settings_dir = FileSystemManager.instance.get_settings_directory()

# 也可以直接访问常量
var skins_dir = FileSystemManager.SKINS_DIR
var soundfont_dir = FileSystemManager.SOUNDFONT_DIR
```

### 查询资源索引

```gdscript
# 获取谱面索引
var charts = FileSystemManager.instance.get_charts_index()
for chart_id in charts.keys():
    var metadata = charts[chart_id]
    print("Chart: %s, Complete: %s" % [chart_id, metadata["is_complete"]])

# 获取皮肤索引
var skins = FileSystemManager.instance.get_skins_index()
for skin_name in skins.keys():
    var metadata = skins[skin_name]
    print("Skin: %s, Path: %s" % [skin_name, metadata["path"]])

# 获取音源索引
var soundfonts = FileSystemManager.instance.get_soundfonts_index()
for sf_name in soundfonts.keys():
    var path = soundfonts[sf_name]
    print("Soundfont: %s at %s" % [sf_name, path])
```

### 获取资源路径

```gdscript
# 获取特定谱面的路径
var chart_path = FileSystemManager.instance.get_chart_path("my_chart_id")

# 获取特定皮肤的路径
var skin_path = FileSystemManager.instance.get_skin_path("Academy")
```

### 验证谱面完整性

```gdscript
var chart_id = "example_chart"
if FileSystemManager.instance.validate_chart(chart_id):
    print("Chart is complete and ready to play")
else:
    print("Chart is missing required files")
```

### 热重载资源

当用户手动添加新资源到 `user://` 目录后，可以重新扫描：

```gdscript
FileSystemManager.instance.rescan_resources()
```

### 监听事件

```gdscript
func _ready():
    var fs_mgr = FileSystemManager.instance
    
    # 监听初始化完成
    fs_mgr.initialization_complete.connect(_on_filesystem_initialized)
    
    # 监听资源扫描完成
    fs_mgr.resource_scan_completed.connect(_on_resource_scanned)
    
    # 监听资源就绪
    fs_mgr.resources_ready.connect(_on_resources_ready)
    
    # 监听错误
    fs_mgr.resource_error.connect(_on_resource_error)

func _on_filesystem_initialized():
    print("Filesystem initialized")

func _on_resource_scanned(resource_type: String, count: int):
    print("Scanned %d %s" % [count, resource_type])

func _on_resources_ready():
    print("All resources ready")

func _on_resource_error(error_message: String):
    print("Error: %s" % error_message)
```

## 谱面格式

### 新格式（推荐）

每个谱面是一个独立文件夹，包含所有资源：

```
Charts/
└── my_awesome_chart/
    ├── my_awesome_chart.json    # 元数据（必需）
    ├── my_awesome_chart.mid     # MIDI 文件（必需）
    ├── my_awesome_chart.ogg     # 音频文件（必需）
    └── my_awesome_chart.jpg     # 封面（可选）
```

**JSON 元数据格式：**

```json
{
    "_id": "my_awesome_chart",
    "name": "My Awesome Chart",
    "artist": "Composer Name",
    "sourceSongName": "Original Song",
    "sourceAlbumName": "Original Album",
    "difficulty": 5,
    "status": "APPROVED",
    "uploadedDate": "2026-01-20T00:00:00Z"
}
```

### 旧格式（兼容）

单个 JSON 文件直接放在 Charts 目录：

```
Charts/
└── 5c9721a12d2ced64fbd027a5.json
```

FileSystemManager 会同时扫描两种格式。

## 皮肤格式

每个皮肤是一个文件夹，包含 5 个必需的 PNG 图片：

```
Skins/
└── MySkin/
    ├── instant.png      # 瞬时音符（必需）
    ├── short.png        # 短音符（必需）
    ├── long-f.png       # 长音符前端（必需）
    ├── long-t.png       # 长音符尾部（必需）
    └── long-b.png       # 长音符主体（必需）
```

缺少任何必需文件的皮肤会被标记为不完整但仍会被索引。

## 玩家自定义内容

### 添加谱面

1. 创建谱面文件夹：`user://Charts/my_chart/`
2. 添加必需文件：`.json`, `.mid`, `.ogg`
3. 重启游戏或调用 `rescan_resources()`

### 添加皮肤

1. 创建皮肤文件夹：`user://Skins/MySkin/`
2. 添加 5 个必需的 PNG 文件
3. 重启游戏或调用 `rescan_resources()`

### 添加音源

1. 将 `.sf2` 文件放入：`user://Soundfont/`
2. 重启游戏或调用 `rescan_resources()`

## 默认资源管理

### 默认资源来源

- **谱面:** `res://Resources/midis_info/*.json`
- **皮肤:** `res://Resources/Skins/*/`
- **音源:** `res://Resources/Soundfont/*.sf2`
- **背景:** `res://Resources/BackgroundImage/*`

### 自动复制逻辑

FileSystemManager 在初始化时检查每个目录：

1. 如果目录为空 → 从 `res://Resources/` 复制默认内容
2. 如果目录有内容 → 跳过复制，使用现有内容

这允许玩家：
- 保留自定义内容
- 删除某个目录让游戏恢复默认
- 混合使用默认和自定义资源

## 与其他系统集成

### DataManager

DataManager 现在使用 FileSystemManager 提供的谱面目录：

```gdscript
# DataManager.gd 中
var midis_dir = FileSystemManager.instance.get_charts_directory()
```

### GameLogger

Logger 现在使用 FileSystemManager 提供的日志目录：

```gdscript
# Logger.gd 中
var logs_dir = FileSystemManager.instance.get_logs_directory()
var log_file_path = logs_dir.path_join("game_%s.log" % date)
```

### EventBus

FileSystemManager 通过 EventBus 发送文件系统相关事件：

```gdscript
# 事件信号
signal filesystem_initialized
signal resources_scanned(resource_type: String, count: int)
signal chart_imported(chart_id: String)
signal skin_imported(skin_name: String)
signal resource_validation_failed(resource_id: String, reason: String)
```

## 调试和测试

### 测试脚本

使用 `Utilities/FileSystemTest.gd` 测试文件系统功能：

1. 将脚本添加到场景
2. 运行游戏
3. 查看控制台输出

### 查看 user:// 目录

在不同平台上的 `user://` 位置：

- **Windows:** `%APPDATA%\Godot\app_userdata\[项目名]\`
- **Linux:** `~/.local/share/godot/app_userdata/[项目名]/`
- **macOS:** `~/Library/Application Support/Godot/app_userdata/[项目名]/`

可以在 Godot 编辑器中打开：
```
Project → Open User Data Folder
```

### 日志

所有文件系统操作都会记录到日志：

```gdscript
GameLogger.instance.info("Message", "FileSystemMGR")
```

查看日志文件：`user://Logs/game_YYYY-MM-DD.log`

## 性能考虑

### 异步加载

- 默认资源复制在后台线程执行，不阻塞启动
- 资源扫描在复制完成后执行
- 使用 `resources_ready` 信号等待资源就绪

### 缓存

- 资源索引缓存在内存中
- 调用 `rescan_resources()` 重建索引
- 不需要频繁扫描，只在需要时调用

### 文件操作

- 使用 `DirAccess` 和 `FileAccess` API
- 递归复制皮肤目录（保持结构）
- 仅复制指定扩展名的文件

## 常见问题

### Q: 如何清空所有用户数据？

A: 手动删除 `user://` 目录内容，下次启动会重新创建并填充默认资源。

### Q: 谱面文件夹和 JSON 文件有什么区别？

A: 文件夹格式是新格式，包含所有资源；JSON 文件是旧格式（向后兼容），仅包含元数据。

### Q: 可以在游戏运行时添加资源吗？

A: 可以，添加后调用 `FileSystemManager.instance.rescan_resources()` 重新扫描。

### Q: 皮肤文件必须是 PNG 吗？

A: 是的，当前实现只支持 PNG 格式。

### Q: 如何知道资源是否加载完成？

A: 连接 `resources_ready` 信号或检查 `is_initialized` 标志。

## 未来扩展

### 计划功能

- [ ] 谱面导入/导出功能
- [ ] 资源包格式支持（.zip）
- [ ] 在线资源下载
- [ ] 资源更新检测
- [ ] 缩略图缓存
- [ ] 资源元数据验证

### Settings 目录

目前 Settings 目录已创建但未使用。未来可用于：

- 玩家配置文件
- 按键绑定
- 游戏进度
- 统计数据

推荐格式：JSON（灵活）或 INI（兼容现有 ConfigLoader）

## 相关文件

- **核心实现:** [Core/FileSystemManager.gd](../Core/FileSystemManager.gd)
- **事件定义:** [Core/EventBus.gd](../Core/EventBus.gd)
- **初始化入口:** [Main.gd](../Main.gd)
- **数据管理集成:** [Core/DataManager.gd](../Core/DataManager.gd)
- **日志集成:** [Utilities/Logger.gd](../Utilities/Logger.gd)
- **测试脚本:** [Utilities/FileSystemTest.gd](../Utilities/FileSystemTest.gd)

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0 | 2026-01-20 | 初始实现 - 完整的文件系统管理器 |

---

**最后更新:** 2026年1月20日  
**维护者:** THMIX 开发团队
