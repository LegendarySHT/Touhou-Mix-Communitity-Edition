extends CoverListItemBase

# cover_texture 继承自 CoverListItemBase，在 _ready() 中赋值
@onready var title_text:Label = $InfoPanel/MidiName
@onready var author_text:Label = $InfoPanel/Author
@onready var uploader:Label = $InfoPanel/Uploader
@onready var album_name:Label = $InfoPanel/AlbumName
@onready var song_name:Label = $InfoPanel/SongName

signal init_finished

# midi数据
var midi_data:MidiData

func _ready() -> void:
	cover_texture = $CoverPanel/cover
	_parallax_enabled = false
	button = get_node_or_null("Button")
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
	init_finished.emit()

## 重写基类虚函数：返回 MIDI 封面 Texture2D
func _get_cover_texture() -> Texture2D:
	if not midi_data:
		return null
	return FileSystemManager.instance.get_cover_by_midiData(midi_data)
