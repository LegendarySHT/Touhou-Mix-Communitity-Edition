class_name FlowNote
extends RefCounted

enum NoteType {
	Block = 0,
	Slide,
	Long
}

var start_time: float    		# 生成note时的时间
var duration: float
var type: NoteType
var lane: int            		# 轨道索引
var held_by_touch_id: int = -1  # 按住该音符的触摸点ID
var game_sequence_ref: Object = null  # 新增：指向对应的GameSequence（演奏模式触发使用）

# Node2D 批量绘制缓存字段（Block/Slide 用 x/center_x/half_height/color；Long 用下方 cached_head/tail/body 字段）
# 由 _spawn_note 一次性设置 x/center_x/half_height，由 _update_block_note_fall 每帧更新 center_y
var cached_x: float = 0.0           # 音符左边缘 x（绘制用）
var cached_center_x: float = 0.0    # 音符中心 x（判定查找用）
var cached_center_y: float = 0.0    # 音符中心 y（每帧更新，绘制 + 判定用）
var cached_half_height: float = 0.0 # 音符半高（绘制 + after_distance 计算用）
var cached_color: Color = Color.WHITE # 音符颜色（交替轨道颜色开启时为轨道色，否则为皮肤解析色；_spawn_note 设置）
var is_removed: bool = false        # 已从绘制列表移除标记（防止 _remove_note 后 _process 重复处理）

# 用于滑键
var can_judge: bool = false
var claimed_by_touch_id: int = -1  # 认领该滑块的触点ID（触点认领模型，-1=无认领）

# 防止重复判定标志
var is_judged: bool = false  # 已被判定过，防止同一note重复记录combo

# Block/Slide 是否已过判定线 (synced time 驱动下用于触发过线回调)
var judge_line_passed: bool = false

# 用于长条
var is_held: bool = false    	# 是否被按住
var cooldown: float = 0      	# 长按时的触发计时器
var long_instance_id: int = -1  # 同一长条的唯一 ID（用于 ScoreCalculator 衰减链）
var hold_press_x: float = NAN  # 长条按住时记录的触摸 x（手势偏移基准；NAN 表示非触摸来源）

# Long 音符批量绘制缓存字段（与 Block/Slide 共用 cached_* 命名，由 _spawn_note / _update_long_note_fall 维护）
var cached_x_base: float = 0.0           # 长条 spawn 时的基准左边缘 x（拖动手势偏移基准）
var cached_head_center_y: float = 0.0    # 长条头部中心 y（每帧更新；按住时钉在判定线）
var cached_tail_center_y: float = 0.0    # 长条尾部中心 y（每帧更新）
var cached_head_half_height: float = 0.0 # 长条头部半高（spawn 时按贴图比例计算）
var cached_tail_half_height: float = 0.0 # 长条尾部半高（spawn 时按贴图比例计算）
var cached_body_top_y: float = 0.0       # 长条 body 顶部 y（每帧更新；edge/center 连接差异已计入）
var cached_body_height: float = 0.0      # 长条 body 高度（每帧更新）

static var _next_long_id: int = 0
static func _gen_long_id() -> int:
	_next_long_id += 1
	return _next_long_id

func _init(tp: NoteType, st: float, dur: float, l: int):
	start_time = st
	duration = dur
	type = tp
	lane = l
