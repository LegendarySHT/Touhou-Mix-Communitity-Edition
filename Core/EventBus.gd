## 全局事件总线
## 所有UI组件通过此总线进行通信，解除直接依赖
extends Node

class_name EventBus

## 单例实例
static var instance: EventBus

## ========== 数据事件 ==========
signal data_ready(data_manager: DataManager)
signal data_loaded_complete
signal midi_data_updated(midi_id: String)
signal album_selected(album_id: String, album_data: AlbumData)
signal song_selected(song_id: String, song_data: SongData)
signal midi_selected(midi_id: String, midi_data: MidiData)

## ========== UI导航事件 ==========
# signal navigate_to_album_view
# signal navigate_to_song_view(album_id: String)
# signal navigate_to_midi_view(song_id: String)
# signal navigate_to_sort_view
# signal navigate_to_detail_view(midi_id: String)
signal navigate_back

## ========== 排序和筛选事件 ==========
signal sort_finished
# signal sort_field_changed(sort_field: int)
# signal sort_direction_changed(ascending: bool)
# signal status_filter_changed(status: String)
signal search_query_changed(query: String)

## ========== UI交互事件 ==========
signal shortcut_menu_toggled(is_open: bool)
signal sort_menu_toggled(is_open: bool)
signal scroll_started(scroll_view_name: String)
signal scroll_finished(scroll_view_name: String)
signal item_hovered(item_type: String, item_id: String)
signal item_unhovered

## ========== 设置和配置事件 ==========
signal settings_changed(setting_name: String, value: Variant)
signal theme_changed(theme_name: String)
signal language_changed(language_code: String)

## ========== 错误和警告事件 ==========
signal error_occurred(error_code: int, error_message: String)
signal warning_occurred(warning_message: String)

func _ready() -> void:
	if instance == null:
		instance = self
		add_to_group("singleton")
	else:
		queue_free()

## 便利函数：发出专辑选择事件
func emit_album_selected(album_id: String, album_data: AlbumData) -> void:
	album_selected.emit(album_id, album_data)

## 便利函数：发出歌曲选择事件
func emit_song_selected(song_id: String, song_data: SongData) -> void:
	song_selected.emit(song_id, song_data)

## 便利函数：发出MIDI选择事件
func emit_midi_selected(midi_id: String, midi_data: MidiData) -> void:
	midi_selected.emit(midi_id, midi_data)

## 便利函数：发出错误事件
func emit_error(error_code: int, error_message: String) -> void:
	error_occurred.emit(error_code, error_message)
	push_error("[EventBus Error %d] %s" % [error_code, error_message])

## 便利函数：发出警告事件
func emit_warning(warning_message: String) -> void:
	warning_occurred.emit(warning_message)
	push_warning("[EventBus Warning] %s" % warning_message)
