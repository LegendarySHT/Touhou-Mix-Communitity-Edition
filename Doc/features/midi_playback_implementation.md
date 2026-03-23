# MIDI 播放实现说明

## 目标

统一描述当前 MIDI 播放链路：后端选择、音源加载、运行期切换和时间同步。

## 主要组件

- `Game/MidiPlaybackManager.gd`：播放入口、后端管理、SoundFont 扫描/切换
- `Game/MidiPlaybackInterfaces.gd`：播放后端接口层
- `addons/midi/MidiPlayer.gd`：GDScript 后端（addons）
- `CSharp/MeltySynthPlayer.cs` + `CSharp/MeltySynthPlayerWrapper.gd`：MeltySynth 后端

## 后端机制

当前支持两种后端：
- `addons`
- `meltysynth`

由 `MidiPlaybackManager` 管理状态：
- `midi_backend`
- `backend_switching`（避免重入切换）

运行时切换示例：

```gdscript
MidiPlaybackManager.instance.set_backend("meltysynth")
```

## 设置变更联动

`MidiPlaybackManager` 监听 `EventBus.settings_changed`，当检测到 `midi_backend` 或通配刷新时：

1. 读取新配置
2. 若后端变化，先停止当前播放
3. 重建后端实例
4. 重新应用当前 MIDI（若存在）

## SoundFont 处理

- 启动时扫描可用音源（用户目录 + 内置目录）
- 提供 `set_soundfont(name)` 统一切换接口
- 配置缺失时回退默认音源

## 时间单位约定（重点）

不同模块时间单位不同，联调时必须统一：

- `MidiPlaybackManager`：tick / 毫秒（推荐使用 `get_position_ms()`）
- `GameplayManager`：秒（`game_time`）
- 可视化/按键序列：毫秒（通常由 `game_time * 1000` 转换）

## 排障建议

1. 后端未切换：检查 `settings_changed` 是否触发、`backend_switching` 是否卡住。
2. 无声音：检查 SoundFont 文件是否存在、路径是否正确。
3. 时序错位：确认 tick/ms/sec 是否混用。

## 关联文档

- `soundfont_selection_feature.md`
- `../quickref/MIDI_BACKEND_QUICK_REFERENCE.md`
