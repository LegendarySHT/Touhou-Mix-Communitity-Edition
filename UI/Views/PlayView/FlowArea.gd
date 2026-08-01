extends Panel

class_name FlowArea
const NOTE_GLOW_SHADER: Shader = preload("res://UI/Views/PlayView/Shaders/NoteGlow.gdshader")
const LONG_BODY_REPEAT_SHADER: Shader = preload("res://UI/Views/PlayView/Shaders/LongBodyRepeat.gdshader")

# 判定线
@onready var jl: HSeparator = $JudgeLine
@onready var ui: UIStateManager = UiStatMGR
@onready var canvas: CanvasLayer = $SVP

########## 配置参数 #############
var auto_mode: bool = false
var judge_mode: int = NoteJudger.JudgeMode.BEST_TIMING_FIFO  # 从 Judge/touch_judging_criteria 配置初始化
var note_judge_width: int = 100  # 统一判定宽度，从 Judge/block_judging_width 配置读取
var note_visual_width: int = 200  # 从 Appearance/block_size 配置读取
var glow_intensity: float = 1.0
var glow_size: float = 20.0
var check_slide_when_finger_up: bool = true  # Judge/check_instant_blocks_when_finger_up
var only_perfect_slides: bool = false  # Judge/only_perfect_instant_blocks_before_judge
var note_judger: NoteJudger = NoteJudger.new()

# 音符下落动画
var trans_before_line: int = Tween.TRANS_LINEAR as int
var ease_before_line: int = Tween.EASE_IN_OUT as int
var trans_after_line: int = Tween.TRANS_LINEAR as int
var ease_after_line: int = Tween.EASE_OUT as int

var note_color_short: Color = Color.DEEP_PINK
var note_color_slide: Color = Color.CYAN
var note_color_long: Color = Color.DARK_ORANGE

# 皮肤core贴图标记：用于决定是否显示光晕
var _skin_has_short_core: bool = true
var _skin_has_instant_core: bool = true
var _skin_has_long_core: bool = true

# 当前皮肤的完整配置（来自 skin.ini 新结构）
# {general:{enable_glow,custom_color}, short:{enable_color,color,random_color}, instant:{...}, long:{...,long_connect_mode,long_f_mode}}
var _skin_config: Dictionary = {}

# 光效总开关（来自 [general] enable_glow）
var _is_glow_enabled: bool = false

# long-f 中部贴图应用方式："repeat"（水平拉伸+垂直重复）或 "stretch"（竖直拉伸）
var _long_f_mode: String = "repeat"

# 长条连接模式："edge"（边缘连接，默认）或 "center"（中心连接）
var _long_connect_mode: String = "edge"

# 随机颜色（由 PlayView 在 _prepare_game 时生成并传入）
# 结构: {note_type_key: Color}，仅在该类型启用 random_color 时存在对应键
var _random_colors: Dictionary = {}

# 最终解析出的音符颜色（结合 custom_color 主开关 + enable_color + random_color）
# 结构: {note_type_key: Color}，键为 "short"/"instant"/"long"
var _resolved_colors: Dictionary = {}

# 判定参数（毫秒）- 与 ScoreCalculator.JUDGE_WINDOWS（秒）对应
var judge_windows: Dictionary = {
	"perfect": 50,    # < 0.05s
	"great": 150,     # < 0.15s
	"good": 200,      # < 0.20s
	"bad": 500        # < 0.50s
}

# 音符生成提前量（毫秒） - 确保音符在到达判定线前有足够时间显示 - 调下落速度也是用它（
var note_generation_lead_time: float = 1000.0

# 下落参数
var _note_fall_time_seconds: float = 1.0
var _note_fall_speed_after_judge_multiplier: float = 1.0
# 渲染裁剪参数：仅影响可见性，不影响判定/时序
var _note_cull_margin_top: float = 120.0
var _note_cull_margin_bottom: float = 180.0
var spark_presets: Dictionary = {}
var spark_scalings: Dictionary = {}
###################################

## note_judged(result: String, offset: String, block_type: int, timing_sec: float, signed_offset_sec: float)
## block_type: KeySequenceManager.BlockType 值 (0=INSTANT,1=SHORT,2=LONG)
## timing_sec: 偏差绝对值(秒)  signed_offset_sec: 带符号偏差(秒)
signal note_judged(result: String, offset: String, block_type: int, timing_sec: float, signed_offset_sec: float)
## long_holding(long_instance_id: int) - 长条持续加分 tick
signal long_holding(long_instance_id: int)

# 音符相关
var lane_width: float = 0
var active_notes: Array = []  # 存储活跃的音符
var _notes_by_lane: Dictionary = {}  # 按轨道分组索引：{lane: Array[FlowNote]}，加速音符判定查找

@onready var nt_b = load("res://UI/Views/PlayView/note_block.tscn").instantiate()
@onready var nt_s = load("res://UI/Views/PlayView/note_slide.tscn").instantiate()
@onready var nt_l = load("res://UI/Views/PlayView/note_long.tscn").instantiate()
@onready var particle = load("res://UI/Views/PlayView/particleSquare.tscn").instantiate()

# 粒子对象池：预创建固定数量实例并复用，避免每次按键 duplicate()+queue_free()
const _PARTICLE_POOL_SIZE = 12
var _particle_pool: Array = []

# 音符对象池：分离三种类型，避免重复创建节点（第1阶段：基础框架）
const _NOTE_POOL_BLOCK_SIZE = 30   # Block 音符池大小
const _NOTE_POOL_SLIDE_SIZE = 30   # Slide 音符池大小
const _NOTE_POOL_LONG_SIZE = 6     # Long 音符池大小
var _note_pool_block: Array[Node] = []   # Block 音符复用池
var _note_pool_slide: Array[Node] = []   # Slide 音符复用池
var _note_pool_long: Array[Node] = []    # Long 音符复用池

var _note_fall_calculator: NoteFallCalculator = NoteFallCalculator.new()

var parent_node: Node = null

# 【方案C】从PlayView同步的当前播放时间（毫秒）
## 这个时间来自 MidiPlaybackManager.get_position_ms()，已包含缓冲补偿
## 用于确保note判定与MIDI播放位置完全同步
var _synced_current_time: float = 0.0

## 音频延迟补偿（毫秒，正值=音频输出有延迟需延后视觉/判定，负值=音频提前需提前视觉/判定）
## 来自 ConfigManager [Gameplay] audio_playback_delay，由 DelayAdjust 校准得出
## 应用方式：仅在 set_current_time 和 _get_realtime_position_ms 两个入口减去此值
## _judge_note 的 input_time_ms 已来自上述入口（或 note.start_time 与 current_time 同坐标系），不再二次减
## 效果：音符视觉下落与判定时机同步延后/提前，使点击时机与音频到达耳朵的时刻对齐
var _audio_playback_delay_ms: float = 0.0

# 修改为从PlayView传入的音符列表
var notes_list: Array[FlowNote] = []  # 移除测试用的音符
var note_idx: int = 0

# 多点触控支持
var touch_positions: Dictionary = {}  # 存储每个触摸点的位置
var active_holds: Dictionary = {}     # 存储正在按住长条音符的触摸点ID和对应的音符

# 输入去重：防止桌面环境下鼠标与触摸事件双触发导致一次点击判定多个音符
const _PRESS_DEDUP_MS: float = 5.0
const _PRESS_DEDUP_DISTANCE: float = 6.0
var _last_press_time_ms: float = -1000000.0
var _last_press_pos: Vector2 = Vector2(-1000000.0, -1000000.0)
var _last_press_was_mouse: bool = false

var pressed_keys: Dictionary = {}

func init_flow_area():
	# 保存 notes_list，因为 clear_flow_area() 会清空它
	var saved_notes = notes_list.duplicate()
	clear_flow_area()
	notes_list = saved_notes
	note_idx = 0

	if EvtBus and not EvtBus.config_changed.is_connected(_on_config_changed):
		EvtBus.config_changed.connect(_on_config_changed)

	auto_mode = ConfigManager.instance.get_int("Playback", "auto_mode", 0) == 1
	
	# 从配置读取判定模式
	judge_mode = ConfigManager.instance.get_int("Judge", "touch_judging_criteria", NoteJudger.JudgeMode.BEST_TIMING_FIFO)
	check_slide_when_finger_up = ConfigManager.instance.get_int("Judge", "check_instant_blocks_when_finger_up", 1) == 1
	only_perfect_slides = ConfigManager.instance.get_int("Judge", "only_perfect_instant_blocks_before_judge", 0) == 1
	# 判定时间偏移（由 DelayAdjust 校准得出，影响判定时机与音符视觉下落）
	_audio_playback_delay_ms = float(ConfigManager.instance.get_int("Gameplay", "audio_playback_delay", 0))
	
	# 从配置读取比例系数
	var block_size_ratio = ConfigManager.instance.get_float("Appearance", "block_size", 6.5)
	var block_judge_ratio = ConfigManager.instance.get_float("Judge", "block_judging_width", 1.0)
	
	_apply_note_fall_config_from_settings()
	var lc = parent_node.get_lane_count()
	
	# 计算可游玩区域宽度
	var safe_width: float = max(1.0, get_viewport().get_visible_rect().size.x - 2.0 * float(parent_node.lane_padding))
	
	# 根据比例计算音符宽度（最小10px防止过小）
	note_visual_width = max(10.0, safe_width / block_size_ratio)
	note_judge_width = max(10.0, note_visual_width * block_judge_ratio)
	
	# 计算轨道间距
	if lc <= 1:
		lane_width = safe_width
	else:
		lane_width = (safe_width - float(note_visual_width)) / float(lc - 1)
	
	# 设置判定线位置
	jl.position.y = get_viewport().get_visible_rect().size.y - parent_node.judge_line_offset_y
	
	# 配置初始化
	spark_presets["Perfect"] = ConfigManager.instance.get_int("Lane", "perfect_spark_preset", 0)
	spark_scalings["Perfect"] = ConfigManager.instance.get_float("Lane", "perfect_spark_scaling", 50)
	spark_presets["Great"] = ConfigManager.instance.get_int("Lane", "great_spark_preset", 0)
	spark_scalings["Great"] = ConfigManager.instance.get_float("Lane", "great_spark_scaling", 50)
	spark_presets["Good"] = ConfigManager.instance.get_int("Lane", "good_spark_preset", 0)
	spark_scalings["Good"] = ConfigManager.instance.get_float("Lane", "good_spark_scaling", 50)
	spark_presets["Bad"] = ConfigManager.instance.get_int("Lane", "bad_spark_preset", 0)
	spark_scalings["Bad"] = ConfigManager.instance.get_float("Lane", "bad_spark_scaling", 50)
	_init_particle_pool()
	_init_note_pool()
	# 应用解析后的颜色（由 load_note_skin + PlayView 随机颜色生成共同决定）
	# 池刚初始化时只有模板颜色，refresh_note_colors 会同步更新池中节点
	refresh_note_colors()

	set_note_width(note_visual_width)

	# 预计算下落距离和速度
	_note_fall_distance = jl.position.y + _note_max_size_y
	_note_fall_speed = _note_fall_calculator.compute_speed_px_per_ms(_note_fall_distance, _note_fall_time_seconds)

func _apply_note_fall_config_from_settings() -> void:
	var note_fall_time = ConfigManager.instance.get_float("Generator", "note_fall_time", 1.5)
	note_generation_lead_time = max(1.0, note_fall_time * 1000.0)

	var note_fall_mode = ConfigManager.instance.get_int("Generator", "note_fall_mode", 0)
	var note_fall_speed_after_judge_multiplier = ConfigManager.instance.get_float("Generator", "note_fall_speed_after_judge_multiplier", -1.0)
	if note_fall_speed_after_judge_multiplier <= 0.0:
		note_fall_speed_after_judge_multiplier = ConfigManager.instance.get_float("Appearance", "grace_time", 1.0)

	match note_fall_mode:
		0:
			var uniform_config = EasingMapper.get_preset_config(0)
			trans_before_line = EasingMapper.string_to_trans(uniform_config["before_func"])
			ease_before_line = EasingMapper.string_to_ease(uniform_config["before_phase"])
			trans_after_line = EasingMapper.string_to_trans(uniform_config["after_func"])
			ease_after_line = EasingMapper.string_to_ease(uniform_config["after_phase"])
		1:
			var accelerate_config = EasingMapper.get_preset_config(1)
			trans_before_line = EasingMapper.string_to_trans(accelerate_config["before_func"])
			ease_before_line = EasingMapper.string_to_ease(accelerate_config["before_phase"])
			trans_after_line = EasingMapper.string_to_trans(accelerate_config["after_func"])
			ease_after_line = EasingMapper.string_to_ease(accelerate_config["after_phase"])
		2:
			var before_func = ConfigManager.instance.get_string("Generator", "note_fall_easing_before_func", "LINEAR")
			var before_phase = ConfigManager.instance.get_string("Generator", "note_fall_easing_before_phase", "IN")
			var after_func = ConfigManager.instance.get_string("Generator", "note_fall_easing_after_func", "LINEAR")
			var after_phase = ConfigManager.instance.get_string("Generator", "note_fall_easing_after_phase", "IN")

			trans_before_line = EasingMapper.string_to_trans(before_func)
			ease_before_line = EasingMapper.string_to_ease(before_phase)
			trans_after_line = EasingMapper.string_to_trans(after_func)
			ease_after_line = EasingMapper.string_to_ease(after_phase)
		_:
			var fallback_config = EasingMapper.get_preset_config(0)
			trans_before_line = EasingMapper.string_to_trans(fallback_config["before_func"])
			ease_before_line = EasingMapper.string_to_ease(fallback_config["before_phase"])
			trans_after_line = EasingMapper.string_to_trans(fallback_config["after_func"])
			ease_after_line = EasingMapper.string_to_ease(fallback_config["after_phase"])

	_note_fall_time_seconds = note_fall_time
	_note_fall_speed_after_judge_multiplier = max(0.01, note_fall_speed_after_judge_multiplier)

func _on_config_changed(key: String, section: String, value: Variant) -> void:
	if section == "Playback" and key == "auto_mode":
		auto_mode = int(value) == 1
		GLogger.info("FlowArea auto_mode updated: %s" % ("ON" if auto_mode else "OFF"), "FlowArea")
		return

	if section == "Gameplay" and key == "audio_playback_delay":
		_audio_playback_delay_ms = float(value)
		return

	if section == "Judge":
		if key == "touch_judging_criteria":
			judge_mode = int(value)
			return
		if key == "block_judging_width":
			# 需要重新计算音符尺寸
			_recalculate_note_dimensions()
			return
		if key == "check_instant_blocks_when_finger_up":
			check_slide_when_finger_up = int(value) == 1
			return
		if key == "only_perfect_instant_blocks_before_judge":
			only_perfect_slides = int(value) == 1
			return

	if section == "Appearance" and key == "block_size":
		# 需要重新计算音符尺寸
		_recalculate_note_dimensions()
		return

	if section != "Generator":
		return

	if key in [
		"note_fall_time",
		"note_fall_mode",
		"note_fall_speed_after_judge_multiplier",
		"note_fall_easing_before_func",
		"note_fall_easing_before_phase",
		"note_fall_easing_after_func",
		"note_fall_easing_after_phase"
	]:
		_apply_note_fall_config_from_settings()
		_note_fall_distance = jl.position.y + _note_max_size_y
		_note_fall_speed = _note_fall_calculator.compute_speed_px_per_ms(_note_fall_distance, _note_fall_time_seconds)
		GLogger.info("Note fall config hot-reloaded: [%s] %s=%s" % [section, key, str(value)], "FlowArea")

## 重新计算音符尺寸（根据比例系数）
func _recalculate_note_dimensions() -> void:
	var block_size_ratio = ConfigManager.instance.get_float("Appearance", "block_size", 6.5)
	var block_judge_ratio = ConfigManager.instance.get_float("Judge", "block_judging_width", 1.0)
	var safe_width: float = max(1.0, get_viewport().get_visible_rect().size.x - 2.0 * float(parent_node.lane_padding))
	
	note_visual_width = max(10.0, safe_width / block_size_ratio)
	note_judge_width = max(10.0, note_visual_width * block_judge_ratio)
	
	set_note_width(note_visual_width)
	GLogger.info("Note dimensions recalculated: visual_width=%d, judge_width=%d" % [int(note_visual_width), int(note_judge_width)], "FlowArea")

# 修改音符颜色
func set_note_color(type: FlowNote.NoteType, cl: Color):
	match type:
		FlowNote.NoteType.Block:
			nt_b.get_node("core").modulate = cl
		FlowNote.NoteType.Slide:
			nt_s.get_node("core").modulate = cl
		FlowNote.NoteType.Long:
			for i in nt_l.get_node("VBoxC").get_children():
				i.get_node("core").modulate = cl

# 创建完全透明的纹理用于缺失贴图回退
func _create_transparent_texture(width: int = 64, height: int = 64) -> Texture2D:
	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var texture = ImageTexture.create_from_image(image)
	return texture

# 修改音符皮肤 数组顺序[短块图片，短块上色区图片，滑块。。。，长条（从头到尾）]
func set_note_texture(texture_array: Array):
	# 创建透明纹理作为回退
	var transparent_texture = _create_transparent_texture()
	
	# 短块
	if texture_array.size() > 0 and texture_array[0]:
		nt_b.texture = texture_array[0]
	else:
		nt_b.texture = transparent_texture
	
	if texture_array.size() > 1 and texture_array[1]:
		nt_b.get_node("core").texture = texture_array[1]
	else:
		nt_b.get_node("core").texture = transparent_texture
	
	# 滑块
	if texture_array.size() > 2 and texture_array[2]:
		nt_s.texture = texture_array[2]
	else:
		nt_s.texture = transparent_texture
	
	if texture_array.size() > 3 and texture_array[3]:
		nt_s.get_node("core").texture = texture_array[3]
	else:
		nt_s.get_node("core").texture = transparent_texture
	
	# 长条头部
	if texture_array.size() > 4 and texture_array[4]:
		nt_l.get_node("VBoxC/head").texture = texture_array[4]
	else:
		nt_l.get_node("VBoxC/head").texture = transparent_texture
	
	if texture_array.size() > 5 and texture_array[5]:
		nt_l.get_node("VBoxC/head/core").texture = texture_array[5]
	else:
		nt_l.get_node("VBoxC/head/core").texture = transparent_texture
	
	# 长条身体
	if texture_array.size() > 6 and texture_array[6]:
		nt_l.get_node("VBoxC/body").texture = texture_array[6]
	else:
		nt_l.get_node("VBoxC/body").texture = transparent_texture
	
	if texture_array.size() > 7 and texture_array[7]:
		nt_l.get_node("VBoxC/body/core").texture = texture_array[7]
	else:
		nt_l.get_node("VBoxC/body/core").texture = transparent_texture
	
	# 长条尾部
	if texture_array.size() > 8 and texture_array[8]:
		nt_l.get_node("VBoxC/tail").texture = texture_array[8]
	else:
		nt_l.get_node("VBoxC/tail").texture = transparent_texture
	
	if texture_array.size() > 9 and texture_array[9]:
		nt_l.get_node("VBoxC/tail/core").texture = texture_array[9]
	else:
		nt_l.get_node("VBoxC/tail/core").texture = transparent_texture

# 加载并应用指定皮肤的贴图
func load_note_skin(skin_name: String = "旧版2 [内置]") -> void:
	# 获取皮肤贴图字典
	var skin_textures = {}
	if SkinMGR:
		skin_textures = SkinMGR.get_skin_textures(skin_name)
		# 加载皮肤完整配置（新结构）
		_skin_config = SkinMGR.get_skin_config(skin_name)
		# 读取光效总开关与长条连接模式
		_is_glow_enabled = SkinMGR.is_glow_enabled(skin_name)
		_long_connect_mode = SkinMGR.get_long_connect_mode(skin_name)

	# 更新core贴图标记
	_skin_has_short_core = skin_textures.has("short_core")
	_skin_has_instant_core = skin_textures.has("instant_core")
	_skin_has_long_core = skin_textures.has("long_b_core") or skin_textures.has("long_f_core") or skin_textures.has("long_t_core")

	# 构建纹理数组，按顺序: short, short_core, instant, instant_core, long_b, long_b_core, long_f, long_f_core, long_t, long_t_core
	var texture_array = [
		skin_textures.get("short"),
		skin_textures.get("short_core"),
		skin_textures.get("instant"),
		skin_textures.get("instant_core"),
		skin_textures.get("long_b"),
		skin_textures.get("long_b_core"),
		skin_textures.get("long_f"),
		skin_textures.get("long_f_core"),
		skin_textures.get("long_t"),
		skin_textures.get("long_t_core")
	]

	# 应用贴图
	set_note_texture(texture_array)

	# 应用 long-f 中部贴图模式（repeat / stretch）
	_apply_long_f_mode()

	# 解析音符颜色（基于新皮肤配置 + 已有 _random_colors）
	_resolve_note_colors()
	# 重新应用颜色到模板（load_note_skin 后 _init_note_pool 会用新模板重建）
	set_note_color(FlowNote.NoteType.Block, _resolved_colors.get("short", Color.WHITE))
	set_note_color(FlowNote.NoteType.Slide, _resolved_colors.get("instant", Color.WHITE))
	set_note_color(FlowNote.NoteType.Long, _resolved_colors.get("long", Color.WHITE))

	# 清空音符对象池，使下次 _init_note_pool 用新皮肤纹理重建节点
	_clear_and_free_note_pools()

	print("[FlowArea] Loaded note skin: %s, glow=%s, connect_mode=%s, core flags: short=%s, instant=%s, long=%s" % [skin_name, _is_glow_enabled, _long_connect_mode, _skin_has_short_core, _skin_has_instant_core, _skin_has_long_core])

## 根据 _skin_config + _random_colors 解析出最终音符颜色
## 规则：
##   custom_color 主开关 OFF → 该类型 color = Color.WHITE
##   主开关 ON + enable_color ON + random_color ON → color = _random_colors[key]
##   主开关 ON + enable_color ON + random_color OFF → color = config[key].color
##   主开关 ON + enable_color OFF → color = Color.WHITE
func _resolve_note_colors() -> void:
	_resolved_colors.clear()
	var custom_color_on: bool = false
	if _skin_config.has("general"):
		custom_color_on = bool(_skin_config["general"].get("custom_color", false))

	for key in ["short", "instant", "long"]:
		var color := Color.WHITE
		if custom_color_on and _skin_config.has(key):
			var sec: Dictionary = _skin_config[key]
			if bool(sec.get("enable_color", false)):
				if bool(sec.get("random_color", false)) and _random_colors.has(key):
					color = _random_colors[key]
				else:
					color = sec.get("color", Color.WHITE)
		_resolved_colors[key] = color

## 重新解析颜色并应用到模板 + 对象池中所有节点（用于随机颜色刷新等场景）
## 当对象池已存在（如 retry）时，set_note_color 只改模板不影响池中已创建节点，
## 此方法会遍历池中节点同步更新 core.modulate 和光效颜色
func refresh_note_colors() -> void:
	_resolve_note_colors()
	set_note_color(FlowNote.NoteType.Block, _resolved_colors.get("short", Color.WHITE))
	set_note_color(FlowNote.NoteType.Slide, _resolved_colors.get("instant", Color.WHITE))
	set_note_color(FlowNote.NoteType.Long, _resolved_colors.get("long", Color.WHITE))
	# 同步更新池中已存在的节点
	for note in _note_pool_block:
		if is_instance_valid(note):
			note.get_node("core").modulate = _resolved_colors.get("short", Color.WHITE)
			_apply_note_glow(note, _resolved_colors.get("short", Color.WHITE), FlowNote.NoteType.Block)
	for note in _note_pool_slide:
		if is_instance_valid(note):
			note.get_node("core").modulate = _resolved_colors.get("instant", Color.WHITE)
			_apply_note_glow(note, _resolved_colors.get("instant", Color.WHITE), FlowNote.NoteType.Slide)
	for note in _note_pool_long:
		if is_instance_valid(note):
			for i in note.get_node("VBoxC").get_children():
				i.get_node("core").modulate = _resolved_colors.get("long", Color.WHITE)
			_apply_note_glow(note, _resolved_colors.get("long", Color.WHITE), FlowNote.NoteType.Long)

# 根据皮肤配置设置 long-f 中部贴图的应用方式
# repeat → 水平拉伸+垂直重复（用 shader 实现）；stretch → 竖直拉伸（默认 STRETCH_SCALE）
func _apply_long_f_mode() -> void:
	var mode = "repeat"
	if _skin_config.has("long") and _skin_config["long"].has("long_f_mode"):
		mode = _skin_config["long"]["long_f_mode"]
	_long_f_mode = mode
	# 应用到模板
	_apply_long_f_mode_to_body(nt_l.get_node_or_null("VBoxC/body"))
	_apply_long_f_mode_to_body(nt_l.get_node_or_null("VBoxC/body/core"))
	# 应用到池中所有 long note（皮肤热切换时同步更新）
	for note_node in _note_pool_long:
		if is_instance_valid(note_node):
			_apply_long_f_mode_to_body(note_node.get_node_or_null("VBoxC/body"))
			_apply_long_f_mode_to_body(note_node.get_node_or_null("VBoxC/body/core"))

# 设置单个 body 节点的 long-f 贴图模式
# repeat 模式：附加 LongBodyRepeat shader（水平 UV 0-1 拉伸，垂直 UV 重复）
# stretch 模式：移除 material，恢复默认 STRETCH_SCALE 行为
func _apply_long_f_mode_to_body(_tr) -> void:
	if not (_tr is TextureRect):
		return
	if _long_f_mode == "repeat":
		var mat = _tr.material
		if mat == null or not (mat is ShaderMaterial) or (mat as ShaderMaterial).shader != LONG_BODY_REPEAT_SHADER:
			var new_mat := ShaderMaterial.new()
			new_mat.shader = LONG_BODY_REPEAT_SHADER
			_tr.material = new_mat
	else:
		_tr.material = null

# 清空音符对象池中所有节点（皮肤热切换时调用，使下次 _init_note_pool 用新模板重建）
func _clear_and_free_note_pools() -> void:
	for note in _note_pool_block:
		if is_instance_valid(note):
			note.queue_free()
	_note_pool_block.clear()
	for note in _note_pool_slide:
		if is_instance_valid(note):
			note.queue_free()
	_note_pool_slide.clear()
	for note in _note_pool_long:
		if is_instance_valid(note):
			note.queue_free()
	_note_pool_long.clear()

# 确保节点持有独立的 repeat shader material 副本（避免多 note 共享同一 material）
func _ensure_independent_repeat_material(_tr) -> void:
	if not (_tr is TextureRect):
		return
	var mat = _tr.material
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader == LONG_BODY_REPEAT_SHADER:
		_tr.material = (mat as ShaderMaterial).duplicate()

# 更新长条 body 的垂直重复次数（每帧调用，因 body 高度动态变化）
# v_repeat = body 高度 / 贴图原始高度；body 比贴图短时至少重复 1 次（拉伸显示）
func _update_long_body_v_repeat(note: FlowNote, body_height: float) -> void:
	if _long_f_mode != "repeat" or body_height <= 0.0:
		return
	_set_v_repeat_for(note.cached_body, body_height)
	var body_core = note.rect.get_node_or_null("VBoxC/body/core")
	_set_v_repeat_for(body_core, body_height)

func _set_v_repeat_for(_tr, body_height: float) -> void:
	if not (_tr is TextureRect):
		return
	var mat = _tr.material
	if not (mat is ShaderMaterial):
		return
	if (mat as ShaderMaterial).shader != LONG_BODY_REPEAT_SHADER:
		return
	var tex = _tr.texture
	var tex_h = 1.0
	if tex and tex.get_height() > 0:
		tex_h = float(tex.get_height())
	var v_repeat = max(1.0, body_height / tex_h)
	(mat as ShaderMaterial).set_shader_parameter("v_repeat", v_repeat)

# 修改音符宽度
func set_note_width(wid: float):
	for nt in [nt_b, nt_s, nt_l]:
		# 关键：使用 custom_minimum_size 而非 size.x（修复 VBoxContainer 覆盖问题）
		nt.custom_minimum_size = Vector2(wid, 0)
		nt.size.x = wid  # 保留兼容性
		if nt == nt_l:
			nt = nt.get_node("VBoxC/head")
		_note_max_size_y = _note_max_size_y if _note_max_size_y > nt.size.y else nt.size.y

func clear_flow_area():
	# 斩断 FlowNote ↔ GameSequence 的 RefCounted 循环引用，释放旧音符
	if notes_list:
		for note in notes_list:
			if note.game_sequence_ref != null:
				note.game_sequence_ref.flow_note_ref = null
				note.game_sequence_ref = null
		notes_list.clear()

	for note in active_notes.duplicate():
		if note.tween:
			note.tween.kill()
		if note.rect:
			note.rect.visible = false
			# 改为回池而不是 queue_free()
			_return_note_to_pool(note.rect, note.type)
			note.rect = null

	active_notes.clear()
	_clear_lane_index()
	active_holds.clear()
	touch_positions.clear()
	pressed_keys.clear()
	note_idx = 0

## 检查是否还有活跃音符（用于游戏结束后等待音符自然消除）
func has_active_notes() -> bool:
	return active_notes.size() > 0


var _note_max_size_y: float = 0
var _note_fall_speed: float = 0
var _note_fall_distance: float = 0

func _create_note(tp: FlowNote.NoteType, x: float, _lane_idx: int = -1) -> Node:
	# 改为从池中取而不是 duplicate()
	var note_rect: Node = _get_note_from_pool(tp)
	note_rect.visible = true  # 从池中取出后立即可见

	# _reset_note_for_reuse 会将 core.modulate 重置为 WHITE，此处需重新应用解析后的颜色
	# 颜色由 _resolved_colors 决定（custom_color + enable_color + random_color 综合解析）
	var resolved_color := _get_resolved_color_for_type(tp)
	match tp:
		FlowNote.NoteType.Block:
			note_rect.get_node("core").modulate = resolved_color
		FlowNote.NoteType.Slide:
			note_rect.get_node("core").modulate = resolved_color
		FlowNote.NoteType.Long:
			for i in note_rect.get_node("VBoxC").get_children():
				i.get_node("core").modulate = resolved_color

	# 应用光效（颜色由 _resolved_colors 决定）
	_apply_note_glow(note_rect, resolved_color, tp)
	# base position 只承载 x（轨道偏移），y 恒为 0；
	# 动态下落 y 走 offset_transform_position，绕过 Control 布局重算
	note_rect.position = Vector2(x, 0)
	note_rect.offset_transform_position = Vector2.ZERO

	return note_rect

## 根据 NoteType 返回 _resolved_colors 中对应的颜色
func _get_resolved_color_for_type(tp: FlowNote.NoteType) -> Color:
	match tp:
		FlowNote.NoteType.Block:
			return _resolved_colors.get("short", Color.WHITE)
		FlowNote.NoteType.Slide:
			return _resolved_colors.get("instant", Color.WHITE)
		FlowNote.NoteType.Long:
			return _resolved_colors.get("long", Color.WHITE)
	return Color.WHITE

func _spawn_note(note_index: int) -> void:
	if note_index >= notes_list.size():
		return
	
	var nt = notes_list[note_index]
	# 关键：重置 Note 数据对象的判定状态（修复多音符同时判定问题）
	nt.is_judged = false
	nt.can_judge = false
	nt.is_held = false
	nt.held_by_touch_id = -1
	nt.cooldown = 0
	nt.judge_line_passed = false
	if nt.type == FlowNote.NoteType.Long:
		nt.long_head_height = 0.0
		nt.long_tail_height = 0.0

	# 计算音符位置
	var beam_node_for_note = parent_node.lane_area.get_lane_by_idx(nt.lane)
	var beam_margin = max(0.0, (beam_node_for_note.beam_size.x - note_visual_width) / 2.0)
	var start_x = beam_node_for_note.position.x + beam_margin
	
	var rect = _create_note(nt.type, start_x, nt.lane)
	nt.set_rect(rect)

	# 计算下落位置
	var note_half = rect.size.y/2
	if nt.type == FlowNote.NoteType.Long:
		await get_tree().process_frame
		nt.long_tail_height = nt.rect.get_node("VBoxC/tail").size.y
		nt.long_head_height = nt.rect.get_node("VBoxC/head").size.y
		nt.cached_vbox = nt.rect.get_node("VBoxC")
		nt.cached_head = nt.rect.get_node("VBoxC/head")
		nt.cached_tail = nt.rect.get_node("VBoxC/tail")
		nt.cached_body = nt.rect.get_node("VBoxC/body")
		# repeat 模式下，确保每个 note 实例的 body material 是独立副本
		# （否则多根长条共享同一 material，v_repeat 会互相覆盖）
		if _long_f_mode == "repeat":
			_ensure_independent_repeat_material(nt.cached_body)
			_ensure_independent_repeat_material(nt.rect.get_node_or_null("VBoxC/body/core"))
		_apply_note_glow(nt.rect, _resolved_colors.get("long", Color.WHITE), FlowNote.NoteType.Long)
		note_half = nt.long_tail_height / 2.0
	
	var target_pos_y = jl.position.y - note_half
	nt.rect.offset_transform_position.y = target_pos_y - _note_fall_distance

	if nt.type == FlowNote.NoteType.Long:
		active_notes.append(nt)
		_add_note_to_lane_index(nt)
		nt.tween = null
		_update_long_note_fall(nt, _synced_current_time)
		return

	# Block/Slide: 使用 synced time 驱动 (与 Long 一致), 不再使用 Tween
	# 消除 Tween 墙钟时间与判定 MIDI 时间之间的漂移
	active_notes.append(nt)
	_add_note_to_lane_index(nt)
	nt.tween = null
	_update_block_note_fall(nt, _synced_current_time)

func _compute_center_y_by_judge_time(judge_time_ms: float, current_time_ms: float, half_height: float) -> float:
	var pre_ms = max(1.0, _note_fall_time_seconds * 1000.0)
	var spawn_time_ms = judge_time_ms - pre_ms

	if current_time_ms <= judge_time_ms:
		if current_time_ms < spawn_time_ms:
			# 提前生成时继续保持匀速下落，避免音符在顶端静止等待
			var early_dt_ms = spawn_time_ms - current_time_ms
			return jl.position.y - _note_fall_distance - early_dt_ms * _note_fall_speed
		var progress = clamp((current_time_ms - spawn_time_ms) / pre_ms, 0.0, 1.0)
		var eased = _note_fall_calculator.evaluate_curve_progress(progress, trans_before_line, ease_before_line)
		return jl.position.y - _note_fall_distance + eased * _note_fall_distance

	var window_y = get_viewport().get_visible_rect().size.y
	var after_distance = max(1.0, window_y - jl.position.y + half_height)
	var after_time_ms = max(
		1.0,
		_note_fall_calculator.compute_after_line_duration_seconds(after_distance, _note_fall_speed, _note_fall_speed_after_judge_multiplier) * 1000.0
	)
	var after_progress = clamp((current_time_ms - judge_time_ms) / after_time_ms, 0.0, 1.0)
	var eased_after = _note_fall_calculator.evaluate_curve_progress(after_progress, trans_after_line, ease_after_line)
	return jl.position.y + eased_after * after_distance

## Block/Slide 音符的 synced time 驱动位置更新 (替代 Tween)
## 每帧由 _process 调用, 根据 _synced_current_time 计算音符位置
## 同时处理过线回调 (Slide 检查/auto_mode) 和 Miss 判定
func _update_block_note_fall(note: FlowNote, current_time_ms: float) -> void:
	if not note.rect:
		return

	var rect_ctrl := note.rect as Control
	var half_height = rect_ctrl.size.y * 0.5
	var center_y = _compute_center_y_by_judge_time(note.start_time, current_time_ms, half_height)
	rect_ctrl.offset_transform_position.y = center_y - half_height

	# 过线回调: 音符首次到达/超过判定线时触发 (原 Tween.finished 逻辑)
	if not note.judge_line_passed and current_time_ms >= note.start_time:
		note.judge_line_passed = true
		if note.is_judged or note.rect == null:
			return
		if note.type == FlowNote.NoteType.Slide:
			_check_slide_stat(note)
		if note.is_judged or note.rect == null:
			return
		if auto_mode:
			_auto_click(note)

	# Miss 判定: 音符超出窗口底部且未被击打 (原第二 Tween.finished 逻辑)
	if not note.is_judged and note.rect != null:
		var window_y = _cached_viewport_height
		if center_y >= window_y:
			_remove_note(note)
			note_judged.emit("Miss", "", note.type, 1.0, 0.0)

func _update_long_note_fall(note: FlowNote, current_time_ms: float) -> void:
	if not note.rect:
		return

	var head := note.cached_head as Control
	var tail := note.cached_tail as Control

	if note.long_head_height <= 0.0:
		note.long_head_height = head.size.y
	if note.long_tail_height <= 0.0:
		note.long_tail_height = tail.size.y

	var head_half = note.long_head_height * 0.5
	var tail_half = note.long_tail_height * 0.5

	var head_center = _compute_center_y_by_judge_time(note.start_time, current_time_ms, head_half)
	if note.is_held:
		head_center = jl.position.y
	var tail_center = _compute_center_y_by_judge_time(note.start_time + max(0.0, note.duration), current_time_ms, tail_half)

	var tail_top = tail_center - tail_half
	var tail_bottom = tail_center + tail_half
	var tail_judge_y = tail_center  # 使用 tail 中心而非顶部判定，避免特效位置过低
	var head_top = head_center - head_half

	# 长条连接模式：edge（边缘连接，body 从 tail_bottom 到 head_top）
	# 或 center（中心连接，body 从 tail_center 到 head_center，head/tail 各向 body 偏移半高）
	var body_target_h: float
	var root_offset_y: float
	if _long_connect_mode == "center":
		# 中心连接：body 覆盖纯时长距离（head_center - tail_center）
		body_target_h = max(0.0, head_center - tail_center)
		note.rect.size.y = note.long_tail_height + body_target_h + note.long_head_height
		# tail 向 body 靠拢半高（下移半个 tail 高度）
		tail.offset_transform_position.y = note.long_tail_height * 0.5
		# head 向 body 靠拢半高（上移半个 head 高度）
		head.offset_transform_position.y = -note.long_head_height * 0.5
		# root 锚定：使 tail 的视觉中心 = tail_center
		# root 顶部 = tail_center - tail_half - tail_half（因为 tail 中心相对 root 顶部偏移 tail_half + tail.offset）
		# 简化：root 顶部 = tail_top - tail_half（让 tail 的视觉中心落在 tail_center）
		root_offset_y = tail_top - note.long_tail_height * 0.5
	else:
		# 边缘连接（默认）：body 从 tail_bottom 到 head_top
		body_target_h = max(0.0, head_top - tail_bottom)
		note.rect.size.y = note.long_tail_height + body_target_h + note.long_head_height
		tail.offset_transform_position.y = 0.0
		head.offset_transform_position.y = 0.0
		root_offset_y = tail_top

	# repeat 模式下，按 body 高度更新垂直重复次数
	_update_long_body_v_repeat(note, body_target_h)
	note.rect.offset_transform_position.y = root_offset_y

	if not note.is_judged and not note.is_held and note.held_by_touch_id < 0:
		var window_y = _cached_viewport_height
		if tail_judge_y >= window_y:
			_remove_note(note)
			note_judged.emit("Miss", "", note.type, 1.0, 0.0)

func _update_note_visibility(note: FlowNote) -> void:
	# 仅做渲染层裁剪：不移除，不影响判定，仅设置 visible
	if not note or not note.rect:
		return

	var rect_ctrl := note.rect as Control
	if rect_ctrl == null:
		return

	var top_y := rect_ctrl.position.y + rect_ctrl.offset_transform_position.y
	var visual_height := rect_ctrl.size.y

	if note.type == FlowNote.NoteType.Long and rect_ctrl.has_node("VBoxC"):
		var vbox := note.cached_vbox as Control
		if vbox:
			visual_height = max(visual_height, vbox.size.y)

	var bottom_y = top_y + max(1.0, visual_height)
	var view_h := _cached_viewport_height
	var visible_top := -_note_cull_margin_top
	var visible_bottom := view_h + _note_cull_margin_bottom

	rect_ctrl.visible = (bottom_y >= visible_top and top_y <= visible_bottom)

var _auto_hold_idx: int = 0
func _auto_click(note: FlowNote):
	if not note.rect:
		return
	if parent_node.play_mode and note.game_sequence_ref:
		_trigger_midi_notes_from_sequence(note.game_sequence_ref)
	if note.type == FlowNote.NoteType.Long:
		_judge_note(note)
		_hold_long_note(_auto_hold_idx + 666, note)
		_auto_hold_idx += 1
	else:
		_judge_note(note)

# 因为在for循环遍历时erase会导致漏元素，所以推迟元素的移除
func _delay_free(list, item_to_free):
	list.erase(item_to_free)

# ========== 音符对象池管理（第1阶段：框架 + 第2阶段：重置逻辑） =========
func _get_pool_by_type(tp: FlowNote.NoteType) -> Array[Node]:
	"""根据音符类型返回对应的池"""
	match tp:
		FlowNote.NoteType.Block:
			return _note_pool_block
		FlowNote.NoteType.Slide:
			return _note_pool_slide
		FlowNote.NoteType.Long:
			return _note_pool_long
		_:
			return _note_pool_block  # 默认

func _get_pool_max_size(tp: FlowNote.NoteType) -> int:
	"""根据音符类型返回池的最大大小"""
	match tp:
		FlowNote.NoteType.Block:
			return _NOTE_POOL_BLOCK_SIZE
		FlowNote.NoteType.Slide:
			return _NOTE_POOL_SLIDE_SIZE
		FlowNote.NoteType.Long:
			return _NOTE_POOL_LONG_SIZE
		_:
			return _NOTE_POOL_BLOCK_SIZE

func _reset_note_for_reuse(note: Node, note_type: FlowNote.NoteType) -> void:
	"""重用节点前的完整状态重置。避免上一次使用的残留（第2阶段关键）"""
	
	# ✅ P0: 位置、可见性、基础属性
	# base position 由 _create_note 重新设置，此处只需重置偏移变换
	note.offset_transform_position = Vector2.ZERO
	note.visible = true
	note.modulate = Color.WHITE  # 清除任何颜色/透明残留
	note.z_index = 0
	note.scale = Vector2.ONE
	note.rotation = 0.0
	
	# ✅ P1: 关键 - 重新应用尺寸约束（用 custom_minimum_size 而非 size）
	# 这是之前失败的核心原因！VBoxContainer 会覆盖 size.x，但尊重 custom_minimum_size
	match note_type:
		FlowNote.NoteType.Block, FlowNote.NoteType.Slide:
			note.custom_minimum_size = Vector2(note_visual_width, 0)
		FlowNote.NoteType.Long:
			note.custom_minimum_size = Vector2(note_visual_width, 0)
			note.size.x = note_visual_width
			note.size.y = 0
			var body = note.get_node_or_null("VBoxC/body")
			if body:
				body.custom_minimum_size.y = 0
			# 重置 head/tail 的 offset_transform_position（center 模式会修改它）
			var head_node = note.get_node_or_null("VBoxC/head")
			if head_node:
				head_node.offset_transform_position = Vector2.ZERO
			var tail_node = note.get_node_or_null("VBoxC/tail")
			if tail_node:
				tail_node.offset_transform_position = Vector2.ZERO
			# 清理长条的长条特有状态
			note.set_meta("_needs_height_recalc", true)  # 标记需要在 _spawn_note 里重新计算
	
	# ✅ P2: 清理动画状态（关键！）
	if note.has_meta("_last_tween"):
		var old_tween = note.get_meta("_last_tween")
		if old_tween and old_tween.is_valid():
			old_tween.kill()
		note.remove_meta("_last_tween")
	
	# ✅ P3: 清理子节点状态
	for child in note.get_children():
		child.visible = true
		child.modulate = Color.WHITE

func _apply_note_glow(note_root: Node, c: Color, note_type: FlowNote.NoteType = FlowNote.NoteType.Block) -> void:
	# 光效总开关关闭 → 清除 material 并返回
	if not _is_glow_enabled or glow_intensity <= 0.0:
		_clear_glow(note_root)
		return

	# 光效颜色 = 音符颜色（已是 _resolved_colors 中的值，或白色）
	var glow_color = c
	if note_root is Panel:
		var vbox = note_root.get_node_or_null("VBoxC")
		if vbox:
			for child in vbox.get_children():
				if child is TextureRect and child.name != "body":
					var uv_center := Vector2(0.5, 0.60) if child.name == "head" else Vector2(0.5, 0.40)
					_ensure_glow_child(child, glow_color, FlowNote.NoteType.Long, uv_center)
		return
	_ensure_glow_child(note_root, glow_color, note_type)

## 清除音符节点的光效 material（关闭光效时调用）
func _clear_glow(note_root: Node) -> void:
	if note_root is Panel:
		var vbox = note_root.get_node_or_null("VBoxC")
		if vbox:
			for child in vbox.get_children():
				if child is TextureRect:
					var glow = child.get_node_or_null("_glow")
					if glow and glow.material:
						glow.material = null
		return
	if note_root is TextureRect:
		var glow = note_root.get_node_or_null("_glow")
		if glow and glow.material:
			glow.material = null

func _ensure_glow_child(tr_: TextureRect, col: Color, note_type: FlowNote.NoteType = FlowNote.NoteType.Block, uv_center: Vector2 = Vector2(0.5, 0.5)) -> void:
	var glow: ColorRect = tr_.get_node_or_null("_glow")
	if glow == null:
		push_warning("[FlowArea] Glow node not found in note")
		return
	if glow.material == null:
		var mat := ShaderMaterial.new()
		mat.shader = NOTE_GLOW_SHADER
		glow.material = mat
	var mat2 := glow.material as ShaderMaterial
	mat2.set_shader_parameter("glow_color", col)
	mat2.set_shader_parameter("glow_intensity", glow_intensity)
	mat2.set_shader_parameter("note_uv_center", uv_center)

	# 光晕大小：使用全局 glow_size（long 保留 +3 偏移以视觉加粗）
	match note_type:
		FlowNote.NoteType.Long:
			mat2.set_shader_parameter("glow_stretch", 0.6)
			mat2.set_shader_parameter("glow_size", glow_size + 3)
			mat2.set_shader_parameter("note_uv_half", Vector2(0.25, 0.1667))
		_:
			mat2.set_shader_parameter("glow_stretch", 1.0)
			mat2.set_shader_parameter("glow_size", glow_size)
			mat2.set_shader_parameter("note_uv_half", Vector2(0.1667, 0.1667))

func set_glow_params(intensity: float, size_val: float) -> void:
	glow_intensity = clampf(intensity, 0.0, 2.0)
	glow_size = clampf(size_val, 1.0, 30.0)

func _init_note_pool() -> void:
	"""初始化音符对象池：预创建固定数量的节点并复用"""
	# 池已初始化则复用（clear_flow_area 回池而非释放，池不会被清空）
	if not _note_pool_block.is_empty() or not _note_pool_slide.is_empty() or not _note_pool_long.is_empty():
		return
	# Block 音符池
	for _i in _NOTE_POOL_BLOCK_SIZE:
		var note_node = nt_b.duplicate()
		note_node.visible = false
		canvas.add_child(note_node)
		_note_pool_block.append(note_node)
	
	# Slide 音符池
	for _i in _NOTE_POOL_SLIDE_SIZE:
		var note_node = nt_s.duplicate()
		note_node.visible = false
		canvas.add_child(note_node)
		_note_pool_slide.append(note_node)
	
	# Long 音符池
	for _i in _NOTE_POOL_LONG_SIZE:
		var note_node = nt_l.duplicate()
		note_node.visible = false
		canvas.add_child(note_node)
		_note_pool_long.append(note_node)

	for note in _note_pool_block:
		_apply_note_glow(note, _resolved_colors.get("short", Color.WHITE), FlowNote.NoteType.Block)
	for note in _note_pool_slide:
		_apply_note_glow(note, _resolved_colors.get("instant", Color.WHITE), FlowNote.NoteType.Slide)
	for note in _note_pool_long:
		_apply_note_glow(note, _resolved_colors.get("long", Color.WHITE), FlowNote.NoteType.Long)

func _get_note_from_pool(tp: FlowNote.NoteType) -> Node:
	"""从池中获取一个音符节点，如果池空则创建新的"""
	var pool = _get_pool_by_type(tp)
	
	# 关键：清理池中已释放的节点（解决 queue_free 延迟导致的无效节点问题）
	while not pool.is_empty():
		var note = pool.pop_back()
		if is_instance_valid(note):
			# 从池取出后立即重置（修复尺寸、位置等问题）
			_reset_note_for_reuse(note, tp)
			return note
		# 否则继续弹出下一个（跳过已释放的节点）
	
	# 池空或所有节点都已释放：发出警告并创建新节点作为临时扩容
	GLogger.warning("Note pool overflow for type %d, creating new node" % tp, "FlowArea")
	var new_node = null
	match tp:
		FlowNote.NoteType.Block:
			new_node = nt_b.duplicate()
		FlowNote.NoteType.Slide:
			new_node = nt_s.duplicate()
		FlowNote.NoteType.Long:
			new_node = nt_l.duplicate()
		_:
			new_node = nt_b.duplicate()
	_reset_note_for_reuse(new_node, tp)
	canvas.add_child(new_node)
	return new_node

func _return_note_to_pool(note: Node, tp: FlowNote.NoteType) -> void:
	"""将音符节点返回到池中重复使用"""
	note.visible = false
	var pool = _get_pool_by_type(tp)
	if pool.size() < _get_pool_max_size(tp):
		# 仍有空间，加入池
		pool.append(note)
	else:
		# 池满时仍保留节点并加入池，避免隐藏孤儿节点和后续状态错乱
		note.offset_transform_position = Vector2.ZERO
		note.visible = false
		pool.append(note)

func _remove_note(note: FlowNote) -> void:
	if note.rect:
		# 改为回池而不是 queue_free()
		_return_note_to_pool(note.rect, note.type)
		note.rect = null
		call_deferred("_delay_free", active_notes, note)
	
	_remove_note_from_lane_index(note)
	
	if note.tween:
		note.tween.kill()
	
	# 如果是被按住的长条音符，清理触摸点
	if note.is_held and note.held_by_touch_id in active_holds:
		call_deferred("_delay_free", active_holds, note.held_by_touch_id)

# ========== 轨道索引维护（用于加速音符判定） ==========
func _add_note_to_lane_index(note: FlowNote) -> void:
	if not _notes_by_lane.has(note.lane):
		_notes_by_lane[note.lane] = []
	_notes_by_lane[note.lane].append(note)

func _remove_note_from_lane_index(note: FlowNote) -> void:
	if _notes_by_lane.has(note.lane):
		var lane_notes: Array = _notes_by_lane[note.lane]
		lane_notes.erase(note)

func _clear_lane_index() -> void:
	_notes_by_lane.clear()

## 获取触摸位置附近的轨道音符列表（当前轨道 ± 相邻轨道）
func _get_notes_near_lane(lane: int) -> Array:
	var result: Array = []
	for offset in [-1, 0, 1]:
		var check_lane = lane + offset
		if _notes_by_lane.has(check_lane):
			result.append_array(_notes_by_lane[check_lane])
	return result

## 根据触摸X坐标估算轨道索引
func _estimate_lane_from_x(x: float) -> int:
	var lc = parent_node.get_lane_count()
	if lc <= 1:
		return 0
	var safe_start = float(parent_node.lane_padding)
	var relative_x = x - safe_start
	var lane = int(relative_x / lane_width)
	return clampi(lane, 0, lc - 1)

func _gui_input(event: InputEvent) -> void:
	if parent_node.is_pause:
		accept_event()
		return

	var event_time_ms := _get_realtime_position_ms()
	if event is InputEventScreenTouch:
		if event.pressed:
			# 手指按下
			touch_positions[event.index] = event.position
			_handle_press(event.index, event.position, event_time_ms)
		else:
			# 手指松开
			if event.index in touch_positions:
				touch_positions.erase(event.index)
				_handle_release(event.index, event_time_ms)
			elif event.index >= 0:
				# 诊断：收到释放事件但无对应按下记录（可能是极快轻触导致按下事件被丢弃）
				push_warning("[FlowArea] Orphan touch release: index=%d, no corresponding press found" % event.index)
	
	# 处理触摸拖动
	elif event is InputEventScreenDrag:
		touch_positions[event.index] = event.position
		_handle_touch_drag(event.index, event.position)

	# 仅在拖动时检查 slide 可判定状态，避免点按误标记同轨道其他 slide 为可判定
	if event is InputEventScreenDrag and event.index in touch_positions:
		_check_slides_at_touch_pos(event.index, touch_positions[event.index], event_time_ms)

func _input(event: InputEvent) -> void:

	if ui.current_state == ui.UIState.PLAY_VIEW and event is InputEventKey:
		accept_event()
		if event.is_echo():
			return

		if parent_node.key_map and event.keycode in parent_node.key_map:
			if parent_node.is_pause:
				accept_event()
				return

			if event.pressed:
				var idx = parent_node.key_map.find(event.keycode)
				var event_time_ms := _get_realtime_position_ms()
				pressed_keys[event.keycode] = idx
				# 使用统一的判定函数，支持所有音符类型
				var bn = judge_note_at_lane(idx, idx, event_time_ms)
				if bn:
					if bn.type == FlowNote.NoteType.Long:
						_hold_long_note(event.keycode, bn)
				else:
					parent_node.lane_area.light_lane(idx)
			else:
				pressed_keys.erase(event.keycode)
				var released_lane = parent_node.key_map.find(event.keycode)
				_handle_release(event.keycode, _get_realtime_position_ms(), released_lane)
		elif event.keycode == KEY_ESCAPE and event.pressed:
			parent_node.show_or_hide_menu()

# 处理触摸按下
func _handle_press(touch_id: int, pos: Vector2, input_time_ms: float = -1.0) -> void:
	var judge_time_ms := input_time_ms
	if judge_time_ms < 0.0:
		judge_time_ms = _get_realtime_position_ms()

	# 去重逻辑：部分 Android 设备单次触摸会同时发送鼠标+触摸双事件
	# - 触摸事件间不互相去重（保留多指能力）
	# - 触摸事件仅在前一次是鼠标事件时去重（处理 Android 模拟鼠标）
	# - 鼠标事件始终去重（桌面端原生防重复）
	var should_dedup := false
	if touch_id == -1:
		# 鼠标事件：始终检查去重
		should_dedup = abs(judge_time_ms - _last_press_time_ms) <= _PRESS_DEDUP_MS and pos.distance_to(_last_press_pos) <= _PRESS_DEDUP_DISTANCE
	else:
		# 触摸事件：仅在前一次是鼠标事件时去重
		should_dedup = _last_press_was_mouse and abs(judge_time_ms - _last_press_time_ms) <= _PRESS_DEDUP_MS and pos.distance_to(_last_press_pos) <= _PRESS_DEDUP_DISTANCE
	_last_press_was_mouse = touch_id == -1
	_last_press_time_ms = judge_time_ms
	_last_press_pos = pos
	if should_dedup:
		return

	var estimated_lane := _estimate_lane_from_x(pos.x)
	var candidate_notes: Array = _get_notes_near_lane(estimated_lane)
	if candidate_notes.is_empty():
		return
	if only_perfect_slides:
		# 仅判定完美滑块开启时，点击/按键选音符阶段直接忽略滑块
		candidate_notes = candidate_notes.filter(func(n):
			return n.type != FlowNote.NoteType.Slide
		)
		if candidate_notes.is_empty():
			return

	var note = note_judger.find_best_note(pos, candidate_notes, jl.position.y, note_judge_width, judge_mode)
	if note == null:
		return
	if parent_node.play_mode and note.game_sequence_ref:
		_trigger_midi_notes_from_sequence(note.game_sequence_ref)
	if note.type == FlowNote.NoteType.Slide:
		# 仅在关闭“仅判定完美滑块”时允许点击滑块，且按点块计分
		_judge_note(note, true, judge_time_ms, FlowNote.NoteType.Block)
	else:
		_judge_note(note, true, judge_time_ms)
	if note.type == FlowNote.NoteType.Long:
		_hold_long_note(touch_id, note, pos.x)

# 处理触摸松开 释放长条音符
func _handle_release(touch_id: int, input_time_ms: float = -1.0, released_lane: int = -1) -> void:
	var judge_time_ms := input_time_ms if input_time_ms >= 0.0 else _get_realtime_position_ms()

	if check_slide_when_finger_up:
		_judge_slides_on_release(touch_id, released_lane, judge_time_ms)

	# 清理与该触点/按键绑定的滑块按住状态，避免后续拖动或同帧事件误判
	for note in active_notes:
		if note.type != FlowNote.NoteType.Slide:
			continue
		if released_lane >= 0:
			if note.lane == released_lane:
				note.can_judge = false
				note.held_by_touch_id = -1
		elif note.held_by_touch_id == touch_id:
			note.can_judge = false
			note.held_by_touch_id = -1

	if touch_id not in active_holds:
		return
	
	var note = active_holds[touch_id]
	note.is_held = false
	
	# 如果VBoxC没有完全移动完毕，提前判定
	# if note.rect.size.y > note.rect.get_node("VBoxC").size.y * 0.2:
		# 判定为Good（提前释放）
		# note_judged.emit("Good", "提前释放")
	
	# 移除音符
	_remove_note(note)
	active_holds.erase(touch_id)

# 处理触摸拖动
func _handle_touch_drag(touch_id: int, pos: Vector2) -> void:
	if touch_id not in active_holds:
		return

	var note = active_holds[touch_id]
	if not note.is_held or note.held_by_touch_id != touch_id:
		return

	if is_nan(note.hold_press_x):
		return  # 非触摸来源（键盘/自动模式）不跟踪手势

	note.rect.offset_transform_position.x = pos.x - note.hold_press_x

# 按住长条音符
# 注意：调用方负责在调用此函数之前已通过 _judge_note() 完成判定
func _hold_long_note(touch_id: int, note: FlowNote, press_x: float = NAN) -> void:
	# 兜底：长条进入按住态后不应再走未判定 Miss 分支
	note.is_judged = true
	note.is_held = true
	note.held_by_touch_id = touch_id
	note.hold_press_x = press_x  # NAN 表示非触摸来源（键盘/自动模式），_handle_touch_drag 将跳过
	# 为新长条分配唯一实例 ID（用于 ScoreCalculator 独立衰减链）
	if note.long_instance_id < 0:
		note.long_instance_id = FlowNote._gen_long_id()
	active_holds[touch_id] = note

# 检查slide音符是否在手指范围内（用于自动判定接近判定线的slide）
func _check_slides_at_touch_pos(touch_id: int, pos: Vector2, input_time_ms: float = -1.0) -> void:
	var judge_time_ms := input_time_ms
	if judge_time_ms < 0.0:
		judge_time_ms = _get_realtime_position_ms()

	for note in active_notes.filter(func (n):
			if n.type == FlowNote.NoteType.Slide:
				return true
			return false
			):
		if note == null or note.rect == null or not is_instance_valid(note.rect):
			continue
		var rect = note.rect as Control
		if rect == null:
			continue

		# 如果slide音符在触摸点范围内
		var note_x = rect.position.x + rect.size.x / 2
		var distance_to_touch = abs(pos.x - note_x)

		if note.can_judge and note.held_by_touch_id == touch_id and distance_to_touch > note_judge_width:
			note.can_judge = false
			note.held_by_touch_id = -1

		if distance_to_touch < note_judge_width and not note.can_judge:
			note.can_judge = true
			note.held_by_touch_id = touch_id
			# return

func _check_slide_stat(note: FlowNote):
	if note.is_judged:
		return

	# 检查是否有按键或触摸手指在该音符的判定范围内
	var has_input_on_lane = note.lane in pressed_keys.values()
	if not has_input_on_lane and note.rect != null:
		# 触摸模式: 实时检查是否有手指在 slide 音符的判定宽度内
		# 与 _check_slides_at_touch_pos 的 distance_to_touch < note_judge_width 逻辑一致
		# 这样即使手指按下后未拖动( can_judge 未被设置), 也能在过线时自动判定
		var rect_ctrl := note.rect as Control
		var note_x = rect_ctrl.position.x + rect_ctrl.size.x / 2
		for touch_pos in touch_positions.values():
			if abs(touch_pos.x - note_x) < note_judge_width:
				has_input_on_lane = true
				break

	if has_input_on_lane:
		if parent_node.play_mode and note.game_sequence_ref:
			_trigger_midi_notes_from_sequence(note.game_sequence_ref)
		if only_perfect_slides:
			_judge_note(note, false, note.start_time, -1, "Perfect")
		else:
			_judge_note(note)
		note.can_judge = false
		return

	if note.can_judge:
		if parent_node.play_mode and note.game_sequence_ref:
			_trigger_midi_notes_from_sequence(note.game_sequence_ref)
		if only_perfect_slides:
			_judge_note(note, false, note.start_time, -1, "Perfect")
		else:
			_judge_note(note)
		note.can_judge = false

func _judge_slides_on_release(touch_id: int, released_lane: int, judge_time_ms: float) -> void:
	var perfect_window_ms = float(judge_windows["perfect"])
	var pending_notes: Array[FlowNote] = []

	for note in active_notes:
		if note == null or note.is_judged or note.is_held or note.type != FlowNote.NoteType.Slide:
			continue
		if note.rect == null or not is_instance_valid(note.rect):
			continue

		if released_lane >= 0:
			if note.lane != released_lane or not note.can_judge:
				continue
		elif note.held_by_touch_id != touch_id or not note.can_judge:
			continue

		if abs(judge_time_ms - note.start_time) <= perfect_window_ms:
			pending_notes.append(note)

	for note in pending_notes:
		if parent_node.play_mode and note.game_sequence_ref:
			_trigger_midi_notes_from_sequence(note.game_sequence_ref)
		_judge_note(note, false, judge_time_ms, -1, "Perfect")

## 获取音符的代表 Y 坐标（屏幕坐标）
## Long 音符使用 VBoxC/head 中心 Y，其他使用 rect 中心 Y
func _get_note_center_y(note: FlowNote) -> float:
	if note.type == FlowNote.NoteType.Long:
		var head := note.rect.get_node("VBoxC/head") as Control
		return head.global_position.y + head.size.y * 0.5
	return note.rect.position.y + note.rect.offset_transform_position.y + note.rect.size.y * 0.5

## 键盘模式专用：在指定轨道范围内查找最合适的音符并完成判定
## 触摸模式请使用 _handle_press()（通过 NoteJudger 实现）
func judge_note_at_lane(lane_l: int, lane_r: int, input_time_ms: float = -1.0) -> FlowNote:
	var best_note: FlowNote = null
	var best_score: float = INF

	# 使用轨道索引加速：只遍历目标轨道范围内的音符
	var candidate_notes: Array = []
	for lane in range(lane_l, lane_r + 1):
		if _notes_by_lane.has(lane):
			candidate_notes.append_array(_notes_by_lane[lane])

	for note in candidate_notes:
		if note.is_held:
			continue
		if only_perfect_slides and note.type == FlowNote.NoteType.Slide:
			continue

		var note_y: float = _get_note_center_y(note)

		match judge_mode:
			NoteJudger.JudgeMode.NEAREST, NoteJudger.JudgeMode.BEST_TIMING, NoteJudger.JudgeMode.NEAREST_JUDGE:
				# 键盘模式无点击位置，以判定线 Y 为参考选最近音符
				var diff: float = abs(jl.position.y - note_y)
				if diff < best_score:
					best_score = diff
					best_note = note
			NoteJudger.JudgeMode.BEST_TIMING_FIFO:
				# 先现先判：选最靠近底部（note_y 最大）的音符
				var score: float = -note_y
				if score < best_score:
					best_score = score
					best_note = note

	if best_note:
		if parent_node.play_mode and best_note.game_sequence_ref:
			_trigger_midi_notes_from_sequence(best_note.game_sequence_ref)
		if best_note.type == FlowNote.NoteType.Slide:
			# 键盘点击滑块按点块计分；与按住触发（滑块计分）路径互斥
			_judge_note(best_note, true, input_time_ms, FlowNote.NoteType.Block)
		else:
			_judge_note(best_note, true, input_time_ms)
		return best_note
	return null

## 新增：从GameSequence触发MIDI音符（演奏模式）
func _trigger_midi_notes_from_sequence(game_seq: Object) -> void:
	# game_seq 是 KeySequenceManager.GameSequence 对象
	if not game_seq or game_seq.original_notes.is_empty():
		return
	
	var midi_player = MidiPlaybackManager.instance.midi_player
	if not midi_player:
		return
	
	# 触发原始notes中的所有MIDI音符
	for note in game_seq.original_notes:
		if note is MidiParser.NoteEvent:
			var track_idx := int(note.track_index)

			# 触发note_on
			if midi_player.has_method("trigger_note_on"):
				midi_player.call("trigger_note_on", note.pitch, note.velocity, note.channel, track_idx)
			elif midi_player.has_method("note_on"):
				midi_player.note_on(note.channel, note.pitch, note.velocity)

			# 非阻塞调度 note_off（避免循环内 await 导致后续音符串行延后）
			var delay_seconds = (game_seq.duration_ms / 1000.0) if game_seq.duration_ms > 0 else 0.1
			_schedule_note_off(midi_player, note.pitch, note.velocity, note.channel, delay_seconds, track_idx)

func _schedule_note_off(midi_player: Object, pitch: int, velocity: int, channel: int, delay_seconds: float, track_index: int = 0) -> void:
	var timer = get_tree().create_timer(max(delay_seconds, 0.01))
	timer.timeout.connect(func():
		if not is_instance_valid(midi_player):
			return
		if midi_player.has_method("trigger_note_off"):
			midi_player.call("trigger_note_off", pitch, velocity, channel, track_index)
		elif midi_player.has_method("note_off"):
			midi_player.note_off(channel, pitch)
	)

func _trigger_touch_vibration() -> void:
	if not Input.has_method("vibrate_handheld"):
		return
	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		return
	if ConfigManager.instance.get_int("Playback", "vibrate_on_touch", 1) != 1:
		return
	var duration_ms = max(1.0, ConfigManager.instance.get_int("Playback", "vibration_duration", 20))
	Input.vibrate_handheld(duration_ms, 0.5)

func _init_particle_pool() -> void:
	if not _particle_pool.is_empty():
		return
	for _i in _PARTICLE_POOL_SIZE:
		var ptc = particle.duplicate()
		canvas.add_child(ptc)
		ptc.visible = false
		ptc.particle_done.connect(_on_particle_done.bind(ptc))
		_particle_pool.append(ptc)

func _on_particle_done(ptc: Node2D) -> void:
	ptc.visible = false
	_particle_pool.append(ptc)

func _get_particle_from_pool() -> Node2D:
	if _particle_pool.is_empty():
		# 池耗尽时回退创建（密集谱面极端情况）
		var ptc := particle.duplicate() as Node2D
		canvas.add_child(ptc)
		ptc.particle_done.connect(_on_particle_done.bind(ptc))
		return ptc
	return _particle_pool.pop_back()

func _generate_particle(type: String, pos: Vector2, scl: int = 200) -> void:
	var ptc := _get_particle_from_pool()
	ptc.position = pos
	ptc.set_particle_scale(scl)
	ptc.visible = true
	ptc.play(type)
	
## 【方案C】同步当前播放时间（毫秒）
## 由 PlayView._process() 每帧调用，确保 FlowArea 的时间与 MIDI 播放位置完全同步
func set_current_time(time_ms: float) -> void:
	_synced_current_time = time_ms - _audio_playback_delay_ms

func _get_realtime_position_ms() -> float:
	var playback_mgr = MidiPlaybackManager.instance
	if playback_mgr:
		return playback_mgr.get_realtime_position_ms() - _audio_playback_delay_ms
	return _synced_current_time

func _judge_note(judge_note: FlowNote, trigger_vibration: bool = false, input_time_ms: float = -1.0,
		block_type_override: int = -1, result_override: String = ""):
	# 防止重复判定：如果该note已被判定过，直接返回
	if judge_note.is_judged:
		return

	# input_time_ms 已来自 _get_realtime_position_ms()（已减 offset）或 note.start_time（与 current_time 同坐标系）
	# 无需再次减 offset，直接使用即可避免双重减法
	var judge_time_ms := input_time_ms if input_time_ms >= 0.0 else _get_realtime_position_ms()
	var time_diff = judge_note.start_time - judge_time_ms  # 毫秒，优先使用事件时刻的实时播放位置
	var abs_diff = abs(time_diff)
	var result: String = result_override

	if result.is_empty():
		result = "Bad"
		if abs_diff <= judge_windows["perfect"]:
			result = "Perfect"
		elif abs_diff <= judge_windows["great"]:
			result = "Great"
		elif abs_diff <= judge_windows["good"]:
			result = "Good"
		elif abs_diff <= judge_windows["bad"]:
			result = "Bad"

	# 转换为秒，传递给 ScoreCalculator 所需的数据
	var timing_sec: float = abs_diff / 1000.0
	var signed_offset_sec: float = time_diff / 1000.0
	# 默认将 NoteType 映射到 BlockType；点击滑块时可覆盖为 INSTANT
	var block_type: int = block_type_override if block_type_override >= 0 else judge_note.type

	# 标记该note已被判定，防止重复
	judge_note.is_judged = true
	var hit_pos := Vector2.ZERO
	if judge_note.rect:
		hit_pos = judge_note.rect.position + judge_note.rect.offset_transform_position + judge_note.rect.size / 2.0
	
	note_judged.emit(result, "%s%.1f ms" % ["+" if time_diff>=0 else "", time_diff],
		block_type, timing_sec, signed_offset_sec)
	if trigger_vibration:
		_trigger_touch_vibration()
	if judge_note.type != FlowNote.NoteType.Long:
		_remove_note(judge_note)

	# 特效
	var light_color = _get_resolved_color_for_type(judge_note.type)
	get_parent().lane_area.light_lane(judge_note.lane, light_color)
	
	var preset = spark_presets.get(result, 0)
	if preset > 0 and judge_note.type != FlowNote.NoteType.Long and hit_pos != Vector2.ZERO:
		_generate_particle(result, hit_pos, spark_scalings.get(result, 200))

var _is_pause: bool = false
var _cached_viewport_height: float = 0.0
func _process(delta: float) -> void:
	_cached_viewport_height = get_viewport().get_visible_rect().size.y
	if not parent_node:
		return

	# 暂停处理
	if parent_node.is_pause and not _is_pause:
		for i in active_notes:
			if i.tween:
				i.tween.pause()
		_is_pause = true
	elif not parent_node.is_pause and _is_pause:
		for i in active_notes:
			if i.tween:
				i.tween.play()
		_is_pause = false

	if _is_pause:
		return

	# 生成音符
	while note_idx < notes_list.size() and notes_list[note_idx].start_time < parent_node.current_time + note_generation_lead_time:
		_spawn_note(note_idx)
		note_idx += 1

	for note in active_notes:
		if note.type == FlowNote.NoteType.Long:
			_update_long_note_fall(note, _synced_current_time)
		elif note.type == FlowNote.NoteType.Block or note.type == FlowNote.NoteType.Slide:
			_update_block_note_fall(note, _synced_current_time)
		_update_note_visibility(note)
	
	# 自动按长条
	if auto_mode:
		for long in active_notes.filter(func(nt):
			if nt.type == FlowNote.NoteType.Long and not nt.is_held and nt.rect:
				var head = nt.cached_head
				return abs(head.global_position.y + head.size.y/2 - jl.position.y) < 12
			return false):
			_auto_click(long)

	# 更新长条音符的按住进度和显示
	for touch_id in active_holds.keys():
		var note = active_holds[touch_id]
		if not note or not note.rect or not note.is_held:
			continue

		var long_end_time = note.start_time + max(0.0, note.duration)
		if _synced_current_time >= long_end_time:
			var tail = note.cached_tail as Control
			var t_half = tail.size.y * 0.5
			var preset = spark_presets.get("Perfect", 0)
			if preset > 0:
				_generate_particle("Perfect", tail.global_position + Vector2(float(note_visual_width) * 0.5, t_half), spark_scalings.get("Perfect", 200))
			_remove_note(note)
			active_holds.erase(touch_id)
			continue

		# 加分及加combo
		if note.cooldown > 0.25: # 0.25是触发频率
			note.cooldown = 0
			long_holding.emit(note.long_instance_id)
		else:
			note.cooldown += delta
