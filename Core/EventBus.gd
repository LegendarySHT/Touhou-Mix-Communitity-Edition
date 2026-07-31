## 全局事件总线
## 所有UI组件通过此总线进行通信，解除直接依赖
extends Node

class_name EventBus
@warning_ignore_start("unused_signal")
## ========== 数据事件 ==========
signal data_loaded_complete
signal album_selected(album_id: String)
signal song_selected(song_id: String)
signal midi_selected(midi_id: String, midi_data: MidiData)
signal enter_track_view_with(midi: MidiData)
signal start_game_with(midi: MidiData)

## ========== UI导航事件 ==========
## 设置页面及商店页面使用
signal page_left
signal page_right

## ========== 排序和筛选事件 ==========
signal sort_finished
signal search_query_changed(query: String)

## ========== 设置和配置事件 ==========
signal settings_changed(setting_name: String, value: Variant)
signal config_changed(key: String, section: String, value: Variant)
signal theme_changed(theme_name: String)

## ========== 文件系统事件 ==========
signal midi_deleted(midi_id: String)
## charts 扫描缓存后台校验完成
## 参数：是否有变化（true 时 UI 应刷新列表）
## 启动时先从缓存恢复 charts_index 让用户立即操作，后台 worker 校验文件状态
## 校验完成后 emit 此信号；changed=true 表示发现了新增/删除/修改的文件夹，UI 需刷新
signal charts_cache_validated(changed: bool)

## ========== 收藏夹事件 ==========
## 收藏夹数据加载并验证完成
signal favorites_loaded
## 收藏夹数据更新（通用刷新触发）
signal favorites_updated
## 收藏夹创建
signal favorite_list_created(favorite_id: String)
## 收藏夹删除
signal favorite_list_deleted(favorite_id: String)
## 收藏夹重命名
signal favorite_list_renamed(favorite_id: String, new_name: String)
## MIDI 被添加到或移除出收藏夹
signal favorite_midi_changed(favorite_id: String, midi_id: String, added: bool)
## 请求浏览收藏夹内容（AlbumView 点击列表项时发出）
signal favorite_selected_for_browse(favorite_id: String)
@warning_ignore_restore("unused_signal")

func _ready() -> void:
	add_to_group("singleton")

## 便利函数：发出歌曲选择事件
func emit_song_selected(song_id: String) -> void:
	song_selected.emit(song_id)

## 便利函数：发出MIDI选择事件
func emit_midi_selected(midi_id: String, midi_data: MidiData) -> void:
	midi_selected.emit(midi_id, midi_data)
