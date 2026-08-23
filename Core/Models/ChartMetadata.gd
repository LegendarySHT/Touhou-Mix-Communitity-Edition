class_name ChartMetadata
extends RefCounted

## 谱面元数据 Model（替代原 Dictionary 存储）

var id: String = ""
var folder_name: String = ""
var path: String = ""              ## 谱面文件夹路径
var json_path: String = ""         ## chart.json 路径
var audio_path: String = ""        ## 音频文件路径
var cover_path: String = ""        ## 封面图路径
var is_complete: bool = false      ## 是否完整（含音频文件）

## v3 扁平化字段（扫描 dict 顶层直接提供，避免物化整块 JSON）
var midi_id: String = ""           ## 谱面 JSON 的 _id
var file_hash: String = ""         ## 谱面 JSON 的 file_hash（favorites/别名查找用）
var hash: String = ""              ## 谱面 JSON 的 hash（别名查找用）

## 从 Dictionary 构造（兼容旧格式）
static func from_dict(d: Dictionary) -> ChartMetadata:
	var m = ChartMetadata.new()
	m.id = d.get("id", "")
	m.folder_name = d.get("folder_name", "")
	m.path = d.get("path", "")
	m.json_path = d.get("json_path", "")
	m.audio_path = d.get("audio_path", "")
	m.cover_path = d.get("cover_path", "")
	m.is_complete = d.get("is_complete", false)
	m.midi_id = d.get("midi_id", "")
	m.file_hash = d.get("file_hash", "")
	m.hash = d.get("hash", "")
	return m

## 转为 Dictionary（仅用于序列化/兼容）
func to_dict() -> Dictionary:
	return {
		"id": id,
		"folder_name": folder_name,
		"path": path,
		"json_path": json_path,
		"audio_path": audio_path,
		"cover_path": cover_path,
		"is_complete": is_complete,
		"midi_id": midi_id,
		"file_hash": file_hash,
		"hash": hash,
	}
