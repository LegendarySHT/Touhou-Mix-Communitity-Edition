# TrackView 集成快速参考

## 🎯 集成完成状态

### ✅ 已完成
- Main.gd: MidiPlaybackManager 和 KeySequenceManager 初始化
- TrackView.tscn: 添加 SoundfontSelector 和 PreviewButton 节点
- TrakView.gd: 单例访问修复，4个回调方法实现
- MidiPlaybackManager: 轨道音量控制方法添加

### 📋 修改文件清单
```
d:\Touhou Mix Dev\THMIX Community Edition\
├── Main.gd                                   ✏️ +29行
├── UI\Views\TrackView\TrackView.tscn        ✏️ +12行
├── UI\Views\TrackView\TrakView.gd           ✏️ +85行
├── Game\MidiPlaybackManager.gd              ✏️ +8行
└── Doc\TRACKVIEW_INTEGRATION_SUMMARY.md    📄 新建
```

---

## 🚀 快速测试步骤

### 1. 验证初始化

在Godot Editor中：
```gdscript
# 在Main.gd中添加临时打印语句验证
print("MidiPlaybackManager instance: ", MidiPlaybackManager.instance)
print("KeySequenceManager instance: ", KeySequenceManager.instance)
```

预期输出：
```
MidiPlaybackManager instance: <MidiPlaybackManager#12345>
KeySequenceManager instance: <KeySequenceManager#12346>
```

### 2. 加载TrackView

```gdscript
# 触发进入TrackView的信号
EventBus.instance.enter_track_view_with.emit(some_midi_data)
```

预期行为：
- TrackView 显示MIDI轨道列表
- 音源选择器填充了音源列表
- 预览按钮可点击

### 3. 交互测试

```gdscript
# 测试轨道启用/禁用
track_ui.enable_btn.button_pressed = true

# 测试音源选择
soundfont_selector.select(0)

# 测试预览播放
preview_button.pressed.emit()
```

---

## 🔧 常见问题排查

### 问题1: "MidiPlaybackManager not initialized in Main!"

**原因**: Main._ready() 未正确执行或MidiPlaybackManager初始化失败

**解决**:
1. 检查Main.gd第100-114行的初始化代码是否完整
2. 查看Godot编辑器的输出面板，看是否有初始化日志
3. 确认MidiPlaybackManager.gd文件存在且无语法错误

### 问题2: SoundfontSelector 无法识别

**原因**: TrackView.tscn 中的节点路径不匹配

**解决**:
1. 在Godot编辑器中打开 TrackView.tscn
2. 检查场景树中是否有 SoundfontSelector 节点
3. 如无，手动添加：
   - 右键 VBoxC2 → 添加子节点 → OptionButton
   - 重命名为 "SoundfontSelector"
   - 设置属性：custom_minimum_size = (200, 0)

### 问题3: 预览播放无声音

**原因**: 音源文件未找到或MIDI文件路径错误

**解决**:
1. 检查 Resources/Soundfont 目录是否存在和包含 .sf2 文件
2. 检查MIDI文件是否在 user://files/Charts/ 目录中
3. 查看Godot控制台日志，寻找路径相关错误

### 问题4: 轨道UI不显示

**原因**: MIDI轨道信息获取失败

**解决**:
1. 确认 MidiData 对象正确加载并包含轨道信息
2. 检查 MidiParser.load_and_parse_midi() 返回的 track_infos 是否为空
3. 在 _create_track_views() 添加调试日志：
   ```gdscript
   print("Track infos: ", track_infos)
   ```

---

## 📝 代码示例

### 从GameplayManager中读取TrackView配置

```gdscript
# 在 GameplayManager.start_game() 中
func start_game(midi_data: MidiData) -> void:
    # midi_data 已包含用户在TrackView中的配置：
    # - midi_data.selected_track_indices  → 选中的轨道
    # - midi_data.use_soundfont           → 选中的音源
    
    # 应用配置到MidiPlaybackManager
    MidiPlaybackManager.instance.set_soundfont(midi_data.use_soundfont)
    MidiPlaybackManager.instance.set_selected_tracks(midi_data.selected_track_indices)
    
    # 加载和初始化游戏
    _load_midi_thread(midi_data)
```

### 添加自定义轨道UI交互

```gdscript
# 在 TrakView.gd 中扩展功能
func _on_track_custom_action(track_index: int) -> void:
    var track_ui = midi_tracks[track_index]
    
    # 获取轨道信息
    var track_info = midi_playback_manager.get_track_infos()[track_index]
    
    # 自定义逻辑
    print("Action on track: %s (ID: %d)" % [track_info.name, track_index])
```

---

## 🎓 学习路径

1. **理解整体流程** → 阅读 TRACKVIEW_INTEGRATION_SUMMARY.md
2. **查看架构设计** → 阅读 ARCHITECTURE_OVERVIEW.md
3. **学习具体实现** → 查看各个文件的注释和代码
4. **遵循编码规范** → 参考 DEVELOPER_CHEATSHEET.md 和 SINGLETON_PATTERN_GUIDE.md

---

## 📞 相关API速查

### MidiPlaybackManager 常用方法
```gdscript
MidiPlaybackManager.instance.load_midi(midi_data)           # 加载MIDI
MidiPlaybackManager.instance.play()                         # 播放
MidiPlaybackManager.instance.stop()                         # 停止
MidiPlaybackManager.instance.set_soundfont(name)            # 切换音源
MidiPlaybackManager.instance.set_selected_tracks(indices)   # 设置轨道
MidiPlaybackManager.instance.set_volume_db(volume)          # 设置音量
```

### TrackView 常用信号
```gdscript
EventBus.instance.enter_track_view_with.connect(_on_enter_track_view)
midi_playback_manager.midi_loaded.connect(_on_midi_loaded)
midi_playback_manager.midi_started.connect(_on_midi_started)
midi_playback_manager.midi_finished.connect(_on_midi_finished)
midi_playback_manager.tracks_changed.connect(_on_tracks_changed)
```

---

**文档版本**: 1.0  
**最后更新**: 2026年1月24日  
**适用版本**: Godot 4.5

