extends Panel

class_name FlowArea

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

# 当前皮肤的完整配置（来自 skin.ini 新结构）
# {general:{enable_glow,custom_color}, short:{...}, instant:{...}, long:{...}}（skin 键名保持旧格式：short=点块 Block、instant=滑块 Slide）
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

# 全局随机颜色（非键盘模式 + 皮肤 custom_color 关闭时生效）
# 由 PlayView 在 _prepare_game 时生成并传入，结构同 _random_colors
var _global_random_colors: Dictionary = {}

# 最终解析出的音符颜色（结合 custom_color 主开关 + enable_color + random_color）
# 结构: {note_type_key: Color}，键为 "short"/"instant"/"long"（short=点块 Block、instant=滑块 Slide）
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
## block_type: KeySequenceManager.BlockType 值 (0=Block=点块,1=Slide=滑块,2=Long=长条)
## 与 FlowNote.NoteType / ScoreCalculator.BlockType 同名同值，可直接透传
## timing_sec: 偏差绝对值(秒)  signed_offset_sec: 带符号偏差(秒)
signal note_judged(result: String, offset: String, block_type: int, timing_sec: float, signed_offset_sec: float)
## long_holding(long_instance_id: int) - 长条持续加分 tick
signal long_holding(long_instance_id: int)

# 音符相关
var lane_width: float = 0
var active_notes: Array = []  # 存储活跃的音符
var _notes_by_lane: Dictionary = {}  # 按轨道分组索引：{lane: Array[FlowNote]}，加速音符判定查找

# 精灵图序列帧粒子播放器场景（替代旧的 GPUParticles2D 方块粒子）
const _PARTICLE_SCENE := preload("res://UI/Views/PlayView/particle_player.tscn")

# 粒子对象池：预创建固定数量实例并复用，避免每次按键 instantiate()+queue_free()
const _PARTICLE_POOL_SIZE = 12
var _particle_pool: Array = []

# Block/Slide/Long 音符批量绘制器（PlayView.tscn 场景节点，Node2D _draw 替代 N 个 Control 节点）
@onready var _note_drawer: NoteBatchDrawer = $SVP/NoteBatchDrawer

var _note_fall_calculator: NoteFallCalculator = NoteFallCalculator.new()

var parent_node: Node = null

# 【方案C】从PlayView同步的当前播放时间（毫秒）
## 这个时间来自 MidiPlaybackManager.get_position_ms()，已包含缓冲补偿
## 用于确保note判定与MIDI播放位置完全同步
var _synced_current_time: float = 0.0
var _diag_auto_log_count: int = 0  # TEMP DIAG: auto 判定采样计数（诊断后移除）

# 渲染时钟（毫秒）：来自 PlayView 的平滑视觉墙钟，仅用于计算音符显示位置。
# 判定（过线/Miss/长条结束/滑过认领）仍用 _synced_current_time（音频钟），保证判定与声音对齐。
var _render_time_ms: float = 0.0

# 修改为从PlayView传入的音符列表
var notes_list: Array[FlowNote] = []  # 移除测试用的音符
var note_idx: int = 0

# 多点触控支持
var touch_positions: Dictionary = {}  # 存储每个触摸点的位置
var active_holds: Dictionary = {}     # 存储正在按住长条音符的触摸点ID和对应的音符

# 触点手势状态（滑动事件跟踪）：touch_id -> {
#   "press_pos": Vector2,
#   "press_time_ms": float,
#   "last_pos": Vector2,
#   "last_time_ms": float,
#   "lanes": Array,           # 手指当前覆盖的轨道集合（轨道宽度=音符宽度，可多轨）
# }
# 滑键判定 = 点按(rule 1) + 滑动事件(rule 2/3/4)：
# - rule 1 点按：按 Block 判掉一个音符，同时视为滑入轨道（rule 3 接住列内其余已过线滑键）。
# - rule 2 过线：滑块到判定线瞬间，手指覆盖其轨道 / 键盘键按住 → 判掉（hold-catch）。
# - rule 3 滑入：覆盖集合新增某轨道 → 判掉该轨道已过线且仍在 great 窗口内的滑块。
# - rule 4 滑出/抬手：覆盖集合退出某轨道或抬手 → 判掉该轨道未过线但在 perfect 窗口内的滑块。
# 轨道宽度 = 音符判定宽度：12 轨窄轨下手指可同时覆盖多个轨道，集合差集即滑入/滑出；4 轨宽轨时退化为单轨。
# rule 5 抬手门控：位移 ≥ 一个音符宽度即视为滑出轨道。
var _gestures: Dictionary = {}

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

	# 清空手动 NoteOff 挂起队列（上一局的定时器/代数不应残留到下一局）
	_pending_manual_offs.clear()
	_manual_note_off_gens.clear()

	if EvtBus and not EvtBus.config_changed.is_connected(_on_config_changed):
		EvtBus.config_changed.connect(_on_config_changed)

	auto_mode = ConfigManager.instance.get_int("Playback", "auto_mode", 0) == 1
	
	# 从配置读取判定模式
	judge_mode = ConfigManager.instance.get_int("Judge", "touch_judging_criteria", NoteJudger.JudgeMode.BEST_TIMING_FIFO)
	check_slide_when_finger_up = ConfigManager.instance.get_int("Judge", "check_instant_blocks_when_finger_up", 1) == 1
	only_perfect_slides = ConfigManager.instance.get_int("Judge", "only_perfect_instant_blocks_before_judge", 0) == 1

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
	
	# 计算轨道间距（中间间距从可用宽度扣除，与 LaneEffect 布局一致，触摸估算不溢出）
	var mid_gap: float = float(parent_node.get_mid_lane_gap())
	if lc <= 1:
		lane_width = safe_width
	else:
		lane_width = max(1.0, (safe_width - mid_gap - float(note_visual_width)) / float(lc - 1))
	
	# 设置判定线位置
	_apply_judge_line_thickness()
	_apply_judge_line_position()
	
	# 配置初始化
	spark_presets["Perfect"] = ConfigManager.instance.get_int("Lane", "perfect_spark_preset", 0)
	spark_scalings["Perfect"] = ConfigManager.instance.get_float("Lane", "perfect_spark_scaling", 100)
	spark_presets["Great"] = ConfigManager.instance.get_int("Lane", "great_spark_preset", 0)
	spark_scalings["Great"] = ConfigManager.instance.get_float("Lane", "great_spark_scaling", 100)
	spark_presets["Good"] = ConfigManager.instance.get_int("Lane", "good_spark_preset", 0)
	spark_scalings["Good"] = ConfigManager.instance.get_float("Lane", "good_spark_scaling", 100)
	spark_presets["Bad"] = ConfigManager.instance.get_int("Lane", "bad_spark_preset", 0)
	spark_scalings["Bad"] = ConfigManager.instance.get_float("Lane", "bad_spark_scaling", 100)
	_init_particle_pool()
	_init_note_pool()
	# 应用解析后的颜色（由 load_note_skin + PlayView 随机颜色生成共同决定）
	# 新音符颜色在 _spawn_note 时经 _get_note_color → _resolved_colors 应用，此处只刷新已存在音符
	refresh_note_colors()

	set_note_width(note_visual_width)

	# 同步 drawer 的裁剪参数和视口高度
	if _note_drawer:
		_note_drawer.set_cull_margins(_note_cull_margin_top, _note_cull_margin_bottom)
		_note_drawer.set_viewport_height(get_viewport().get_visible_rect().size.y)

	# 预计算下落距离和速度
	_note_fall_distance = jl.position.y + _note_max_size_y
	_note_fall_speed = _note_fall_calculator.compute_speed_px_per_ms(_note_fall_distance, _note_fall_time_seconds)

func _apply_judge_line_position() -> void:
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	var offset: int = parent_node.judge_line_offset_y if parent_node else 200
	jl.position.y = viewport_height - max(0, offset)
	_note_fall_distance = jl.position.y + _note_max_size_y
	_note_fall_speed = _note_fall_calculator.compute_speed_px_per_ms(_note_fall_distance, _note_fall_time_seconds)

func _apply_judge_line_thickness() -> void:
	var thickness : int = max(1, ConfigManager.instance.get_int("Appearance", "judge_line_thickness", 2))
	var base_style: StyleBox = jl.get_theme_stylebox("separator")
	if base_style is StyleBoxLine:
		var line_style: StyleBoxLine = (base_style as StyleBoxLine).duplicate() as StyleBoxLine
		line_style.thickness = thickness
		jl.add_theme_stylebox_override("separator", line_style)

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

	if section == "Judge":
		if key == "touch_judging_criteria":
			judge_mode = int(value)
			return
		if key == "judge_line_position":
			_apply_judge_line_position()
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

	if section == "Appearance" and key == "judge_line_thickness":
		_apply_judge_line_thickness()
		return

	if section == "Appearance" and key == "block_size":
		# 需要重新计算音符尺寸
		_recalculate_note_dimensions()
		return

	# 粒子特效配置（Lane 段 spark_preset/spark_scaling）：热更新，暂停中调整立即生效
	if section == "Lane" and (key.ends_with("_spark_preset") or key.ends_with("_spark_scaling")):
		for judge in spark_presets.keys():
			var preset_key := "%s_spark_preset" % judge.to_lower()
			var scaling_key := "%s_spark_scaling" % judge.to_lower()
			spark_presets[judge] = ConfigManager.instance.get_int("Lane", preset_key, 0)
			spark_scalings[judge] = ConfigManager.instance.get_float("Lane", scaling_key, 100)
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

# 修改音符皮肤 数组顺序[短块图片，短块上色区图片，滑块。。。，长条（从头到尾）]
func set_note_texture(texture_array: Array):
	# 直接同步到批量绘制器（drawer 为场景节点始终存在；缺失贴图由 drawer 内部回退透明纹理）
	if _note_drawer:
		_note_drawer.set_textures(texture_array[0] if texture_array.size() > 0 else null,
			texture_array[1] if texture_array.size() > 1 else null,
			texture_array[2] if texture_array.size() > 2 else null,
			texture_array[3] if texture_array.size() > 3 else null)
		_note_drawer.set_long_textures(texture_array[4] if texture_array.size() > 4 else null,
			texture_array[5] if texture_array.size() > 5 else null,
			texture_array[6] if texture_array.size() > 6 else null,
			texture_array[7] if texture_array.size() > 7 else null,
			texture_array[8] if texture_array.size() > 8 else null,
			texture_array[9] if texture_array.size() > 9 else null)
		_note_drawer.set_long_body_mode(_long_f_mode)
		# 贴图变化会重算各类型半高：同步刷新最大全高，保证 _note_fall_distance/速度在换肤后不过期
		_note_max_size_y = _note_drawer.get_max_half_height() * 2.0
		_note_fall_distance = jl.position.y + _note_max_size_y
		_note_fall_speed = _note_fall_calculator.compute_speed_px_per_ms(_note_fall_distance, _note_fall_time_seconds)

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

	# 构建纹理数组，按顺序: short(点块Block), short_core, instant(滑块Slide), instant_core, long_b, long_b_core, long_f, long_f_core, long_t, long_t_core
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
	# 每音符颜色在 _spawn_note 时由 _get_note_color → _resolved_colors 应用，无需模板
	_resolve_note_colors()

	# 同步光效开关到 drawer（Long 与 Block/Slide 同走批量绘制，无需重建对象池）
	if _note_drawer:
		_note_drawer.set_glow_enabled(_is_glow_enabled)

	GLogger.info("Loaded note skin: %s, glow=%s, connect_mode=%s" % [skin_name, _is_glow_enabled, _long_connect_mode], "FlowArea")

## 根据 _skin_config + _random_colors + _global_random_colors 解析出最终音符颜色
## 规则（按优先级）：
##   皮肤 custom_color ON → 沿用皮肤规则（含皮肤内 random_color）
##   非键盘模式 + 全局随机 ON → _global_random_colors[key]
##   非键盘模式 + 全局随机 OFF → 全局手动颜色（short/instant/long_block_color）
##   键盘模式 + custom_color OFF → Color.WHITE（现状不变）
func _resolve_note_colors() -> void:
	_resolved_colors.clear()
	var custom_color_on: bool = false
	if _skin_config.has("general"):
		custom_color_on = bool(_skin_config["general"].get("custom_color", false))
	var keyboard_mode: bool = parent_node != null and bool(parent_node.get("keyboard_mode"))
	var global_random_on := ConfigManager.instance.get_int("Appearance", "randomize_block_color", 0) == 1

	for key in ["short", "instant", "long"]:
		var color := Color.WHITE
		if custom_color_on and _skin_config.has(key):
			var sec: Dictionary = _skin_config[key]
			if bool(sec.get("enable_color", false)):
				if bool(sec.get("random_color", false)) and _random_colors.has(key):
					color = _random_colors[key]
				else:
					color = sec.get("color", Color.WHITE)
		elif not keyboard_mode:
			if global_random_on and _global_random_colors.has(key):
				color = _global_random_colors[key]
			else:
				color = _get_global_color(key)
		_resolved_colors[key] = color

## 读取全局手动音符颜色（非键盘模式 + 皮肤 custom_color OFF + 全局随机 OFF 时使用）
## 默认值与 config.ini [Appearance] 保持一致
func _get_global_color(key: String) -> Color:
	var default_hex := "#4ECDC4"  # short=点块
	if key == "instant":
		default_hex = "#FF6B6B"   # instant=滑块
	elif key == "long":
		default_hex = "#45B7D1"   # long=长条
	var raw := ConfigManager.instance.get_string("Appearance", "%s_block_color" % key, default_hex)
	return Color.from_string(raw, Color.WHITE)

## 重新解析颜色并同步到所有活跃音符（用于随机颜色刷新等场景）
## 每音符颜色在 _spawn_note 时由 _get_note_color 应用，此处只刷新已生成仍绘制的音符
func refresh_note_colors() -> void:
	_resolve_note_colors()
	if _note_drawer:
		for note in _note_drawer._notes:
			if is_instance_valid(note):
				note.cached_color = _get_note_color(note.type, note.lane)
		_note_drawer.request_redraw()

# 根据皮肤配置设置 long-f 中部贴图的应用方式
# repeat → 水平拉伸+垂直重复（drawer 分条绘制）；stretch → 竖直拉伸
func _apply_long_f_mode() -> void:
	var mode = "repeat"
	if _skin_config.has("long") and _skin_config["long"].has("long_f_mode"):
		mode = _skin_config["long"]["long_f_mode"]
	_long_f_mode = mode
	# 同步到批量绘制器（皮肤热切换时实时更新）
	if _note_drawer:
		_note_drawer.set_long_body_mode(_long_f_mode)

# 修改音符宽度
func set_note_width(wid: float):
	# 模板 Control 已移除：宽度同步给 drawer，由 drawer 按纹理比例派生各类型半高
	if _note_drawer:
		_note_drawer.set_note_width(wid)
		# 最大音符全高（下落距离用，保证音符在屏幕外生成/消失）
		_note_max_size_y = _note_drawer.get_max_half_height() * 2.0

func clear_flow_area():
	# 斩断 FlowNote ↔ GameSequence 的 RefCounted 循环引用，释放旧音符
	if notes_list:
		for note in notes_list:
			if note.game_sequence_ref != null:
				note.game_sequence_ref.flow_note_ref = null
				note.game_sequence_ref = null
		notes_list.clear()

	# 清空 drawer 的绘制列表（Block/Slide/Long 统一走批量绘制）
	if _note_drawer:
		_note_drawer.clear()

	active_notes.clear()
	_clear_lane_index()
	active_holds.clear()
	touch_positions.clear()
	_gestures.clear()
	pressed_keys.clear()
	note_idx = 0

	# 释放尚未触发的手动 NoteOff（游戏结束/清场时，避免音符一直挂在合成器上）
	_process_manual_note_offs(true)
	_pending_manual_offs.clear()
	_manual_note_off_gens.clear()

## 检查是否还有活跃音符（用于游戏结束后等待音符自然消除）
func has_active_notes() -> bool:
	return active_notes.size() > 0


var _note_max_size_y: float = 0
var _note_fall_speed: float = 0
var _note_fall_distance: float = 0

## 根据 NoteType 返回 _resolved_colors 中对应的颜色
func _get_resolved_color_for_type(tp: FlowNote.NoteType) -> Color:
	match tp:
		FlowNote.NoteType.Block:
			# skin 键名保持旧格式：short=点块(Block)
			return _resolved_colors.get("short", Color.WHITE)
		FlowNote.NoteType.Slide:
			# skin 键名保持旧格式：instant=滑块(Slide)
			return _resolved_colors.get("instant", Color.WHITE)
		FlowNote.NoteType.Long:
			return _resolved_colors.get("long", Color.WHITE)
	return Color.WHITE

## 获取音符最终颜色：交替轨道颜色开启（键盘模式）时优先轨道色，否则回退皮肤解析色
func _get_note_color(tp: FlowNote.NoteType, lane_idx: int) -> Color:
	var lane_cl = parent_node.get_lane_color(lane_idx)
	return lane_cl if lane_cl != null else _get_resolved_color_for_type(tp)

func _spawn_note(note_index: int) -> void:
	if note_index >= notes_list.size():
		return

	var nt = notes_list[note_index]
	# 关键：重置 Note 数据对象的判定状态（修复多音符同时判定问题）
	nt.is_judged = false
	nt.can_judge = false
	nt.claimed_by_touch_id = -1
	nt.is_held = false
	nt.held_by_touch_id = -1
	nt.cooldown = 0
	nt.judge_line_passed = false
	nt.is_removed = false

	# 计算音符位置
	var beam_node_for_note = parent_node.lane_area.get_lane_by_idx(nt.lane)
	var beam_margin = max(0.0, (beam_node_for_note.beam_size.x - note_visual_width) / 2.0)
	var start_x = beam_node_for_note.position.x + beam_margin

	# Long: 走 Node2D 批量绘制（与 Block/Slide 统一），不创建 Control 节点
	if nt.type == FlowNote.NoteType.Long:
		nt.cached_x_base = start_x  # 拖动手势偏移基准（按住时随触摸平移）
		nt.cached_x = start_x
		nt.cached_center_x = start_x + note_visual_width * 0.5
		nt.cached_head_half_height = _note_drawer.get_long_head_half_height()
		nt.cached_tail_half_height = _note_drawer.get_long_tail_half_height()
		nt.cached_color = _get_note_color(nt.type, nt.lane)
		active_notes.append(nt)
		_add_note_to_lane_index(nt)
		_note_drawer.add_note(nt)
		_update_long_note_fall(nt, _synced_current_time, _render_time_ms)
		return

	# Block/Slide: Node2D 批量绘制，不创建 Control 节点
	nt.cached_x = start_x
	nt.cached_center_x = start_x + note_visual_width * 0.5
	nt.cached_half_height = _note_drawer.get_half_height(nt.type)
	# 每音符颜色：交替轨道颜色开启时按轨道色，否则皮肤解析色
	nt.cached_color = _get_note_color(nt.type, nt.lane)

	active_notes.append(nt)
	_add_note_to_lane_index(nt)
	_note_drawer.add_note(nt)
	_update_block_note_fall(nt, _synced_current_time, _render_time_ms)

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
## Node2D 批量绘制版：写入 note.cached_center_y，drawer 在 _draw 中读取
## current_time_ms = 判定时钟（音频），render_time_ms = 渲染时钟（平滑视觉，可选）
func _update_block_note_fall(note: FlowNote, current_time_ms: float, render_time_ms: float = -1.0) -> void:
	if note.is_removed:
		return
	if render_time_ms < 0.0:
		render_time_ms = current_time_ms

	var half_height = note.cached_half_height
	var center_y = _compute_center_y_by_judge_time(note.start_time, render_time_ms, half_height)
	note.cached_center_y = center_y

	# 过线回调: 音符首次到达/超过判定线时触发 (原 Tween.finished 逻辑)
	if not note.judge_line_passed and current_time_ms >= note.start_time:
		note.judge_line_passed = true
		if note.is_judged or note.is_removed:
			return
		if note.type == FlowNote.NoteType.Slide:
			_check_slide_stat(note)
		if note.is_judged or note.is_removed:
			return
		if auto_mode:
			_auto_click(note)

	# Miss 判定: 音符超出窗口底部且未被击打 (原第二 Tween.finished 逻辑)
	if not note.is_judged and not note.is_removed:
		var window_y = _cached_viewport_height
		if center_y >= window_y:
			_remove_note(note)
			note_judged.emit("Miss", "", note.type, 1.0, 0.0)

## current_time_ms = 判定时钟（音频），render_time_ms = 渲染时钟（平滑视觉，可选）
## Node2D 批量绘制版：写入 cached_head_center_y / cached_tail_center_y / cached_body_* 缓存字段，
## drawer 在 _draw() 中读取绘制（body → tail → head），裁剪由 drawer 内部处理
func _update_long_note_fall(note: FlowNote, current_time_ms: float, render_time_ms: float = -1.0) -> void:
	if note.is_removed:
		return
	if render_time_ms < 0.0:
		render_time_ms = current_time_ms

	var head_half = note.cached_head_half_height
	var tail_half = note.cached_tail_half_height

	var head_center = _compute_center_y_by_judge_time(note.start_time, render_time_ms, head_half)
	if note.is_held:
		head_center = jl.position.y
	var tail_center = _compute_center_y_by_judge_time(note.start_time + max(0.0, note.duration), render_time_ms, tail_half)

	note.cached_head_center_y = head_center
	note.cached_tail_center_y = tail_center
	note.cached_center_y = head_center  # 判定/特效用代表中心（NoteJudger / hit_pos）

	# 长条连接模式：edge（边缘连接，body 从 tail_bottom 到 head_top）
	# 或 center（中心连接，body 从 tail_center 到 head_center，head/tail 各向 body 偏移半高）
	# 两种模式下 head/tail 矩形相同（head 半高居中于 head_center，tail 半高居中于 tail_center）
	if _long_connect_mode == "center":
		note.cached_body_top_y = tail_center
		note.cached_body_height = max(0.0, head_center - tail_center)
	else:
		# 边缘连接（默认）：body 从 tail_bottom（tail_center+tail_half）到 head_top（head_center-head_half）
		note.cached_body_top_y = tail_center + tail_half
		note.cached_body_height = max(0.0, (head_center - head_half) - (tail_center + tail_half))

	if not note.is_judged and not note.is_held and note.held_by_touch_id < 0:
		var window_y = _cached_viewport_height
		if tail_center >= window_y:
			_remove_note(note)
			note_judged.emit("Miss", "", note.type, 1.0, 0.0)

var _auto_hold_idx: int = 0
## AUTO 模式自动判定：
## - 点块/长条：按自然类型计分；
## - 滑块：完美滑块判定(only_perfect_slides)开启时按滑动触发（Slide，进入滑块衰减链）计分；
##   关闭时与手动点击滑块一致，按点块(Block)计分（固定倍率并重置滑块衰减链）。
func _auto_click(note: FlowNote):
	if parent_node.play_mode and note.game_sequence_ref:
		_trigger_midi_notes_from_sequence(note.game_sequence_ref)
	if note.type == FlowNote.NoteType.Long:
		_judge_note(note)
		_hold_long_note(_auto_hold_idx + 666, note)
		_auto_hold_idx += 1
	elif note.type == FlowNote.NoteType.Slide and not only_perfect_slides:
		_judge_note(note, false, -1.0, FlowNote.NoteType.Block)
	else:
		_judge_note(note)

# 因为在for循环遍历时erase会导致漏元素，所以推迟元素的移除
func _delay_free(list, item_to_free):
	list.erase(item_to_free)

func set_glow_params(intensity: float, size_val: float) -> void:
	glow_intensity = clampf(intensity, 0.0, 2.0)
	glow_size = clampf(size_val, 1.0, 30.0)
	# 同步到 drawer（Block/Slide 光效由 drawer 管理）
	if _note_drawer:
		_note_drawer.set_glow_params(glow_intensity, glow_size)

func _init_note_pool() -> void:
	"""初始化 NoteBatchDrawer（PlayView.tscn 场景节点，此处仅同步运行状态）"""
	_note_drawer.set_note_width(note_visual_width)
	_note_drawer.set_glow_enabled(_is_glow_enabled)
	_note_drawer.set_glow_params(glow_intensity, glow_size)
	_note_drawer.set_cull_margins(_note_cull_margin_top, _note_cull_margin_bottom)
	_note_drawer.set_viewport_height(get_viewport().get_visible_rect().size.y)

func _remove_note(note: FlowNote) -> void:
	note.is_removed = true
	# Block/Slide/Long 统一从 drawer 移除（remove_note 内部会 queue_redraw 立即清除画面，仍保持同步）
	# 从 active_notes 的移除推迟到帧末执行：
	# AUTO 模式下过线判定在 _process 遍历 active_notes 的循环体内触发 _remove_note，
	# 若此处同步 erase，GDScript 数组迭代器（idx++ 后取 arr.get(idx)）会因元素前移跳过
	# 下一个音符，使其一帧不更新位置/不判定，在判定线附近停滞一帧。
	# 延迟删除后遍历期间数组不再变化；drawer 的 _notes 已同步移除，画面不会残留。
	if _note_drawer:
		_note_drawer.remove_note(note)
	call_deferred("_delay_free", active_notes, note)

	_remove_note_from_lane_index(note)

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
	# 中间间距：偶数键位时右半侧整体右移，估算前先减去间距对齐
	var mid_gap: int = parent_node.get_mid_lane_gap()
	var half := int(lc / 2)
	if mid_gap > 0 and relative_x >= float(half) * lane_width:
		relative_x -= mid_gap
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

	# 拖动时跟踪轨道切换，触发滑键滑动判定（rule 3 滑入 / rule 4 滑出）
	if event is InputEventScreenDrag and event.index in touch_positions:
		_handle_slide_drag(event.index, touch_positions[event.index], event_time_ms)

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

	# 新建手势状态（记录按下/当前覆盖轨道集合，供拖动 rule 3/4 差集检测与抬手门控）
	var g: Dictionary = {
		"press_pos": pos,
		"press_time_ms": judge_time_ms,
		"last_pos": pos,
		"last_time_ms": judge_time_ms,
		"lanes": _finger_lanes(pos.x),  # 手指当前覆盖的轨道集合（音符宽度为轨道宽度，可多轨）
	}
	_gestures[touch_id] = g

	var estimated_lane := _estimate_lane_from_x(pos.x)
	var candidate_notes: Array = _get_notes_near_lane(estimated_lane)
	candidate_notes = candidate_notes.filter(func(n):
		return n != null and not n.is_judged and not n.is_removed and not n.is_held \
			and n.claimed_by_touch_id < 0
	)
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
		# 点击滑块按点块(Block)计分（固定倍率并重置滑块衰减链）
		_judge_note(note, true, judge_time_ms, FlowNote.NoteType.Block)
	else:
		_judge_note(note, true, judge_time_ms)
	if note.type == FlowNote.NoteType.Long:
		_hold_long_note(touch_id, note, pos.x)
	# 同时视为滑入轨道（rule 3）：接住列内其余已过线仍在 great 窗口的滑键（挤在一起的滑键一次点按全判）
	# 完美滑块模式（only_perfect_slides）下滑键仅按滑动判定，点击不接
	if not only_perfect_slides:
		for lane in g["lanes"]:
			_judge_slides_entering_lane(lane, pos, judge_time_ms)

# 处理触摸松开 释放长条音符
func _handle_release(touch_id: int, input_time_ms: float = -1.0, released_lane: int = -1) -> void:
	var judge_time_ms := input_time_ms if input_time_ms >= 0.0 else _get_realtime_position_ms()

	# rule 4（抬手 = 滑出轨道）：判定当前轨道「未过线但在 perfect 窗口内」的滑键。
	# 键盘抬手（released_lane >= 0）不参与：键盘点击滑键已即时判定，无触摸滑动逻辑
	if released_lane < 0 and check_slide_when_finger_up:
		_judge_slides_on_lift(touch_id, judge_time_ms)
	_clear_gesture(touch_id)

	if touch_id not in active_holds:
		return
	
	var note = active_holds[touch_id]
	note.is_held = false
	
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

	# 批量绘制版：平移 cached_x（相对 spawn 基准偏移），drawer 在 _draw 中读取
	note.cached_x = note.cached_x_base + (pos.x - note.hold_press_x)
	note.cached_center_x = note.cached_x + note_visual_width * 0.5
	if _note_drawer:
		_note_drawer.request_redraw()

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

# ========== 滑键滑动判定（事件驱动模型 rule 2/3/4） ==========

## 结束触点手势（抬起时调用）
func _clear_gesture(touch_id: int) -> void:
	_gestures.erase(touch_id)

## 以 Slide 类型判定一个滑键（进入滑块衰减链）
## 滑动事件（rule 2/3/4）与 rule 1 点按的「视为滑入」均走此入口；rule 1 选中的滑键本身按 Block 计分
func _judge_slide_as_slide(note: FlowNote, judge_time_ms: float) -> void:
	if note == null or note.is_judged or note.is_removed or note.is_held:
		return
	if parent_node.play_mode and note.game_sequence_ref:
		_trigger_midi_notes_from_sequence(note.game_sequence_ref)
	_judge_note(note, false, judge_time_ms)
	GLogger.debug("[FlowArea] Slide catch: lane=%d start=%.0fms judge=%.0fms diff=%.0fms" \
		% [note.lane, note.start_time, judge_time_ms, note.start_time - judge_time_ms], "FlowArea")

## 滑键是否可被滑动判定：Slide 类型 + 未判/未移除/未按住 + 手指在判定列内（半宽 = note_judge_width/2）
func _is_slide_catchable(note: FlowNote, pos: Vector2) -> bool:
	if note == null or note.type != FlowNote.NoteType.Slide:
		return false
	if note.is_judged or note.is_removed or note.is_held:
		return false
	if abs(pos.x - note.cached_center_x) > note_judge_width * 0.5:
		return false
	return true

## rule 3 滑入：判定该轨道已过线但仍在 great 窗口内的滑键（仅本轨道，不扫相邻轨）
func _judge_slides_entering_lane(lane: int, pos: Vector2, judge_time_ms: float) -> void:
	var great := float(judge_windows["great"])
	for note in _notes_by_lane.get(lane, []):
		if not _is_slide_catchable(note, pos):
			continue
		if judge_time_ms < note.start_time or judge_time_ms > note.start_time + great:
			continue
		_judge_slide_as_slide(note, judge_time_ms)

## rule 4 滑出/抬手：判定该轨道未过线但在 perfect 窗口内的滑键（仅本轨道，不扫相邻轨）
func _judge_slides_exiting_lane(lane: int, pos: Vector2, judge_time_ms: float) -> void:
	var perfect := float(judge_windows["perfect"])
	for note in _notes_by_lane.get(lane, []):
		if not _is_slide_catchable(note, pos):
			continue
		if judge_time_ms >= note.start_time or judge_time_ms < note.start_time - perfect:
			continue
		_judge_slide_as_slide(note, judge_time_ms)

## 手指拖动：覆盖轨道集合差集触发 rule 3/4（新进入=滑入，退出=滑出）
func _handle_slide_drag(touch_id: int, pos: Vector2, input_time_ms: float = -1.0) -> void:
	if not _gestures.has(touch_id):
		return
	var judge_time_ms := input_time_ms
	if judge_time_ms < 0.0:
		judge_time_ms = _get_realtime_position_ms()
	var g: Dictionary = _gestures[touch_id]
	# 覆盖集合变化前的旧位置（手指仍在旧轨道内），rule 4 用它判断手指是否在该滑键列内
	var prev_pos: Vector2 = g["last_pos"]
	g["last_pos"] = pos
	g["last_time_ms"] = judge_time_ms

	var new_lanes: Array = _finger_lanes(pos.x)
	var old_lanes: Array = g["lanes"]
	if new_lanes == old_lanes:
		return
	for lane in new_lanes:
		if not lane in old_lanes:
			_judge_slides_entering_lane(lane, pos, judge_time_ms)
	for lane in old_lanes:
		if not lane in new_lanes:
			_judge_slides_exiting_lane(lane, prev_pos, judge_time_ms)
	g["lanes"] = new_lanes

## 手指当前覆盖的轨道集合：轨道宽度 = 音符判定宽度（默认即音符宽度），窄轨下可同时覆盖多轨；
## 与 _is_slide_catchable 判定列一致，保证「轨道在集合内 ⇔ 该轨道滑键可判」
func _finger_lanes(x: float) -> Array:
	var lc: int = parent_node.get_lane_count()
	if lc <= 1:
		return [0]
	var half_judge := note_judge_width * 0.5
	var lanes: Array = []
	for lane in range(lc):
		if abs(_note_center_x_for_lane(lane) - x) <= half_judge:
			lanes.append(lane)
	return lanes

## 轨道 lane 内音符的统一中心 X（与 cached_center_x 公式一致；窄轨音符左对齐 beam，勿用几何中心）
func _note_center_x_for_lane(lane: int) -> float:
	var beam = parent_node.lane_area.get_lane_by_idx(lane)
	var center := float(parent_node.lane_padding) + (float(lane) + 0.5) * lane_width
	var mid_gap: int = parent_node.get_mid_lane_gap()
	if mid_gap > 0 and lane >= int(parent_node.get_lane_count() / 2):
		center += float(mid_gap)
	if beam != null:
		center = beam.position.x + max(0.0, (beam.beam_size.x - note_visual_width) / 2.0) + note_visual_width * 0.5
	return center

## 滑键到达判定线的瞬间回调（rule 2 hold-catch）：手指/键盘键覆盖其轨道即接住
## 由 _update_block_note_fall 过线分支调用，每音符仅触发一次
func _check_slide_stat(note: FlowNote):
	if note.is_judged or note.is_removed or note.is_held:
		return

	# 键盘：对应轨道有按键被按住 → 过线接住（键盘点击滑块已即时判定，此处兜底）
	for keycode in pressed_keys:
		if pressed_keys[keycode] == note.lane:
			if parent_node.play_mode and note.game_sequence_ref:
				_trigger_midi_notes_from_sequence(note.game_sequence_ref)
			if only_perfect_slides:
				_judge_note(note, false, note.start_time, -1, "Perfect")
			else:
				_judge_note(note)
			return

	# 触摸 hold-catch（rule 2）：手指覆盖音符所在轨道即接住
	for candidate_touch_id in touch_positions:
		if not _gestures.has(candidate_touch_id):
			continue
		if not note.lane in _finger_lanes(touch_positions[candidate_touch_id].x):
			continue
		_judge_slide_as_slide(note, _synced_current_time)
		return

## rule 5（抬手=滑出轨道）：位移 ≥ 一个音符宽度即视为滑出，判定当前所在轨道
## 未过线但在 perfect 窗口内的滑键
func _judge_slides_on_lift(touch_id: int, input_time_ms: float = -1.0) -> void:
	if not _gestures.has(touch_id):
		return
	var g: Dictionary = _gestures[touch_id]
	if abs(g["last_pos"].x - g["press_pos"].x) < note_visual_width:
		return
	var judge_time_ms := input_time_ms
	if judge_time_ms < 0.0:
		judge_time_ms = _get_realtime_position_ms()
	for lane in _finger_lanes(g["last_pos"].x):
		_judge_slides_exiting_lane(lane, g["last_pos"], judge_time_ms)

## 获取音符的代表 Y 坐标（屏幕坐标；Long 与 Block/Slide 统一用 cached_center_y）
func _get_note_center_y(note: FlowNote) -> float:
	return note.cached_center_y

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
		if note.is_held or note.is_judged or note.is_removed or note.can_judge:
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
			# 键盘点击滑块按点块(Block)计分（重置滑块衰减链）；与滑过接住（Slide 计分：进入衰减链）路径互斥
			_judge_note(best_note, true, input_time_ms, FlowNote.NoteType.Block)
		else:
			_judge_note(best_note, true, input_time_ms)
		return best_note
	return null

## 待触发的手动 NoteOff（驱动源为播放位置 _synced_current_time，而非墙钟 Timer）
## 每项: {abs_end_ms, track, channel, pitch, velocity, gen}
## 用播放位置驱动可避免：
## 1) 提前点击时 NoteOff 被"点击后 duration_ms"锚定而提前发出（音符没响够就停）
## 2) 暂停菜单打开时墙钟 Timer 照走，把正在响的音符掐断
## 3) 同键快速连打时旧音的 NoteOff 把新音掐断（MeltySynth NoteOff 会结束该键全部 voice）
var _pending_manual_offs: Array = []
## "track:channel:pitch" -> 单调递增代数，用于判定某次 NoteOff 是否已被更新的音符取代
var _manual_note_off_gens: Dictionary = {}

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

			# 触发note_on（即时，保证点击反馈）
			if midi_player.has_method("trigger_note_on"):
				midi_player.call("trigger_note_on", note.pitch, note.velocity, note.channel, track_idx)
			elif midi_player.has_method("note_on"):
				midi_player.note_on(note.channel, note.pitch, note.velocity)

			# NoteOff 锚定到音符的绝对结束时刻（原曲 NoteOff 位于 note_start + duration）。
			# 乐器音色由 sustain/release 包络决定，只有在该绝对时刻发出 NoteOff，
			# 音色才与原曲一致；按"点击后 duration_ms"调度会把提前点击的音符提前掐断。
			var abs_end_ms := float(game_seq.start_time_ms + game_seq.duration_ms)
			var gen := _bump_note_off_gen(track_idx, note.channel, note.pitch)
			_pending_manual_offs.append({
				"abs_end_ms": abs_end_ms,
				"track": track_idx,
				"channel": note.channel,
				"pitch": note.pitch,
				"velocity": note.velocity,
				"gen": gen,
			})

## 每帧由 _process 调用，按播放位置触发到期的手动 NoteOff
## force=true 时全部触发（游戏结束/清场时释放残留音符）
func _process_manual_note_offs(force: bool = false) -> void:
	if _pending_manual_offs.is_empty():
		return
	var midi_player = MidiPlaybackManager.instance.midi_player
	var t := _synced_current_time
	var remaining: Array = []
	for entry in _pending_manual_offs:
		if force or t >= entry["abs_end_ms"]:
			# 代数守卫：同键已触发更新的音符则跳过本次 NoteOff（旧音交给新音一起结束）
			if _is_note_off_gen_current(entry["track"], entry["channel"], entry["pitch"], entry["gen"]):
				if midi_player and is_instance_valid(midi_player):
					if midi_player.has_method("trigger_note_off"):
						midi_player.call("trigger_note_off", entry["pitch"], entry["velocity"], entry["channel"], entry["track"])
					elif midi_player.has_method("note_off"):
						midi_player.note_off(entry["channel"], entry["pitch"])
		else:
			remaining.append(entry)
	_pending_manual_offs = remaining

## 递增某键的 NoteOff 代数，返回新代数（使旧的待触发 NoteOff 失效）
func _bump_note_off_gen(track_index: int, channel: int, pitch: int) -> int:
	var key := "%d:%d:%d" % [track_index, channel, pitch]
	var gen: int = int(_manual_note_off_gens.get(key, 0)) + 1
	_manual_note_off_gens[key] = gen
	return gen

## 校验某次 NoteOff 的代数是否仍是最新（未被更新的同键音符取代）
func _is_note_off_gen_current(track_index: int, channel: int, pitch: int, gen: int) -> bool:
	var key := "%d:%d:%d" % [track_index, channel, pitch]
	return int(_manual_note_off_gens.get(key, 0)) == gen

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
		var ptc := _PARTICLE_SCENE.instantiate()
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
		var ptc := _PARTICLE_SCENE.instantiate() as Node2D
		canvas.add_child(ptc)
		ptc.particle_done.connect(_on_particle_done.bind(ptc))
		return ptc
	return _particle_pool.pop_back()

func _generate_particle(type: String, pos: Vector2, scl: int = 100) -> void:
	# 按预设索引取粒子包（预设 0=None，调用方已判断 >0，此处防御性校验）
	var pack_key := ParticleMGR.get_particle_pack_by_index(spark_presets.get(type, 0))
	if pack_key.is_empty():
		return
	var ptc := _get_particle_from_pool()
	ptc.position = pos
	ptc.visible = true
	ptc.play(pack_key, type, scl)
	
## 【方案C】同步当前播放时间（毫秒）
## 由 PlayView._process() 每帧调用，确保 FlowArea 的时间与 MIDI 播放位置完全同步。
## time_ms = 音频钟（判定用）；render_time_ms = 渲染钟（平滑视觉，可选，缺省回退音频钟）。
func set_current_time(time_ms: float, render_time_ms: float = -1.0) -> void:
	_synced_current_time = time_ms
	_render_time_ms = render_time_ms if render_time_ms >= 0.0 else time_ms

func _get_realtime_position_ms() -> float:
	var playback_mgr = MidiPlaybackManager.instance
	if playback_mgr:
		return playback_mgr.get_realtime_position_ms()
	return _synced_current_time

func _judge_note(judge_note: FlowNote, trigger_vibration: bool = false, input_time_ms: float = -1.0,
		block_type_override: int = -1, result_override: String = ""):
	# 防止重复判定：如果该note已被判定过，直接返回
	if judge_note.is_judged:
		return

	# input_time_ms 来自 _get_realtime_position_ms() 或 note.start_time（与 current_time 同坐标系）
	var judge_time_ms := input_time_ms if input_time_ms >= 0.0 else _get_realtime_position_ms()
	var time_diff = judge_note.start_time - judge_time_ms  # 毫秒，优先使用事件时刻的实时播放位置
	var abs_diff = abs(time_diff)
	if auto_mode and _diag_auto_log_count < 30:
		_diag_auto_log_count += 1
		GLogger.info("DIAG auto judge #%d: start=%.1f judge=%.1f diff=%.1f type=%d" % [
			_diag_auto_log_count, judge_note.start_time, judge_time_ms, time_diff, judge_note.type], "FlowArea")
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
	# NoteType 与 BlockType 已统一同名同值（Block=0/Slide=1/Long=2），直接透传；
	# 点击滑块时 override 为 Block（按点块计分）
	var block_type: int = block_type_override if block_type_override >= 0 else judge_note.type

	# 标记该note已被判定，防止重复
	judge_note.is_judged = true
	# 走 Node2D 批量绘制，Long 与 Block/Slide 统一用 cached 字段（cached_center_y = head 中心）
	var hit_pos := Vector2(judge_note.cached_center_x, judge_note.cached_center_y)
	
	note_judged.emit(result, "%s%.1f ms" % ["+" if time_diff>=0 else "", time_diff],
		block_type, timing_sec, signed_offset_sec)
	if trigger_vibration:
		_trigger_touch_vibration()
	if judge_note.type != FlowNote.NoteType.Long:
		_remove_note(judge_note)

	# 特效（轨道光束颜色与音符一致：交替轨道颜色开启时按轨道色点亮）
	var light_color = _get_note_color(judge_note.type, judge_note.lane)
	get_parent().lane_area.light_lane(judge_note.lane, light_color)
	
	var preset = spark_presets.get(result, 0)
	if preset > 0 and judge_note.type != FlowNote.NoteType.Long and hit_pos != Vector2.ZERO:
		_generate_particle(result, hit_pos, spark_scalings.get(result, 100))

var _is_pause: bool = false
var _cached_viewport_height: float = 0.0
func _process(delta: float) -> void:
	_cached_viewport_height = get_viewport().get_visible_rect().size.y
	if not parent_node:
		return

	# 暂停处理（音符下落由 _process 时间驱动，暂停时下方提前 return 即冻结，无需 Tween 暂停）
	if parent_node.is_pause and not _is_pause:
		_is_pause = true
	elif not parent_node.is_pause and _is_pause:
		_is_pause = false

	if _is_pause:
		return

	# 驱动手动音符的 NoteOff（按播放位置触发，暂停时自动停）
	_process_manual_note_offs()

	# 生成音符
	while note_idx < notes_list.size() and notes_list[note_idx].start_time < parent_node.current_time + note_generation_lead_time:
		_spawn_note(note_idx)
		note_idx += 1

	# 每帧更新所有活跃音符位置
	# Block/Slide/Long 统一写入 cached_* 字段，drawer 在 _draw 中批量绘制（Long 由 _update_long_note_fall 维护）
	for note in active_notes:
		if note.type == FlowNote.NoteType.Long:
			_update_long_note_fall(note, _synced_current_time, _render_time_ms)
		else:
			_update_block_note_fall(note, _synced_current_time, _render_time_ms)

	# 位置已更新，通知 Node2D 批量绘制器重绘
	if _note_drawer and not active_notes.is_empty():
		_note_drawer.request_redraw()

	# 自动按长条：
	# - 视觉窗口：head 中心距判定线 < 12px（正常帧下与画面精确对齐）
	# - 音频钟兜底：_synced_current_time 已过 start_time 即接（与 Block/Slide 过线回调一致）
	#   防止开局卡顿/跳帧/迟到生成导致 head 一帧越过 12px 窗口而漏接
	if auto_mode:
		for long in active_notes.filter(func(nt):
			if nt.type == FlowNote.NoteType.Long and not nt.is_held:
				return abs(nt.cached_head_center_y - jl.position.y) < 12 \
					or _synced_current_time >= nt.start_time
			return false):
			_auto_click(long)

	# 更新长条音符的按住进度和显示（Long 与 Block/Slide 统一走 cached 字段）
	for touch_id in active_holds.keys():
		var note = active_holds[touch_id]
		if not note or not note.is_held:
			continue

		var long_end_time = note.start_time + max(0.0, note.duration)
		if _synced_current_time >= long_end_time:
			var preset = spark_presets.get("Perfect", 0)
			if preset > 0:
				_generate_particle("Perfect", Vector2(note.cached_center_x, note.cached_tail_center_y), spark_scalings.get("Perfect", 100))
			_remove_note(note)
			active_holds.erase(touch_id)
			continue

		# 加分（长条持续 tick 只加分，不加 combo；combo 仅由首判增加）
		if note.cooldown > 0.25: # 0.25是触发频率
			note.cooldown = 0
			long_holding.emit(note.long_instance_id)
		else:
			note.cooldown += delta
