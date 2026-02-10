extends Control

# 音符显示区
@onready var flow_area: Panel = $FlowArea

@onready var background: TextureRect = $Background
@onready var menu_btn: TextureButton = $Layer/BackBtn
@onready var progress_bar: ProgressBar = $Layer/TopProgressBar

# 中间
@onready var combo: Label = $Layer/Combo/count
@onready var score: Label = $Layer/Score/count
@onready var score_add: Label = $Layer/Score/add
# 显示perfect的那个部分
@onready var center: VBoxContainer = $Layer/Center
@onready var center_text: Label = $Layer/Center/type
@onready var early_text: Label = $Layer/Center/up
@onready var late_text: Label = $Layer/Center/down

# 底部
@onready var pp_text: Label = $Layer/LeftBottom
@onready var accuracy_text: Label = $Layer/RightBottom

# 菜单及歌曲信息的背景遮罩
@onready var center_bg:ColorRect = $Layer/CenterBackGround
# 菜单
@onready var menu: Control = $Layer/CenterBackGround/Menu
@onready var retry_btn: Button = $Layer/CenterBackGround/Menu/retry
@onready var continue_btn: Button = $Layer/CenterBackGround/Menu/continue
@onready var quit_btn: Button = $Layer/CenterBackGround/Menu/quit
# 歌曲信息
@onready var song_info: Control = $Layer/CenterBackGround/SongInfo
@onready var cover: TextureRect = $Layer/CenterBackGround/SongInfo/PanelContainer/TextureRect
# 原曲
@onready var album: Label = $Layer/CenterBackGround/SongInfo/GridContainer/album
@onready var song: Label = $Layer/CenterBackGround/SongInfo/GridContainer/song
@onready var artist: Label = $Layer/CenterBackGround/SongInfo/GridContainer/artist
# midi
@onready var midi_name: Label = $Layer/CenterBackGround/SongInfo/GridContainer/midiName
@onready var midi_author: Label = $Layer/CenterBackGround/SongInfo/GridContainer/midiAuthor
@onready var midi_duration: Label = $Layer/CenterBackGround/SongInfo/GridContainer/midiDuration
# 难度
@onready var difficulty: Label = $Layer/CenterBackGround/SongInfo/GridContainer/difficulty

# 环境
@onready var env: WorldEnvironment = $FlowArea/SVP/WorldEnvironment

# 轨道光效及键位显示
@onready var lane_area: Control = $Lane

var glow: Environment = null

var current_midi: MidiData = null

@onready var ani: AnimationManager = AnimationManager.instance
@onready var playback_mgr: MidiPlaybackManager = MidiPlaybackManager.instance

var is_midi_playing: bool = false
var midi_start_time: float = 0.0

########## 配置参数 #############
var lane_count: int = 12
var lane_padding: int = 200 # 左右填充安全区
var keyboard_mode: bool = true
var key_map: Array[Key] = [KEY_Q, KEY_W, KEY_D, KEY_J, KEY_I, KEY_O]

var judge_line_offset_y: int = 250

# 光柱特效不透明度
var beam_alpha: float = 0.5

#################################

func _ready() -> void:

	EventBus.instance.start_game_with.connect(_prepare_game)
	UIStateManager.instance.state_changed.connect(_on_state_changed)
	_on_state_changed(UIStateManager.instance.UIState.NONE, UIStateManager.instance.current_state)

	progress_bar.value_changed.connect(_on_top_progress_bar_value_changed)

	flow_area.note_judged.connect(_on_note_judged)
	flow_area.long_holding.connect(_holding_bonus)
	flow_area.parent_node = self

	menu_btn.pressed.connect(show_or_hide_menu)
	continue_btn.pressed.connect(show_or_hide_menu)
	retry_btn.pressed.connect(func ():
		_prepare_game(current_midi)
	)
	quit_btn.pressed.connect(_on_quit_pressed)

	
	# 初始化MIDI播放管理器
	if playback_mgr == null:
		push_error("MidiPlaybackManager not initialized!")
		return
	
	# 连接MIDI播放信号
	playback_mgr.midi_started.connect(_on_midi_started)
	playback_mgr.midi_stopped.connect(_on_midi_stopped)
	playback_mgr.midi_finished.connect(_on_midi_finished)

	glow = env.environment
	env.environment = null

var current_time: float = 0
var max_time: float = 20

func _process(_delta: float) -> void:
	if score_wait_to_add > 0:
		var amount = int(sqrt(score_wait_to_add))
		score.text = str(int(score.text) + amount)
		score_wait_to_add -= amount

	if not is_pause:
		# 如果正在播放MIDI，使用MIDI播放管理器的时间
		current_time = playback_mgr.get_position_ms()
		
		progress_bar.value = current_time
	
		if not env.environment:
			env.environment = glow
	else:
		if env.environment != null:
			env.environment = null

func get_lane_count() -> int:
	return lane_count if not keyboard_mode else key_map.size()

func _on_state_changed(_oldState: UIStateManager.UIState, state: UIStateManager.UIState) -> void:
	var enable:bool = state == UIStateManager.UIState.PLAY_VIEW
	set_process(enable)
	set_process_input(enable)
	get_node("Layer").visible = enable
	
	# 离开播放视图时停止MIDI播放
	if _oldState == UIStateManager.UIState.PLAY_VIEW and state != UIStateManager.UIState.PLAY_VIEW:
		if is_midi_playing and playback_mgr:
			playback_mgr.stop()
			is_midi_playing = false
	
	if enable:
		print("Node: %s , ProcessMode: %s" % [self.name, enable])

var is_pause: bool = false
func show_or_hide_menu():
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

	# 获取封面
	var cover_texture = FileSystemManager.instance.get_cover_by_midiData(midi)
	if cover_texture:
		cover.texture = cover_texture

	# 加载MIDI并转换为FlowArea音符
	_load_and_convert_midi_notes(midi)
	playback_mgr.seek(0)
	playback_mgr.pause()
	
	# 读取并设置音频同步阈值
	var setting_view = get_node_or_null("/root/Main/SettingView")
	if setting_view and setting_view.has_method("get_setting_value"):
		var sync_threshold = setting_view.get_setting_value("audio_sync_threshold")
		if sync_threshold != null:
			playback_mgr.set_sync_threshold(float(sync_threshold))
			print("[PlayView] Audio sync threshold set to %.0f ms" % float(sync_threshold))
	
	# 初始化数据
	_init_display()
	
	lane_area.init_beam(get_lane_count(), flow_area.note_visual_width, judge_line_offset_y, lane_padding)
	lane_area.set_beam_alpha(beam_alpha)
	if keyboard_mode:
		lane_area.init_key_display(key_map)
	
	# 设置进度条最大值
	max_time = midi.duration_ms
	progress_bar.max_value = max_time

	# 等待3秒显示准备界面
	await get_tree().create_timer(3).timeout
	is_pause = false # 结束暂停会启用辉光
	await AnimationManager.instance.animate_fade_out(center_bg, 1).finished
	
	# 开始播放MIDI
	playback_mgr.resume()

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

	# 转换音符格式
	flow_area.init_flow_area(_convert_midi_to_notes(manual_notes, midi_data))
	
	print("[PlayView] Converted %d MIDI notes to FlowArea format" % flow_area.notes_list.size())

## 将MIDI音符转换为FlowArea需要的格式
func _convert_midi_to_notes(midi_notes: Array, _midi_data: MidiData) -> Array[FlowArea.Note]:
	var flow_notes: Array[FlowArea.Note]  = []
	var lc = get_lane_count()

	for note in midi_notes:
		if note is MidiParser.Note and note.event != null:
			var evt = note.event
			
			# 将tick转换为毫秒
			var start_tick = evt.start_time
			var duration_tick = evt.duration
			
			# 使用MidiPlaybackManager的tick_to_ms方法进行精确转换
			var start_ms = playback_mgr.tick_to_ms(start_tick)
			var duration_ms = playback_mgr.tick_to_ms(start_tick + duration_tick) - start_ms
			
			# 确定车道（lane） - 将MIDI音高映射到12个车道
			var lane = evt.pitch % lc

			var block_type = FlowArea.NoteType.Block
			if duration_ms < 500:
				block_type = FlowArea.NoteType.Slide
			if duration_ms > 1000:
				block_type = FlowArea.NoteType.Long
			
			# 创建FlowArea的Note对象
			var flow_note = FlowArea.Note.new(
				block_type,
				start_ms,          # 开始时间
				duration_ms,       # 持续时间
				lane               # 车道
			)
			
			flow_notes.append(flow_note)
	
	# 按开始时间排序
	flow_notes.sort_custom(func(a, b): return a.start_time < b.start_time)
	
	return flow_notes

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
	var _accuracy = float(passed_notes) / total_notes * 100 if total_notes > 0 else 0  # 预留变量，用于未来的结算界面
	
	# 显示结束信息（这里可以扩展为完整的结算界面）
	center_text.text = "完成!"
	center_text.add_theme_color_override("font_color", Color.GREEN)
	center.modulate.a = 1
	
	# 可以在这里触发结算界面
	# EventBus.instance.emit_signal("game_finished", score.text, accuracy, combo.text)

## 退出游戏
func _on_quit_pressed() -> void:
	# 停止MIDI播放
	if is_midi_playing and playback_mgr:
		playback_mgr.stop()
		is_midi_playing = false
	_init_display()
	flow_area.clear_flow_area()
	
	# 返回主菜单或上一级界面
	UIStateManager.instance.go_back()

# 初始化分数等内容的显示
func _init_display():
	score.text = "0"
	combo.text = "0"
	score_wait_to_add = 0
	score_add.text = "+0"

	# 设置歌曲信息
	album.text = current_midi.artist_name
	song.text = current_midi.song_data.name
	# artist.text = current_midi.song_data.artist_name # 没找着歌手在哪
	midi_name.text = current_midi.name
	midi_author.text = current_midi.artist_name
	
	menu.visible = false
	song_info.visible = true
	center_bg.visible = true
	is_pause = true

	# 重置进度条
	_current_rect = null
	_last_rect = null
	for i in progress_bar.get_children():
		i.queue_free()

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
	_set_progress_bar_color(cl)

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

func _holding_bonus():
	var cl = color_map["Perfect"]
	center_text.add_theme_color_override("font_color", cl)
	center_text.text = "Perfect"
	combo.text = str(int(combo.text)+1)

	_set_progress_bar_color(cl)

	# 增加分数
	_set_score_add_amount(50)

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
var _current_rect: ColorRect = null
var _last_rect: ColorRect = null
func _on_top_progress_bar_value_changed(value: float):
	var anchor_l = 0.0 if not _last_rect else _last_rect.anchor_right
	if not _current_rect:
		_current_rect = ColorRect.new()

		_current_rect.anchor_left = anchor_l if anchor_l < 0.002 else anchor_l - 0.001
		_current_rect.color = color_map["Miss"] if not _last_rect else _last_rect.color
		_current_rect.size.y = progress_bar.size.y

		_last_rect = _current_rect
		progress_bar.add_child(_current_rect)
	
	_current_rect.anchor_right = value / progress_bar.max_value

func _set_progress_bar_color(cl: Color):
	if cl == _current_rect.color:
		return

	if not _current_rect or _current_rect.size.x > 20:
		_current_rect = null
		_on_top_progress_bar_value_changed(progress_bar.value)
		return

	_current_rect.color = cl
