extends ListItemBase

@onready var cover_texture:TextureRect = $CoverPanel/cover
@onready var title_text:Label = $InfoPanel/MidiName
@onready var author_text:Label = $InfoPanel/Author
@onready var uploader:Label = $InfoPanel/Uploader
@onready var album_name:Label = $InfoPanel/AlbumName
@onready var song_name:Label = $InfoPanel/SongName

signal init_finished

# midi数据
var midi_data:MidiData

func _ready() -> void:
	button = get_node_or_null("Button")
	parent_node = get_node("/root/Main/Store/StoreMidiList")

	# 直接bind参数会传初始化时的值有点难绷
	button.pressed.connect(func ():
		if midi_data:
			parent_node.on_midi_select(midi_data)
	)

	await init_finished
	enable_selected_animation(button, parent_node)

# 设置midi数据 传入无效值时重置
func set_display(midi: MidiData = null) -> void:
	midi_data = midi
	var enable:bool = true if midi else false
	get_node("CoverPanel").visible = enable
	get_node("InfoPanel").visible = enable
	if enable:
		cover_texture.texture = _load_midi_cover(midi)
		title_text.text = midi.name
		author_text.text = midi.artist_name
		uploader.text = midi.uploader_name
		album_name.text = midi.album_data.name
		song_name.text = midi.song_data.name
	init_finished.emit()

# 封面加载
func _load_midi_cover(midi: MidiData):
	return FileSystemManager.instance.get_cover_by_midiData(midi)	
