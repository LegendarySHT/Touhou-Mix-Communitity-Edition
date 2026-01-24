extends Control

@onready var background: TextureRect = $Background
@onready var menu_btn: TextureButton = $BackBtn
@onready var progress_bar: ProgressBar = $TopProgressBar

@onready var combo: Label = $CenterData/Combo/count
@onready var score: Label = $CenterData/Score/count
# 显示perfect的那个部分
@onready var center_text: Label = $CenterData/Center/type
@onready var early_text: Label = $CenterData/Center/up
@onready var late_text: Label = $CenterData/Center/down
# 底部
@onready var pp_text: Label = $LeftBottom
@onready var accuracy_text: Label = $RightBottom
# 判定线，假如需要距离底部200px的话，把y设置成-200即可
@onready var judgement_line: Line2D = $Line2D

# 菜单及歌曲信息的背景遮罩
@onready var center_bg:ColorRect = $CenterBackGround
# 菜单
@onready var menu: Control = $CenterBackGround/Menu
@onready var retry_btn: Button = $CenterBackGround/Menu/retry
@onready var continue_btn: Button = $CenterBackGround/Menu/continue
@onready var quit_btn: Button = $CenterBackGround/Menu/quit
# 歌曲信息
@onready var song_info: Control = $CenterBackGround/SongInfo
@onready var cover: TextureRect = $CenterBackGround/SongInfo/PanelContainer/TextureRect
# 原曲
@onready var album: Label = $CenterBackGround/SongInfo/GridContainer/album
@onready var song: Label = $CenterBackGround/SongInfo/GridContainer/song
@onready var artist: Label = $CenterBackGround/SongInfo/GridContainer/artist
# midi
@onready var midi_name: Label = $CenterBackGround/SongInfo/GridContainer/midiName
@onready var midi_author: Label = $CenterBackGround/SongInfo/GridContainer/midiAuthor
@onready var midi_duration: Label = $CenterBackGround/SongInfo/GridContainer/midiDuration
# 难度
@onready var difficulty: Label = $CenterBackGround/SongInfo/GridContainer/difficulty

var current_midi:MidiData = null

func _ready() -> void:

	EventBus.instance.start_game_with.connect(_prepare_game)
	UIStateManager.instance.state_changed.connect(_on_state_changed)

func _on_state_changed(_oldState: UIStateManager.UIState, state: UIStateManager.UIState) -> void:
	var enable:bool = state == UIStateManager.UIState.PLAY_VIEW
	set_process(enable)
	set_process_input(enable)
	if enable:
		print("Node: %s , ProcessMode: %s" % [self.name, enable])

func _prepare_game(midi:MidiData) -> void:
	current_midi = midi

	menu.visible = false
	song_info.visible = true
	center_bg.visible = true
	
	cover.texture = FileSystemManager.instance.get_cover_by_midiData(midi)
	album.text = midi.artist_name
	song.text = midi.song_data.name
	# artist.text = midi.song_data.artist_name # 没找着歌手在哪
	midi_name.text = midi.name
	midi_author.text = midi.artist_name
	# midi_duration.text = midi.duration_ms

	await get_tree().create_timer(3).timeout
	AnimationManager.instance.animate_fade_out(center_bg, 1)
