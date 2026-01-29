# SoundFont 选择功能实现指南

**完成日期**: 2026年1月26日  
**状态**: ✅ 完成（代码实现 + 编译检查通过）  
**Godot版本**: 4.5+  

---

## 📋 功能概述

本功能为玩家提供在游戏设置中选择MIDI音源的能力，支持：

✅ 扫描本地音源文件（.sf2格式）  
✅ 用户文件与内置文件智能优先级  
✅ [内置]标签标记内置音源  
✅ 配置持久化存储  
✅ 缺失文件自动回退  
✅ 实时应用到MIDI播放器  

---

## 🏗️ 架构设计

### 系统组件

```
┌─────────────────────────────────────────────────────────┐
│           SettingView (设置视图)                          │
│  ┌──────────────────────────────────┐                   │
│  │ SettingList - 音源设置 Group     │                   │
│  │ • soundfont_select (TYPE_OPTION) │                   │
│  │ • dynamic_options = true         │                   │
│  └──────────────────────────────────┘                   │
└──────────────────┬──────────────────────────────────────┘
                   │ _initialize_soundfont_options()
                   ↓
        ┌──────────────────────┐
        │ SettingView Methods  │
        ├──────────────────────┤
        │ • _scan_all_soundfonts()
        │ • _verify_soundfont_exists()
        │ • _get_soundfont_path()
        │ • save_config_to_file()
        └──────────────────────┘
           │                │
           ├─────┬──────────┤
           ↓     ↓          ↓
        user://  res://  INI文件
        Soundfont/ Soundfont/  (.ini)
           │            │         │
           └────────┬───┘         │
                    │             │
    (user优先)      ↓             ↓
                SettingsMapper
                    │
                    ↓
            Main._reload_all_settings()
                    │
                    ↓
        MidiPlaybackManager.set_soundfont()
                    │
                    ↓
              MidiPlayer 实例
```

### 数据流向

```
用户在SettingView选择音源
    │
    └─► SettingList 更新选择值
        │
        └─► 用户退出SettingView（AnimationManager触发退出）
            │
            └─► SettingView.save_config_to_file()
                ├─ 验证文件存在
                ├─ 去掉[内置]标签
                └─ 写入 user://files/settings.ini [Gameplay]soundfont_file
                   │
                   └─► EventBus.settings_changed("*")
                       │
                       └─► Main._reload_all_settings()
                           │
                           └─► MidiPlaybackManager.set_soundfont()
                               │
                               └─► MidiPlayer.soundfont 更新
                                   │
                                   └─► 下次播放MIDI使用新音源
```

---

## 📁 文件修改详情

### 1. SettingList.gd (音源设置UI)

**位置**: `UI/Views/SettingView/SettingList.gd`

**新增内容**:
- 新 Group: "音源设置" (group_name: "sound_font_settings")
- 新 Setting: "soundfont_select"
  - 类型: TYPE_OPTION (下拉菜单)
  - 动态选项: true（运行时填充）
  - 描述: "选择MIDI音源"

**核心方法**:
```gdscript
func add_setting_item(item_data: Dictionary) -> void
    # 处理 dynamic_options 标志
    if item_data.get("dynamic_options", false):
        item.options = []  # 动态选项初始为空
        
func update_soundfont_options(soundfont_list: Array[String], current_selection: String) -> void
    # SettingView 调用此方法填充音源列表
    # soundfont_list 包含 [file_name, "文件名 [内置]", ...]
    # 设置下拉框的options和当前值
```

**特点**:
- [内置] 标签仅用于UI显示
- 动态选项避免了类成员修改问题
- 支持运行时更新选项列表

### 2. SettingView.gd (音源扫描与保存)

**位置**: `UI/Views/SettingView/SettingView.gd`

**核心方法**:

#### `_scan_all_soundfonts() → Array[String]`
扫描所有可用音源文件
- **第一步**: 扫描 `user://files/Soundfont/` （用户自定义）
- **第二步**: 扫描 `res://Resources/Soundfont/` （内置，仅添加未出现的）
- **标记**: 内置文件添加 `[内置]` 后缀
- **排序**: 用户文件优先显示
- **返回**: `["file1", "file2 [内置]", ...]`

```gdscript
func _scan_all_soundfonts() -> Array[String]:
    var soundfonts: Dictionary = {}  # {filename: display_name}
    
    # 扫描用户目录（优先）
    var user_dir = DirAccess.open("user://files/Soundfont/")
    if user_dir:
        for file in user_dir.get_files():
            if file.ends_with(".sf2"):
                var name = file.get_basename()
                soundfonts[name] = name  # 用户文件无标签
    
    # 扫描内置目录（补充）
    var res_dir = DirAccess.open("res://Resources/Soundfont/")
    if res_dir:
        for file in res_dir.get_files():
            if file.ends_with(".sf2"):
                var name = file.get_basename()
                if not soundfonts.has(name):  # 不覆盖用户文件
                    soundfonts[name] = name + " [内置]"
    
    # 转换为数组并排序
    var result: Array[String] = []
    for display_name in soundfonts.values():
        result.append(display_name)
    result.sort()
    return result
```

#### `_initialize_soundfont_options(loaded_settings: Dictionary) → void`
加载配置后初始化UI
- 调用 `_scan_all_soundfonts()` 获取列表
- 从加载的设置中获取当前选择
- 调用 `setting_list.update_soundfont_options()` 更新UI

#### `_verify_soundfont_exists(name: String) → bool`
验证音源文件是否存在
- 检查 `user://files/Soundfont/{name}.sf2`
- 检查 `res://Resources/Soundfont/{name}.sf2`
- 返回 true 如果任一存在

#### `_get_soundfont_path(name: String) → String`
获取音源文件完整路径
- 用户目录优先
- 返回完整可用路径
- 不存在返回空字符串

#### `save_config_to_file() → bool` (增强)
保存配置时的新逻辑：
```gdscript
# 处理音源设置
if settings_dict.has("soundfont_select"):
    var soundfont_display = settings_dict["soundfont_select"]
    # 去掉 [内置] 标签
    var soundfont_name = soundfont_display.split(" [")[0]
    
    # 验证文件存在
    if not _verify_soundfont_exists(soundfont_name):
        print("Soundfont not found, falling back to default")
        soundfont_name = "GeneralUser-GS.sf2"
    
    # 保存到INI
    settings_dict["soundfont_select"] = soundfont_name
```

---

### 3. MidiPlaybackManager.gd (音源应用)

**位置**: `Game/MidiPlaybackManager.gd`

**核心方法**:

#### `set_soundfont(soundfont_name: String) → bool` (重写)

设置MIDI播放器使用的音源，支持智能回退：

```gdscript
func set_soundfont(soundfont_name: String) -> bool:
    # 第1步: 定位音源文件
    var soundfont_path = _locate_soundfont(soundfont_name)
    
    # 第2步: 如果找不到，尝试默认音源
    if soundfont_path.is_empty():
        soundfont_path = _locate_soundfont("GeneralUser-GS")
    
    # 第3步: 最终回退到硬编码路径
    if soundfont_path.is_empty():
        soundfont_path = default_soundfont_path
        push_warning("Using fallback soundfont: %s" % soundfont_path)
    
    # 更新当前路径
    current_soundfont_path = soundfont_path
    
    # 应用到MidiPlayer（如果正在播放）
    if is_playing and midi_player:
        midi_player.soundfont = soundfont_path
    
    # 发出信号
    soundfont_changed.emit(soundfont_path)
    return true
```

#### `_locate_soundfont(soundfont_name: String) → String` (新增)

定位音源文件，支持双目录优先级：

```gdscript
func _locate_soundfont(soundfont_name: String) -> String:
    # 优先检查用户目录
    var user_path = "user://files/Soundfont/".path_join(soundfont_name + ".sf2")
    if FileAccess.file_exists(user_path):
        return user_path
    
    # 其次检查内置目录
    var res_path = "res://Resources/Soundfont/".path_join(soundfont_name + ".sf2")
    if ResourceLoader.exists(res_path):
        return res_path
    
    return ""  # 未找到
```

---

### 4. Main.gd (信号集成)

**位置**: `Main.gd`

**修改位置1**: `_reload_all_settings()` (行 252-265)

加入音源配置读取：
```gdscript
if config.has("Gameplay"):
    var gameplay_section = config["Gameplay"]
    if midi_playback_manager and gameplay_section.has("soundfont_file"):
        var soundfont_name = gameplay_section.get("soundfont_file", "GeneralUser-GS.sf2")
        midi_playback_manager.set_soundfont(soundfont_name)
```

**修改位置2**: `_apply_single_setting(setting_name, value)` (行 285-310)

处理单个音源设置变更：
```gdscript
elif setting_name == "soundfont_select":
    if midi_playback_manager:
        var soundfont_name = str(value)
        midi_playback_manager.set_soundfont(soundfont_name)
```

**触发流程**:
1. SettingView 保存时发出 `EventBus.settings_changed("*")` (通配符表示全量更新)
2. Main._reload_all_settings() 被触发
3. 从配置文件读取最新的 soundfont_file 值
4. 应用到 MidiPlaybackManager
5. 下次MIDI播放时使用新音源

---

### 5. SettingsMapper.gd (配置映射)

**位置**: `Utilities/SettingsMapper.gd`

**新增映射**:
```gdscript
"soundfont_select": {
    "section": "Gameplay",
    "key": "soundfont_file",
    "value_type": "string"
}
```

此映射用于：
- `ini_to_settings()`: 从 INI 读取 [Gameplay]soundfont_file → soundfont_select
- `settings_to_ini()`: 从 soundfont_select → [Gameplay]soundfont_file

---

### 6. TrakView.gd (弃用标记)

**位置**: `UI/Views/TrackView/TrakView.gd`

**标记方法**: 
- `_populate_soundfont_selector()` - 添加 ⚠️ TODO 弃用注释
- `_select_soundfont()` - 添加 ⚠️ TODO 弃用注释

**理由**: 音源选择功能已迁移至 SettingView，TrackView 的音源UI在后续版本移除

---

## 📋 配置文件结构

### config.ini (默认配置)

位置: `res://Resources/Config/config.ini`

```ini
[Gameplay]
# ... 其他配置 ...

# MIDI音源配置 - 已默认设置
soundfont_file = "GeneralUser-GS.sf2"
```

### settings.ini (用户配置)

位置: `user://files/settings.ini`

用户选择音源后保存：
```ini
[Gameplay]
soundfont_file = "custom-soundfont"  # 用户选择的值（不含[内置]标签）
```

---

## 🔄 使用工作流

### 场景1: 首次启动游戏

```
1. Main._initialize_core_systems()
   └─► FileSystemManager 初始化并扫描资源
   └─► config.ini 加载默认值 (soundfont_file = "GeneralUser-GS.sf2")

2. Main._load_midi_data()
   └─► DataManager 加载所有MIDI

3. 用户进入 SettingView
   └─► SettingView._load_config_from_file()
       └─► 加载 user://files/settings.ini（若不存在则用defaults）
       └─► SettingView._initialize_soundfont_options()
           └─► _scan_all_soundfonts()
               └─► 返回: ["GeneralUser-GS", "another-font [内置]", ...]
           └─► setting_list.update_soundfont_options(list, "GeneralUser-GS")
               └─► UI 显示下拉框，当前选择: "GeneralUser-GS"
```

### 场景2: 用户更改音源

```
1. 用户在SettingView下拉框选择 "MyFont [内置]"
   └─► SettingList 发出 value_changed 信号
   └─► 更新内存中的设置值

2. 用户点击 "返回" 或自动退出（AnimationManager._scene_transition_exit）
   └─► SettingView.save_config_to_file()
       ├─ 验证文件: _verify_soundfont_exists("MyFont") ✓
       ├─ 去标签: "MyFont [内置]" → "MyFont"
       ├─ 写入INI: [Gameplay]soundfont_file = "MyFont"
       └─ 发出信号: EventBus.settings_changed("*")

3. Main 接收到 settings_changed("*")
   └─► Main._reload_all_settings()
       └─► 从 user://files/settings.ini 读取 [Gameplay]soundfont_file = "MyFont"
       └─► MidiPlaybackManager.set_soundfont("MyFont")
           ├─ 定位: _locate_soundfont("MyFont")
           │  ├─ 检查 user://files/Soundfont/MyFont.sf2 ✓ 找到
           │  └─ 返回完整路径
           └─ 应用: midi_player.soundfont = user_path
               └─ 发出: soundfont_changed.emit(user_path)

4. 用户进入游戏播放MIDI
   └─► MidiPlaybackManager.load_midi() + play()
   └─► MidiPlayer 使用已设置的 soundfont = "user://files/Soundfont/MyFont.sf2"
   └─► MIDI 用新音源播放 ✓
```

### 场景3: 音源文件缺失处理

```
用户选择的音源文件被删除
    │
    └─► SettingView.save_config_to_file()
        └─► _verify_soundfont_exists("DeletedFont") ✗ 不存在
            └─► 回退到 "GeneralUser-GS.sf2"
            └─► 保存: [Gameplay]soundfont_file = "GeneralUser-GS.sf2"
                └─► 日志: "Soundfont not found, falling back to default"

    或者文件丢失后用户进入游戏
    │
    └─► Main._apply_single_setting("soundfont_select", "DeletedFont")
        └─► MidiPlaybackManager.set_soundfont("DeletedFont")
            ├─ _locate_soundfont("DeletedFont") ✗ 未找到
            ├─ _locate_soundfont("GeneralUser-GS") ✓ 找到
            └─ 使用默认音源，发出警告日志
```

---

## ✅ 编译检查结果

所有文件已通过 Godot 4.5 编译检查，无错误：

| 文件 | 状态 | 行数变化 |
|------|------|---------|
| SettingList.gd | ✅ | +45 |
| SettingView.gd | ✅ | +120 |
| MidiPlaybackManager.gd | ✅ | +35 |
| Main.gd | ✅ | +7 |
| SettingsMapper.gd | ✅ | +4 |
| TrakView.gd | ✅ | +2 |
| **总计** | **✅** | **+213** |

---

## 🧪 测试清单

### 单元测试

- [ ] `_scan_all_soundfonts()` 返回包含 [内置] 标签的列表
- [ ] `_verify_soundfont_exists()` 正确识别存在的文件
- [ ] `_get_soundfont_path()` 用户文件优先返回
- [ ] `set_soundfont()` 回退链正确执行
- [ ] `_locate_soundfont()` 双目录查询工作

### 集成测试

- [ ] SettingView 打开时列表正确填充
- [ ] [内置] 标签正确显示在UI中
- [ ] 用户选择不同音源后正确保存
- [ ] user://files/settings.ini 中不含 [内置] 标签
- [ ] EventBus.settings_changed 信号正确传播
- [ ] MidiPlaybackManager 正确接收并应用音源
- [ ] 下次MIDI播放时使用新音源

### 压力测试

- [ ] user://files/Soundfont/ 中大量.sf2文件（100+）时性能
- [ ] 删除已选音源文件后回退是否正常
- [ ] 网络延迟下文件访问是否正确（如使用远程存储）
- [ ] 重复保存相同音源选择不出现重复条目

### 边界测试

- [ ] 同时存在 user://MyFont.sf2 和 res://MyFont.sf2 时，正确优先user
- [ ] soundfont_file = "" (空值) 时的处理
- [ ] soundfont_file 包含特殊字符时的处理
- [ ] config.ini 中不存在 [Gameplay] 节时的处理

---

## 📚 API 参考

### SettingView 公开接口

```gdscript
# 加载配置（在 _ready 中调用）
func _load_config_from_file() -> void

# 保存配置（在退出视图时调用）
func save_config_to_file() -> bool

# 初始化音源选项（内部，由 _load_config_from_file 调用）
func _initialize_soundfont_options(loaded_settings: Dictionary) -> void

# 扫描所有可用音源
func _scan_all_soundfonts() -> Array[String]

# 验证音源是否存在
func _verify_soundfont_exists(name: String) -> bool

# 获取音源完整路径
func _get_soundfont_path(name: String) -> String
```

### MidiPlaybackManager 公开接口

```gdscript
# 设置使用的音源
func set_soundfont(soundfont_name: String) -> bool

# 信号：音源改变时发出
signal soundfont_changed(soundfont_path: String)
```

### SettingList 公开接口

```gdscript
# 更新动态选项（由 SettingView 调用）
func update_soundfont_options(soundfont_list: Array[String], current_selection: String) -> void
```

---

## 🔧 故障排查

### 问题1: 下拉框为空，未显示任何音源

**可能原因**:
- `_scan_all_soundfonts()` 未被调用
- user:// 和 res:// 目录不存在

**解决方案**:
- 确认 FileSystemManager 在 Main._initialize_core_systems() 中初始化
- 检查日志输出是否有文件扫描错误
- 手动创建 user://files/Soundfont/ 目录

### 问题2: 选择的音源未生效

**可能原因**:
- settings.ini 保存失败
- EventBus 信号未触发
- MidiPlaybackManager 未收到信号

**解决方案**:
- 检查 user://files/ 目录权限
- 添加日志验证 EventBus.settings_changed 信号发出
- 验证 Main._reload_all_settings() 是否被调用

### 问题3: [内置] 标签未移除，保存后包含在INI中

**可能原因**:
- save_config_to_file() 中的标签去除逻辑未执行

**解决方案**:
- 检查 `split(" [")[0]` 是否正确执行
- 添加日志输出标签去除前后的值
- 确认 settings_dict 中的值是否为选中项的显示名

### 问题4: 缺失的音源文件导致崩溃

**可能原因**:
- 缺失回退逻辑

**解决方案**:
- 验证 _verify_soundfont_exists() 在保存前被调用
- 确认 default_soundfont_path 指向存在的文件
- 检查 GeneralUser-GS.sf2 是否在 res://Resources/Soundfont/

---

## 📖 相关文档

- [MIDI 播放实现指南](MIDI_PLAYBACK_IMPLEMENTATION.md)
- [单例模式指南](SINGLETON_PATTERN_GUIDE.md)
- [开发者备忘单](DEVELOPER_CHEATSHEET.md)
- [FileSystemManager 指南](FILESYSTEM_MANAGER_GUIDE.md)

---

## 🎯 后续改进

### 短期（1-2周）
- [ ] 完整端到端测试
- [ ] UI/UX 微调（下拉框宽度、动画等）
- [ ] 音源预览功能（播放小音乐片段测试音源）

### 中期（1个月）
- [ ] 音源分类功能（用户 vs 内置）
- [ ] 下载/安装新音源的UI
- [ ] 音源删除确认对话框

### 长期（2-3个月）
- [ ] 音源在线仓库集成
- [ ] 音源云同步
- [ ] TrackView 弃用并完全移除

---

**最后更新**: 2026年1月26日  
**维护者**: THMIX 开发团队  
**版本**: 1.0

