# FileSystemManager 快速指南

## 职责

`Core/FileSystemManager.gd` 负责：

1. 初始化 `user://files` 目录结构
2. 扫描资源（Charts / Soundfont / Skins / BackgroundImage）
3. 维护资源索引（如 `charts_index`）

## 初始化入口

在 `Main._initialize_core_systems()` 中：

```gdscript
filesystem_manager = FileSystemManager.new()
add_child(filesystem_manager)
filesystem_manager.initialize_directory_structure()
```

## 关键状态

- `is_initialized`
- `resources_scanned`
- `charts_index: Dictionary`

## 常用接口

```gdscript
var charts = FileSystemManager.instance.get_charts_index()
var chart_json = FileSystemManager.instance.get_chart_json_path(chart_id)
```

## 与 DataManager 的关系

- `DataManager.load_all_midis_async()` 依赖 `charts_index`
- 因此必须先完成目录初始化与资源扫描

## 常见问题

### `charts_index` 为空
- 检查 `Resources/Charts` 或 `user://files/Charts` 是否有合法条目
- 检查是否在扫描完成前就触发了数据加载

### 路径跨平台异常
- 使用 `PathHelper` 获取路径，不要手写平台分支路径
