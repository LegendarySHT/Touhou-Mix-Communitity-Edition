# 📖 项目文档索引

欢迎使用 **THMIX Community Version 重构版**！

本页面是项目文档的中心枢纽，帮助你快速找到所需的信息。

---

## 🎯 按用途快速查找

### 我是新开发者，不了解项目

👉 从这里开始：
1. **[README.md](README.md)** - 5分钟了解项目是什么
2. **[QUICK_START.md](QUICK_START.md)** - 10分钟学会基本用法
3. **[ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md)** - 理解项目结构

### 我需要快速查找代码示例

👉 查看：
- **[DEVELOPER_CHEATSHEET.md](DEVELOPER_CHEATSHEET.md)** - 常用代码片段速查表
- **[QUICK_START.md](QUICK_START.md)** - 常见用法示例章节

### 我需要了解完整的架构设计

👉 阅读：
- **[REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md)** - 详细的架构说明文档
- **[ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md)** - 架构可视化和流程图

### 我需要检查重构完成情况

👉 查看：
- **[COMPLETION_CHECKLIST.md](COMPLETION_CHECKLIST.md)** - 重构完成清单和统计数据
- **[MIGRATION_PROGRESS.md](MIGRATION_PROGRESS.md)** - 迁移进度追踪

### 我需要了解文件重组织情况

👉 查看：
- **[FILE_REORGANIZATION.md](FILE_REORGANIZATION.md)** - 文件移动记录和路径更新指南

### 我需要修改特定功能

👉 根据功能找文件：

| 功能 | 文件 | 文档 |
|------|------|------|
| 数据管理 | Core/DataManager.gd | [QUICK_START.md](QUICK_START.md#第一步) |
| 排序过滤 | Core/SortingEngine.gd | [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#核心数据层) |
| UI状态 | Core/UIStateManager.gd | [QUICK_START.md](QUICK_START.md#监听游戏状态) |
| 全局事件 | Core/EventBus.gd | [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#全局事件总线) |
| UI组件 | UI/Components/ | [QUICK_START.md](QUICK_START.md#第二步) |
| 动画 | UI/Animations/AnimationManager.gd | [QUICK_START.md](QUICK_START.md#添加带有动画的按钮) |
| 游戏逻辑 | Game/*.gd | [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#游戏逻辑框架) |

---

## 📚 完整文档导航

### 项目文档 (4个文件)

| 文件 | 适合谁 | 阅读时间 | 内容 |
|------|--------|----------|------|
| **[README.md](README.md)** | 所有人 | 5-10分钟 | 项目概述、架构、功能介绍 |
| **[QUICK_START.md](QUICK_START.md)** | 开发者 | 15-20分钟 | 快速入门、代码示例、常见问题 |
| **[REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md)** | 架构师 | 30-45分钟 | 详细重构说明、迁移步骤、使用指南 |
| **[ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md)** | 设计师 | 20-30分钟 | 结构可视化、依赖关系、流程图 |

### 开发文档 (4个文件)

| 文件 | 用途 | 何时查看 |
|------|------|---------|
| **[DEVELOPER_CHEATSHEET.md](DEVELOPER_CHEATSHEET.md)** | 快速参考 | 日常开发 |
| **[COMPLETION_CHECKLIST.md](COMPLETION_CHECKLIST.md)** | 项目状态 | 了解进度 |
| **[MIGRATION_PROGRESS.md](MIGRATION_PROGRESS.md)** | 迁移进度 | 迁移过程中 |
| **[FILE_REORGANIZATION.md](FILE_REORGANIZATION.md)** | 文件重组 | 路径问题排查 |

### 源代码文件 (19个)

#### Core 层 (7个文件)
```
Core/
├── Models/
│   ├── MidiData.gd          数据模型
│   ├── SongData.gd          数据模型
│   └── AlbumData.gd         数据模型
├── DataManager.gd           数据管理
├── SortingEngine.gd         排序引擎
├── UIStateManager.gd        状态管理
└── EventBus.gd             事件总线
```

#### UI 层 (3个文件)
```
UI/
├── Components/
│   ├── ListItemBase.gd      列表项基类
│   └── BaseScrollList.gd    滚动列表基类
└── Animations/
    └── AnimationManager.gd  动画管理
```

#### Game 层 (4个文件)
```
Game/
├── GameplayManager.gd       游戏管理
├── AudioManager.gd          音频管理
├── ScoreCalculator.gd       分数计算
└── NotesRenderer.gd         谱面渲染
```

#### Resources 层 (3个文件)
```
Resources/
├── Config/config.ini        全局配置
├── Skins/default_theme.ini  默认主题
└── Songs/song_template.ini  歌曲模板
```

#### Utilities 层 (2个文件)
```
Utilities/
├── ConfigLoader.gd          配置加载器
└── Logger.gd               日志系统
```

---

## 🗺️ 文档知识图

```
开始 ──► README.md (项目概述)
        │
        ├──► QUICK_START.md (快速上手)
        │    ├──► 创建视图示例
        │    ├──► 常见用法
        │    └──► 常见问题
        │
        ├──► ARCHITECTURE_OVERVIEW.md (结构可视化)
        │    ├──► 目录树
        │    ├──► 数据流向
        │    └──► 交互流程
        │
        ├──► REFACTOR_SUMMARY.md (深入详解)
        │    ├──► 架构改进对比
        │    ├──► 后续迁移步骤
        │    └──► 调试技巧
        │
        └──► DEVELOPER_CHEATSHEET.md (开发速查)
             ├──► 常用代码片段
             ├──► 常见任务
             └──► 快速修复
```

---

## 📖 阅读建议

### 对于不同的角色

#### 👨‍💼 项目经理
- 阅读: README.md、COMPLETION_CHECKLIST.md
- 关注: 功能完成度、时间表、质量指标

#### 🏗️ 系统架构师
- 阅读: ARCHITECTURE_OVERVIEW.md、REFACTOR_SUMMARY.md
- 关注: 架构设计、模块依赖、扩展性

#### 💻 核心开发者
- 阅读: 所有文档
- 关注: 代码结构、API设计、性能指标

#### 🎨 UI/UX 开发者
- 阅读: QUICK_START.md、DEVELOPER_CHEATSHEET.md
- 关注: UI组件、动画管理、状态管理

#### 🎮 游戏逻辑开发者
- 阅读: REFACTOR_SUMMARY.md、Game/目录注释
- 关注: 游戏框架、分数计算、音频管理

#### 🧪 QA/测试
- 阅读: COMPLETION_CHECKLIST.md、DEVELOPER_CHEATSHEET.md
- 关注: 功能覆盖率、已知问题、调试方法

---

## 🔍 按关键词搜索

### 数据相关
- 数据管理: [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#数据管理datamanagergd)
- 数据模型: [Core/Models/](Core/Models/)
- 数据查询: [QUICK_START.md](QUICK_START.md#1-获取和显示midi列表)
- 排序和过滤: [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#排序引擎sortenginegd)

### UI相关
- UI状态: [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#ui状态管理uistatemanagergd)
- 列表组件: [QUICK_START.md](QUICK_START.md#第二步-创建一个专辑列表视图)
- 动画: [QUICK_START.md](QUICK_START.md#3-添加带有动画的按钮)
- 事件系统: [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#全局事件总线eventbusgd)

### 游戏相关
- 游戏流程: [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#游戏管理器gameplaymanagergd)
- 分数系统: [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#分数计算器scorecalculatorgd)
- 音频管理: [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#音频管理audiomanagergd)

### 配置和工具
- 配置文件: [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#游戏配置resourcesconfigconfigini)
- 主题系统: [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#主题配置resourcesskinsdefault_themeini)
- 日志系统: [Utilities/Logger.gd](Utilities/Logger.gd)

### 迁移和升级
- 迁移步骤: [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md#后续迁移步骤)
- 集成指南: [QUICK_START.md](QUICK_START.md#第一步-在-maingd-中初始化核心系统)
- 最佳实践: [DEVELOPER_CHEATSHEET.md](DEVELOPER_CHEATSHEET.md#-最佳实践)

---

## 🎓 学习路径推荐

### 完全新手 (2小时)
1. README.md (10分钟)
2. ARCHITECTURE_OVERVIEW.md (20分钟)
3. QUICK_START.md (30分钟)
4. 动手写一个简单列表 (60分钟)

### 有经验的开发者 (1小时)
1. QUICK_START.md (20分钟)
2. REFACTOR_SUMMARY.md 浏览关键部分 (20分钟)
3. DEVELOPER_CHEATSHEET.md (10分钟)
4. 查看源代码注释 (10分钟)

### 架构师或高级开发者 (90分钟)
1. README.md (10分钟)
2. ARCHITECTURE_OVERVIEW.md (30分钟)
3. REFACTOR_SUMMARY.md 详细阅读 (40分钟)
4. 查看所有源代码设计 (10分钟)

---

## 📊 文档统计

| 类型 | 数量 | 总字数 |
|------|------|--------|
| 核心文档 | 4 | ~3500 |
| 开发文档 | 2 | ~2500 |
| 源代码 | 19 | ~2500(代码) |
| 配置文件 | 3 | ~200 |
| **总计** | **28** | **~8700+** |

---

## 🔗 快速链接

### 本地文件
- [项目根目录](.)
- [Core/ 核心模块](Core/)
- [UI/ 用户界面](UI/)
- [Game/ 游戏逻辑](Game/)
- [Resources/ 资源配置](Resources/)
- [Utilities/ 工具类](Utilities/)

### 重要配置
- [全局配置](Resources/Config/config.ini)
- [UI主题](Resources/Skins/default_theme.ini)
- [歌曲模板](Resources/Songs/song_template.ini)

---

## ❓ 常见问题快速答案

**Q: 我应该从哪里开始？**  
A: 从 [README.md](README.md) 开始

**Q: 我想快速学会怎么用？**  
A: 看 [QUICK_START.md](QUICK_START.md)

**Q: 我想了解架构设计？**  
A: 阅读 [ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md) 和 [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md)

**Q: 我需要代码示例？**  
A: 查看 [DEVELOPER_CHEATSHEET.md](DEVELOPER_CHEATSHEET.md)

**Q: 我想修改某个功能，应该改哪个文件？**  
A: 查看本页面的"按用途快速查找"表格

**Q: 这个项目的状态怎么样？**  
A: 查看 [COMPLETION_CHECKLIST.md](COMPLETION_CHECKLIST.md)

---

## 📞 获取帮助

如果你在文档中找不到答案：

1. **查看源代码注释** - 每个文件都有详细的GDScript文档注释
2. **查看DEVELOPER_CHEATSHEET** - 可能有你要找的快速修复
3. **联系开发团队** - 提出Issue或讨论

---

## 🚀 下一步

现在你已经了解了文档的结构，选择你需要的文件开始吧！

**建议按顺序阅读：**
1. [README.md](README.md) - 了解项目
2. [QUICK_START.md](QUICK_START.md) - 学会基本用法
3. 查看源代码 - 深入理解实现

祝你开发愉快！🎉

---

**最后更新**: 2026年1月13日  
**文档版本**: 1.0  
**Godot版本**: 4.5+
