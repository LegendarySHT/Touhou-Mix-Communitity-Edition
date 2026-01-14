## 数据管理器
## 负责歌曲数据的加载、缓存和查询
extends Node

class_name DataManager

## 单例实例
static var instance: DataManager

## 所有专辑数据 (ID -> AlbumData)
var albums: Dictionary[String, AlbumData] = {}

## 所有歌曲数据 (ID -> SongData)
var songs: Dictionary[String, SongData] = {}

## 所有MIDI谱面数据 (ID -> MidiData)
var midis: Dictionary[String, MidiData] = {}

## MIDI数据按专辑分组 (AlbumID -> SongID -> [MidiID])
var midi_tree: Dictionary = {}

## 原始JSON数据缓存（可选，用于调试和重新加载）
var json_cache: Dictionary = {}

## 数据加载状态
var is_loading: bool = false

## 加载完成信号
signal data_loaded

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
	
	add_to_group("singleton")

## 从midis_info目录异步加载所有MIDI数据
func load_all_midis_async() -> void:
	if is_loading:
		return
	
	is_loading = true
	
	var thread = Thread.new()
	thread.start(_load_midis_thread)
	thread.wait_to_finish()
	
	is_loading = false
	data_loaded.emit()

## 线程函数：加载MIDI数据
func _load_midis_thread() -> void:
	var midis_dir = "res://Resources/midis_info/"
	var dir = DirAccess.open(midis_dir)
	
	if dir == null:
		push_error("Failed to open midis_info directory: %s" % midis_dir)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".json") and not file_name.begins_with("."):
			var file_path = midis_dir.path_join(file_name)
			_load_midi_file(file_path)
		
		file_name = dir.get_next()

## 加载单个MIDI文件
func _load_midi_file(file_path: String) -> void:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("Failed to open file: %s" % file_path)
		return
	
	var content = file.get_as_text()
	var json = JSON.parse_string(content)
	
	if json == null:
		push_warning("Failed to parse JSON: %s" % file_path)
		return
	
	_process_midi_json(json as Dictionary)

## 处理MIDI JSON数据
func _process_midi_json(json_data: Dictionary) -> void:
	# 提取基本信息
	var midi_id = json_data.get("_id", "")
	if midi_id.is_empty():
		return
	
	# 创建MIDI数据对象
	var midi = MidiData.new()
	midi.from_json(json_data)
	midis[midi_id] = midi
	
	# 缓存原始JSON
	json_cache[midi_id] = json_data
	
	# 处理歌曲信息
	var song_json = json_data.get("song", {}) as Dictionary
	var song_id = song_json.get("_id", "")
	if not song_id.is_empty():
		if not songs.has(song_id):
			var song = SongData.new()
			song.from_json(song_json)
			songs[song_id] = song
		
		var song = songs[song_id]
		song.add_midi_id(midi_id)
		midi.song_data = song
	
	# 处理专辑信息
	var album_json = json_data.get("album", {}) as Dictionary
	var album_id = album_json.get("_id", "")
	if not album_id.is_empty():
		if not albums.has(album_id):
			var album = AlbumData.new()
			album.from_json(album_json)
			albums[album_id] = album
		
		var album = albums[album_id]
		if not song_id.is_empty():
			album.add_song_id(song_id)
		album.total_midi_count += 1
		midi.album_data = album
		
		# 构建树结构
		if not midi_tree.has(album_id):
			midi_tree[album_id] = {}
		if not midi_tree[album_id].has(song_id):
			midi_tree[album_id][song_id] = []
		midi_tree[album_id][song_id].append(midi_id)

## 获取所有专辑列表（按发布日期排序）
func get_all_albums() -> Array[AlbumData]:
	var result: Array[AlbumData] = []
	for album in albums.values():
		result.append(album)
	
	# 按发布日期排序
	result.sort_custom(func(a: AlbumData, b: AlbumData) -> bool:
		return a.release_date > b.release_date
	)
	
	return result

## 获取专辑下的所有歌曲
func get_songs_by_album(album_id: String) -> Array[SongData]:
	var result: Array[SongData] = []
	
	if not midi_tree.has(album_id):
		return result
	
	var song_ids = midi_tree[album_id].keys()
	for song_id in song_ids:
		if songs.has(song_id):
			result.append(songs[song_id])
	
	return result

## 获取歌曲下的所有MIDI谱面
func get_midis_by_song(song_id: String) -> Array[MidiData]:
	var result: Array[MidiData] = []
	
	for album_id in midi_tree.keys():
		if midi_tree[album_id].has(song_id):
			var midi_ids = midi_tree[album_id][song_id] as Array
			for midi_id in midi_ids:
				if midis.has(midi_id):
					result.append(midis[midi_id])
	
	return result

## 按MIDI ID获取单个MIDI谱面
func get_midi_by_id(midi_id: String) -> MidiData:
	return midis.get(midi_id)

## 按专辑ID获取专辑
func get_album_by_id(album_id: String) -> AlbumData:
	return albums.get(album_id)

## 按歌曲ID获取歌曲
func get_song_by_id(song_id: String) -> SongData:
	return songs.get(song_id)

## 按状态过滤MIDI谱面
func get_midis_by_status(status: String) -> Array[MidiData]:
	var result: Array[MidiData] = []
	
	for midi in midis.values():
		if midi.status == status:
			result.append(midi)
	
	return result

## 获取所有MIDI谱面列表
func get_all_midis() -> Array[MidiData]:
	var result: Array[MidiData] = []
	for midi in midis.values():
		result.append(midi)
	return result

## 获取数据统计信息
func get_statistics() -> Dictionary:
	return {
		"total_albums": albums.size(),
		"total_songs": songs.size(),
		"total_midis": midis.size(),
		"pending_count": get_midis_by_status("PENDING").size(),
		"approved_count": get_midis_by_status("APPROVED").size(),
		"included_count": get_midis_by_status("INCLUDED").size(),
		"dead_count": get_midis_by_status("DEAD").size()
	}

## 清空所有数据
func clear_data() -> void:
	albums.clear()
	songs.clear()
	midis.clear()
	midi_tree.clear()
	json_cache.clear()
