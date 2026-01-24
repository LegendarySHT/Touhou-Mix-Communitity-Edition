## MIDI播放管理器
## 负责MIDI文件的加载、播放、轨道选择和音源管理
extends Node

class_name MidiPlaybackManager

## 单例实例
static var instance: MidiPlaybackManager

## MIDI播放器引用
var midi_player: Node

## 当前加载的MIDI数据
var current_midi_data: MidiData

## 当前解析的音符列表
var current_notes: Array = []

## MIDI播放状态
var is_playing: bool = false

## 当前播放位置（毫秒）
var position_ms: float = 0.0

## 总时长（毫秒）
var duration_ms: float = 0.0

## 可用的SoundFont列表（缓存）
var available_soundfonts: Array = []

## 默认SoundFont路径
var default_soundfont_path: String = "res://Resources/Soundfont/GeneralUser-GS.sf2"

## 当前使用的SoundFont路径
var current_soundfont_path: String = ""

## MIDI播放器配置
var midi_player_config: Dictionary = {
	"max_polyphony": 96,
	"loop": false,
	"volume_db": -20.0
}

## 信号：MIDI加载完成
signal midi_loaded(midi_data: MidiData)

## 信号：MIDI开始播放
signal midi_started

## 信号：MIDI暂停
signal midi_paused

## 信号：MIDI停止
signal midi_stopped

## 信号：MIDI播放完成
signal midi_finished

## 信号：轨道选择改变
signal tracks_changed(selected_indices: Array[int])

## 信号：音源改变
signal soundfont_changed(soundfont_path: String)

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	
	add_to_group("singleton")
	
	# 初始化MIDI播放器
	_initialize_midi_player()
	
	# 扫描可用的SoundFont
	_scan_soundfonts()
	
	# 设置默认音源
	current_soundfont_path = default_soundfont_path

func _process(_delta: float) -> void:
	if is_playing and midi_player != null:
		# 更新当前播放位置
		position_ms = midi_player.position

## 初始化MIDI播放器
func _initialize_midi_player() -> void:
	# 检查MidiPlayer插件是否存在
	var midi_player_scene = load("res://addons/midi/MidiPlayer.tscn")
	if midi_player_scene == null:
		push_error("MidiPlayer addon not found!")
		return
	
	midi_player = midi_player_scene.instantiate()
	midi_player.name = "MidiPlayer"
	add_child(midi_player)
	
	# 配置MidiPlayer
	if midi_player.has_meta("script"):
		midi_player.max_polyphony = midi_player_config["max_polyphony"]
		midi_player.loop = midi_player_config["loop"]
		midi_player.volume_db = midi_player_config["volume_db"]
		midi_player.bus = "Master"
	
	# 连接信号
	if midi_player.has_signal("finished"):
		midi_player.finished.connect(_on_midi_finished)

## 加载MIDI文件
## 返回: success (bool)
func load_midi(midi_data: MidiData) -> bool:
	if midi_data == null:
		push_error("MidiData is null")
		return false
	
	# 保存当前MIDI数据
	current_midi_data = midi_data
	
	# 使用FileSystemManager定位MIDI文件路径
	var midi_file_path = _locate_midi_file(midi_data)
	if midi_file_path.is_empty():
		push_error("Cannot locate MIDI file for: %s" % midi_data.id)
		return false
	
	# 存储路径
	current_midi_data.midi_file_path = midi_file_path
	
	# 解析MIDI文件
	var parse_result = MidiParser.load_and_parse_midi(midi_file_path)
	if not parse_result["success"]:
		push_error("Failed to parse MIDI file: %s" % midi_file_path)
		return false
	
	# 保存解析结果
	current_notes = parse_result["notes"]
	current_midi_data.parsed_notes = current_notes
	current_midi_data.track_count = parse_result["track_infos"].size()
	current_midi_data.bpm = parse_result["bpm"]
	current_midi_data.duration_ms = parse_result["duration"]
	duration_ms = parse_result["duration"]
	
	# 如果未选择轨道，则默认选择所有轨道
	if current_midi_data.selected_track_indices.is_empty():
		for i in range(current_midi_data.track_count):
			current_midi_data.selected_track_indices.append(i)
	
	# 加载到MidiPlayer
	if midi_player != null:
		midi_player.file = midi_file_path
	
	# 发出信号
	midi_loaded.emit(current_midi_data)
	
	return true

## 播放MIDI
func play() -> void:
	if midi_player == null:
		push_error("MidiPlayer not initialized")
		return
	
	if current_midi_data == null:
		push_error("No MIDI loaded")
		return
	
	# 设置音源
	if not current_soundfont_path.is_empty():
		midi_player.soundfont = current_soundfont_path
	
	midi_player.play()
	is_playing = true
	midi_started.emit()

## 停止播放
func stop() -> void:
	if midi_player == null:
		return
	
	midi_player.stop()
	is_playing = false
	position_ms = 0.0
	midi_stopped.emit()

## 暂停播放
func pause() -> void:
	if midi_player == null:
		return
	
	midi_player.playing = false
	is_playing = false
	midi_paused.emit()

## 继续播放
func resume() -> void:
	if midi_player == null:
		return
	
	midi_player.playing = true
	is_playing = true
	midi_started.emit()

## 跳转到指定位置
func seek(position: float) -> void:
	if midi_player == null:
		return
	
	position_ms = position
	midi_player.seek(position)

## 设置选中的轨道
func set_selected_tracks(track_indices: Array[int]) -> void:
	if current_midi_data == null:
		return
	
	current_midi_data.set_selected_tracks(track_indices)
	tracks_changed.emit(track_indices)

## 设置音源文件
func set_soundfont(soundfont_name: String) -> bool:
	# 检查文件是否存在
	var soundfont_path = "res://Resources/Soundfont/%s" % soundfont_name
	if not ResourceLoader.exists(soundfont_path):
		push_warning("Soundfont file not found: %s" % soundfont_path)
		return false
	
	current_soundfont_path = soundfont_path
	if current_midi_data != null:
		current_midi_data.set_soundfont(soundfont_name)
	
	# 如果正在播放，立即切换音源
	if is_playing and midi_player != null:
		midi_player.soundfont = soundfont_path
	
	soundfont_changed.emit(soundfont_path)
	return true

## 设置音量
func set_volume_db(volume: float) -> void:
	if midi_player == null:
		return
	
	midi_player.volume_db = volume
	midi_player_config["volume_db"] = volume

## 设置特定轨道的音量（相对于主音量）
func set_track_volume_db(track_index: int, volume_db: float) -> void:
	if midi_player == null or current_midi_data == null:
		return
	
	# 注：此方法为框架实现
	# MidiPlayer插件可能不直接支持轨道级音量控制
	# 实际实现可能需要在MidiPlayer或自定义播放器中扩展
	# 当前版本记录日志供调试
	print("[MidiPlaybackManager] Set track %d volume to %.2f dB" % [track_index, volume_db])

## 获取已选中轨道对应的Note
func get_selected_track_notes() -> Array:
	if current_midi_data == null or current_notes.is_empty():
		return []
	
	return MidiParser.extract_notes_by_track(current_notes, current_midi_data.selected_track_indices)

## 扫描可用的SoundFont文件
func _scan_soundfonts() -> void:
	available_soundfonts.clear()
	
	var soundfont_dir = "res://Resources/Soundfont"
	var dir = DirAccess.open(soundfont_dir)
	
	if dir == null:
		push_warning("Soundfont directory not found: %s" % soundfont_dir)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".sf2"):
			available_soundfonts.append(file_name)
		file_name = dir.get_next()

## 获取可用的SoundFont列表
func get_available_soundfonts() -> Array:
	return available_soundfonts.duplicate()

## 辅助函数：定位MIDI文件路径
func _locate_midi_file(midi_data: MidiData) -> String:
	# 使用FileSystemManager的文件索引来定位MIDI文件
	var filesystem_manager = FileSystemManager.instance
	if filesystem_manager == null:
		push_error("FileSystemManager not initialized")
		return ""

	# 从charts索引中查找（优先使用已缓存的路径）
	var charts_index = filesystem_manager.get_charts_index()
	for folder_name in charts_index.keys():
		var metadata: Dictionary = charts_index[folder_name]
		var chart_id: String = metadata.get("id", "")
		if chart_id == midi_data.id or chart_id == midi_data.file_hash:
			# 首选使用索引中缓存的路径
			var chart_path: String = metadata.get("path", "")
			if chart_path.is_empty():
				chart_path = FileSystemManager.CHARTS_DIR.path_join(folder_name)
			# 1) 按 chart_id 命名的mid
			var midi_file_path: String = chart_path.path_join(chart_id + ".mid")
			if FileAccess.file_exists(midi_file_path):
				return midi_file_path
			# 2) 按 midi_data.id 命名的mid（旧格式）
			var alt_id_path: String = chart_path.path_join(midi_data.id + ".mid")
			if FileAccess.file_exists(alt_id_path):
				return alt_id_path
			# 3) 按 midi_data.file_hash 命名的mid（若提供）
			if not midi_data.file_hash.is_empty():
				var hash_path: String = chart_path.path_join(midi_data.file_hash + ".mid")
				if FileAccess.file_exists(hash_path):
					return hash_path
			# 4) 作为后备，尝试 res:// 目录同名路径
			var res_chart_path: String = FileSystemManager.DEFAULT_CHARTS_SRC.path_join(folder_name)
			var res_candidates = [
				res_chart_path.path_join(chart_id + ".mid"),
				res_chart_path.path_join(midi_data.id + ".mid"),
				res_chart_path.path_join(midi_data.file_hash + ".mid") if not midi_data.file_hash.is_empty() else ""
			]
			for candidate in res_candidates:
				if candidate != "" and FileAccess.file_exists(candidate):
					return candidate

	return ""

## 回调：MIDI播放完成
func _on_midi_finished() -> void:
	is_playing = false
	midi_finished.emit()

## 获取当前MIDI的轨道信息列表
func get_track_infos() -> Array:
	if current_midi_data == null or current_notes.is_empty():
		return []
	
	# 重新解析以获取完整轨道信息
	var parse_result = MidiParser.load_and_parse_midi(current_midi_data.midi_file_path)
	if parse_result["success"]:
		return parse_result["track_infos"]
	
	return []
