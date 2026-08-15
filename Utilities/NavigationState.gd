## 导航位置记录（静态工具类）
## 存储位置：ChartDb meta 集合（文档 _id="navigation"），随数据库读取，与谱面数据同源同生命周期
## 语义（与产品约定一致）：
##   - 进入 SongView 时记录所选专辑（album_id）
##   - 进入 MidiView 时记录歌曲（song_id），切换 midi 时记录具体选中项（midi_id）
##   - 退回 AlbumView 时清空记录
##   - TrackView/PlayView/ScoreView/SettingView 等二级页面不写不清
## 恢复：下次启动仅两种深度——仅 album → 直接进入 SongView；有 song（及 midi）→ 直接进入 MidiView
class_name NavigationState
extends RefCounted

## 内存缓存：避免热路径反复读 DB（首次读取后写操作同步更新）
static var _cache: Dictionary = {}
static var _loaded: bool = false

## 读取完整状态（含缓存），字段缺失时补空串
## 注意：不命名为 load()，避免与 Godot 内置全局函数 load(path) 在类内裸调用时冲突
## DB 未就绪时返回空而不置缓存标记，下次调用会重试（不缓存"未就绪"的空结果）
static func load_state() -> Dictionary:
	if not _loaded:
		if ChartDB and ChartDB.IsOpen():
			_cache = ChartDB.GetNavigation()
			_loaded = true
		else:
			return {}
	return _cache

## 写入完整状态（立即落库）
static func save(album_id: String, song_id: String, midi_id: String) -> void:
	_set_state({
		"album_id": str(album_id),
		"song_id": str(song_id),
		"midi_id": str(midi_id),
	})

## 局部更新（保留其余字段，如 MidiView 只改 midi_id）
static func update(changes: Dictionary) -> void:
	var state := load_state()
	for key in changes:
		state[key] = str(changes[key])
	_set_state(state)

## 清空记录（退回 AlbumView 时调用；必须落库，否则旧记录残留导致下次启动误恢复）
static func clear() -> void:
	_set_state({"album_id": "", "song_id": "", "midi_id": ""})

static func get_album_id() -> String:
	return str(load_state().get("album_id", ""))

static func get_song_id() -> String:
	return str(load_state().get("song_id", ""))

static func get_midi_id() -> String:
	return str(load_state().get("midi_id", ""))

static func _set_state(state: Dictionary) -> void:
	_cache = {
		"album_id": str(state.get("album_id", "")),
		"song_id": str(state.get("song_id", "")),
		"midi_id": str(state.get("midi_id", "")),
	}
	_loaded = true
	if ChartDB and ChartDB.IsOpen():
		ChartDB.SaveNavigation(_cache)
