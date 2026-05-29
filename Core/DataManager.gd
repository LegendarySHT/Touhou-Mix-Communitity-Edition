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

## 数据加载状态 (初始为True防止还没启动就被读取)
var is_loading: bool = true

## 加载完成信号
signal data_loaded

func json_get(json, key, default):
	var intermediate = json.get(key, default)
	if not json or not intermediate:
		return default
	return json.get(key, default)

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
	
	add_to_group("singleton")

## 从midis_info目录异步加载所有MIDI数据
func load_all_midis_async() -> void:
	if not is_loading:
		return
	
	# var thread = Thread.new()
	# var result = thread.start(_load_midis)
	if FileSystemManager.instance == null:
		push_error("FileSystemManager not initialized")
		return
	
	while not FileSystemManager.instance.is_initialized:
		await get_tree().process_frame
	_load_midis()

## 线程函数：加载MIDI数据
## 使用新的谱面格式（从 FileSystemManager 获取谱面索引）
func _load_midis() -> void:
	print("[DataMGR] Thread started, loading MIDI data...")
	
	# 获取谱面索引
	var charts = FileSystemManager.instance.get_charts_index()
	print("[DataMGR] Got charts index: %d charts" % charts.size())
	
	if charts.is_empty():
		print("[DataMGR] No charts found in FileSystemManager index")
		return
	
	# 处理每个谱面
	var processed_count = 0
	print("[DataMGR] Starting to process %d charts..." % charts.size())
	
	for folder_name in charts.keys():
		var metadata = charts[folder_name]
		_process_new_format_chart(metadata)
		processed_count += 1
		
		# 每处理 10 个谱面释放一帧，保持 Loading 动画流畅
		if processed_count % 10 == 0:
			await get_tree().process_frame
	
	print("[DataMGR] Finished processing %d charts, now emitting signal..." % processed_count)
	print("[DataMGR] Midis in dictionary: %d" % midis.size())

	# 为无专辑/歌曲的 MIDI 合成 Unknown 分组
	await _ensure_unknown_grouping()

	_emit_data_loaded()

func _emit_data_loaded():
	print("[DataMGR] _emit_data_loaded() called")
	is_loading = false
	var stats = get_statistics()
	print("[DataMGR] Stats - Albums: %d, Songs: %d, MIDIs: %d" %
		[stats.total_albums, stats.total_songs, stats.total_midis])
	print("[DataMGR] Emitting data_loaded signal...")
	data_loaded.emit()
	print("[DataMGR] data_loaded signal emitted!")

## 处理新格式的谱面数据（文件夹结构）
func _process_new_format_chart(metadata: Dictionary) -> void:
	var chart_id = metadata.get("id", "")
	var json_data = metadata.get("data", {})
	var folder_name = metadata.get("folder_name", "")
	
	# 调试日志
	if chart_id.is_empty():
		print("[DataMGR] WARN: Chart metadata missing id field. Folder: %s" % folder_name)
		return
	
	if json_data.is_empty():
		print("[DataMGR] WARN: Chart %s has empty JSON data. Folder: %s" % [chart_id, folder_name])
		return
	
	# 创建MIDI数据对象
	var midi = MidiData.new()
	midi.from_json(json_data)
	
	# 验证是否成功设置了 id
	if midi.id.is_empty():
		print("[DataMGR] WARN: Failed to set MIDI id for chart %s" % chart_id)
		return
	
	# print("[DataMGR] DEBUG: Adding MIDI %s (from folder %s) to dictionary" % [chart_id, folder_name])
	midis[chart_id] = midi
	# print("[DataMGR] DEBUG: MIDI added. Current midis count: %d" % midis.size())
	
	# 缓存原始JSON
	json_cache[chart_id] = json_data
	
	# 处理歌曲和专辑信息
	_process_song_and_album_info(json_data, midi, chart_id)

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
	
	# 处理歌曲和专辑信息
	_process_song_and_album_info(json_data, midi, midi_id)

## 处理歌曲和专辑信息
func _process_song_and_album_info(json_data: Dictionary, midi: MidiData, midi_id: String) -> void:
	if json_data.has("song") and json_data.has("album"):
		_process_nested_format(json_data, midi, midi_id)
	else:
		GameLogger.instance.warning("Chart missing song/album: %s" % midi_id, "DataMGR")
func _process_nested_format(json_data: Dictionary, midi: MidiData, midi_id: String) -> void:
	# 处理歌曲信息
	var song_json = json_get(json_data, "song", {}) as Dictionary
	var song_id = song_json.get("_id", "")
	
	if song_id and not song_id.is_empty():
		if not songs.has(song_id):
			var currentSong = SongData.new()
			currentSong.from_json(song_json)
			songs[song_id] = currentSong
		
		var song = songs[song_id]
		song.add_midi_id(midi_id)
		midi.song_data = song
		midi.author_name = json_data.get("author", "")
	
	# 处理专辑信息
	var album_json = json_get(json_data, "album", {}) as Dictionary
	var album_id = album_json.get("_id", "")
	
	if album_id and not album_id.is_empty():
		if not albums.has(album_id):
			var album = AlbumData.new()
			album.from_json(album_json)
			albums[album_id] = album
		
		var currentAlbum = albums[album_id]
		if not song_id.is_empty():
			currentAlbum.add_song_id(song_id)
		currentAlbum.total_midi_count += 1
		midi.album_data = currentAlbum
		
		# 更新专辑的最早上传日期
		if not midi.uploaded_date.is_empty():
			if currentAlbum.earliest_uploaded_date.is_empty() or midi.uploaded_date < currentAlbum.earliest_uploaded_date:
				currentAlbum.earliest_uploaded_date = midi.uploaded_date
		
		# 构建树结构
		_add_to_midi_tree(album_id, song_id, midi_id)

func _add_to_midi_tree(album_id: String, song_id: String, midi_id: String) -> void:
	if not midi_tree.has(album_id):
		midi_tree[album_id] = {}
	if not midi_tree[album_id].has(song_id):
		midi_tree[album_id][song_id] = []
	
	# 确保数组存在后添加
	if not midi_tree[album_id][song_id] is Array:
		midi_tree[album_id][song_id] = []
	
	(midi_tree[album_id][song_id] as Array).append(midi_id)

## ========== Unknown 分组合成 ==========

const UNKNOWN_ALBUM_ID := "__unknown_album__"
const UNKNOWN_SONG_ID  := "__unknown_song__"

## 为没有专辑/歌曲的 MIDI 合成 Unknown 分组（在 _load_midis 末尾调用）
func _ensure_unknown_grouping() -> void:
	# 先清理上一次可能残留的 Unknown 条目
	_cleanup_unknown_grouping()
	
	var orphan_midis: Array[MidiData] = []
	var scan_count := 0
	for midi in midis.values():
		if midi.album_data == null or midi.song_data == null:
			orphan_midis.append(midi)
		scan_count += 1
		if scan_count % 500 == 0:
			await get_tree().process_frame
	
	if orphan_midis.is_empty():
		return
	
	# 创建 Unknown 专辑
	var unknown_album := AlbumData.new()
	unknown_album.id = UNKNOWN_ALBUM_ID
	unknown_album.name = "Unknown"
	albums[UNKNOWN_ALBUM_ID] = unknown_album
	
	# 创建 Unknown 歌曲
	var unknown_song := SongData.new()
	unknown_song.id = UNKNOWN_SONG_ID
	unknown_song.name = "Unknown"
	songs[UNKNOWN_SONG_ID] = unknown_song
	
	unknown_album.add_song_id(UNKNOWN_SONG_ID)
	
	# 初始化 midi_tree 条目
	if not midi_tree.has(UNKNOWN_ALBUM_ID):
		midi_tree[UNKNOWN_ALBUM_ID] = {}
	midi_tree[UNKNOWN_ALBUM_ID][UNKNOWN_SONG_ID] = []
	
	for midi in orphan_midis:
		midi.album_data = unknown_album
		midi.song_data = unknown_song
		unknown_album.total_midi_count += 1
		(midi_tree[UNKNOWN_ALBUM_ID][UNKNOWN_SONG_ID] as Array).append(midi.id)
		
		# 更新 Unknown 专辑的最早上传日期
		if not midi.uploaded_date.is_empty():
			if unknown_album.earliest_uploaded_date.is_empty() or midi.uploaded_date < unknown_album.earliest_uploaded_date:
				unknown_album.earliest_uploaded_date = midi.uploaded_date
	
	print("[DataMGR] Created Unknown album with %d orphan MIDIs" % orphan_midis.size())

## 清理之前合成的 Unknown 条目（避免重复）
func _cleanup_unknown_grouping() -> void:
	# 从 midi_tree 移除 Unknown 条目
	if midi_tree.has(UNKNOWN_ALBUM_ID):
		midi_tree.erase(UNKNOWN_ALBUM_ID)
	albums.erase(UNKNOWN_ALBUM_ID)
	songs.erase(UNKNOWN_SONG_ID)

## ========== 专辑排序查询 ==========

## 获取排序后的专辑列表（按 ConfigManager [Browse] 设置排序）
func get_sorted_albums() -> Array[AlbumData]:
	var album_array: Array[AlbumData] = []
	for album in albums.values():
		album_array.append(album)
	
	# 读取排序配置
	var method_str := ConfigManager.instance.get_string("Browse", "album_sort_method", "creation_time")
	var dir_str := ConfigManager.instance.get_string("Browse", "album_sort_direction", "asc")
	
	var method := SortingEngine.parse_album_sort_method(method_str)
	var direction := SortingEngine.SortDirection.ASCENDING if dir_str == "asc" else SortingEngine.SortDirection.DESCENDING
	
	return SortingEngine.instance.sort_albums(album_array, method, direction)

## 获取所有专辑列表（委托到 get_sorted_albums）
func get_all_albums() -> Array[AlbumData]:
	return get_sorted_albums()

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

## 从内存中移除指定 MIDI 及其关联的空 Song / Album
## 参数: midi_id - MidiData 的 id 字段
func remove_midi(midi_id: String) -> void:
	if not midis.has(midi_id):
		GameLogger.instance.warning("remove_midi: midi_id not found: %s" % midi_id, "DataMGR")
		return

	var midi: MidiData = midis[midi_id]
	var song_id: String = midi.song_data.id if midi.song_data else ""
	var album_id: String = midi.album_data.id if midi.album_data else ""

	# 从 midis 与缓存移除
	midis.erase(midi_id)
	json_cache.erase(midi_id)

	# 从 midi_tree 移除，并级联清理空的 Song / Album
	if not album_id.is_empty() and not song_id.is_empty() and midi_tree.has(album_id):
		var album_tree: Dictionary = midi_tree[album_id]
		if album_tree.has(song_id):
			var midi_ids: Array = album_tree[song_id]
			midi_ids.erase(midi_id)
			if midi_ids.is_empty():
				# Song 下已无 midi，移除 Song
				album_tree.erase(song_id)
				songs.erase(song_id)
				# Album 下已无 song，移除 Album
				if album_tree.is_empty():
					midi_tree.erase(album_id)
					albums.erase(album_id)

	GameLogger.instance.info("Removed midi from memory: %s" % midi_id, "DataMGR")
