## 皮肤管理器
## 负责管理皮肤资源的扫描、配置加载与贴图获取
## 支持内置皮肤（res://）与用户皮肤（user://）的统一管理
extends Node

class_name SkinManager

## ========== 目录路径定义（通过 PathHelper 动态获取） ==========
static var SKINS_DIR: String:
	get: return PathHelper.get_skins_dir()

## 默认资源源目录
const DEFAULT_SKINS_SRC = "res://Resources/Skins/"

## 皮肤配置文件名（放置在皮肤包目录下）
const SKIN_CONFIG_FILE = "skin.ini"

## 皮肤配置默认光晕大小（与 config.ini 中的全局默认值对齐：short/instant=5.0，long=5.0+3=8.0）
const SKIN_GLOW_SIZE_DEFAULT_SHORT = 5.0
const SKIN_GLOW_SIZE_DEFAULT_INSTANT = 5.0
const SKIN_GLOW_SIZE_DEFAULT_LONG = 8.0

## ========== 资源索引 ==========
## 皮肤索引 {skin_name: SkinMetadata}
var skins_index: Dictionary = {}
var _scan_requested: bool = false

func _ready() -> void:
	add_to_group("singleton")
	# 不在 _ready 中主动扫描。扫描由 FileSystemManager._scan_all_resources()
	# 在目录结构初始化完成后统一触发，确保默认皮肤已复制到位。
	GLogger.info("SkinManager initialized (deferred scan)", "SkinMGR")

## 扫描皮肤目录 - 同时扫描内置和用户皮肤
func scan_skins() -> void:
	# await get_tree().process_frame
	_scan_requested = true
	skins_index.clear()

	# 先扫描内置皮肤
	var builtin_skins_dir = DEFAULT_SKINS_SRC
	_scan_skins_from_dir(builtin_skins_dir, true)

	# 再扫描用户皮肤
	_scan_skins_from_dir(SKINS_DIR, false)

	GLogger.info("Scanned %d skins" % skins_index.size(), "SkinMGR")

## 从指定目录扫描皮肤
func _scan_skins_from_dir(dir_path: String, is_builtin: bool) -> void:
	var dir = DirAccess.open(dir_path)
	if dir == null:
		if is_builtin:
			GLogger.warning("Failed to open built-in skins directory: %s" % dir_path, "SkinMGR")
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	var _count = 0

	while folder_name != "":
		if not dir.current_is_dir() or folder_name.begins_with("."):
			folder_name = dir.get_next()
			continue

		if dir.current_is_dir():
			var skin_path = dir_path.path_join(folder_name)
			var skin_key = folder_name

			# 如果是内置皮肤，添加 [内置] 标记
			if is_builtin:
				skin_key = "%s [内置]" % folder_name

			var metadata = _load_skin_metadata(skin_path, skin_key, is_builtin)

			if metadata != null and not metadata.is_empty():
				skins_index[skin_key] = SkinMetadata.from_dict(metadata)

		_count += 1
		folder_name = dir.get_next()
		if _count % 10 == 0:
			await get_tree().process_frame

	dir.list_dir_end()

## 加载皮肤元数据
func _load_skin_metadata(skin_path: String, skin_name: String, is_builtin: bool = false) -> Dictionary:
	# 不再检查必需文件，允许部分贴图缺失
	var metadata = {
		"name": skin_name,
		"path": skin_path,
		"is_builtin": is_builtin,
		"is_complete": true,
		"missing_files": [],
		# 皮肤级配置（光晕颜色/大小、long-f 贴图应用方式等）
		"config": _load_or_generate_skin_config(skin_path, is_builtin)
	}

	return metadata

## 加载或自动生成皮肤配置
## 用户皮肤（user://）若缺失 skin.ini 会自动写入磁盘；内置皮肤（res://）仅返回内存配置
func _load_or_generate_skin_config(skin_path: String, is_builtin: bool) -> Dictionary:
	var config_path = skin_path.path_join(SKIN_CONFIG_FILE)

	# 1. 尝试加载已存在的 skin.ini
	if FileAccess.file_exists(config_path):
		var loaded = _load_skin_config_from_file(config_path)
		if not loaded.is_empty():
			return loaded
		# 加载失败（文件损坏等）：回退到自动生成，并打印警告
		GLogger.warning("Skin config corrupted, regenerating: %s" % config_path, "SkinMGR")

	# 2. 自动生成默认配置
	var config = _generate_default_skin_config(skin_path)

	# 3. 用户皮肤写入磁盘；内置皮肤跳过（res:// 在导出后为只读）
	if not is_builtin:
		_save_skin_config_to_file(config_path, config)
		GLogger.info("Generated skin config: %s" % config_path, "SkinMGR")

	return config

## 从文件加载皮肤配置并解析为结构化 Dictionary
## 返回空 Dictionary 表示加载/解析失败
func _load_skin_config_from_file(config_path: String) -> Dictionary:
	var file = FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return {}
	var content = file.get_as_text()
	file.close()

	# 复用项目通用的 INI 解析逻辑（段→键→字符串值）
	var raw = IniParser.parse(content)
	if raw.is_empty():
		return {}

	return _normalize_skin_config(raw)

## 根据皮肤目录中的 core 贴图存在情况生成默认配置
## 规则：
##   有 core 贴图 → glow_use_custom_size=false（光晕大小跟随全局设置），glow_size 写入全局默认值作为参考
##   无 core 贴图 → glow_use_custom_size=true，glow_size=0（用自定义 0 禁用光晕）
func _generate_default_skin_config(skin_path: String) -> Dictionary:
	var has_short_core = _skin_file_exists(skin_path, SKIN_TEXTURES["short_core"])
	var has_instant_core = _skin_file_exists(skin_path, SKIN_TEXTURES["instant_core"])
	var has_long_core = _skin_file_exists(skin_path, SKIN_TEXTURES["long_b_core"]) \
		or _skin_file_exists(skin_path, SKIN_TEXTURES["long_f_core"]) \
		or _skin_file_exists(skin_path, SKIN_TEXTURES["long_t_core"])

	return {
		"short": {
			"glow_use_custom_color": false,
			"glow_custom_color": Color.WHITE,
			"glow_use_custom_size": (not has_short_core),
			"glow_size": SKIN_GLOW_SIZE_DEFAULT_SHORT if has_short_core else 0.0
		},
		"instant": {
			"glow_use_custom_color": false,
			"glow_custom_color": Color.WHITE,
			"glow_use_custom_size": (not has_instant_core),
			"glow_size": SKIN_GLOW_SIZE_DEFAULT_INSTANT if has_instant_core else 0.0
		},
		"long": {
			"glow_use_custom_color": false,
			"glow_custom_color": Color.WHITE,
			"glow_use_custom_size": (not has_long_core),
			"glow_size": SKIN_GLOW_SIZE_DEFAULT_LONG if has_long_core else 0.0,
			"long_f_mode": "repeat"
		}
	}

## 检查皮肤目录下某个贴图文件是否存在
## 兼容 res://（ResourceLoader.exists）与 user://（FileAccess.file_exists）
func _skin_file_exists(skin_path: String, file_name: String) -> bool:
	var file_path = skin_path.path_join(file_name)
	if file_path.begins_with("res://"):
		return ResourceLoader.exists(file_path)
	return FileAccess.file_exists(file_path)

## 将解析得到的 {section: {key: str}} 规范化为带类型的结构化 Dictionary
## 缺失的键使用默认值补全，确保下游可以安全读取
func _normalize_skin_config(raw: Dictionary) -> Dictionary:
	return {
		"short": _normalize_note_section(raw.get("short", {}), SKIN_GLOW_SIZE_DEFAULT_SHORT, false),
		"instant": _normalize_note_section(raw.get("instant", {}), SKIN_GLOW_SIZE_DEFAULT_INSTANT, false),
		"long": _normalize_note_section(raw.get("long", {}), SKIN_GLOW_SIZE_DEFAULT_LONG, true)
	}

## 规范化单个键型的配置节
func _normalize_note_section(section_raw: Dictionary, default_size: float, is_long: bool) -> Dictionary:
	var result: Dictionary = {
		"glow_use_custom_color": _parse_bool(section_raw.get("glow_use_custom_color", "false")),
		"glow_custom_color": _parse_color(section_raw.get("glow_custom_color", "#ffffff")),
		"glow_use_custom_size": _parse_bool(section_raw.get("glow_use_custom_size", "false")),
		"glow_size": _parse_float(section_raw.get("glow_size", str(default_size)))
	}
	if is_long:
		var mode = section_raw.get("long_f_mode", "repeat")
		result["long_f_mode"] = "stretch" if mode == "stretch" else "repeat"
	return result

## 将字符串解析为 bool（接受 "true"/"false"/"1"/"0"）
func _parse_bool(value) -> bool:
	if value is bool:
		return value
	var s = str(value).to_lower()
	return s == "true" or s == "1"

## 将字符串解析为 float（无效输入返回 0.0）
func _parse_float(value) -> float:
	if value is float:
		return value
	if value is int:
		return float(value)
	return str(value).to_float()

## 将字符串解析为 Color（接受 "#RRGGBB" / "#RRGGBBAA" / 颜色名）
func _parse_color(value) -> Color:
	if value is Color:
		return value
	var s = str(value).strip_edges()
	if s.is_empty():
		return Color.WHITE
	# Color.html 安全解析 hex；失败时返回 Color.MAGENTA 作为可见错误标记，这里回退到 WHITE
	var col = Color.from_string(s, Color.WHITE)
	return col

## 将结构化配置 Dictionary 写入 skin.ini 文件
func _save_skin_config_to_file(config_path: String, config: Dictionary) -> void:
	var content = _serialize_skin_config(config)
	var file = FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		GLogger.warning("Failed to write skin config: %s" % config_path, "SkinMGR")
		return
	file.store_string(content)
	file.close()

## 将配置 Dictionary 序列化为 INI 文本
func _serialize_skin_config(config: Dictionary) -> String:
	var lines: Array = ["# 自动生成的皮肤配置文件 - 可手动编辑", ""]
	for section in ["short", "instant", "long"]:
		if not config.has(section):
			continue
		lines.append("[%s]" % section)
		var sec = config[section]
		lines.append("glow_use_custom_color=%s" % str(sec.get("glow_use_custom_color", false)).to_lower())
		lines.append("glow_custom_color=%s" % _color_to_hex(sec.get("glow_custom_color", Color.WHITE)))
		lines.append("glow_use_custom_size=%s" % str(sec.get("glow_use_custom_size", false)).to_lower())
		lines.append("glow_size=%s" % str(sec.get("glow_size", 0.0)))
		if section == "long":
			lines.append("long_f_mode=%s" % str(sec.get("long_f_mode", "repeat")))
		lines.append("")
	return "\n".join(lines)

## 将 Color 转换为 #RRGGBB 字符串
func _color_to_hex(col: Color) -> String:
	return "#%02x%02x%02x" % [int(round(col.r * 255)), int(round(col.g * 255)), int(round(col.b * 255))]

## 获取指定皮肤的配置 Dictionary
## 返回结构：{short:{...}, instant:{...}, long:{...}}；查找不到时返回空 Dictionary
func get_skin_config(skin_name: String) -> Dictionary:
	var skin_data: SkinMetadata = skins_index.get(skin_name, null)
	if skin_data == null:
		# 尝试移除 [内置] 标记查找
		if skin_name.ends_with(" [内置]"):
			var pure_name = skin_name.substr(0, skin_name.length() - 8)
			skin_data = skins_index.get(pure_name, null)
		if skin_data == null:
			GLogger.warning("Skin config not found: %s" % skin_name, "SkinMGR")
			return {}
	return skin_data.config

## 获取所有可用皮肤列表
func get_available_skins() -> Array:
	var result: Array = []

	for skin_name in skins_index.keys():
		result.append(skin_name)

	return result

## 获取皮肤贴图文件映射
const SKIN_TEXTURES = {
	"short": "short.png",
	"short_core": "short-core.png",
	"instant": "instant.png",
	"instant_core": "instant-core.png",
	"long_t": "long-t.png",
	"long_t_core": "long-t-core.png",
	"long_f": "long-f.png",
	"long_f_core": "long-f-core.png",
	"long_b": "long-b.png",
	"long_b_core": "long-b-core.png"
}

## 获取指定皮肤的贴图字典
func get_skin_textures(skin_name: String) -> Dictionary:
	var result: Dictionary = {}

	# 获取皮肤数据
	var skin_data: SkinMetadata = skins_index.get(skin_name, null)
	if skin_data == null:
		# 尝试移除 [内置] 标记查找（用于内置皮肤）
		if skin_name.ends_with(" [内置]"):
			var pure_name = skin_name.substr(0, skin_name.length() - 8)
			skin_data = skins_index.get(pure_name, null)

		if skin_data == null:
			GLogger.warning("Skin not found: %s" % skin_name, "SkinMGR")
			return result

	var skin_path = skin_data.path
	if skin_path.is_empty():
		return result

	# 加载所有贴图
	for texture_key in SKIN_TEXTURES:
		var file_name = SKIN_TEXTURES[texture_key]
		var file_path = skin_path.path_join(file_name)

		if file_path.begins_with("res://"):
			# 内置资源直接加载
			if ResourceLoader.exists(file_path):
				result[texture_key] = load(file_path)
		else:
			# 用户目录资源动态加载 - 先检查文件是否存在
			if FileAccess.file_exists(file_path):
				var image = Image.load_from_file(file_path)
				if image:
					var texture = ImageTexture.create_from_image(image)
					result[texture_key] = texture

	return result

## 获取默认皮肤的贴图
func get_default_skin_textures() -> Dictionary:
	return get_skin_textures("旧版2 [内置]")

## 获取皮肤路径
func get_skin_path(skin_name: String) -> String:
	if not skins_index.has(skin_name):
		return ""

	var metadata: SkinMetadata = skins_index[skin_name]
	return metadata.path

## 获取皮肤索引
func get_skins_index() -> Dictionary:
	return skins_index
