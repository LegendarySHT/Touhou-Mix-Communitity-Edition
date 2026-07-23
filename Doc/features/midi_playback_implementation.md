# MIDI 播放实现说明

## 目标

统一描述当前 MIDI 播放链路：后端初始化、音源加载和时间同步。

## 主要组件

- `Game/MidiPlaybackManager.gd`：播放入口、SoundFont 扫描/切换
- `Game/MidiPlaybackInterfaces.gd`：播放后端接口层
- `CSharp/MeltySynthPlayer.cs` + `CSharp/MeltySynthPlayerWrapper.gd`：MeltySynth 后端（唯一后端）
- `addons/midi/SMF.gd`：SMF 解析库，供 `Utilities/MidiParser.gd` 解析 MIDI 文件使用（不再作为播放后端）

## 后端机制

当前仅使用 MeltySynth（C#）后端，由 `MidiPlaybackManager._initialize_backend()` 在启动时初始化。
历史上曾存在的 `addons`（GDScript MidiPlayer）后端已下线，不再支持运行时切换。

## 设置变更联动

`MidiPlaybackManager` 监听 `EventBus.settings_changed`，响应以下设置变更：

- `soundfont_select`：重新加载音源
- `use_system_stopwatch`：切换系统时钟模式
- `max_polyphony`：重新设置复音数并重载 SoundFont（必要时恢复播放）

## SoundFont 处理

- 启动时扫描可用音源（用户目录 + 内置目录）
- 提供 `set_soundfont(name)` 统一切换接口
- 配置缺失时回退默认音源

## 时间单位约定（重点）

不同模块时间单位不同，联调时必须统一：

- `MidiPlaybackManager`：tick / 毫秒（推荐使用 `get_position_ms()`）
- `PlayView.gd` / `NoteFallCalculator`：秒（游戏内主时钟）
- `KeySequenceManager`：毫秒（通常由 `game_time * 1000` 转换）

> 注：项目当前不存在 `GameplayManager`，游戏时间由 `PlayView` 与 `NoteFallCalculator` 维护。

## 排障建议

1. 无声音：检查 SoundFont 文件是否存在、路径是否正确。
2. 时序错位：确认 tick/ms/sec 是否混用。

## 关联文档

- `soundfont_selection_feature.md`
