extends CoverListItemBase

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

func _ready() -> void:
	cover_texture = $CoverPanel/cover
	_parallax_enabled = false
	# StoreMidiNode 本身即 Button（原 PanelContainer + 子 Button 已合并）
	button = self
	parent_node = get_node("/root/Main/Store/StoreMidiList")

	# 直接bind参数会传初始化时的值有点难绷
	button.pressed.connect(func ():
		if midi_data:
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
		album_name.text = "null" if not midi.album_data else midi.album_data.name
		song_name.text = "null" if not midi.song_data else midi.song_data.name
	# midi 变化（含从 null 切到非 null）时刷新封面：先释放旧封面，再立即加载新封面
	if midi_changed:
		release_cover()
		if enable:
			start_cover_load()
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
