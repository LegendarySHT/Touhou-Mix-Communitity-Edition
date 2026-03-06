## 配置值解析工具类（纯静态）
## 用于将配置字符串转换为相应的数据类型
class_name ConfigParser

## 键码名称到 KeyCode 的映射表
const KEY_NAME_MAP: Dictionary = {
	# 数字键
	"0": Key.KEY_0, "1": Key.KEY_1, "2": Key.KEY_2, "3": Key.KEY_3, "4": Key.KEY_4,
	"5": Key.KEY_5, "6": Key.KEY_6, "7": Key.KEY_7, "8": Key.KEY_8, "9": Key.KEY_9,
	
	# 字母键（支持大小写）
	"A": Key.KEY_A, "a": Key.KEY_A,
	"B": Key.KEY_B, "b": Key.KEY_B,
	"C": Key.KEY_C, "c": Key.KEY_C,
	"D": Key.KEY_D, "d": Key.KEY_D,
	"E": Key.KEY_E, "e": Key.KEY_E,
	"F": Key.KEY_F, "f": Key.KEY_F,
	"G": Key.KEY_G, "g": Key.KEY_G,
	"H": Key.KEY_H, "h": Key.KEY_H,
	"I": Key.KEY_I, "i": Key.KEY_I,
	"J": Key.KEY_J, "j": Key.KEY_J,
	"K": Key.KEY_K, "k": Key.KEY_K,
	"L": Key.KEY_L, "l": Key.KEY_L,
	"M": Key.KEY_M, "m": Key.KEY_M,
	"N": Key.KEY_N, "n": Key.KEY_N,
	"O": Key.KEY_O, "o": Key.KEY_O,
	"P": Key.KEY_P, "p": Key.KEY_P,
	"Q": Key.KEY_Q, "q": Key.KEY_Q,
	"R": Key.KEY_R, "r": Key.KEY_R,
	"S": Key.KEY_S, "s": Key.KEY_S,
	"T": Key.KEY_T, "t": Key.KEY_T,
	"U": Key.KEY_U, "u": Key.KEY_U,
	"V": Key.KEY_V, "v": Key.KEY_V,
	"W": Key.KEY_W, "w": Key.KEY_W,
	"X": Key.KEY_X, "x": Key.KEY_X,
	"Y": Key.KEY_Y, "y": Key.KEY_Y,
	"Z": Key.KEY_Z, "z": Key.KEY_Z,
	
	# 特殊键
	";": Key.KEY_SEMICOLON,
	":": Key.KEY_SEMICOLON,
	",": Key.KEY_COMMA,
	"<": Key.KEY_COMMA,
	".": Key.KEY_PERIOD,
	">": Key.KEY_PERIOD,
	"/": Key.KEY_SLASH,
	"?": Key.KEY_SLASH,
	"\\": Key.KEY_BACKSLASH,
	"|": Key.KEY_BACKSLASH,
	"[": Key.KEY_BRACKETLEFT,
	"{": Key.KEY_BRACKETLEFT,
	"]": Key.KEY_BRACKETRIGHT,
	"}": Key.KEY_BRACKETRIGHT,
	"-": Key.KEY_MINUS,
	"_": Key.KEY_MINUS,
	"=": Key.KEY_EQUAL,
	"+": Key.KEY_EQUAL,
	" ": Key.KEY_SPACE,
}

## 将逗号分隔的键位字符串解析为 KeyCode 数组
## 支持格式：
##   - "Q,W,D,J,I,O"   （单个大写字符）
##   - "q,w,d,j,i,o"   （单个小写字符）
##   - "A,S,D,F,J,K,L,;" （字母和符号）
##
## 参数：
##   key_string: 配置中的键位字符串，逗号分隔
##
## 返回：
##   Array[Key]: 解析后的 KeyCode 数组，无法识别的键会被跳过
static func parse_keyboard_keys(key_string: String) -> Array[Key]:
	if key_string.is_empty():
		GameLogger.instance.warning("Keyboard keys string is empty, using default", "ConfigParser")
		return _get_default_keyboard_keys()
	
	var keys: Array[Key] = []
	var key_parts = key_string.split(",")
	
	for key_part in key_parts:
		var key_part_stripped = key_part.strip_edges()
		if key_part_stripped.is_empty():
			continue
		
		# 尝试直接查表
		if key_part_stripped in KEY_NAME_MAP:
			keys.append(KEY_NAME_MAP[key_part_stripped])
			continue
		
		# 尝试去掉 "KEY_" 前缀后查表
		var without_prefix = key_part_stripped
		if key_part_stripped.begins_with("KEY_"):
			without_prefix = key_part_stripped.substr(4)
		
		if without_prefix in KEY_NAME_MAP:
			keys.append(KEY_NAME_MAP[without_prefix])
			continue
		
		# 无法识别，记录警告
		GameLogger.instance.warning(
			"Cannot parse keyboard key: '%s'" % key_part_stripped,
			"ConfigParser"
		)
	
	# 如果解析失败（结果为空），返回默认值
	if keys.is_empty():
		GameLogger.instance.warning(
			"Failed to parse any keys from '%s', using default" % key_string,
			"ConfigParser"
		)
		return _get_default_keyboard_keys()
	
	return keys

## 获取默认键位配置
static func _get_default_keyboard_keys() -> Array[Key]:
	return [
		Key.KEY_A, Key.KEY_S, Key.KEY_D, Key.KEY_F,
		Key.KEY_J, Key.KEY_K, Key.KEY_L, Key.KEY_SEMICOLON
	]
