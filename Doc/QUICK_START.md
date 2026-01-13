# 新架构快速入门指南

## 🎯 核心概念

新架构分为 5 个层次：

```
┌─────────────────────────────────────┐
│   UI 层 (UI/)                       │  <- 用户界面
├─────────────────────────────────────┤
│   事件总线 (EventBus)               │  <- 组件通信
├─────────────────────────────────────┤
│   状态管理 (UIStateManager)         │  <- UI状态控制
├─────────────────────────────────────┤
│   数据层 (Core/)                    │  <- 数据管理和排序
└─────────────────────────────────────┘
│   游戏逻辑 (Game/)                  │  <- 游戏实现
└─────────────────────────────────────┘
```

---

## 🚀 快速开始

### 第一步: 在 Main.gd 中初始化核心系统

```gdscript
# Main.gd

extends Node

func _ready() -> void:
	# 1. 实例化数据管理器
	var data_manager = DataManager.new()
	add_child(data_manager)
	
	# 2. 实例化事件总线
	var event_bus = EventBus.new()
	add_child(event_bus)
	
	# 3. 实例化状态管理器
	var state_manager = UIStateManager.new()
	add_child(state_manager)
	
	# 4. 实例化动画管理器
	var animation_manager = AnimationManager.new()
	add_child(animation_manager)
	
	# 5. 异步加载MIDI数据
	data_manager.load_all_midis_async()
	data_manager.data_loaded.connect(_on_data_loaded)

func _on_data_loaded() -> void:
	print("Data loaded successfully!")
	# 现在可以开始使用数据
	var albums = DataManager.instance.get_all_albums()
	print("Total albums: %d" % albums.size())
```

### 第二步: 创建一个专辑列表视图

```gdscript
# UI/Views/AlbumView.gd

extends BaseScrollList
class_name AlbumView

@onready var vbox = $VBoxContainer

func _ready() -> void:
	# 设置容器
	container = vbox
	item_size = 100.0
	item_spacing = 10.0
	enable_snap = true
	
	# 监听数据加载完成
	EventBus.data_loaded_complete.connect(_on_data_loaded)
	
	# 监听列表项选择
	item_focused.connect(_on_item_focused)

func _on_data_loaded() -> void:
	# 获取所有专辑
	var albums = DataManager.instance.get_all_albums()
	
	# 添加到列表
	for album in albums:
		var item = create_and_add_item(album.id, "album")
		_initialize_album_item(item, album)

func _initialize_album_item(item: ListItemBase, album: AlbumData) -> void:
	# 这里可以设置项目的外观和数据
	item.custom_minimum_size = Vector2(300, 100)
	# ... 设置其他属性

func _on_item_focused(item_id: String) -> void:
	# 当列表项被选中时
	var album = DataManager.instance.get_album_by_id(item_id)
	EventBus.emit_album_selected(item_id, album)
	
	# 转换UI状态到歌曲视图
	UIStateManager.instance.change_state(UIStateManager.UIState.SONG_VIEW)
```

### 第三步: 处理导航和事件

```gdscript
# Scene/Navigation.gd

extends Node
class_name NavigationController

func _ready() -> void:
	# 监听事件总线的所有导航事件
	EventBus.album_selected.connect(_on_album_selected)
	EventBus.navigate_back.connect(_on_navigate_back)
	
	# 监听状态改变
	UIStateManager.instance.state_changed.connect(_on_state_changed)

func _on_album_selected(album_id: String, album_data: AlbumData) -> void:
	print("Album selected: %s" % album_data.name)
	# 在这里实现导航逻辑
	# 例如：显示歌曲列表
	_show_song_view(album_id)

func _on_navigate_back() -> void:
	UIStateManager.instance.go_back()

func _on_state_changed(old_state: int, new_state: int) -> void:
	var state_name = UIStateManager.instance.get_state_name(new_state)
	print("UI State changed to: %s" % state_name)
```

---

## 📚 常见用法

### 1. 获取和显示MIDI列表

```gdscript
# 获取特定歌曲的所有MIDI
var song_id = "5e84f0a484679d16d79ab456"
var midis = DataManager.instance.get_midis_by_song(song_id)

# 按下载数降序排序
var sorted_midis = SortingEngine.instance.get_sorted_midis(
	midis,
	SortingEngine.SortField.DOWNLOAD_COUNT,
	SortingEngine.SortDirection.DESCENDING
)

# 按状态过滤（只显示已发布的）
var approved_midis = SortingEngine.instance.filter_by_status(
	sorted_midis,
	"APPROVED"
)
```

### 2. 搜索MIDI

```gdscript
var all_midis = DataManager.instance.midis.values()
var search_results = SortingEngine.instance.search_midis(all_midis, "Lost Word")

for midi in search_results:
	print("Found: %s by %s" % [midi.name, midi.artist_name])
```

### 3. 添加带有动画的按钮

```gdscript
@onready var play_button = $PlayButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)

func _on_play_pressed() -> void:
	# 使用动画管理器播放动画
	var animator = AnimationManager.instance
	animator.animate_scale(play_button, Vector2(0.95, 0.95), 0.1)
	
	# 延迟启动游戏
	animator.delay_call(func():
		_start_game()
	, 0.1)

func _start_game() -> void:
	var midi = DataManager.instance.get_midi_by_id(current_midi_id)
	GameplayManager.instance.start_game(midi)
```

### 4. 监听游戏状态

```gdscript
func _ready() -> void:
	GameplayManager.instance.game_state_changed.connect(_on_game_state_changed)
	GameplayManager.instance.game_time_updated.connect(_on_game_time_updated)

func _on_game_state_changed(old_state: int, new_state: int) -> void:
	match new_state:
		GameplayManager.GameState.PLAYING:
			print("Game started!")
			$UI/PauseButton.show()
		GameplayManager.GameState.PAUSED:
			print("Game paused!")
		GameplayManager.GameState.FINISHED:
			print("Game finished!")
			_show_results()

func _on_game_time_updated(current_time: float, total_time: float) -> void:
	$UI/TimeLabel.text = "%d / %d" % [current_time, total_time]
```

### 5. 使用动画序列

```gdscript
func _on_menu_button_pressed() -> void:
	var animator = AnimationManager.instance
	
	# 创建序列动画
	var tween = animator.create_sequence("menu_animation")
	tween.tween_property($MenuPanel, "position:y", 100, 0.3)
	tween.parallel().tween_callback(play_sound)
	tween.tween_callback(func(): print("Animation complete!"))
```

---

## 🎮 创建自定义游戏谱面

### 1. 准备文件结构

```
Resources/Songs/my_song/
├── song.ini          # 歌曲元数据
├── music.ogg         # 音乐文件
├── chart.mid         # MIDI谱面
├── background.png    # 背景图
└── cover.jpg        # 封面
```

### 2. 编写 song.ini

```ini
[song_info]
name = "My Custom Song"
artist = "Me"
album = "Custom Album"
duration = 180

[chart_info]
title = "My Song - Normal"
difficulty = "Normal"
creator = "Me"

[audio]
path = "music.ogg"
offset = 0
bpm = 120

[midi]
path = "chart.mid"
format = "type0"
notes_track = 0
```

### 3. 自动加载

DataManager 会在启动时自动发现并加载所有歌曲！

---

## 🐛 调试技巧

### 打印当前状态

```gdscript
var state_mgr = UIStateManager.instance
state_mgr.print_state_info()
```

### 输出：
```
Current State: ALBUM_VIEW (0)
Previous State: IDLE (255)
History Depth: 0
```

### 监控内存使用

```gdscript
var animator = AnimationManager.instance
print("Active animations: %d" % animator.get_active_tween_count())

var data = DataManager.instance
var stats = data.get_statistics()
print(stats)
```

### 输出：
```
{
  "total_albums": 120,
  "total_songs": 2500,
  "total_midis": 15000,
  "pending_count": 150,
  "approved_count": 14800,
  "included_count": 50,
  "dead_count": 0
}
```

---

## ⚠️ 常见问题

### Q: 如何访问单例？
A: 所有核心管理器都是单例：
```gdscript
DataManager.instance
EventBus.instance
UIStateManager.instance
AnimationManager.instance
GameplayManager.instance
```

### Q: 事件总线和信号有什么区别？
A:
- **事件总线** - 用于不同模块之间的通信（全局）
- **信号** - 用于单个对象的通信（局部）

### Q: 如何避免内存泄漏？
A:
```gdscript
# ✅ 好的做法
signal my_signal
my_signal.connect(_on_my_signal)  # 自动管理

# ⚠️ 需要小心
EventBus.album_selected.connect(_on_album_selected)
# 在_exit_tree中断开：
EventBus.album_selected.disconnect(_on_album_selected)

# ✅ 最安全的做法
EventBus.album_selected.connect(_on_album_selected, CONNECT_ONE_SHOT)
```

### Q: 如何自定义列表项外观？
A:
```gdscript
class_name CustomAlbumItem
extends ListItemBase

func _on_selected() -> void:
	# 被选中时的自定义逻辑
	modulate = Color.YELLOW
	scale = Vector2(1.1, 1.1)

func _on_deselected() -> void:
	# 取消选中时的自定义逻辑
	modulate = Color.WHITE
	scale = Vector2(1.0, 1.0)
```

---

## 📖 下一步阅读

1. 详细架构说明 -> [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md)
2. Core 数据层 -> [Core/DataManager.gd](Core/DataManager.gd)
3. UI 组件基类 -> [UI/Components/BaseScrollList.gd](UI/Components/BaseScrollList.gd)
4. 游戏逻辑 -> [Game/GameplayManager.gd](Game/GameplayManager.gd)

---

**Happy Coding! 🎵**
