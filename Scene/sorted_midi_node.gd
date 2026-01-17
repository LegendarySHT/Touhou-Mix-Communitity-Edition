extends MarginContainer
var be_selected=0

func _ready():
	get_node("MC/MC/status").text=get_meta("status")
	get_node("MC/VBox/MidiName").text=get_meta("name")
	get_node("MC/VBox/Author").text=get_meta("artistName")
	if get_meta("artistName")=="":
		get_node("MC/VBox/Author").text="Unknow"
	get_node("Button").set_meta("index",get_meta("index"))

func _select(toggled_on):
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_parallel(true)
	
	if(toggled_on):
		if be_selected:
			print("选中：%s / %s"%[get_meta("album"),get_meta("song")])
			Global.select_midi=get_meta("id")
			UiStatMGR.change_state(UiStatMGR.UIState.MIDI_VIEW)
		tween.tween_property(self,"scale",Vector2(1.07,1.07),0.15)
		tween.tween_property(get_node("Line2D"),"default_color",Color("#938aff"),0.15)
		be_selected=1
	else:
		tween.tween_property(self,"scale",Vector2(1,1),0.25)
		tween.tween_property(get_node("Line2D"),"default_color",Color("#ffffff"),0.25)
		be_selected=0

func setup_with_midi(midi:MidiData, index:int):
	set_meta("status",midi.status)
	set_meta("trialCount",midi.trial_count)
	set_meta("downloadCount",midi.download_count)
	set_meta("loveCount",midi.love_count)
	set_meta("upCount",midi.up_count)

	set_meta("name",midi.name)
	set_meta("desc", midi.description)
	set_meta("id",midi.id)
	set_meta("artistName",midi.artist_name)
	set_meta("hash", midi.file_hash)
	set_meta("index", index)
	if midi.album_data:
		set_meta("album",midi.album_data.name)
	if midi.song_data:
		set_meta("song",midi.song_data.name)

	get_node("MC/MC/status").text=midi.status
	get_node("MC/VBox/MidiName").text=midi.name
	get_node("MC/VBox/Author").text=midi.artist_name
