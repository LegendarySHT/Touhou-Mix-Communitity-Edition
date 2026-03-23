# MIDI 运行时配置持久化速查

## 数据位置

`Core/Models/MidiData.gd` 将运行时字段存储在 JSON 的 `_runtime` 对象中。

## 关键 API

```gdscript
var runtime_cfg = midi_data.export_runtime_config()
```

`export_runtime_config()` 包含：
- `midi_volume` / `vocal_volume`
- `vocal_file_path` / `vocal_offset_ms`
- `selected_track_indices` / `selected_track_configs`
- `track_channel_mute_state` / `track_channel_volume_config`
- `track_channel_instrument_overrides`
- `solo_pairs` / `use_soundfont`

## 读取路径

`MidiData.from_json(json_data)` 会从 `_runtime` 恢复上述字段；
JSON 字典键转字符串的场景已在模型内处理（轨道/通道索引会转回整数）。

## 典型流程

1. 加载 MIDI -> `from_json()` 恢复运行时配置。
2. 用户在 Track/Play 页修改音量或轨道状态。
3. 退出页面时导出并写回 JSON。
4. 下次载入自动恢复。

## 注意事项

- 首次未配置时使用默认值。
- 保存时不要覆盖非 `_runtime` 元数据字段。
- 轨道索引字典落盘后是字符串，读取时必须转回整数。
