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
		
		# 每处理 100 个谱面打印一次进度
		if processed_count % 100 == 0:
			print("[DataMGR] Processing charts: %d/%d" % [processed_count, charts.size()])
			await get_tree().process_frame
	
	print("[DataMGR] Finished processing %d charts, now emitting signal..." % processed_count)
	print("[DataMGR] Midis in dictionary: %d" % midis.size())

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
	# 检查是哪种格式
	# 格式1：有直接的song和album对象（嵌套格式）
	if json_data.has("song") and json_data.has("album"):
		# 第二种格式：嵌套的song和album对象
		_process_nested_format(json_data, midi, midi_id)
	# 格式2：直接字段（第一种格式）
	else:
		# 第一种格式：直接字段，需要自己构造song和album
		_process_flat_format(json_data, midi, midi_id)

## 处理嵌套格式（第二种格式）
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
		
		# 构建树结构
		_add_to_midi_tree(album_id, song_id, midi_id)

## 处理扁平格式（第一种格式）
func _process_flat_format(json_data: Dictionary, midi: MidiData, midi_id: String) -> void:
	# 提取源信息
	var source_album_name = json_get(json_data, "sourceAlbumName", "")
	var source_song_name = json_get(json_data, "sourceSongName", "")
	
	# 如果源信息为空，使用默认值
	if source_album_name.is_empty():
		source_album_name = "Unknown Album"
	if source_song_name.is_empty():
		source_song_name = "Unknown Song"
	
	# 使用源信息创建歌曲ID和专辑ID
	var song_id = "song_" + source_song_name.sha256_text().substr(0, 16)
	var album_id = "album_" + source_album_name.sha256_text().substr(0, 16)
	
	# 处理歌曲信息
	if not songs.has(song_id):
		var currentSong = SongData.new()
		currentSong.id = song_id
		currentSong.name = source_song_name
		currentSong.name_en = source_song_name
		currentSong.track_number = 0
		
		# 从touhouSongIndex获取音轨号（如果可用）
		var touhou_song_index = json_data.get("touhouSongIndex", -1)
		if touhou_song_index >= 0:
			currentSong.track_number = touhou_song_index
		
		songs[song_id] = currentSong
	
	var song = songs[song_id]
	song.add_midi_id(midi_id)
	midi.song_data = song
	
	# 处理专辑信息
	if not albums.has(album_id):
		var currentAlbum = AlbumData.new()
		currentAlbum.id = album_id
		currentAlbum.name = source_album_name
		
		# 尝试从touhouAlbumIndex获取缩写
		var touhou_album_index = json_data.get("touhouAlbumIndex", -1)
		if touhou_album_index >= 0:
			currentAlbum.abbreviation = "TH%02d" % touhou_album_index
		
		# 从uploadedDate获取发布日期
		var uploaded_date = json_get(json_data, "uploadedDate", "")
		if not uploaded_date.is_empty():
			# 尝试解析日期
			var date_parts = uploaded_date.split("T")[0].split("-")
			if date_parts.size() >= 3:
				currentAlbum.release_date = "%s年%s月%s日" % [date_parts[0], date_parts[1], date_parts[2]]
		
		# 封面URL
		var cover_url = json_get(json_data, "coverUrl", "")
		if not cover_url.is_empty():
			currentAlbum.cover_url = cover_url
		
		albums[album_id] = currentAlbum
	
	var album = albums[album_id]
	if not song_id.is_empty():
		album.add_song_id(song_id)
	album.total_midi_count += 1
	midi.album_data = album
	
	# 构建树结构
	_add_to_midi_tree(album_id, song_id, midi_id)

## 添加到MIDI树结构
func _add_to_midi_tree(album_id: String, song_id: String, midi_id: String) -> void:
	if not midi_tree.has(album_id):
		midi_tree[album_id] = {}
	if not midi_tree[album_id].has(song_id):
		midi_tree[album_id][song_id] = []
	
	# 确保数组存在后添加
	if not midi_tree[album_id][song_id] is Array:
		midi_tree[album_id][song_id] = []
	
	(midi_tree[album_id][song_id] as Array).append(midi_id)

## 获取所有专辑列表（按发布日期排序）
func get_all_albums() -> Array[AlbumData]:
	var result: Array[AlbumData] = []
	for album in albums.values():
		result.append(album)
	
	# 按发布日期排序
	result.sort_custom(func(a: AlbumData, b: AlbumData) -> bool:
		return a.release_date < b.release_date
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
