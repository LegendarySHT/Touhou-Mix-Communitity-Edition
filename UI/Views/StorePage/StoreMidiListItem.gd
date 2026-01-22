extends ListItemBase

@onready var cover_texture:TextureRect = $CoverPanel/cover
@onready var title_text:Label = $InfoPanel/MidiName
@onready var author_text:Label = $InfoPanel/Author
@onready var uploader:Label = $InfoPanel/Uploader
@onready var album_name:Label = $InfoPanel/AlbumName
@onready var song_name:Label = $InfoPanel/SongName

# midi数据
var midi_data:MidiData

func _ready() -> void:
	if not button:
		button = get_node_or_null("Button")
		
	pivot_offset = size / 2
	enable_selected_animation(button)

# 设置midi数据 传入无效值时重置
func set_display(midi) -> void:
	midi_data = midi
	var enable:bool = true if midi else false
	get_node("CoverPanel").visible = enable
	get_node("InfoPanel").visible = enable
	if enable:
		title_text.text = midi.name
		author_text.text = midi.artist_name
		uploader.text = midi.uploader_name
		album_name.text = midi.album_data.name
		song_name.text = midi.song_data.name
