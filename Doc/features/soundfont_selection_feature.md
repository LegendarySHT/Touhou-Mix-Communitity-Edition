# SoundFont 选择功能

## 功能范围

该功能覆盖：扫描可用音源、设置界面选择、配置持久化、播放端应用。

## 关键模块

- `UI/Views/SettingView/SettingView.gd`：扫描与保存选择值
- `UI/Views/SettingView/SettingList.gd`：动态下拉选项
- `Game/MidiPlaybackManager.gd`：接收并应用音源
- `Utilities/ConfigManager.gd`：读取/写入配置

## 工作流

1. SettingView 扫描音源文件（用户目录优先，内置目录补充）
2. 用户在设置页选择 SoundFont
3. 退出设置页时写入配置
4. 触发 `EventBus.settings_changed`
5. `MidiPlaybackManager` 重新加载并应用音源

## 规则

- 用户目录优先于内置目录（同名覆盖）
- 找不到目标音源时自动回退默认值
- UI 显示名与真实文件名分离，保存时使用可解析的文件名

## 验证清单

- [ ] 设置页能列出全部 `.sf2` 文件
- [ ] 切换后写入配置文件
- [ ] 切换后新播放会使用新音源
- [ ] 删除已选音源后可自动回退默认音源

## 关联文档

- `midi_playback_implementation.md`
