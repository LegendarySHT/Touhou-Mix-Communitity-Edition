## 缓动函数映射器
## 负责缓动类型的编码、解码和转换，提供字符串<->Tween常量的双向映射
class_name EasingMapper

## 缓动函数类型枚举（对应Godot的Tween.TRANS_*）
enum EasingFunc {
	LINEAR = Tween.TRANS_LINEAR as int,
	QUAD = Tween.TRANS_QUAD as int,
	CUBIC = Tween.TRANS_CUBIC as int,
	QUART = Tween.TRANS_QUART as int,
	QUINT = Tween.TRANS_QUINT as int,
	SINE = Tween.TRANS_SINE as int,
	CIRC = Tween.TRANS_CIRC as int,
	ELASTIC = Tween.TRANS_ELASTIC as int,
	BACK = Tween.TRANS_BACK as int,
	BOUNCE = Tween.TRANS_BOUNCE as int,
}

## 缓动相位枚举（对应Godot的Tween.EASE_*）
enum EasingPhase {
	IN = Tween.EASE_IN as int,
	OUT = Tween.EASE_OUT as int,
	IN_OUT = Tween.EASE_IN_OUT as int,
}

## 缓动函数名称映射
static var func_names: Dictionary = {
	"LINEAR": EasingFunc.LINEAR,
	"QUAD": EasingFunc.QUAD,
	"CUBIC": EasingFunc.CUBIC,
	"QUART": EasingFunc.QUART,
	"QUINT": EasingFunc.QUINT,
	"SINE": EasingFunc.SINE,
	"CIRC": EasingFunc.CIRC,
	"ELASTIC": EasingFunc.ELASTIC,
	"BACK": EasingFunc.BACK,
	"BOUNCE": EasingFunc.BOUNCE,
}

## 缓动函数显示名称（用于UI）
static var func_display_names: Dictionary = {
	"LINEAR": "Linear",
	"QUAD": "Quad",
	"CUBIC": "Cubic",
	"QUART": "Quart",
	"QUINT": "Quint",
	"SINE": "Sine",
	"CIRC": "Circ",
	"ELASTIC": "Elastic",
	"BACK": "Back",
	"BOUNCE": "Bounce",
}

## 缓动相位名称映射
static var phase_names: Dictionary = {
	"IN": EasingPhase.IN,
	"OUT": EasingPhase.OUT,
	"IN_OUT": EasingPhase.IN_OUT,
}

## 缓动相位显示名称（用于UI）
static var phase_display_names: Dictionary = {
	"IN": "In",
	"OUT": "Out",
	"IN_OUT": "InOut",
}

## 反向映射：整数值 -> 名称
static var trans_int_to_name: Dictionary = {}
static var ease_int_to_name: Dictionary = {}

func _init():
	# 初始化反向映射
	if trans_int_to_name.is_empty():
		for name in func_names.keys():
			trans_int_to_name[func_names[name]] = name
	
	if ease_int_to_name.is_empty():
		for name in phase_names.keys():
			ease_int_to_name[phase_names[name]] = name

## 将缓动函数名称字符串转换为Tween.TRANS_*常量
## @param name 缓动函数名称（如"LINEAR", "QUAD"等），不区分大小写
## @return Tween.TRANS_*常量值，如果不存在则返回LINEAR
static func string_to_trans(name: String) -> int:
	var upper_name = name.to_upper()
	if upper_name in func_names:
		return func_names[upper_name]
	
	GameLogger.instance.warning("Unknown easing function: %s, using LINEAR as fallback" % name, "EasingMapper")
	return EasingFunc.LINEAR

## 将缓动相位名称字符串转换为Tween.EASE_*常量
## @param name 缓动相位名称（如"IN", "OUT", "IN_OUT"等），不区分大小写
## @return Tween.EASE_*常量值，如果不存在则返回OUT
static func string_to_ease(name: String) -> int:
	var upper_name = name.to_upper()
	if upper_name in phase_names:
		return phase_names[upper_name]
	
	GameLogger.instance.warning("Unknown easing phase: %s, using OUT as fallback" % name, "EasingMapper")
	return EasingPhase.OUT

## 将Tween.TRANS_*常量转换为缓动函数名称
## @param trans Tween.TRANS_*常量值
## @return 缓动函数名称（如"LINEAR"），如果不存在则返回"LINEAR"
static func trans_to_string(trans: int) -> String:
	if trans in trans_int_to_name:
		return trans_int_to_name[trans]
	
	GameLogger.instance.warning("Unknown trans constant: %d, using LINEAR as fallback" % trans, "EasingMapper")
	return "LINEAR"

## 将Tween.EASE_*常量转换为缓动相位名称
## @param ease_type Tween.EASE_*常量值
## @return 缓动相位名称（如"OUT"），如果不存在则返回"OUT"
static func ease_to_string(ease_type: int) -> String:
	if ease_type in ease_int_to_name:
		return ease_int_to_name[ease_type]
	
	GameLogger.instance.warning("Unknown ease constant: %d, using OUT as fallback" % ease_type, "EasingMapper")
	return "OUT"

## 生成组合的缓动名称字符串（func + phase）
## @param func_name 缓动函数名称（如"LINEAR"）
## @param phase_name 缓动相位名称（如"OUT"）
## @return 组合名称（如"LINEAR_OUT"）
static func get_combined_name(func_name: String, phase_name: String) -> String:
	return "%s_%s" % [func_name.to_upper(), phase_name.to_upper()]

## 获取所有缓动函数的选项列表（用于UI下拉列表）
## @return 包含{name, display_name}的数组
static func get_func_options() -> Array:
	var options = []
	for name in func_names.keys():
		options.append({
			"name": name,
			"display_name": func_display_names.get(name, name)
		})
	return options

## 获取所有缓动相位的选项列表（用于UI下拉列表）
## @return 包含{name, display_name}的数组
static func get_phase_options() -> Array:
	var options = []
	for name in phase_names.keys():
		options.append({
			"name": name,
			"display_name": phase_display_names.get(name, name)
		})
	return options

## 获取预设缓动配置
## 返回预设模式的缓动信息
static func get_preset_config(preset_mode: int) -> Dictionary:
	match preset_mode:
		0:  # 匀速
			return {
				"before_func": "LINEAR",
				"before_phase": "IN",
				"after_func": "LINEAR",
				"after_phase": "IN"
			}
		1:  # 加速下落
			return {
				"before_func": "QUAD",
				"before_phase": "IN",
				"after_func": "QUAD",
			 	"after_phase": "IN"
			}
		_:  # 默认（匀速）
			return {
				"before_func": "LINEAR",
				"before_phase": "IN",
				"after_func": "LINEAR",
				"after_phase": "IN"
			}
