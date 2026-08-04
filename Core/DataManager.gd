## 数据管理器
## 负责歌曲数据的惰性水合缓存与查询（数据唯一源 = ChartDb LiteDB）
## 启动不再构造全部 MidiData；视图需要时经 _ensureMidi/_ensureSong/_ensureAlbum 按需水合
extends Node

class_name DataManager

## 所有专辑数据 (ID -> AlbumData) —— 惰性水合缓存
var albums: Dictionary[String, AlbumData] = {}

## 所有歌曲数据 (ID -> SongData) —— 惰性水合缓存
var songs: Dictionary[String, SongData] = {}

## 所有MIDI谱面数据 (folder_name -> MidiData) —— 惰性水合缓存
## 规范键 = ChartDb 的主键（folder_name），经 LookupChartKey 统一解析别名
var midis: Dictionary[String, MidiData] = {}

## 数据加载状态 (初始为True防止还没启动就被读取)
var is_loading: bool = true
## 待重载标志：charts 缓存校验发现变化但当前正在加载，标记待重载
## 当前加载完成后检查此标志，若为 true 则重新加载
var _pending_reload: bool = false

## 加载完成信号
signal data_loaded

func _ready() -> void:
	add_to_group("singleton")
	# 监听 charts 缓存后台校验完成信号
	# 启动时 FileSystemManager 先从缓存恢复 charts_index 让用户立即操作
	# 后台校验若发现变化（新增/删除/修改文件夹），清空水合缓存重新加载并 emit data_loaded
	# 这样 UI 通过已监听的 data_loaded 信号自动刷新，无需额外耦合
	if EvtBus:
		EvtBus.charts_cache_validated.connect(_on_charts_cache_validated)

## charts 缓存校验完成回调
## changed=true 表示发现了新增/删除/修改的文件夹，需清空水合缓存并重新加载
## changed=false 表示缓存完全有效，无需重建
func _on_charts_cache_validated(changed: bool) -> void:
	if not changed:
		return
	# 如果当前正在加载（基于缓存数据的第一次加载），标记待重载
	# 当前加载完成后会检查此标志并重新加载
	if is_loading:
		GLogger.info("Charts cache validated with changes, but data is loading, pending reload", "DataMGR")
		_pending_reload = true
		return
	GLogger.info("Charts cache validated with changes, rebuilding data caches...", "DataMGR")
	_rebuild_data_tree()

## 从 DB 轻量加载门：不再构造全部 MidiData（性能主菜）
## 数据全部在 ChartDb，视图需要时惰性水合；这里只做就绪门 + emit data_loaded
func load_all_midis_async() -> void:
	if not is_loading:
		return

	if FileSystemManager.instance == null:
		push_error("FileSystemManager not initialized")
		return

	while not FileSystemManager.instance.is_initialized:
		await get_tree().process_frame
	_emit_data_loaded()

func _emit_data_loaded():
	GLogger.info("_emit_data_loaded() called", "DataMGR")
	is_loading = false
	# 检查是否在校验期间发现了缓存变化，需要重新加载
	if _pending_reload:
		_pending_reload = false
		GLogger.info("Pending reload triggered by cache validation, rebuilding...", "DataMGR")
		_rebuild_data_tree()
		return
	var stats = get_statistics()
	GLogger.info("Stats - Albums: %d, Songs: %d, MIDIs: %d" % [stats.total_albums, stats.total_songs, stats.total_midis], "DataMGR")
	GLogger.info("Emitting data_loaded signal...", "DataMGR")
	data_loaded.emit()
	GLogger.info("data_loaded signal emitted!", "DataMGR")

## 清空旧水合缓存，重新进入轻量加载
func _rebuild_data_tree() -> void:
	albums.clear()
	songs.clear()
	midis.clear()
	is_loading = true
	load_all_midis_async()

## ========== 惰性水合 ==========

## 按规范键（folder_name）水合 MidiData，缓存命中返回同一实例（对象身份稳定）
func _ensureMidi(chart_key: String) -> MidiData:
	if chart_key.is_empty():
		return null
	if midis.has(chart_key):
		return midis[chart_key]
	if ChartDB == null or not ChartDB.IsOpen():
		return null

	var json_data: Dictionary = ChartDB.GetChartJson(chart_key)
	if json_data.is_empty():
		return null

	var midi := MidiData.new()
	midi.from_json(json_data)
	if midi.id.is_empty():
		return null

	# 关联 song/album（DB 聚合；孤儿 → __unknown，由 RebuildAlbumsSongs 归组）
	var song_id: String = json_data.get("song_id", "")
	var album_id: String = json_data.get("album_id", "")
	midi.song_data = _ensureSong(song_id) if not song_id.is_empty() else null
	midi.album_data = _ensureAlbum(album_id) if not album_id.is_empty() else null

	# 初始化人声配置：仅对未保存过 vocal_enabled 配置的新 MIDI 生效，已保存的配置尊重用户选择
	var runtime_config: Variant = json_data.get("_runtime", {})
	var has_saved_vocal_enabled = runtime_config is Dictionary and runtime_config.has("vocal_enabled")
	if not has_saved_vocal_enabled:
		var audio_path: String = ChartDB.GetAudioPath(chart_key)
		if not audio_path.is_empty() and FileAccess.file_exists(audio_path):
			midi.vocal_enabled = true
			midi.vocal_file_path = audio_path
		else:
			midi.vocal_enabled = false

	midis[chart_key] = midi
	return midi

## 按 song_id 水合 SongData（DB songs 集合为聚合，含 midi_ids）
func _ensureSong(song_id: String) -> SongData:
	if song_id.is_empty():
		return null
	if songs.has(song_id):
		return songs[song_id]
	if ChartDB == null or not ChartDB.IsOpen():
		return null

	var d: Dictionary = ChartDB.GetSong(song_id)
	if d.is_empty():
		return null

	var s := SongData.new()
	s.from_json(d)
	s.midi_ids.assign(d.get("midi_ids", []))
	songs[song_id] = s
	return s

## 按 album_id 水合 AlbumData（DB albums 集合为聚合，含 song_ids/total_midi_count/earliest_uploaded_date）
func _ensureAlbum(album_id: String) -> AlbumData:
	if album_id.is_empty():
		return null
	if albums.has(album_id):
		return albums[album_id]
	if ChartDB == null or not ChartDB.IsOpen():
		return null

	var d: Dictionary = ChartDB.GetAlbum(album_id)
	if d.is_empty():
		return null
	return _hydrateAlbum(album_id, d)

## 从 DB album dict 构造 AlbumData 并入缓存（get_sorted_albums 复用已拉取的 dict，避免二次读库）
func _hydrateAlbum(album_id: String, d: Dictionary) -> AlbumData:
	var a := AlbumData.new()
	a.from_json(d)
	a.song_ids.assign(d.get("song_ids", []))
	a.total_midi_count = d.get("total_midi_count", 0)
	a.earliest_uploaded_date = d.get("earliest_uploaded_date", "")
	albums[album_id] = a
	return a

## ========== 专辑排序查询 ==========

## 获取排序后的专辑列表（按 ConfigManager [Browse] 设置排序）
func get_sorted_albums() -> Array[AlbumData]:
	var album_array: Array[AlbumData] = []
	if ChartDB == null or not ChartDB.IsOpen():
		return album_array
	for d: Variant in ChartDB.GetAlbums():
		if d is Dictionary and not (d as Dictionary).is_empty():
			var album_dict: Dictionary = d as Dictionary
			var album_id: String = String(album_dict.get("_id", ""))
			var album: AlbumData = null
			if albums.has(album_id):
				album = albums[album_id]
			else:
				album = _hydrateAlbum(album_id, album_dict)
			if album:
				album_array.append(album)

	# 读取排序配置
	var method_str := ConfigManager.instance.get_string("Browse", "album_sort_method", "creation_time")
	var dir_str := ConfigManager.instance.get_string("Browse", "album_sort_direction", "asc")

	var method := SortingEngine.parse_album_sort_method(method_str)
	var direction := SortingEngine.SortDirection.ASCENDING if dir_str == "asc" else SortingEngine.SortDirection.DESCENDING

	return SortEngine.sort_albums(album_array, method, direction)

## 获取所有专辑列表（委托到 get_sorted_albums）
func get_all_albums() -> Array[AlbumData]:
	return get_sorted_albums()

## 获取专辑下的所有歌曲
func get_songs_by_album(album_id: String) -> Array[SongData]:
	var result: Array[SongData] = []
	var album = _ensureAlbum(album_id)
	if album == null:
		return result
	for song_id in album.song_ids:
		var song = _ensureSong(song_id)
		if song:
			result.append(song)
	return result

## 获取歌曲下的所有MIDI谱面
func get_midis_by_song(song_id: String) -> Array[MidiData]:
	var result: Array[MidiData] = []
	if ChartDB == null or not ChartDB.IsOpen():
		return result
	for chart_key: String in ChartDB.GetMidiKeysBySong(song_id):
		var midi: MidiData = _ensureMidi(chart_key)
		if midi:
			result.append(midi)
	return result

## 按MIDI ID/别名获取单个MIDI谱面（统一经 LookupChartKey 解析到规范键，返回同一实例）
func get_midi_by_id(midi_id: String) -> MidiData:
	if midi_id.is_empty():
		return null
	if ChartDB == null or not ChartDB.IsOpen():
		return midis.get(midi_id)
	var chart_key: String = ChartDB.LookupChartKey(midi_id)
	if chart_key.is_empty():
		return null
	return _ensureMidi(chart_key)

## 按专辑ID获取专辑
func get_album_by_id(album_id: String) -> AlbumData:
	return _ensureAlbum(album_id)

## 按歌曲ID获取歌曲
func get_song_by_id(song_id: String) -> SongData:
	return _ensureSong(song_id)

## 按状态过滤MIDI谱面
func get_midis_by_status(status: String) -> Array[MidiData]:
	var result: Array[MidiData] = []
	if ChartDB == null or not ChartDB.IsOpen():
		return result
	for chart_key: String in ChartDB.GetChartsByStatus(status):
		var midi: MidiData = _ensureMidi(chart_key)
		if midi:
			result.append(midi)
	return result

## 获取所有MIDI谱面列表（全量水合，仅全量视图需要）
func get_all_midis() -> Array[MidiData]:
	var result: Array[MidiData] = []
	if ChartDB == null or not ChartDB.IsOpen():
		return result
	for chart_key: String in ChartDB.GetAllChartKeys():
		var midi: MidiData = _ensureMidi(chart_key)
		if midi:
			result.append(midi)
	return result

## 全库搜索（DB 驱动，只水合命中项；DelView 扁平搜索等"整个库"场景用）
## 与 SortEngine.search_midis（当前集内过滤，保持顺序）互补
func search_all_midis(query: String) -> Array[MidiData]:
	var result: Array[MidiData] = []
	if ChartDB == null or not ChartDB.IsOpen() or query.is_empty():
		return result
	for chart_key: String in ChartDB.SearchMidiKeys(query):
		var midi: MidiData = _ensureMidi(chart_key)
		if midi:
			result.append(midi)
	return result

## 预览用：只水合前 N 张谱面（避免全量水合）
func get_midis_preview(count: int) -> Array[MidiData]:
	var result: Array[MidiData] = []
	if ChartDB == null or not ChartDB.IsOpen() or count <= 0:
		return result
	var keys: Array = ChartDB.GetAllChartKeys()
	var limit: int = min(count, keys.size())
	for i in range(limit):
		var midi: MidiData = _ensureMidi(String(keys[i]))
		if midi:
			result.append(midi)
	return result

## 获取数据统计信息（DB 聚合，零水合）
func get_statistics() -> Dictionary:
	if ChartDB == null or not ChartDB.IsOpen():
		return {
			"total_albums": 0,
			"total_songs": 0,
			"total_midis": 0,
			"pending_count": 0,
			"approved_count": 0,
			"included_count": 0,
			"dead_count": 0
		}
	return {
		"total_albums": ChartDB.CountAlbums(),
		"total_songs": ChartDB.CountSongs(),
		"total_midis": ChartDB.CountCharts(),
		"pending_count": ChartDB.CountByStatus("PENDING"),
		"approved_count": ChartDB.CountByStatus("APPROVED"),
		"included_count": ChartDB.CountByStatus("INCLUDED"),
		"dead_count": ChartDB.CountByStatus("DEAD")
	}

## 清空所有数据缓存
func clear_data() -> void:
	albums.clear()
	songs.clear()
	midis.clear()

## 从内存水合缓存中移除指定 MIDI（DB 删除由 FileSystemManager.delete_chart → ChartDB.RemoveChart 完成）
## 参数: midi_id - MidiData 的 id 字段或 file_hash
func remove_midi(midi_id: String) -> void:
	if ChartDB != null and ChartDB.IsOpen():
		var chart_key: String = ChartDB.LookupChartKey(midi_id)
		if not chart_key.is_empty():
			midis.erase(chart_key)
			GLogger.info("Removed midi from memory: %s (key: %s)" % [midi_id, chart_key], "DataMGR")
			return
	midis.erase(midi_id)
	GLogger.info("Removed midi from memory: %s" % midi_id, "DataMGR")
