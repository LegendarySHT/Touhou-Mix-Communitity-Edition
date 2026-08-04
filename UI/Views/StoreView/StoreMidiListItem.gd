extends CoverListItemBase
class_name StoreMidiListItem

const TextScrollHelper = preload("res://UI/Components/TextScrollHelper.gd")

# cover_texture 继承自 CoverListItemBase，在 _ready() 中赋值
# MidiName / Author 在 CoverPanel/Panel 下；Uploader / AlbumName / SongName 在 InfoPanel 下
@onready var title_text:Label = $CoverPanel/Panel/MidiName
@onready var author_text:Label = $CoverPanel/Panel/Author
@onready var uploader:Label = $InfoPanel/Uploader
@onready var album_name:Label = $InfoPanel/AlbumName
@onready var song_name:Label = $InfoPanel/SongName

# 文字滚动状态（每 Label 独立）
var _title_scroll_state: TextScrollHelper.State = null
var _author_scroll_state: TextScrollHelper.State = null
var _uploader_scroll_state: TextScrollHelper.State = null
var _album_scroll_state: TextScrollHelper.State = null
var _song_scroll_state: TextScrollHelper.State = null

signal init_finished

# midi数据
var midi_data:MidiData

## 资源哈希（用于下载和状态查询）
var chart_hash: String = ""
## 下载状态
var download_state: int = 0  # ResourceManager.DownloadState
## 是否为远程 chart（非本地 MidiData）
var is_remote_chart: bool = false
## 脉冲动画 Tween（下载中提示）
var _pulse_tween: Tween
## 原始歌曲名（用于下载完成后恢复显示）
var _original_song_name: String = ""

func _ready() -> void:
	cover_texture = $CoverPanel/cover
	_parallax_enabled = false
	# StoreMidiNode 本身即 Button（原 PanelContainer + 子 Button 已合并）
	button = self
	parent_node = get_node("/root/Main/Store/StoreMidiList")

	# 直接bind参数会传初始化时的值有点难绷
	# 通过实例变量读取，确保按下时获取最新值
	button.pressed.connect(func ():
		if is_remote_chart:
			parent_node.on_remote_chart_select(chart_hash)
		elif midi_data:
			parent_node.on_midi_select(midi_data)
	)

	await init_finished
	enable_selected_animation(button, parent_node)
	# 直接开始加载封面（不等列表构建完毕）
	start_cover_load()

# 设置midi数据 传入无效值时重置
func set_display(midi: MidiData = null) -> void:
	var midi_changed: bool = midi_data != midi
	midi_data = midi
	var enable:bool = true if midi else false
	get_node("CoverPanel").visible = enable
	get_node("InfoPanel").visible = enable
	if enable:
		title_text.text = midi.name
		author_text.text = midi.artist_name
		uploader.text = midi.uploader_name
		album_name.text = midi.album_name if not midi.album_name.is_empty() else "null"
		song_name.text = midi.song_name if not midi.song_name.is_empty() else "null"
	# midi 变化（含从 null 切到非 null）时刷新封面
	if midi_changed:
		if enable:
			# 切到新 midi：保留旧 texture 显示直到新封面加载完成
			switch_cover_data()
			start_cover_load()
		else:
			# 切到 null：彻底释放封面 texture，避免不可见项持有 Texture 引用阻止 GC
			release_cover()
	# 文本变化后重算滚动（仅在有数据时）
	if enable:
		call_deferred("_setup_text_scrolls")
	init_finished.emit()

## 启动/重算所有标签的文字滚动
## await 一帧让布局稳定，确保 clip 容器 size 正确
func _setup_text_scrolls() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	_title_scroll_state = TextScrollHelper.setup(title_text, title_text.get_parent(), title_text.text, _title_scroll_state)
	_author_scroll_state = TextScrollHelper.setup(author_text, author_text.get_parent(), author_text.text, _author_scroll_state)
	_uploader_scroll_state = TextScrollHelper.setup(uploader, uploader.get_parent(), uploader.text, _uploader_scroll_state)
	_album_scroll_state = TextScrollHelper.setup(album_name, album_name.get_parent(), album_name.text, _album_scroll_state)
	_song_scroll_state = TextScrollHelper.setup(song_name, song_name.get_parent(), song_name.text, _song_scroll_state)

## 重写基类虚函数：返回 MIDI 封面 Texture2D
func _get_cover_texture() -> Texture2D:
	if not midi_data:
		return null
	return FileSystemManager.instance.get_cover_by_midiData(midi_data)

## 重写基类虚函数：返回封面文件路径（主线程调用，供异步加载器使用）
func _resolve_cover_path() -> String:
	if not midi_data:
		return ""
	var fs_mgr := FileSystemManager.instance
	if not fs_mgr:
		return ""
	return fs_mgr.get_cover_path_by_midiData(midi_data)

## 设置远程 chart 数据显示（从服务端列表获取）
func set_remote_display(chart_data: Dictionary) -> void:
	chart_hash = str(chart_data.get("hash", ""))
	is_remote_chart = true
	download_state = ResMGR.get_download_state(chart_hash)

	# 填充显示字段
	title_text.text = str(chart_data.get("title", "Unknown"))
	author_text.text = str(chart_data.get("artistName", ""))
	uploader.text = "Upload by " + str(chart_data.get("uploaderName", ""))
	album_name.text = str(chart_data.get("albumName", "null"))
	_original_song_name = str(chart_data.get("songName", "null"))
	song_name.text = _original_song_name

	get_node("CoverPanel").visible = true
	get_node("InfoPanel").visible = true

	# 更新下载状态显示
	_update_download_state_ui()

	# 加载远程封面
	_load_remote_cover(chart_hash)

	call_deferred("_setup_text_scrolls")
	init_finished.emit()

## 更新下载状态的 UI 显示
func _update_download_state_ui() -> void:
	# 根据下载状态更新 song_name 标签文字
	# 已下载：显示 ▶ 前缀提示可游玩
	# 未下载：显示"点击下载"
	# 下载中：显示"下载中..."（带脉冲动画）
	# 失败：显示"下载失败，点击重试"
	match download_state:
		ResourceManager.DownloadState.DOWNLOADED:
			_stop_pulse_animation()
			# 显示播放图标前缀，提示可点击游玩
			# 保留 set_remote_display 中设置的原始歌曲名
			if not _original_song_name.is_empty():
				song_name.text = "▶ " + _original_song_name
		ResourceManager.DownloadState.DOWNLOADING:
			song_name.text = "下载中..."
			_start_pulse_animation()
		ResourceManager.DownloadState.NOT_DOWNLOADED:
			_stop_pulse_animation()
			song_name.text = "点击下载"
		ResourceManager.DownloadState.FAILED:
			_stop_pulse_animation()
			song_name.text = "下载失败，点击重试"

## 启动脉冲动画（下载中提示）
func _start_pulse_animation() -> void:
	_stop_pulse_animation()
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(song_name, "modulate:a", 0.3, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(song_name, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween = tween

## 停止脉冲动画
func _stop_pulse_animation() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_pulse_tween = null
	song_name.modulate.a = 1.0

## 从服务端加载远程封面
func _load_remote_cover(target_hash: String) -> void:
	if NetManager.instance == null or not NetManager.instance.is_online:
		return
	if cover_texture:
		cover_texture.visible = false
	var cover_url := "%s/api/charts/%s/cover" % [NetManager.instance.server_url, target_hash]
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(cover_url)
	if err != OK:
		http.queue_free()
		return
	var resp = await http.request_completed
	http.queue_free()
	if not is_instance_valid(self):
		return
	var result_code = resp[0]
	var response_code = resp[1]
	var response_body = resp[3]
	if result_code != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	if not response_body is PackedByteArray or response_body.size() == 0:
		return
	var image := Image.new()
	var err_img := image.load_jpg_from_buffer(response_body)
	if err_img != OK:
		err_img = image.load_png_from_buffer(response_body)
	if err_img != OK:
		return
	var tex := ImageTexture.create_from_image(image)
	if cover_texture:
		cover_texture.texture = tex
		cover_texture.visible = true

## 刷新下载状态（供 StoreView 下载完成后调用）
func refresh_download_state() -> void:
	if is_remote_chart and not chart_hash.is_empty():
		download_state = ResMGR.get_download_state(chart_hash)
		_update_download_state_ui()

func _exit_tree() -> void:
	_stop_pulse_animation()
