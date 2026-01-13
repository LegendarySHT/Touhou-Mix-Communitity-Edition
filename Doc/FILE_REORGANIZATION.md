# 文件重组织记录

## 重组日期
2026年1月13日

## 重组目标
- 清理根目录，提高项目结构可读性
- 将文件按功能分类到合适的目录
- 集中管理文档文件

## 文件移动记录

### 文档文件 → DOC/
```
README.md                    → DOC/README.md
QUICK_START.md              → DOC/QUICK_START.md
REFACTOR_SUMMARY.md         → DOC/REFACTOR_SUMMARY.md
ARCHITECTURE_OVERVIEW.md    → DOC/ARCHITECTURE_OVERVIEW.md
DEVELOPER_CHEATSHEET.md     → DOC/DEVELOPER_CHEATSHEET.md
COMPLETION_CHECKLIST.md     → DOC/COMPLETION_CHECKLIST.md
MIGRATION_PROGRESS.md       → DOC/MIGRATION_PROGRESS.md
INDEX.md                    → DOC/INDEX.md
```

### 场景文件 → Scenes/
```
MidiStore.tscn              → Scenes/MidiStore.tscn
```

### UI脚本 → UI/Components/
```
background.gd               → UI/Components/background.gd
background.gd.uid           → UI/Components/background.gd.uid
camera_2d.gd                → UI/Components/camera_2d.gd
camera_2d.gd.uid            → UI/Components/camera_2d.uid
shortcut_menu.gd            → UI/Components/shortcut_menu.gd
shortcut_menu.gd.uid        → UI/Components/shortcut_menu.gd.uid
sort_button.gd              → UI/Components/sort_button.gd
sort_button.gd.uid          → UI/Components/sort_button.gd.uid
store_button.gd             → UI/Components/store_button.gd
store_button.gd.uid         → UI/Components/store_button.gd.uid
Sorted_Midi_Scroll.gd       → UI/Components/Sorted_Midi_Scroll.gd
Sorted_Midi_Scroll.gd.uid   → UI/Components/Sorted_Midi_Scroll.gd.uid
```

### UI视图 → UI/Views/
```
SettingPage.gd              → UI/Views/SettingPage.gd
SettingPage.gd.uid          → UI/Views/SettingPage.gd.uid
```

### 资源文件 → Resources/
```
方正黑体_GBK.ttf             → Resources/Fonts/方正黑体_GBK.ttf
方正黑体_GBK.ttf.import      → Resources/Fonts/方正黑体_GBK.ttf.import
ButtonGroup/                → Resources/ButtonGroup/
Gradient/                   → Resources/Gradient/
icon/                       → Resources/icon/
song_cover/                 → Resources/song_cover/
midis_info/                 → Resources/midis_info/
```

### 工具文件 → Utilities/
```
testsong.txt                → Utilities/testsong.txt
```

## 根目录保留文件

这些文件必须保留在根目录：
```
Main.gd                     # 主入口脚本
Main.tscn                   # 主场景
Global.gd                   # 全局单例
project.godot               # Godot项目配置
export_presets.cfg          # 导出配置
.gitignore                  # Git配置
.gitattributes              # Git属性
.editorconfig               # 编辑器配置
```

## 目录结构（重组后）

```
THMIX Community Version/
├── .godot/                 # Godot引擎生成文件
├── Core/                   # 核心业务逻辑
│   ├── Models/
│   ├── DataManager.gd
│   ├── SortingEngine.gd
│   ├── UIStateManager.gd
│   └── EventBus.gd
├── DOC/                    # 项目文档 ✨ 新建
│   ├── README.md
│   ├── QUICK_START.md
│   ├── REFACTOR_SUMMARY.md
│   ├── ARCHITECTURE_OVERVIEW.md
│   ├── DEVELOPER_CHEATSHEET.md
│   ├── COMPLETION_CHECKLIST.md
│   ├── MIGRATION_PROGRESS.md
│   ├── INDEX.md
│   └── FILE_REORGANIZATION.md
├── Game/                   # 游戏逻辑
│   ├── GameplayManager.gd
│   ├── AudioManager.gd
│   ├── ScoreCalculator.gd
│   └── NotesRenderer.gd
├── Resources/              # 资源文件
│   ├── ButtonGroup/
│   ├── Config/
│   ├── Fonts/              # ✨ 新建
│   │   └── 方正黑体_GBK.ttf
│   ├── Gradient/
│   ├── icon/
│   ├── midis_info/
│   ├── Skins/
│   ├── song_cover/
│   └── Songs/
├── Scene/                  # 原有场景脚本（待迁移）
│   └── AlbumList.gd
│   └── ...
├── Scenes/                 # 场景文件 ✨ 新建
│   └── MidiStore.tscn
├── UI/                     # 用户界面
│   ├── Animations/
│   │   └── AnimationManager.gd
│   ├── Components/
│   │   ├── BaseScrollList.gd
│   │   ├── ListItemBase.gd
│   │   ├── background.gd
│   │   ├── camera_2d.gd
│   │   ├── shortcut_menu.gd
│   │   ├── sort_button.gd
│   │   ├── store_button.gd
│   │   └── Sorted_Midi_Scroll.gd
│   └── Views/              # ✨ 新建
│       └── SettingPage.gd
├── Utilities/              # 工具类
│   ├── ConfigLoader.gd
│   ├── Logger.gd
│   ├── MigrationHelper.gd
│   ├── IntegrationTest.gd
│   ├── QuickTest.gd
│   └── testsong.txt
├── Main.gd                 # 主入口
├── Main.tscn              # 主场景
├── Global.gd              # 全局单例
├── project.godot          # 项目配置
└── export_presets.cfg     # 导出配置
```

## 需要更新的引用

### 1. 场景文件中的脚本路径
所有使用了移动脚本的 `.tscn` 文件需要更新 `script` 引用路径

### 2. GDScript 中的预加载路径
```gdscript
# 旧路径示例
preload("res://SettingPage.gd")
preload("res://background.gd")

# 新路径
preload("res://UI/Views/SettingPage.gd")
preload("res://UI/Components/background.gd")
```

### 3. 节点路径获取
如果有使用相对路径或绝对路径获取节点，需要确认是否受影响

### 4. 资源路径
```gdscript
# 旧路径
load("res://方正黑体_GBK.ttf")
load("res://icon/xxx.png")

# 新路径
load("res://Resources/Fonts/方正黑体_GBK.ttf")
load("res://Resources/icon/xxx.png")
```

## 注意事项

1. **Godot会自动更新某些引用**：当文件移动时，Godot编辑器通常会自动更新场景文件中的引用
2. **手动检查**：建议打开Godot编辑器检查是否有"missing script"或"missing resource"错误
3. **测试**：移动后需要测试所有功能确保路径正确
4. **版本控制**：如果使用Git，注意文件移动的提交信息

## 后续行动

- [ ] 在Godot编辑器中打开项目
- [ ] 检查控制台是否有路径错误
- [ ] 测试所有场景和脚本
- [ ] 更新任何硬编码的路径
- [ ] 继续将 Scene/ 目录中的旧代码迁移到 UI/Views/

## 参考文档

相关文档位置：
- 架构总览：[DOC/ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md)
- 迁移进度：[DOC/MIGRATION_PROGRESS.md](MIGRATION_PROGRESS.md)
- 开发指南：[DOC/DEVELOPER_CHEATSHEET.md](DEVELOPER_CHEATSHEET.md)
