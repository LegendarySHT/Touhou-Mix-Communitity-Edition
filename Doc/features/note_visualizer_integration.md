# 音符可视化集成说明

## 当前实现边界

项目当前以 `KeySequenceManager` + 播放时间推进完成打歌输入序列管理；
历史文档中提及的 `Game/NotesRenderer.gd` 不属于当前代码基线。

## 相关模块

- `Game/KeySequenceManager.gd`
  - `sequences_classified`
  - `keys_generated`
  - `keys_optimized`
- `Game/NoteFallCalculator.gd`：音符下落位置计算（游戏时间推进的核心）
- `Game/MidiPlaybackManager.gd`：播放位置（tick/ms）
- `UI/Views/PlayView/`：消费按键序列并渲染（`PlayView.gd`、`FlowArea.gd`、`FlowNote.gd`、`NoteJudger.gd`）
- `Game/ScoreCalculator.gd`：判定与计分

## 集成建议

1. 数据准备：在 MIDI 载入后生成按键序列。
2. 时间同步：渲染层统一使用毫秒时间轴。
3. 判定输入：按键事件映射到当前窗口内的目标音符。
4. 结算反馈：调用 `ScoreCalculator.record_judgment()`。

## 时间同步注意事项

- 游戏主时钟由 `PlayView` 维护（秒），渲染侧使用 `game_time * 1000` 转毫秒。
- 若直接读取播放管理器，优先 `MidiPlaybackManager.get_position_ms()`。
- 不要在同一逻辑中混用 tick 与秒。

## 迁移说明

若后续新增专用渲染器（例如 `NotesRenderer`），应将其作为 UI/渲染层组件，
保持 `KeySequenceManager` 负责序列数据，避免把渲染细节回写到 Core 数据模型。
