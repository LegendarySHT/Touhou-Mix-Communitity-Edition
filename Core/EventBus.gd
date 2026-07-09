## 全局事件总线
## 所有UI组件通过此总线进行通信，解除直接依赖
extends Node

class_name EventBus

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

func _ready() -> void:
	add_to_group("singleton")

## 便利函数：发出歌曲选择事件
func emit_song_selected(song_id: String) -> void:
	song_selected.emit(song_id)

## 便利函数：发出MIDI选择事件
func emit_midi_selected(midi_id: String, midi_data: MidiData) -> void:
	midi_selected.emit(midi_id, midi_data)
