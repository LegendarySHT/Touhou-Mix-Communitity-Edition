extends Control

# 音符显示区
@onready var flow_area: Panel = $FlowArea

@onready var background: TextureRect = $Background
@onready var dim_overlay: ColorRect = $DimOverlay
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

# 轨道光效及键位显示
@onready var lane_area: Control = $Lane

# 背景配置走 ThemeManager（theme.ini [backgrounds] 段），不再从 config.ini 读取
const BG_BLUR_SHADER_PATH := "res://UI/Views/PlayView/Shaders/BackgroundBlur.gdshader"
const BG_FLASH_SHADER_PATH := "res://UI/Views/PlayView/Shaders/BackgroundFlash.gdshader"

# auto标识
@onready var auto_label: Label = $AutoLabel
@onready var debug_info_label: Label = $Layer/DebugInfo

var current_midi: MidiData = null
## play_result 仅作为传递给 ScoreView 的展示数据容器
var play_result: ScoreView.ScoreData = null

@onready var ani: AnimationManager = AniMGR
@onready var playback_mgr: MidiPlaybackManager = MidiPlaybackManager.instance
@onready var key_sequence_mgr: KeySequenceManager = KeySequenceManager.instance
@onready var score_calc: ScoreCalculator = ScoreCalculator.instance

var midi_start_time: float = 0.0

## 本次游玩开始时间（毫秒，墙钟），用于计算游玩时长统计
var _play_start_time: int = 0

## 演奏模式标志：true = 演奏模式（响应键盘触发音符），false = 听奏模式（MIDI只在背景播放）
var play_mode: bool = true

## 生成的游戏键序列（演奏模式使用）
var game_sequences: Array[KeySequenceManager.GameSequence] = []

var _is_finishing_game: bool = false

## position stall 检测：当 loop=false 时 MIDI 播放结束后 position 被 clamp 到 midiFile.Length
## 若 duration_ms 与 midiFile.Length 不一致，进度条可能永远无法达到 max_value
## 通过检测 position 停止增长来触发游戏结束
var _last_playback_position: float = -1.0
var _position_stall_frames: int = 0
const _PLAYBACK_STALL_THRESHOLD := 30  # 30帧 ≈ 0.5秒

var _blur_bake_viewport: SubViewport = null
var _blur_bake_texture_rect: TextureRect = null
var _blur_bake_id: int = 0

########## 配置参数 #############
# 有一部分配置参数在flow_area里面
var lane_count: int = 12
var lane_padding: int = 100 # 左右填充安全区
var keyboard_mode: bool = false
var key_map: Array[Key] = []
var key_display_names: Array[String] = []

var judge_line_offset_y: int = 250

# 光柱特效不透明度
var beam_alpha: float = 0.5
var flash_color: Color = Color.WHITE
var _flash_tween: Tween = null
# 交替轨道颜色（仅键盘模式生效，开启时覆盖音符颜色及轨道光效颜色）
var keyboard_alt_color: bool = true
var keyboard_alt_color_count: int = 2
var keyboard_alt_colors: Array[Color] = [Color.RED, Color.BLUE] # 交替颜色序列，颜色数量可大于轨道数一半（多余的不会被用到）
# 左右间距（像素；键盘模式且键位数为偶数时在中间额外加此间距，分隔左右手）
var keyboard_mode_gap: int = 0
# 轨道分隔线（仅键盘模式生效，相邻轨道之间与两端生成竖线）
var keyboard_lane_separator: bool = false

var show_debug_info: bool = false
var debug_info_refresh_interval: float = 0.5
var debug_info_elapsed: float = 0.0

#################################

func _ready() -> void:
	# 从配置加载键盘和轨道相关的参数
	_load_lane_parameters()
	_load_debug_display_setting()
	_load_note_skin_setting()
	
	# 窗口大小变化
	get_window().size_changed.connect(_init_lane_display)
	if not get_window().focus_exited.is_connected(_on_window_focus_exited):
		get_window().focus_exited.connect(_on_window_focus_exited)

	EvtBus.start_game_with.connect(_prepare_game)
	UiStatMGR.state_changed.connect(_on_state_changed)
	_on_state_changed(UiStatMGR.UIState.NONE, UiStatMGR.current_state)

	flow_area.note_judged.connect(_on_note_judged)
	flow_area.long_holding.connect(_on_long_holding)
	flow_area.parent_node = self

	retry_btn.pressed.connect(func ():
		_prepare_game()
	)
	
	# 初始化MIDI播放管理器
	if playback_mgr == null:
		push_error("MidiPlaybackManager not initialized!")
		return
	
	# 从配置加载演奏模式设置
	_load_play_mode_setting()
	
	# 连接配置变更信号
	if not EvtBus.config_changed.is_connected(_on_lane_config_changed):
		EvtBus.config_changed.connect(_on_lane_config_changed)
	if not EvtBus.config_changed.is_connected(_on_config_changed):
		EvtBus.config_changed.connect(_on_config_changed)
	_set_debug_overlay_visible(show_debug_info)

	if ThemeMGR:
		ThemeMGR.register_theme_applier(self)
		apply_theme()

## 应用主题色（由 ThemeManager 广播调用 + _ready 首次自调）
func apply_theme() -> void:
	if not menu or not menu.theme:
		return
	var btn_theme := menu.theme
	var p := ThemeMGR.get_color("primary")
	ThemeMGR._theme_button_set_color(btn_theme, p)
	# 基础按钮阴影
	var normal := btn_theme.get_stylebox("normal", "Button")
	if normal is StyleBoxFlat:
		normal.shadow_color = Color(p.r, p.g, p.b, 0.3)
		normal.shadow_size = 8
	var hover := btn_theme.get_stylebox("hover", "Button")
	if hover is StyleBoxFlat:
		var hc := p.lightened(0.15)
		hover.shadow_color = Color(hc.r, hc.g, hc.b, 0.35)
		hover.shadow_size = 12
	# Continue 按钮：比其他按钮更亮
	if continue_btn:
		var sb_n := continue_btn.get_theme_stylebox("normal")
		if sb_n is StyleBoxFlat:
			sb_n.bg_color = p.lightened(0.15)
		var sb_h := continue_btn.get_theme_stylebox("hover")
		if sb_h is StyleBoxFlat:
			sb_h.bg_color = p.lightened(0.30)
	# Quit 按钮：pressed 状态用 danger 色
	if quit_btn:
		var sb_p := quit_btn.get_theme_stylebox("pressed")
		if sb_p is StyleBoxFlat:
			sb_p.bg_color = ThemeMGR.DANGER_COLOR

func _exit_tree() -> void:
	if ThemeMGR:
		ThemeMGR.unregister_theme_applier(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_auto_pause_on_background("app_notification_%d" % what)

var current_time: float = 0
var max_time: float = 20

# 视觉时钟（毫秒）：墙钟 delta 累加，平滑驱动音符渲染位置；
# 判定仍走 current_time（音频钟），保证判定与听到的声音对齐。
var _visual_time_ms: float = 0.0
# 视觉钟软锚定：每帧纠正与音频钟偏差的 2%，上限 ±0.5ms/帧（≈60ms/s 收敛，肉眼不可见）
const _VISUAL_ANCHOR_RATE := 0.02
const _VISUAL_ANCHOR_MAX_MS := 0.5
# 需要硬锚定（开始播放/暂停恢复时对齐音频钟，避免大跳）
var _visual_time_needs_anchor: bool = true

func _process(delta: float) -> void:
	if score_wait_to_add > 0:
		var amount = int(sqrt(score_wait_to_add))
		score.text = str(int(score.text) + amount)
		score_wait_to_add -= amount

	if show_debug_info and debug_info_label and debug_info_label.visible:
		debug_info_elapsed += delta
		if debug_info_elapsed >= debug_info_refresh_interval:
			debug_info_elapsed = 0.0
			_update_debug_overlay()

	if not is_pause:
		if _is_finishing_game:
			# 游戏结束阶段：用delta模拟时间推进，让剩余音符自然下落
			current_time += delta * 1000.0
			_visual_time_ms = current_time
			flow_area.set_current_time(current_time, current_time)
		else:
			# 如果正在播放MIDI，使用MIDI播放管理器的时间（判定时钟）
			current_time = playback_mgr.get_position_ms()
			progress_bar.value = current_time
			# 视觉时钟：墙钟累加 + 软锚定音频钟（渲染平滑，判定仍用音频钟）
			if _visual_time_needs_anchor:
				_visual_time_ms = current_time
				_visual_time_needs_anchor = false
			else:
				_visual_time_ms += delta * 1000.0
				var drift: float = current_time - _visual_time_ms
				_visual_time_ms += clampf(drift * _VISUAL_ANCHOR_RATE, -_VISUAL_ANCHOR_MAX_MS, _VISUAL_ANCHOR_MAX_MS)
			# 【方案C】同步双时钟到FlowArea：判定用音频钟，渲染用平滑视觉钟
			flow_area.set_current_time(current_time, _visual_time_ms)

			# 检测MIDI播放结束：position连续多帧不增长说明已被clamp到midiFile.Length
			# 当 duration_ms 与 midiFile.Length 不一致时，进度条可能永远无法达到 max_value
			if current_time > 0 and abs(current_time - _last_playback_position) < 0.5:
				_position_stall_frames += 1
				if _position_stall_frames >= _PLAYBACK_STALL_THRESHOLD:
					_position_stall_frames = 0
					print("[PlayView] Playback position stalled at %.1fms, triggering game finished" % current_time)
					_on_game_finished()
			else:
				_position_stall_frames = 0
			_last_playback_position = current_time
	
func get_lane_count() -> int:
	return lane_count if not keyboard_mode else key_map.size()

## 获取轨道交替颜色（仅键盘模式 + 交替轨道颜色开启时返回，否则返回 null）
## 交替方式：两端对称，colors[lane_idx % int(轨道数/2) % colors.size()]
## 返回 null 时调用方回退到皮肤解析色
func get_lane_color(lane_idx: int):
	if lane_idx == -1 or not keyboard_mode or not keyboard_alt_color:
		return null
	if keyboard_alt_colors.is_empty():
		return null
	@warning_ignore("integer_division")
	var lc = int(get_lane_count() / 2)
	if lc <= 0:
		return null
	return keyboard_alt_colors[lane_idx % lc % keyboard_alt_colors.size()]

## 解析交替颜色序列字符串（逗号分隔的 #RRGGBB / RRGGBB），空串或无效项跳过
func _parse_alt_colors(colors_str: String) -> Array[Color]:
	var result: Array[Color] = []
	for part in colors_str.split(",", false):
		var p := part.strip_edges()
		if p.is_empty() or not Color.html_is_valid(p):
			continue
		result.append(Color.from_string(p, Color.WHITE))
	return result

## 中间间距：键盘模式且键位数为偶数时返回设置的间距，否则 0
## 用于把左右手轨道分隔更远（LaneEffect 布局与触摸轨道估算共用）
func get_mid_lane_gap() -> int:
	if not keyboard_mode:
		return 0
	if get_lane_count() % 2 != 0:
		return 0
	return keyboard_mode_gap

## 轨道分隔线是否显示（键盘模式开启且选项开启；LaneEffect.init_beam 据此生成竖线）
func get_lane_separator_enabled() -> bool:
	return keyboard_mode and keyboard_lane_separator

func _on_state_changed(_oldState: UIStateManager.UIState, state: UIStateManager.UIState) -> void:
	var enable:bool = state == UIStateManager.UIState.PLAY_VIEW
	set_process(enable)
	get_node("Layer").visible = enable

	# 离开播放视图时统一清理所有资源（无论从哪条路径退出都走这里）
	if _oldState == UIStateManager.UIState.PLAY_VIEW and state != UIStateManager.UIState.PLAY_VIEW:
		if playback_mgr:
			playback_mgr.stop()
			playback_mgr.clear_manual_control_notes()
		flow_area.clear_flow_area()
		game_sequences.clear()
		_teardown_blur_bake_viewport()
		# 不 unload_midi / 不 clear_sequences / 不 clear_parsed_notes：
		# 同一 MIDI 在 MidiView/TrackView/PlayView 间切换时复用解析数据与 GameSequence 缓存，
		# 避免反复重解析/重生成。离开 MidiView 或切换 MidiList 项时才彻底清理
		# 重置状态，供下次 _prepare_game 使用
		_is_finishing_game = false
		is_pause = true

	if enable:
		print("Node: %s , ProcessMode: %s" % [self.name, enable])
		# 从设置界面切回时，背景配置可能已变更，重新应用 play 背景（含 cover 模式烘焙）
		if _oldState == UIStateManager.UIState.SETTINGS_VIEW and current_midi != null:
			_apply_play_background()

## 新增：配置变更回调
func _on_config_changed(key: String, section: String, value: Variant) -> void:
	if section == "Appearance" and key == "background_dim_color":
		_apply_background_dim()
		return

	if section == "Appearance" and key == "background_image_flash_color":
		var color_str = str(value)
		if color_str.is_valid_html_color():
			flash_color = Color(color_str)
		return

	if section == "Appearance" and key in ["note_glow_intensity", "note_glow_size"]:
		var gi = ConfigManager.instance.get_float("Appearance", "note_glow_intensity", 0.5)
		var gs = ConfigManager.instance.get_float("Appearance", "note_glow_size", 5.0)
		if flow_area and flow_area.has_method("set_glow_params"):
			flow_area.set_glow_params(gi, gs)
		return
	
	if section == "Appearance" and key == "block_skin_preset":
		var skin_name = str(value)
		if flow_area and flow_area.has_method("load_note_skin"):
			flow_area.load_note_skin(skin_name)
		return

	if section == "General" and key == "display_debug_info":
		show_debug_info = int(value) == 1
		_set_debug_overlay_visible(show_debug_info)
		return

	if section == "Playback" and key == "auto_mode":
		var auto_enabled = int(value) == 1
		if flow_area:
			flow_area.auto_mode = auto_enabled
		auto_label.visible = auto_enabled
		GLogger.info("PlayView auto mode changed: %s" % ("ON" if auto_enabled else "OFF"), "PlayView")
		return

	if section == "Playback" and key == "performing_mode":
		var new_mode = int(value) == 1

		# 只在值实际改变时处理
		if new_mode == play_mode:
			return

		play_mode = new_mode
		
		if play_mode:
			# 演奏模式开启：重新应用手动控制notes标记
			if playback_mgr and game_sequences.size() > 0:
				var classification = key_sequence_mgr.get_last_notes_classification()
				var manual_control_notes = classification["manual_control_notes"]
				playback_mgr.set_manual_control_notes(manual_control_notes)
				GLogger.info("Performing mode ON: reapplied manual control notes (%d)" % manual_control_notes.size(), "PlayView")
		else:
			# 演奏模式关闭：清除手动控制notes标记，恢复全自动播放
			if playback_mgr:
				playback_mgr.clear_manual_control_notes()
				GLogger.info("Performing mode OFF: cleared manual control notes", "PlayView")

func _load_debug_display_setting() -> void:
	show_debug_info = ConfigManager.instance.get_int("General", "display_debug_info", 0) == 1


func _load_note_skin_setting() -> void:
	# 如果 FileSystemManager 还未完成资源扫描，等待扫描完成
	if FileSystemManager.instance and not FileSystemManager.instance.resources_scanned:
		print("[PlayView] Waiting for FileSystemManager to scan resources...")
		if not FileSystemManager.instance.resources_ready.is_connected(_on_skin_resources_ready):
			FileSystemManager.instance.resources_ready.connect(_on_skin_resources_ready)
		return
	
	_do_load_note_skin()

func _on_skin_resources_ready() -> void:
	_do_load_note_skin()

func _do_load_note_skin() -> void:
	# 从配置加载皮肤设置
	var skin_name = ConfigManager.instance.get_string("Appearance", "block_skin_preset", "旧版2 [内置]")

	# 应用皮肤
	if flow_area and flow_area.has_method("load_note_skin"):
		flow_area.load_note_skin(skin_name)
		print("[PlayView] Loaded note skin: %s" % skin_name)

## 根据当前皮肤的 random_color 配置生成随机颜色并推送到 FlowArea
## 仅在 custom_color 主开关 + 该类型 enable_color + random_color 均开启时生成
## 必须在 flow_area.init_flow_area() 之前调用，使对象池节点用新颜色重建
func _regenerate_random_note_colors() -> void:
	if not flow_area:
		return
	var skin_name = ConfigManager.instance.get_string("Appearance", "block_skin_preset", "旧版2 [内置]")
	var skin_config = SkinMGR.get_skin_config(skin_name)
	if skin_config.is_empty():
		return
	var custom_color_on := false
	if skin_config.has("general"):
		custom_color_on = bool(skin_config["general"].get("custom_color", false))
	if not custom_color_on:
		# 主开关关闭，清空随机颜色（_resolve_note_colors 会回退到 WHITE）
		flow_area._random_colors = {}
		return

	var random_colors: Dictionary = {}
	for key in ["short", "instant", "long"]:
		if not skin_config.has(key):
			continue
		var sec: Dictionary = skin_config[key]
		if bool(sec.get("enable_color", false)) and bool(sec.get("random_color", false)):
			# 强制饱和度 1.0：纯色相至少一个通道恒为 0，加色同色叠加不会发白，颜色也不淡
			# （饱和 <1 的粉彩色三个通道都 >0，同色光效叠加会往白里走）
			random_colors[key] = Color.from_hsv(randf(), 1.0, 1.0)
	flow_area._random_colors = random_colors
	print("[PlayView] Generated random note colors: %s" % str(random_colors.keys()))

func _set_debug_overlay_visible(_is_visible: bool) -> void:
	if debug_info_label == null:
		return

	debug_info_label.visible = _is_visible
	debug_info_elapsed = debug_info_refresh_interval
	if visible:
		_update_debug_overlay()

func _update_debug_overlay() -> void:
	if debug_info_label == null:
		return

	var fps = Engine.get_frames_per_second()
	var frame_ms = (1000.0 / max(1.0, float(fps)))
	var draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects_in_frame = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var memory_static_mb = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)
	var memory_static_max_mb = float(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / (1024.0 * 1024.0)

	debug_info_label.text = "FPS: %d (%.2f ms)\n渲染: DrawCalls %d | Objects %d\n内存: %.1f MB / 峰值 %.1f MB" % [
		fps,
		frame_ms,
		draw_calls,
		objects_in_frame,
		memory_static_mb,
		memory_static_max_mb
	]

var is_pause: bool = false:
	set(v):
		is_pause = v
		if playback_mgr:
			if is_pause:
				playback_mgr.pause()
			else:
				playback_mgr.resume()
				# 暂停期间音频钟冻结，恢复时硬锚定视觉钟，避免音符位置大跳
				_visual_time_needs_anchor = true

func show_or_hide_menu():
	song_info.visible = false
	if is_pause:
		is_pause = false
		ani.animate_fade_out(menu, 0.2, "_show_menu")
		ani.animate_fade_out(center_bg, 0.2, "_show_bg")
	else:
		_show_pause_menu()

func _show_pause_menu() -> void:
	song_info.visible = false
	is_pause = true
	ani.animate_fade_in(menu, 0.2, "_show_menu")
	ani.animate_fade_in(center_bg, 0.2, "_show_bg")

func _on_window_focus_exited() -> void:
	_auto_pause_on_background("window_focus_exited")

func _auto_pause_on_background(reason: String) -> void:
	if UiStatMGR.current_state != UIStateManager.UIState.PLAY_VIEW:
		return
	if playback_mgr and not playback_mgr.is_playing:
		return
	if is_pause:
		return

	_show_pause_menu()
	GLogger.info("Auto pause triggered by background event: %s" % reason, "PlayView")

func _prepare_game(midi:MidiData = current_midi) -> void:
	current_midi = midi
	play_result = ScoreView.ScoreData.new()
	_is_finishing_game = false
	_last_playback_position = -1.0
	_position_stall_frames = 0

	# 先初始化显示并显示歌曲信息面板
	_init_display()

	# 重置 ScoreCalculator
	if score_calc:
		score_calc.reset()
	# 生成随机颜色（若皮肤配置启用）— 必须在 init_flow_area 前完成，使对象池节点用新颜色重建
	_regenerate_random_note_colors()
	flow_area.init_flow_area()
	auto_label.visible = flow_area.auto_mode

	# 线程化预解析 MIDI：将昂贵的文件 I/O + 数据结构构建移到 worker 线程
	# 主线程在 await 期间继续渲染歌曲信息面板 + 转场动画
	if not await playback_mgr.preparse_midi_async(midi):
		push_error("Failed to preparse MIDI: " + midi.name)
	# 加载 MIDI（此时已命中解析缓存，仅做配置应用 + 后端加载）
	_load_and_convert_midi_notes(midi)

	# 确保游戏模式下不循环播放
	playback_mgr.set_loop(false)

	# 新增：从配置读取演奏模式
	var performing_mode = ConfigManager.instance.get_int("Playback", "performing_mode", 1)
	play_mode = (performing_mode == 1)
	GLogger.info("Performing mode: %s" % ("ON" if play_mode else "OFF"), "PlayView")

	# 新增：连接配置变更信号
	if not EvtBus.config_changed.is_connected(_on_config_changed):
		EvtBus.config_changed.connect(_on_config_changed)

	# 计算初始seek位置：-1000ms（固定：给予UI准备时间）- 音符下落时间（配置项）
	var note_fall_time = ConfigManager.instance.get_float("Generator", "note_fall_time", 1.5)
	var seek_position = -(1000 + note_fall_time * 1000)
	playback_mgr.seek(seek_position)
	# 视觉钟硬锚定：开局 pre-roll 从负时间起，首次 resume 对齐音频钟
	_visual_time_needs_anchor = true
	is_pause = true

	# 读取并设置音频同步阈值
	var setting_view = get_node_or_null("/root/Main/skew/C/SettingView")
	if setting_view and setting_view.has_method("get_setting_value"):
		var sync_threshold = setting_view.get_setting_value("audio_sync_threshold")
		if sync_threshold != null:
			playback_mgr.set_sync_threshold(float(sync_threshold))
			print("[PlayView] Audio sync threshold set to %.0f ms" % float(sync_threshold))

	# 提前启动 generate_keys 的 worker 线程（主线程筛选音符 + 后台线程跑 generate_keys）
	# 通常 MidiView 已触发过 generate_keys，此处命中缓存直接返回（0ms）
	# 若未命中（如跳过 MidiView 直接进 PlayView），worker 线程跑，主线程不阻塞
	# 若 MidiView 的 worker 还在跑，await 会让出主线程，转场动画继续播放
	var gen_task_id := await _start_generate_game_sequences(midi)

	# 等待 generate_keys worker 完成（每帧让出主线程，动画继续推进）
	# 完成后做后续处理（分类提交、缓存序列）
	await _finish_generate_game_sequences(midi, gen_task_id)
	print("[PlayView] After _finish_generate_game_sequences, game_sequences.size() = %d" % game_sequences.size())

	# 将生成的游戏序列转换为FlowArea所需的音符格式
	var flow_notes = _convert_game_sequences_to_flow_notes(game_sequences)
	print("[PlayView] After _convert_game_sequences_to_flow_notes, flow_notes.size() = %d" % flow_notes.size())
	flow_area.notes_list = flow_notes
	# 告知 ScoreCalculator 总音符数(LONG的持续 tick 不计入)
	if score_calc:
		score_calc.total_notes = flow_notes.size()
	play_result.total_notes = flow_notes.size()
	print("[PlayView] FlowArea initialized with %d game sequences" % flow_notes.size())
	# 设置进度条最大值
	progress_bar.max_value = current_midi.duration_ms

	# 歌曲信息面板显示期间预启动人声：加载 + play + 立即暂停
	# 此处主线程可阻塞（有歌曲信息面板遮罩），消除 is_pause=false 时
	# resume() 触发 start_vocal_playback 的同步加载/解码卡顿
	await playback_mgr.prepare_vocal_playback()

	# 歌曲信息面板已显示足够时间（所有加载时会造成卡顿的部分已处理完毕），现在淡出
	await get_tree().create_timer(1).timeout
	await AniMGR.animate_fade_out(center_bg, 1).finished

	# 记录游玩开始时间（用于统计游玩时长）
	_play_start_time = Time.get_ticks_msec()
	# 开始播放MIDI
	is_pause = false

## 加载MIDI（不再处理FlowArea初始化，该部分由KeySequenceManager处理）
func _load_and_convert_midi_notes(midi_data: MidiData) -> void:
	if playback_mgr == null:
		push_error("MidiPlaybackManager not available!")
		return

	# 加载MIDI
	if not playback_mgr.load_midi(midi_data):
		push_error("Failed to load MIDI for gameplay")
		return
	
	# 应用TrackView中保存的MIDI配置（音量、静音、独奏等）
	_apply_midi_runtime_config(midi_data)
	
	print("[PlayView] MIDI loaded and runtime config applied")

## 将KeySequenceManager生成的游戏序列转换为FlowArea所需的格式
func _convert_game_sequences_to_flow_notes(sequences: Array) -> Array[FlowNote]:
	print("[PlayView] _convert_game_sequences_to_flow_notes called with %d sequences" % sequences.size())
	var flow_notes: Array[FlowNote] = []
	var lc = get_lane_count()
	print("[PlayView] Lane count: %d" % lc)

	for seq in sequences:
		# 确定车道：优先使用 KeySequenceManager 计算的 lane（可能因速度限制而偏移），
		# 后备使用 pitch % lc（向后兼容未设置 lane 的旧序列）
		var lane: int
		if seq.lane >= 0:
			lane = seq.lane
		else:
			lane = seq.pitch % lc
		
		# BlockType 与 NoteType 语义不同，需要转换
		# BlockType: INSTANT=滑块, SHORT=点块, LONG=长条
		# NoteType: Block=点块, Slide=滑块, Long=长条
		var note_type: int
		match seq.block_type:
			0:  # INSTANT = 滑块 → Slide
				note_type = FlowNote.NoteType.Slide
			1:  # SHORT = 点块 → Block
				note_type = FlowNote.NoteType.Block
			2:  # LONG = 长条 → Long
				note_type = FlowNote.NoteType.Long
		
		# 创建FlowArea的Note对象
		var flow_note = FlowNote.new(
			note_type,
			seq.start_time_ms,   # 开始时间（毫秒）
			seq.duration_ms,     # 持续时间（毫秒）
			lane                 # 车道
		)
		
		# 建立双向映射（先斩断旧引用避免 RefCounted 循环泄漏）
		if seq.flow_note_ref != null:
			seq.flow_note_ref.game_sequence_ref = null
			seq.flow_note_ref = null
		seq.flow_note_ref = flow_note
		flow_note.game_sequence_ref = seq
		
		flow_notes.append(flow_note)
	
	print("[PlayView] Converted %d sequences to flow notes" % flow_notes.size())
	# FlowArea期望按时间排序（虽然KeySequenceManager应该已排序）
	flow_notes.sort_custom(func(a, b): return a.start_time < b.start_time)
	
	return flow_notes

## 启动游戏序列生成（主线程筛选音符 + 启动 worker 线程跑 generate_keys）
## 返回 worker task_id（-1 表示未启动，如缺 key_sequence_mgr 或无启用音符）
## 调用方后续通过 await _finish_generate_game_sequences(midi, task_id) 等待完成并做后续处理
## 注意：本函数是 async（start_generate_keys_async 内部等待旧任务时需让出主线程）
func _start_generate_game_sequences(midi_data: MidiData) -> int:
	if key_sequence_mgr == null:
		GLogger.warning("KeySequenceManager not available", "PlayView")
		return -1

	if midi_data.parsed_notes.is_empty():
		GLogger.warning("No parsed notes available for key generation", "PlayView")
		return -1

	# screen_width 已不进 cache_key，且 lane_area.size.x 永远是 40（Lane 节点 anchors_preset=0 不拉伸）
	# 不再调用 set_screen_size：读 lane_area.size.x 没意义，KSM 内部用默认 1920 即可
	# （仅影响 _judge_block_type 速度限制的边缘场景，FlowArea 显示位置由 viewport 宽度算）

	# 按启用的(track, channel)筛选音符（主线程，30-100ms）
	var enabled_notes = _filter_notes_by_enabled_track_channels(midi_data.parsed_notes, midi_data)

	if enabled_notes.is_empty():
		GLogger.warning("No notes in enabled (track, channel) pairs", "PlayView")
		return -1

	# 启动 worker 线程跑 generate_keys
	# 传入 midi_id 和 enabled_pairs 以启用缓存命中
	# enabled_pairs 必须是扁平的 {"track:channel": true} 格式（MidiData.get_enabled_pairs_flat）
	# 与 MidiListItem 一致，否则 cache_key 中的 pairs_hash 不同会导致缓存 miss
	# await start_generate_keys_async：若 MidiView 的 worker 还在跑，这里会让出主线程等待
	# 旧实现不 await 会导致 OS.delay_msec 同步 sleep 卡死转场动画
	var task_id := await key_sequence_mgr.start_generate_keys_async(
		enabled_notes, current_midi.id, midi_data.get_enabled_pairs_flat()
	)
	return task_id

## 等待游戏序列生成完成 + 后续处理（分类提交、缓存序列）
## 若 task_id == -1 表示未启动生成，直接清空 game_sequences
func _finish_generate_game_sequences(_midi_data: MidiData, task_id: int) -> void:
	if task_id == -1:
		game_sequences.clear()
		return

	# 等待 worker 完成（每帧让出，通常 800ms await 后已完成）
	await key_sequence_mgr.await_generate_keys(task_id)

	# 获取KeySequenceManager统计的真实分类结果
	var classification = key_sequence_mgr.get_last_notes_classification()
	var manual_control_notes = classification["manual_control_notes"]
	var auto_play_notes = classification["auto_play_notes"]

	# 将真实分类提交给MidiPlaybackManager
	# 仅在演奏模式开启时下发手动控制；关闭时必须清空以恢复自动播放
	if playback_mgr:
		if play_mode:
			playback_mgr.set_manual_control_notes(manual_control_notes)
			GLogger.info(
				"[Performing ON] Submitted notes classification: %d manual, %d auto" %
				[manual_control_notes.size(), auto_play_notes.size()],
				"PlayView"
			)
		else:
			playback_mgr.clear_manual_control_notes()
			GLogger.info(
				"[Performing OFF] Cleared manual control notes: all notes will auto-play (manual=%d, auto=%d)" %
				[manual_control_notes.size(), auto_play_notes.size()],
				"PlayView"
			)

	# 缓存生成的游戏序列
	var raw_sequences = key_sequence_mgr.get_game_sequences()
	print("[PlayView] get_game_sequences returned %d items" % raw_sequences.size())
	game_sequences = raw_sequences
	print("[PlayView] game_sequences assigned, size = %d" % game_sequences.size())

	GLogger.info("Generated %d game sequences for play mode" % game_sequences.size(), "PlayView")

## 按启用的(track, channel)筛选音符
func _filter_notes_by_enabled_track_channels(all_notes: Array, midi_data: MidiData) -> Array:
	var filtered: Array = []
	
	if midi_data == null:
		GLogger.warning("midi_data is null when filtering notes", "PlayView")
		return filtered

	# selected_track_configs 是 Dictionary，格式: {track_idx: [channel1, channel2, ...]}
	if midi_data.selected_track_configs.is_empty():
		if midi_data._track_config_initialized:
			push_error("[PlayView] All (track, channel) pairs are disabled! Cannot play game without enabled notes.")
		else:
			push_error("[PlayView] No (track, channel) configuration found and no default configuration applied!")
		return filtered

	GLogger.info("selected_track_configs: %s" % str(midi_data.selected_track_configs), "PlayView")
	GLogger.info("Filtering %d notes by enabled (track, channel) pairs" % all_notes.size(), "PlayView")
	
	# 筛选音符
	var pair_stats = {}  # 统计每个(track, channel)对的音符数
	for note in all_notes:
		if note is MidiParser.NoteEvent:
			var track_idx = int(note.track_index)
			var channel = int(note.channel)
			var pair_key = "%d:%d" % [track_idx, channel]

			# 统计
			if not pair_stats.has(pair_key):
				pair_stats[pair_key] = 0
			pair_stats[pair_key] += 1

			# 筛选
			if midi_data.is_track_channel_selected(track_idx, channel):
				filtered.append(note)
	
	GLogger.info("Track-channel note stats: %s" % str(pair_stats), "PlayView")
	GLogger.info("Filtered result by (track,channel): %d notes out of %d" % [filtered.size(), all_notes.size()], "PlayView")
	
	return filtered

## 从ConfigManager加载键盘和轨道相关的参数
func _load_lane_parameters() -> void:
	var config_mgr = ConfigManager.instance
	
	# 加载轨道数量（默认12）
	lane_count = config_mgr.get_int("Lane", "lane_count", 12)
	# 加载左右安全区（默认100）
	lane_padding = config_mgr.get_int("Judge", "canvas_horizontal_padding", 100)
	# 加载判定线高度（默认200）
	judge_line_offset_y = max(0, config_mgr.get_int("Judge", "judge_line_position", 200))
	
	# 加载键盘模式（0=关闭，1=开启，默认0）
	keyboard_mode = config_mgr.get_int("Lane", "keyboard_mode", 0) == 1
	
	# 加载键盘键位字符串（默认 "A,S,D,F,J,K,L,;"）
	var keyboard_keys_str = config_mgr.get_string("Lane", "keyboard_mode_keys", "A,S,D,F,J,K,L,;")
	key_map = ConfigParser.parse_keyboard_keys(keyboard_keys_str)
	# 加载键盘键位显示名称（与 key_map 对齐，空字符串=使用按键默认名）
	var keyboard_names_str = config_mgr.get_string("Lane", "keyboard_mode_display_names", "")
	key_display_names = ConfigParser.parse_keyboard_display_names(keyboard_names_str, key_map.size())

	# 加载交替轨道颜色（默认开启；仅键盘模式生效）
	keyboard_alt_color = config_mgr.get_bool("Lane", "keyboard_alt_color", true)
	keyboard_alt_color_count = max(1, config_mgr.get_int("Lane", "keyboard_alt_color_count", 2))
	keyboard_alt_colors = _parse_alt_colors(
		config_mgr.get_string("Lane", "keyboard_alt_colors", "#ff0000,#0000ff")
	)
	# 颜色数组对齐到声明的数量（不足补白，多余截断）
	while keyboard_alt_colors.size() < keyboard_alt_color_count:
		keyboard_alt_colors.append(Color.WHITE)
	keyboard_alt_colors.resize(keyboard_alt_color_count)

	# 左右间距（偶数键位时中间额外间距）
	keyboard_mode_gap = max(0, config_mgr.get_int("Lane", "keyboard_mode_gap", 0))
	# 轨道分隔线（仅键盘模式生效）
	keyboard_lane_separator = config_mgr.get_bool("Lane", "keyboard_lane_separator", false)

	GLogger.info(
		"PlayView lane parameters loaded: lane_count=%d, lane_padding=%d, keyboard_mode=%s, key_map_size=%d" % 
		[lane_count, lane_padding, str(keyboard_mode), key_map.size()],
		"PlayView"
	)
	beam_alpha = config_mgr.get_float("Lane", "flash_alpha", 0.8)
	if lane_area and lane_area.has_method("set_beam_alpha"):
		lane_area.set_beam_alpha(beam_alpha)
	var note_glow_intensity = config_mgr.get_float("Appearance", "note_glow_intensity", 0.5)
	var note_glow_size = config_mgr.get_float("Appearance", "note_glow_size", 5.0)
	if flow_area and flow_area.has_method("set_glow_params"):
		flow_area.set_glow_params(note_glow_intensity, note_glow_size)


## 处理 Lane/Judge 段配置变更（轨道数量、键位、左右安全区）
func _on_lane_config_changed(key: String, section: String, value: Variant) -> void:
	if section != "Lane" and section != "Judge":
		return
	
	var should_reinit = false

	if section == "Judge" and key == "judge_line_position":
		var new_offset : int = max(0, int(value))
		if new_offset != judge_line_offset_y:
			judge_line_offset_y = new_offset
			should_reinit = true
			if flow_area and flow_area.has_method("_apply_judge_line_position"):
				flow_area._apply_judge_line_position()
			GLogger.info("PlayView judge_line_offset_y updated: %d" % judge_line_offset_y, "PlayView")

	if section == "Judge" and key == "canvas_horizontal_padding":
		var new_lane_padding = int(value)
		if new_lane_padding != lane_padding:
			lane_padding = new_lane_padding
			should_reinit = true
			GLogger.info("PlayView lane_padding updated: %d" % lane_padding, "PlayView")
	
	match key:
		"lane_count":
			if section == "Lane":
				var new_lane_count = int(value)
				if new_lane_count != lane_count:
					lane_count = new_lane_count
					# 仅在非键盘模式时需要重初始化轨道显示
					if not keyboard_mode:
						should_reinit = true
					GLogger.info("PlayView lane_count updated: %d" % lane_count, "PlayView")
		
		"keyboard_mode":
			if section == "Lane":
				var new_mode = int(value) == 1
				if new_mode != keyboard_mode:
					keyboard_mode = new_mode
					should_reinit = true
					GLogger.info("PlayView keyboard_mode updated: %s" % str(keyboard_mode), "PlayView")
		
		"keyboard_mode_keys":
			if section == "Lane":
				var new_keys = ConfigParser.parse_keyboard_keys(str(value))
				if new_keys.size() != key_map.size() or _are_keys_different(new_keys, key_map):
					key_map = new_keys
					# 键位变化时同步重算 display_names（按新 key 数量对齐）
					key_display_names = ConfigParser.parse_keyboard_display_names(
						ConfigManager.instance.get_string("Lane", "keyboard_mode_display_names", ""),
						key_map.size()
					)
					# 仅在键盘模式时需要重初始化
					if keyboard_mode:
						should_reinit = true
					GLogger.info("PlayView keyboard_mode_keys updated: %d keys" % key_map.size(), "PlayView")

		"keyboard_mode_display_names":
			if section == "Lane":
				key_display_names = ConfigParser.parse_keyboard_display_names(str(value), key_map.size())
				# 仅在键盘模式时需要重初始化（刷新标签文本）
				if keyboard_mode:
					should_reinit = true
				GLogger.info("PlayView keyboard_mode_display_names updated: %d names" % key_display_names.size(), "PlayView")

		"keyboard_alt_color", "keyboard_alt_color_count", "keyboard_alt_colors":
			if section == "Lane":
				var old_alt_color := keyboard_alt_color
				var old_alt_count := keyboard_alt_color_count
				var old_alt_colors: Array = keyboard_alt_colors.duplicate()
				keyboard_alt_color = int(value) == 1 if key == "keyboard_alt_color" else keyboard_alt_color
				if key == "keyboard_alt_color_count":
					keyboard_alt_color_count = max(1, int(value))
				if key == "keyboard_alt_colors":
					keyboard_alt_colors = _parse_alt_colors(str(value))
					while keyboard_alt_colors.size() < keyboard_alt_color_count:
						keyboard_alt_colors.append(Color.WHITE)
					keyboard_alt_colors.resize(keyboard_alt_color_count)
				# 仅键盘模式且颜色配置有变化时重初始化（刷新音符/光束颜色）
				if keyboard_mode and (keyboard_alt_color != old_alt_color or keyboard_alt_color_count != old_alt_count or keyboard_alt_colors != old_alt_colors):
					should_reinit = true
				GLogger.info("PlayView keyboard_alt_color updated: enabled=%s count=%d colors=%s" %
					[str(keyboard_alt_color), keyboard_alt_color_count, str(keyboard_alt_colors)], "PlayView")

		"keyboard_mode_gap":
			if section == "Lane":
				var new_gap: int = max(0, int(value))
				if new_gap != keyboard_mode_gap:
					keyboard_mode_gap = new_gap
					should_reinit = true
					GLogger.info("PlayView keyboard_mode_gap updated: %d" % keyboard_mode_gap, "PlayView")

		"keyboard_lane_separator":
			if section == "Lane":
				var new_sep := int(value) == 1
				if new_sep != keyboard_lane_separator:
					keyboard_lane_separator = new_sep
					if keyboard_mode:
						should_reinit = true
					GLogger.info("PlayView keyboard_lane_separator updated: %s" % str(keyboard_lane_separator), "PlayView")

		"flash_alpha":
			if section == "Lane":
				beam_alpha = float(value)
				if lane_area and lane_area.has_method("set_beam_alpha"):
					lane_area.set_beam_alpha(beam_alpha)
	
	if should_reinit:
		# 仅在游戏未开始或者允许的情况下重新初始化轨道
		if not (playback_mgr and playback_mgr.is_playing):
			_reinit_lane_display()

## 比较两个KeyCode数组是否不同
func _are_keys_different(keys1: Array[Key], keys2: Array[Key]) -> bool:
	if keys1.size() != keys2.size():
		return true
	for i in range(keys1.size()):
		if keys1[i] != keys2[i]:
			return true
	return false

## 重新初始化轨道显示
## 清空旧轨道并根据当前配置重新初始化
func _reinit_lane_display() -> void:
	if flow_area == null or lane_area == null:
		return
	
	# 重新初始化流动区域
	flow_area.init_flow_area()
	
	# 重新初始化轨道光效（lane_area 已经是 LaneEffect 实例）
	lane_area.init_beam(get_lane_count(), self)
	lane_area.set_beam_alpha(beam_alpha)
	
	# 如果启用了键盘模式，显示键位提示
	if keyboard_mode and key_map.size() > 0:
		lane_area.init_key_display(key_map, key_display_names)
	
	GLogger.info("PlayView lane display reinitialized", "PlayView")

## 从配置加载演奏模式设置
func _load_play_mode_setting() -> void:
	var performing_mode = ConfigManager.instance.get_int("Playback", "performing_mode", 1)
	play_mode = (performing_mode == 1)
	GLogger.info("PlayView play mode: %s" % ("ON" if play_mode else "OFF"), "PlayView")

## 应用TrackView中保存的MIDI运行时配置（音量、静音、独奏等）
func _apply_midi_runtime_config(midi_data: MidiData) -> void:
	if playback_mgr == null:
		return
	
	# 应用全局音量 (MIDI音量实际效果为UI值的2倍: 0.5=0dB, 1.0=+6dB)
	# 默认值(0.5)回退全局 default_midi_volume，与 TrackView 保持一致
	playback_mgr.set_volume_db(linear_to_db(playback_mgr.get_effective_midi_volume(midi_data.midi_volume) * 2.0))
	
	# 应用轨道-通道的静音状态
	# track_channel_mute_state: {track_idx: {channel: bool}}
	if not midi_data.track_channel_mute_state.is_empty():
		for track_idx in midi_data.track_channel_mute_state.keys():
			var channels = midi_data.track_channel_mute_state[track_idx]
			if channels is Dictionary:
				for channel in channels.keys():
					var is_muted = channels[channel]
					playback_mgr.set_track_channel_mute(track_idx, channel, is_muted)
	
	# 应用独奏状态（Additive Solo）
	# solo_pairs: {"track:channel": true}
	if not midi_data.solo_pairs.is_empty():
		for solo_key in midi_data.solo_pairs.keys():
			# solo_key 格式: "track:channel"
			var parts = solo_key.split(":")
			if parts.size() == 2:
				var track = int(parts[0])
				var channel = int(parts[1])
				# 独奏意味着这个轨道要启用，其他非独奏的轨道要静音
				playback_mgr.set_track_channel_mute(track, channel, false)

	# 应用音轨-通道的音量调整
	# track_channel_volume_config: {track_idx: {channel: volume_value}}（值为线性 0.0-1.0）
	if not midi_data.track_channel_volume_config.is_empty():
		for track_idx in midi_data.track_channel_volume_config.keys():
			var channels = midi_data.track_channel_volume_config[track_idx]
			if channels is Dictionary:
				for channel in channels.keys():
					var volume = channels[channel]
					# 设置通道音量（线性值直接透传，勿再除以100）
					playback_mgr.set_track_channel_volume(int(track_idx), int(channel), float(volume))
	
	# 应用乐器覆盖（如果有）
	if not midi_data.track_channel_instrument_overrides.is_empty():
		for track_index in midi_data.track_channel_instrument_overrides.keys():
			var channels = midi_data.track_channel_instrument_overrides[track_index]
			for channel in channels.keys():
				var instrument = channels[channel]
				var bank = instrument.get("bank", 0)
				var program = instrument.get("program", 0)
				# 设置乐器
				if playback_mgr.has_method("set_track_channel_program"):
					playback_mgr.set_track_channel_program(track_index, channel, bank, program)
	
	# 应用人声偏移量
	playback_mgr.set_vocal_offset_ms(midi_data.vocal_offset_ms)
	
	GLogger.info("MIDI runtime config applied: volume=%d%%, mute_states=%d, solo_pairs=%d" %
		[int(round(midi_data.midi_volume * 100.0)), midi_data.track_channel_mute_state.size(), midi_data.solo_pairs.size()], "PlayView")

## 游戏结束回调
func _on_game_finished() -> void:
	if _is_finishing_game:
		return
	_is_finishing_game = true

	print("[PlayView] Game finished!")

	# 停止MIDI播放但不暂停FlowArea，让剩余音符继续自然下落
	if playback_mgr:
		playback_mgr.stop()

	# 等待所有音符自然消除（被判定或落出屏幕），最长等待10秒
	var safety_timer := get_tree().create_timer(10.0)
	while flow_area.has_active_notes():
		if safety_timer.time_left <= 0.0:
			break
		await get_tree().process_frame

	# 音符全部消除后，从 ScoreCalculator 拿最终快照（包含自然Miss）
	var snap = score_calc.get_snapshot()
	# 记录本次游玩实际耗时（毫秒），用于服务端统计
	snap["play_duration_ms"] = Time.get_ticks_msec() - _play_start_time
	play_result.score = snap["total_score"]
	play_result.max_combo = snap["max_combo"]
	play_result.accuracy = snap["accuracy"]
	play_result.performance_point = snap["pp"]
	play_result.count["Perfect"] = snap["judge_counts"][ScoreCalculator.Judgment.PERFECT]
	play_result.count["Great"] = snap["judge_counts"][ScoreCalculator.Judgment.GREAT]
	play_result.count["Good"] = snap["judge_counts"][ScoreCalculator.Judgment.GOOD]
	play_result.count["Bad"] = snap["judge_counts"][ScoreCalculator.Judgment.BAD]
	play_result.count["Miss"] = snap["judge_counts"][ScoreCalculator.Judgment.MISS]
	play_result.early_count = snap["early_count"]
	play_result.late_count = snap["late_count"]

	# 进入结算界面（资源清理已统一由 _on_state_changed 处理）
	await get_tree().create_timer(1).timeout
	UiStatMGR.change_state(UIStateManager.UIState.SCORE_VIEW, false)
	get_node("/root/Main/ScoreView").set_display(play_result)
	# 异步上传成绩（不阻塞结算界面）
	_upload_score_async(current_midi, snap)

## 异步上传成绩（fire-and-forget，失败仅记日志）
func _upload_score_async(midi: MidiData, snapshot: Dictionary) -> void:
	if midi == null or midi.file_hash.is_empty():
		GLogger.warning("Score upload skipped: midi is null or file_hash empty (midi=%s hash=%s)" % [str(midi), str(midi.file_hash) if midi else "null"], "PlayView")
		return
	if NetManager.instance == null or not NetManager.instance.is_online:
		GLogger.warning("Score upload skipped: offline (NetManager=%s is_online=%s)" % [str(NetManager.instance), str(NetManager.instance.is_online) if NetManager.instance else "null"], "PlayView")
		return
	if ScoreManager.instance == null:
		GLogger.warning("Score upload skipped: ScoreManager not ready", "PlayView")
		return
	GLogger.info("Score upload starting: midi=%s pp=%s" % [midi.file_hash, str(snapshot.get("pp", 0))], "PlayView")
	var result = await ScoreManager.instance.upload_score(midi, snapshot)
	if result.get("ok", false):
		GLogger.info("Score uploaded: midi=%s pp=%s" % [midi.file_hash, str(snapshot.get("pp", 0))], "PlayView")
		# 通知个人信息页刷新统计
		EvtBus.score_uploaded.emit(midi.file_hash)
	else:
		GLogger.warning("Score upload failed: %s (status=%s)" % [result.get("error", "unknown"), str(result.get("status", 0))], "PlayView")

## 退出游戏（中途退出）
func _on_quit_pressed() -> void:
	# 中途退出：上传成绩（评级强制为 W），等待上传完成后再返回，确保排行榜刷新时数据已写入
	await _upload_score_on_quit()
	# 返回上级界面（_on_state_changed 统一处理 MIDI 停止、音符回收、背景清理等）
	UiStatMGR.go_back()

## 中途退出时上传成绩：评级强制 W，cleared=false
## await 此方法可等待上传完成
func _upload_score_on_quit() -> void:
	if current_midi == null or current_midi.file_hash.is_empty():
		return
	if NetManager.instance == null or not NetManager.instance.is_online:
		return
	if ScoreManager.instance == null:
		return
	if score_calc == null:
		return
	var snap = score_calc.get_snapshot()
	# 强制评级为 W（中途退出），服务端据此排序到最后并允许完成记录覆盖
	snap["rank"] = "W"
	# 记录本次游玩实际耗时（毫秒），W 评级时长仍计入统计
	snap["play_duration_ms"] = Time.get_ticks_msec() - _play_start_time
	await _upload_score_async(current_midi, snap)

# 初始化分数等内容的显示
func _init_display():
	_is_finishing_game = false
	score.text = "0"
	combo.text = "0"
	score_wait_to_add = 0
	score_add.text = "+0"

	pp_text.text = "0.00pp"
	accuracy_text.text = "100.00%"

	# 设置歌曲信息（封面只加载一次，同时传给信息面板和背景）
	var cover_texture = FileSystemManager.instance.get_cover_by_midiData(current_midi)
	var has_custom_cover := _has_cover_for_current_midi()
	if cover_texture:
		cover.texture = cover_texture
	_apply_play_background(cover_texture, has_custom_cover)

	ani.animate_fade_in(center_bg, 0.2, "_show_bg")
	album.text = current_midi.artist_name
	song.text = current_midi.song_name
	artist.text = current_midi.author_name if current_midi.author_name else "Unknow"
	var s := int(current_midi.duration_ms / 1000.0)
	@warning_ignore("integer_division")
	midi_duration.text = "%02d:%02d" % [s / 60, s % 60]
	midi_name.text = current_midi.name
	midi_author.text = current_midi.artist_name
	
	menu.visible = false
	song_info.visible = true

	center.modulate.a = 0
	center_bg.visible = true
	is_pause = true
	
	# 恢复flow_area显示
	flow_area.visible = true

	# 重置进度条
	_current_rect = null
	_last_rect = null

	progress_bar.value = 0
	for i in progress_bar.get_children():
		i.queue_free()
	
	_init_lane_display()

	auto_label.visible = flow_area.auto_mode


func _apply_play_background(p_cover: Texture2D = null, p_has_custom_cover: bool = false) -> void:
	if background == null:
		return

	_apply_background_dim()

	# 背景配置统一从 ThemeManager 读取（theme.ini [backgrounds] 段）
	var bg_config := ThemeMGR.get_view_background("play")
	var bg_type: String = bg_config.get("type", "gradient")

	if bg_type == "cover":
		# 封面模式：PlayView 独有逻辑（曲包封面 + 模糊烘焙）
		# ThemeManager 的 apply_background 对 cover 类型不实际应用，留给 PlayView 处理
		var blur_strength := float(bg_config.get("cover_blur", 0.35))
		# 优先使用调用方传入的封面（避免重复加载和 charts_index 扫描）
		var cover_texture: Texture2D = p_cover
		var has_custom: bool = p_has_custom_cover
		if p_cover == null:
			has_custom = _has_cover_for_current_midi()
			if has_custom:
				cover_texture = FileSystemManager.instance.get_cover_by_midiData(current_midi)
		if has_custom and cover_texture:
			background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			background.texture = _prepare_background_texture(cover_texture)
			background.modulate = Color.WHITE
			background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			_set_cover_blur_material(blur_strength)
			return
		# 无封面可用，降级到纯色（使用 play 段的 solid_color）
		var fallback_color: String = bg_config.get("solid_color", "#10121AFF")
		_apply_background_solid(fallback_color)
		return

	# image / solid / gradient 委托给 ThemeManager 统一应用
	ThemeMGR.apply_background(background, "play")
	_clear_cover_blur_material()


func _apply_background_solid(color_html: String) -> void:
	background.texture = null
	background.modulate = Color(color_html) if color_html.is_valid_html_color() else Color("#10121AFF")
	_clear_cover_blur_material()


func _set_cover_blur_material(blur_strength: float) -> void:
	background.material = null
	var tex = background.texture
	if tex == null:
		return
	_bake_blurred_background(tex, blur_strength)


func _clear_cover_blur_material() -> void:
	background.material = null
	_teardown_blur_bake_viewport()


func _bake_blurred_background(cover_texture: Texture2D, blur_strength: float) -> void:
	_blur_bake_id += 1
	var my_id = _blur_bake_id

	if _blur_bake_viewport:
		_blur_bake_viewport.queue_free()
		_blur_bake_viewport = null
		_blur_bake_texture_rect = null

	if blur_strength <= 0.001:
		background.material = null
		return

	var window_size = DisplayServer.window_get_size()
	var bake_size := Vector2i(window_size)
	if bake_size.x > 1920 or bake_size.y > 1080:
		var s = min(1920.0 / bake_size.x, 1080.0 / bake_size.y)
		bake_size = Vector2i(bake_size * s)

	_blur_bake_viewport = SubViewport.new()
	_blur_bake_viewport.size = bake_size
	_blur_bake_viewport.transparent_bg = true
	_blur_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_blur_bake_viewport)

	_blur_bake_texture_rect = TextureRect.new()
	_blur_bake_texture_rect.texture = cover_texture
	_blur_bake_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_blur_bake_texture_rect.stretch_mode = background.stretch_mode
	_blur_bake_texture_rect.position = Vector2.ZERO
	_blur_bake_texture_rect.size = bake_size
	_blur_bake_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_bake_viewport.add_child(_blur_bake_texture_rect)

	var shader = load(BG_BLUR_SHADER_PATH)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("blur_strength", clampf(blur_strength, 0.0, 1.0))
	_blur_bake_texture_rect.material = mat

	await RenderingServer.frame_post_draw

	if my_id != _blur_bake_id or _blur_bake_viewport == null:
		return

	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.texture = _blur_bake_viewport.get_texture()
	background.material = null


func _teardown_blur_bake_viewport() -> void:
	if _blur_bake_viewport:
		_blur_bake_viewport.queue_free()
		_blur_bake_viewport = null
		_blur_bake_texture_rect = null
	_blur_bake_id += 1


func _apply_background_dim() -> void:
	if dim_overlay == null:
		return
	var dim_color_html = ConfigManager.instance.get_string("Appearance", "background_dim_color", "#0000007F")
	if dim_color_html.is_valid_html_color():
		dim_overlay.color = Color(dim_color_html)
	else:
		dim_overlay.color = Color(0, 0, 0, 0.5)
	_setup_dim_overlay_shader()
	var flash_color_html = ConfigManager.instance.get_string("Appearance", "background_image_flash_color", "#FFFFFF00")
	if flash_color_html.is_valid_html_color():
		flash_color = Color(flash_color_html)
	else:
		flash_color = Color(1, 1, 1, 0)
	var mat := dim_overlay.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("flash_color", flash_color)

func _setup_dim_overlay_shader() -> void:
	if dim_overlay.material and dim_overlay.material is ShaderMaterial:
		return
	var shader := load(BG_FLASH_SHADER_PATH)
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("flash_color", flash_color)
	mat.set_shader_parameter("flash_progress", 0.0)
	dim_overlay.material = mat

func _set_flash_progress(value: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("flash_progress", value)


func _flash_background() -> void:
	if dim_overlay == null or flash_color.a <= 0:
		return
	var mat := dim_overlay.material as ShaderMaterial
	if mat == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	mat.set_shader_parameter("flash_progress", 1.0)
	_flash_tween = create_tween()
	_flash_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_method(_set_flash_progress.bind(mat), 1.0, 0.0, 1)

func _prepare_background_texture(source_texture: Texture2D) -> Texture2D:
	if source_texture == null:
		return null

	var image := source_texture.get_image()
	if image == null or image.is_empty():
		return source_texture

	if not image.has_mipmaps():
		# 异步生成 mipmap：先返回原图避免阻塞当前帧，下一帧再替换为 mipmap 版本
		_generate_mipmaps_deferred(image)
		return source_texture

	return source_texture

func _generate_mipmaps_deferred(image: Image) -> void:
	await RenderingServer.frame_post_draw
	if is_instance_valid(self) and image != null and not image.is_empty():
		image.generate_mipmaps()
		background.texture = ImageTexture.create_from_image(image)


func _has_cover_for_current_midi() -> bool:
	if current_midi == null or FileSystemManager.instance == null:
		return false

	var result = FileSystemManager.instance._lookup_chart(current_midi.file_hash)
	if result.is_empty():
		result = FileSystemManager.instance._lookup_chart(current_midi.id)
	if result.is_empty():
		return false
	var metadata: ChartMetadata = result["metadata"]
	return not metadata.cover_path.is_empty() and FileAccess.file_exists(metadata.cover_path)

func _init_lane_display():
	# 窗口大小变化时重新计算音符尺寸
	if flow_area and flow_area.has_method("_recalculate_note_dimensions"):
		flow_area._recalculate_note_dimensions()
	lane_area.init_beam(get_lane_count(), self)
	lane_area.set_beam_alpha(beam_alpha)
	if keyboard_mode:
		lane_area.init_key_display(key_map, key_display_names)

const color_map = {
	"Perfect": Color.PURPLE,
	"Great": Color.ORANGE,
	"Good": Color.DARK_OLIVE_GREEN,
	"Bad": Color.ROYAL_BLUE,
	"Miss": Color.RED
}

# ---- 帧内判定 UI 合并刷新 ----
# 三押/多指同帧多次判定时，Label.set_text / add_theme_color_override / tween 创建 / 全屏闪光
# 都是引擎 C++ 原生开销（GDScript profiler 不统计），同帧 ×N 会叠加成帧时间尖峰。
# 策略：计分数据（record_judgment / score_wait_to_add）逐判定实时累加，展示部分攒到帧末
# call_deferred 合并刷一次 —— 同帧 3 次判定只更新 1 次 UI。
var _judge_ui_dirty: bool = false
var _judge_ui_result: String = ""
var _judge_ui_offset: String = ""
var _judge_ui_cl: Color = Color.WHITE
var _judge_ui_snap: Dictionary = {}
# LONG 持续加分 tick：只刷数据类 UI，跳过 center 动画/偏移指示/背景闪光（保持旧轻量语义）
var _judge_ui_hold_tick: bool = false

func _on_note_judged(result: String, offset: String, block_type: int, timing_sec: float, signed_offset_sec: float):
	# ---- 委托 ScoreCalculator 计算（数据源，逐判定实时） ----
	var judgment = ScoreCalculator.Judgment.MISS
	match result:
		"Perfect": judgment = ScoreCalculator.Judgment.PERFECT
		"Great":   judgment = ScoreCalculator.Judgment.GREAT
		"Good":    judgment = ScoreCalculator.Judgment.GOOD
		"Bad":     judgment = ScoreCalculator.Judgment.BAD
		"Miss":    judgment = ScoreCalculator.Judgment.MISS

	var snap = score_calc.record_judgment(judgment, block_type, timing_sec, signed_offset_sec)

	# 分数增量逐判定累加（_process 逐帧消化）
	_score_add_accumulate(int(snap["last_score_add"]))

	# 展示数据合并：用本帧最后一次判定的快照，帧末统一刷新一次
	_queue_judge_ui(result, offset, color_map[result], snap)

## LONG 持续 tick 加分（已委托 ScoreCalculator）
func _on_long_holding(long_instance_id: int):
	var snap = score_calc.record_long_sustain(ScoreCalculator.Judgment.PERFECT, long_instance_id)
	_score_add_accumulate(int(snap["last_score_add"]))
	_queue_judge_ui("Perfect", "", color_map["Perfect"], snap, true)

## 存展示快照并排定帧末刷新；同帧后续判定只覆盖快照，不重复排队。
## 用 call_deferred 而非 _process 做帧末 flush：PlayView._process 先于子节点 FlowArea._process
## 执行，auto 判定发生在 FlowArea._process，若用 _process 刷会把反馈推迟一帧；call_deferred
## 在整帧结束后统一 flush，覆盖 input / PlayView._process / FlowArea._process 所有来源的判定。
func _queue_judge_ui(result: String, offset: String, cl: Color, snap: Dictionary, is_hold_tick: bool = false) -> void:
	_judge_ui_result = result
	_judge_ui_offset = offset
	_judge_ui_cl = cl
	_judge_ui_snap = snap
	_judge_ui_hold_tick = is_hold_tick
	if not _judge_ui_dirty:
		_judge_ui_dirty = true
		_apply_judge_ui.call_deferred()

## 帧末统一应用判定 UI（Label/颜色/tween/闪光全部只执行一次）
func _apply_judge_ui() -> void:
	if not _judge_ui_dirty:
		return
	_judge_ui_dirty = false
	var snap: Dictionary = _judge_ui_snap
	var result: String = _judge_ui_result
	var cl: Color = _judge_ui_cl
	var offset: String = _judge_ui_offset
	var is_hold_tick: bool = _judge_ui_hold_tick

	center_text.text = result
	center_text.add_theme_color_override("font_color", cl)

	# combo显示
	combo.text = str(snap["combo"])

	# 增加分数（增量已逐判定累加到 score_wait_to_add，这里只刷展示）
	var score_add_amount := int(snap["last_score_add"])
	if score_add_amount != 0:
		score_add.text = "+%d" % score_add_amount
		score_add.modulate.a = 1
		var tween = ani._create_tween("score_add_out")
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(score_add, "modulate:a", 0.0, 2)
		ani.animate_pulse(score_add, 1, 1.1, 0.1, "score_pluse")

	# 设置进度条颜色
	_set_progress_bar_color(cl)

	# pp和准度
	pp_text.text = snap["pp_text"]
	accuracy_text.text = snap["accuracy_text"]

	# LONG hold tick：轻量路径，到这里就结束（不清偏移指示、不播 center 动画、不闪背景）
	if is_hold_tick:
		return

	# 显示偏移
	early_text.self_modulate.a = 0
	late_text.self_modulate.a = 0
	if result != "Miss" and offset != "":
		if offset[0] == "+":
			early_text.text = offset
			early_text.self_modulate.a = 1
		else:
			late_text.text = offset
			late_text.self_modulate.a = 1

	# 动画
	center.rotation_degrees = (randf()-0.5) * 5
	var pulse: Tween = ani._create_tween("center pluse")
	pulse.set_parallel(true)
	center.scale = Vector2.ONE * 1.1
	pulse.tween_property(center, "scale", Vector2.ONE, 0.1)
	pulse.tween_property(center, "rotation_degrees", 0, 0.1)

	var fade = ani._create_tween("center fade out")
	center.modulate.a = 1
	fade.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	fade.tween_property(center, "modulate:a", 0.0, 2)

	if result != "Miss":
		_flash_background()

var score_wait_to_add = 0
func _score_add_accumulate(amount: int) -> void:
	if amount == 0:
		return
	score_wait_to_add += amount

# 进度条颜色填充回调
var _current_rect: ColorRect = null
var _last_rect: ColorRect = null
func _on_top_progress_bar_value_changed(value: float):
	if is_pause:
		return

	var anchor_l = 0.0 if not _last_rect else _last_rect.anchor_right
	if not _current_rect:
		_current_rect = ColorRect.new()

		_current_rect.anchor_left = anchor_l if anchor_l < 0.002 else anchor_l - 0.001
		_current_rect.color = color_map["Miss"] if not _last_rect else _last_rect.color
		_current_rect.size.y = progress_bar.size.y

		_last_rect = _current_rect
		progress_bar.add_child(_current_rect)
	
	_current_rect.anchor_right = value / progress_bar.max_value

	# 游戏结束
	if value >= progress_bar.max_value:
		_on_game_finished()

func _set_progress_bar_color(cl: Color):
	if not _current_rect or (_current_rect.size.x > 15 and cl != _current_rect.color):
		_current_rect = null
		_on_top_progress_bar_value_changed(progress_bar.value)
		return

	_current_rect.color = cl
