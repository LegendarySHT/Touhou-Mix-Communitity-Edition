# MIDI 后端快速参考

## 可用后端

- `addons`
- `meltysynth`

## 关键接口

```gdscript
MidiPlaybackManager.instance.set_backend("meltysynth")
MidiPlaybackManager.instance.set_soundfont("GeneralUser-GS.sf2")
```

## 运行期切换要点

1. 切换前先停止当前播放。
2. 避免重复切换（`backend_switching` 防抖）。
3. 切换后如有当前 MIDI，重新加载到新后端。

## 联动配置

- 配置来源：`ConfigManager`
- 触发方式：`EventBus.settings_changed`
- 目标模块：`MidiPlaybackManager`

## 排障

- 切换无效：检查 `settings_changed` 是否触发。
- 播放失败：检查 C# 侧 MeltySynth 包装是否初始化成功。
- 无声音：检查 SoundFont 文件存在与路径可访问。
