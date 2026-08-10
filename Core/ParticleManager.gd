## 粒子管理器
## 负责管理粒子包的扫描、配置加载与精灵图获取
## 支持内置粒子（res://Resources/Particles）与用户粒子（user://files/Particles）统一管理
## 结构参考 SkinManager：
##   粒子包目录下含 particle.ini（配置）+ 若干精灵图（序列帧 spritesheet）
##   particle.ini 声明单帧尺寸/总帧数/帧率/是否循环/是否淡出，以及
##   Perfect/Great/Good/Bad 四种判定分别使用的精灵图
extends Node

class_name ParticleManager

## ========== 目录路径定义（通过 PathHelper 动态获取） ==========
static var PARTICLES_DIR: String:
	get: return PathHelper.get_particles_dir()

## 内置粒子源目录
const DEFAULT_PARTICLES_SRC = "res://Resources/Particles/"

## 粒子包配置文件名（放在粒子包目录下）
const PARTICLE_CONFIG_FILE = "particle.ini"

## 内置包显示后缀（与皮肤一致）
const BUILTIN_SUFFIX = " [内置]"

## 四种判定类型（读取 [perfect]/[great]/[good]/[bad] 节的顺序）
const JUDGE_TYPES: Array[String] = ["Perfect", "Great", "Good", "Bad"]

## ========== 资源索引 ==========
## 粒子包索引 {pack_key: Dictionary}
## pack_key = 文件夹名（内置加 [内置] 后缀）
## 字段：{name, path, is_builtin, size, frame, fps, loop, fade_out, cols, rows, files}
##   files: {judge_type: 精灵图文件名}
var particles_index: Dictionary = {}

## 精灵图缓存 {pack_key: {judge_type: Texture2D}}
var _texture_cache: Dictionary = {}

func _ready() -> void:
	add_to_group("singleton")
	GLogger.info("ParticleManager initialized (deferred scan)", "ParticleMGR")

## 清空粒子索引（由 FileSystemManager._scan_all_resources 统一扫描前调用）
func clear_index() -> void:
	particles_index.clear()
	_texture_cache.clear()

## ========== 扫描 ==========

## 扫描粒子包目录（worker 线程执行）
## 先扫内置（res://），再扫用户（user://），结果经 result_wrapper 回传主线程合并
func _build_particles_index_worker(result_wrapper: Dictionary) -> void:
	var local_particles: Dictionary = {}
	var local_logs: Array = []
	_scan_dir_worker(DEFAULT_PARTICLES_SRC, true, local_particles, local_logs)
	_scan_dir_worker(PARTICLES_DIR, false, local_particles, local_logs)
	result_wrapper["particles"] = local_particles
	result_wrapper["logs"] = local_logs

## worker 内部：扫描单个粒子目录
## 只收集含 particle.ini 的文件夹；日志收集到数组（worker 线程不直接调 GLogger）
func _scan_dir_worker(dir_path: String, is_builtin: bool, local_particles: Dictionary, local_logs: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while folder_name != "":
		if not dir.current_is_dir() or folder_name.begins_with("."):
			folder_name = dir.get_next()
			continue
		var pack_path := dir_path.path_join(folder_name)
		var pack_key := folder_name + (BUILTIN_SUFFIX if is_builtin else "")
		var data := _load_pack_worker(pack_path, pack_key, is_builtin, local_logs)
		if not data.is_empty():
			local_particles[pack_key] = data
		folder_name = dir.get_next()
	dir.list_dir_end()

## worker 内部：加载单个粒子包（解析 particle.ini + 校验精灵图存在性）
## 返回空 Dictionary 表示不是有效粒子包（无 particle.ini / 配置损坏 / 无精灵图）
func _load_pack_worker(pack_path: String, pack_key: String, is_builtin: bool, local_logs: Array) -> Dictionary:
	var config_path := pack_path.path_join(PARTICLE_CONFIG_FILE)
	if not PathHelper.file_exists(config_path):
		return {}

	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return {}
	var content := file.get_as_text()
	file.close()

	# 复用项目通用 INI 解析逻辑（段→键→字符串值）
	var raw := IniParser.parse(content)
	if raw.is_empty():
		return {}

	var normalized := _normalize_pack_config(raw)
	if normalized.is_empty():
		local_logs.append({"msg": "Particle pack config invalid (missing size): %s" % config_path, "is_warning": true})
		return {}

	# 校验至少存在一张精灵图（用于任意判定类型），否则视为无效包
	if not _has_any_sprite(pack_path, normalized.get("files", {})):
		local_logs.append({"msg": "Particle pack has no sprites: %s" % pack_path, "is_warning": true})
		return {}

	return {
		"name": pack_key,
		"path": pack_path,
		"is_builtin": is_builtin,
		"size": normalized.get("size", 0),
		"frame": normalized.get("frame", 0),
		"fps": normalized.get("fps", 30.0),
		"loop": normalized.get("loop", false),
		"fade_out": normalized.get("fade_out", true),
		"cols": normalized.get("cols", 0),
		"rows": normalized.get("rows", 0),
		"files": normalized.get("files", {}),
	}

## 将 INI 解析结果 {section: {key: str}} 规范化为带类型的结构化 Dictionary
## 缺失键用默认值补全；无有效 size 返回空 Dictionary（调用方视为无效包）
func _normalize_pack_config(raw: Dictionary) -> Dictionary:
	var general: Dictionary = raw.get("general", {})
	var size := int(general.get("size", "0"))
	if size <= 0:
		return {}

	var frame := int(general.get("frame", "0"))
	if frame < 0:
		frame = 0
	var fps := float(general.get("fps", "30"))
	if fps <= 0.0:
		fps = 30.0
	var cols := int(general.get("cols", "0"))
	var rows := int(general.get("rows", "0"))

	var files: Dictionary = {}
	for judge in JUDGE_TYPES:
		var sec: Dictionary = raw.get(judge.to_lower(), {})
		var file_name: String = sec.get("file", "")
		if not file_name.is_empty():
			files[judge] = file_name

	return {
		"size": size,
		"frame": frame,
		"fps": fps,
		"loop": _parse_bool(general.get("loop", "false")),
		"fade_out": _parse_bool(general.get("fade_out", "true")),
		"cols": cols,
		"rows": rows,
		"files": files,
	}

## 检查粒子包目录下是否至少存在一张配置声明的精灵图
## res:// 走 ResourceLoader（导出后源图以 .ctex 存在，FileAccess 不可读），user:// 走文件存在性检查
func _has_any_sprite(pack_path: String, files: Dictionary) -> bool:
	for judge in JUDGE_TYPES:
		var file_name: String = files.get(judge, "")
		if file_name.is_empty():
			continue
		var file_path := pack_path.path_join(file_name)
		if file_path.begins_with("res://"):
			if ResourceLoader.exists(file_path):
				return true
		elif PathHelper.file_exists(file_path):
			return true
	return false

## 将字符串解析为 bool（接受 "true"/"false"/"1"/"0"）
func _parse_bool(value) -> bool:
	if value is bool:
		return value
	var s := str(value).to_lower()
	return s == "true" or s == "1"

## ========== 查询接口 ==========

## 获取全部粒子包键（按名称排序，保证跨平台/跨枚举顺序的 preset 索引稳定）
func get_particle_list() -> Array:
	var keys := particles_index.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return a.to_lower() < b.to_lower()
	)
	return keys

## 获取粒子包数据（未找到返回空 Dictionary）
func get_particle_data(pack_key: String) -> Dictionary:
	return particles_index.get(pack_key, {})

## 按预设索引取粒子包键（索引 0 = None，1 起对应 get_particle_list() 顺序）
## 越界返回空字符串
func get_particle_pack_by_index(index: int) -> String:
	if index <= 0:
		return ""
	var list := get_particle_list()
	if index > list.size():
		return ""
	return list[index - 1]

## 获取粒子包在某判定类型下使用的精灵图（Texture2D）
## 当前判定类型未配置/缺失时依次回退 Perfect→Great→Good→Bad
## 仍找不到返回 null（播放器会透明播完）
func get_particle_texture(pack_key: String, judge_type: String) -> Texture2D:
	if _texture_cache.has(pack_key) and _texture_cache[pack_key].has(judge_type):
		return _texture_cache[pack_key][judge_type]

	var data := get_particle_data(pack_key)
	if data.is_empty():
		return null
	var pack_path: String = data.get("path", "")
	var files: Dictionary = data.get("files", {})

	# 当前判定类型的精灵图
	var tex := _try_load_sprite(pack_path, files.get(judge_type, ""))
	# 回退：按 Perfect→Great→Good→Bad 顺序找可用的
	if tex == null:
		for jt in JUDGE_TYPES:
			if jt == judge_type:
				continue
			tex = _try_load_sprite(pack_path, files.get(jt, ""))
			if tex != null:
				break

	# 缓存结果（含 null，避免反复读盘）
	if not _texture_cache.has(pack_key):
		_texture_cache[pack_key] = {}
	_texture_cache[pack_key][judge_type] = tex
	return tex

## 加载单张精灵图：内置走 ResourceLoader，用户目录走 Image 动态加载
func _try_load_sprite(pack_path: String, file_name: String) -> Texture2D:
	if file_name.is_empty():
		return null
	var file_path := pack_path.path_join(file_name)
	if file_path.begins_with("res://"):
		if ResourceLoader.exists(file_path):
			return load(file_path)
		return null
	if PathHelper.file_exists(file_path):
		var image := Image.load_from_file(file_path)
		if image:
			return ImageTexture.create_from_image(image)
	return null

## 清空精灵图缓存（粒子包重扫时调用）
func clear_texture_cache() -> void:
	_texture_cache.clear()
