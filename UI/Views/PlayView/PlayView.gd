extends Control

# 音符显示区
@onready var flow_area: Panel = $FlowArea

@onready var background: TextureRect = $Background
@onready var menu_btn: TextureButton = $BackBtn
@onready var progress_bar: ProgressBar = $TopProgressBar

# 中间
@onready var combo: Label = $Combo/count
@onready var score: Label = $Score/count
@onready var score_add: Label = $Score/add
# 显示perfect的那个部分
@onready var center: VBoxContainer = $Center
@onready var center_text: Label = $Center/type
@onready var early_text: Label = $Center/up
@onready var late_text: Label = $Center/down

# 底部
@onready var pp_text: Label = $LeftBottom
@onready var accuracy_text: Label = $RightBottom

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

var current_midi: MidiData = null

@onready var ani: AnimationManager = AnimationManager.instance
@onready var playback_mgr: MidiPlaybackManager = MidiPlaybackManager.instance

var is_midi_playing: bool = false
var midi_start_time: float = 0.0

func _ready() -> void:

	EventBus.instance.start_game_with.connect(_prepare_game)
	UIStateManager.instance.state_changed.connect(_on_state_changed)

	progress_bar.value_changed.connect(_on_top_progress_bar_value_changed)

	flow_area.note_judged.connect(_on_note_judged)
	menu_btn.pressed.connect(_show_or_hide_menu)
	continue_btn.pressed.connect(_show_or_hide_menu)
	retry_btn.pressed.connect(_on_retry_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	flow_area.parent_node = self
	
	# 初始化MIDI播放管理器
	if playback_mgr == null:
		push_error("MidiPlaybackManager not initialized!")
		return
	
	# 连接MIDI播放信号
	playback_mgr.midi_started.connect(_on_midi_started)
	playback_mgr.midi_stopped.connect(_on_midi_stopped)
	playback_mgr.midi_finished.connect(_on_midi_finished)

var current_time: float = 0
var max_time: float = 20

func _process(_delta: float) -> void:
	if score_wait_to_add > 0:
		var amount = 3 if score_wait_to_add > 3 else score_wait_to_add
		score.text = str(int(score.text) + amount)
		score_wait_to_add -= amount

	if not is_pause:
		# 如果正在播放MIDI，使用MIDI播放管理器的时间
		current_time = playback_mgr.get_position_ms()
		progress_bar.value = current_time

func _on_state_changed(_oldState: UIStateManager.UIState, state: UIStateManager.UIState) -> void:
	var enable:bool = state == UIStateManager.UIState.PLAY_VIEW
	set_process(enable)
	set_process_input(enable)
	
	# 离开播放视图时停止MIDI播放
	if _oldState == UIStateManager.UIState.PLAY_VIEW and state != UIStateManager.UIState.PLAY_VIEW:
		if is_midi_playing and playback_mgr:
			playback_mgr.stop()
			is_midi_playing = false
	
	if enable:
		print("Node: %s , ProcessMode: %s" % [self.name, enable])

var is_pause: bool = false
func _show_or_hide_menu():
	song_info.visible = false
	is_pause = not is_pause
	
	# 暂停时停止MIDI播放，继续时恢复
	if is_midi_playing and playback_mgr:
		if is_pause:
			playback_mgr.pause()
		else:
			playback_mgr.resume()
	
	if is_pause:
		ani.animate_fade_in(menu, 0.2, "_show_menu")
		ani.animate_fade_in(center_bg, 0.2, "_show_bg")
	else:
		ani.animate_fade_out(menu, 0.2, "_show_menu")
		ani.animate_fade_out(center_bg, 0.2, "_show_bg")

func _prepare_game(midi:MidiData) -> void:
	current_midi = midi

	menu.visible = false
	song_info.visible = true
	center_bg.visible = true
	
	# 获取封面
	var cover_texture = FileSystemManager.instance.get_cover_by_midiData(midi)
	if cover_texture:
		cover.texture = cover_texture
	
	# 设置歌曲信息
	album.text = midi.artist_name
	song.text = midi.song_data.name
	# artist.text = midi.song_data.artist_name # 没找着歌手在哪
	midi_name.text = midi.name
	midi_author.text = midi.artist_name
	
	# 重置版面
	flow_area.clear_flow_area()

	# 初始化数据
	_init_data_display()
	
	# 加载MIDI并转换为FlowArea音符
	_load_and_convert_midi_notes(midi)
	playback_mgr.pause()
	
	# 等待3秒显示准备界面
	await get_tree().create_timer(3).timeout
	await AnimationManager.instance.animate_fade_out(center_bg, 1).finished
	
	# 开始播放MIDI
	playback_mgr.resume()
	# _start_midi_playback()

## 加载并转换MIDI音符为FlowArea格式
func _load_and_convert_midi_notes(midi_data: MidiData) -> void:
	if playback_mgr == null:
		push_error("MidiPlaybackManager not available!")
		return

	# 加载MIDI
	if not playback_mgr.load_midi(midi_data):
		push_error("Failed to load MIDI for gameplay")
		return

	# 获取手动控制的音符（玩家需要演奏的部分）
	var classification = playback_mgr.classify_notes(
		midi_data.parsed_notes, 
		[0, 1, 2]  # 假设前3个轨道是手动控制的，可以根据需要调整
	)

	var manual_notes = classification["manual_control_notes"]
	if manual_notes.is_empty():
		push_warning("No manual control notes found. Using all notes instead.")
		manual_notes = midi_data.parsed_notes

	# 设置进度条最大值
	max_time = midi_data.duration_ms
	progress_bar.max_value = max_time
	
	# 转换音符格式
	flow_area.notes_list = _convert_midi_to_notes(manual_notes, midi_data)
	flow_area.note_idx = 0  # 重置音符索引
	
	print("[PlayView] Converted %d MIDI notes to FlowArea format" % flow_area.notes_list.size())

## 将MIDI音符转换为FlowArea需要的格式
func _convert_midi_to_notes(midi_notes: Array, _midi_data: MidiData) -> Array[FlowArea.Note]:
	var flow_notes: Array[FlowArea.Note]  = []

	for note in midi_notes:
		if note is MidiParser.Note and note.event != null:
			var evt = note.event
			
			# 将tick转换为毫秒
			var start_tick = evt.start_time
			var duration_tick = evt.duration
			
			# 使用MidiPlaybackManager的tick_to_ms方法进行精确转换
			var start_ms = playback_mgr.tick_to_ms(start_tick)
			var duration_ms = playback_mgr.tick_to_ms(start_tick + duration_tick) - start_ms
			
			# 计算到达时间（音符前端到达判定线的时间）
			# 这里可以根据游戏难度调整提前量，这里使用200ms提前量
			var arrival_time = start_ms + 200  # 音符在start_time + 200ms时到达判定线
			
			# 确定车道（lane） - 将MIDI音高映射到12个车道
			var lane = evt.pitch % flow_area.lane_count

			var block_type = FlowArea.NoteType.Block
			if duration_ms < 50:
				block_type = FlowArea.NoteType.Slide
			if duration_ms > 1000:
				block_type = FlowArea.NoteType.Long
			
			# 创建FlowArea的Note对象
			var flow_note = FlowArea.Note.new(
				block_type,
				start_ms,          # 开始时间
				arrival_time,      # 到达时间
				duration_ms,       # 持续时间
				lane               # 车道
			)
			
			flow_notes.append(flow_note)
	
	# 按开始时间排序
	flow_notes.sort_custom(func(a, b): return a.start_time < b.start_time)
	
	return flow_notes

## 开始MIDI播放
func _start_midi_playback() -> void:
	if playback_mgr == null:
		push_error("Cannot start MIDI playback: manager not available")
		return
	
	# 重置播放位置
	current_time = 0
	progress_bar.value = 0
	flow_area.note_idx = 0
	
	# 开始播放
	playback_mgr.play()
	midi_start_time = Time.get_ticks_msec()
	is_midi_playing = true
	
	print("[PlayView] Started MIDI playback")

## MIDI播放开始回调
func _on_midi_started() -> void:
	print("[PlayView] MIDI playback started")
	is_midi_playing = true

## MIDI播放停止回调
func _on_midi_stopped() -> void:
	print("[PlayView] MIDI playback stopped")
	is_midi_playing = false

## MIDI播放完成回调
func _on_midi_finished() -> void:
	print("[PlayView] MIDI playback finished")
	is_midi_playing = false
	
	# 游戏结束，可以在这里调用结束界面
	_on_game_finished()

## 游戏结束回调（可以扩展为显示结算界面）
func _on_game_finished() -> void:
	print("[PlayView] Game finished!")
	
	# 计算分数和准确率
	var total_notes = flow_area.notes_list.size()
	var passed_notes = flow_area.note_idx
	var accuracy = float(passed_notes) / total_notes * 100 if total_notes > 0 else 0
	
	# 显示结束信息（这里可以扩展为完整的结算界面）
	center_text.text = "完成!"
	center_text.add_theme_color_override("font_color", Color.GREEN)
	center.modulate.a = 1
	
	# 可以在这里触发结算界面
	# EventBus.instance.emit_signal("game_finished", score.text, accuracy, combo.text)

## 重试游戏
func _on_retry_pressed() -> void:
	# _show_or_hide_menu()  # 关闭菜单
	
	# # 重置游戏状态
	# _init_data_display()
	# current_time = 0
	# progress_bar.value = 0
	# flow_area.note_idx = 0
	
	# # 重新开始MIDI播放
	# if current_midi:
	# 	_start_midi_playback()
	_prepare_game(current_midi)

## 退出游戏
func _on_quit_pressed() -> void:
	# 停止MIDI播放
	if is_midi_playing and playback_mgr:
		playback_mgr.stop()
		is_midi_playing = false
	_init_data_display()
	flow_area.clear_flow_area()
	
	# 返回主菜单或上一级界面
	UIStateManager.instance.change_state(UIStateManager.UIState.MIDI_VIEW)

# 初始化分数等内容的显示
func _init_data_display():
	score.text = "0"
	combo.text = "0"
	score_wait_to_add = 0
	score_add.text = "+0"

const color_map = {
	"Perfect": Color.PURPLE,
	"Great": Color.ORANGE,
	"Good": Color.DARK_OLIVE_GREEN,
	"Bad": Color.ROYAL_BLUE,
	"Miss": Color.RED
}

func _on_note_judged(result: String, offset: String):
	center_text.text = result
	var cl = color_map[result]
	var score_add_amount = 0
	match result:
		"Perfect":
			score_add_amount = 150
		"Great":
			score_add_amount = 100
		"Good":
			score_add_amount = 50
	center_text.add_theme_color_override("font_color", cl)

	# combo显示
	if result in ["Bad", "Miss"]:
		combo.text = "0"
	else:
		combo.text = str(int(combo.text)+1)

	# 增加分数
	_set_score_add_amount(score_add_amount)

	# 设置进度条颜色
	_set_progress_bar_color(color_map[result])

	# 显示偏移
	early_text.self_modulate.a = 0
	late_text.self_modulate.a = 0
	if result != "Miss":
		if offset[0] == "+":
			early_text.text = offset
			early_text.self_modulate.a = 1
		else:
			late_text.text = offset
			late_text.self_modulate.a = 1

	# 动画
	center.rotation_degrees = (randf()-0.5) * 5
	var tween: Tween = ani._create_tween("center pluse")
	tween.set_parallel(true)
	center.scale = Vector2.ONE * 1.1
	tween.tween_property(center, "scale", Vector2.ONE, 0.1)
	tween.tween_property(center, "rotation_degrees", 0, 0.1)

	var t = ani._create_tween("center fade out")
	center.modulate.a = 1
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(center, "modulate:a", 0.0, 2)

var score_wait_to_add = 0
func _set_score_add_amount(amount: int):
	if amount == 0:
		return
	score_wait_to_add += amount
	score_add.text = "+%d" % amount

	score_add.modulate.a = 1
	var tween = ani._create_tween("score_add_out")
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(score_add, "modulate:a", 0.0, 2)
	ani.animate_pulse(score_add, 1, 1.1, 0.1, "score_pluse")

# 进度条颜色填充回调
var current_color: Color = color_map["Miss"]
var current_rect: ColorRect = null
func _on_top_progress_bar_value_changed(value: float):
	var window_rect: Rect2 = get_viewport().get_visible_rect()
	var pos_r: int = int(window_rect.position.x + window_rect.size.x)
	pos_r *= value / progress_bar.max_value
	if current_rect:
		current_rect.size.x = pos_r - current_rect.global_position.x
	else:
		current_rect = ColorRect.new()
		current_rect.color = current_color
		current_rect.size = progress_bar.size
		current_rect.size.x = pos_r
		var pos = Vector2.ZERO
		if progress_bar.get_child_count() > 0:
			pos = Vector2(pos_r, 0)
		current_rect.global_position = pos

		progress_bar.add_child(current_rect)

func _set_progress_bar_color(cl: Color):
	if cl == current_color:
		return
	if current_rect and current_rect.size.x < 10:
		current_rect.color = cl
	else:
		current_rect = null
	current_color = cl
