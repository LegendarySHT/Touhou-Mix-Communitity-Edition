class_name ChartMetadata
extends RefCounted

## 谱面元数据 Model（替代原 Dictionary 存储）

var id: String = ""
var folder_name: String = ""
var path: String = ""              ## 谱面文件夹路径
var json_path: String = ""         ## chart.json 路径
var audio_path: String = ""        ## 音频文件路径
var cover_path: String = ""        ## 封面图路径
var data: Dictionary = {}          ## 原始 JSON 数据
var is_complete: bool = false      ## 是否完整（含音频文件）

## 从 Dictionary 构造（兼容旧格式）
static func from_dict(d: Dictionary) -> ChartMetadata:
	var m = ChartMetadata.new()
	m.id = d.get("id", "")
	m.folder_name = d.get("folder_name", "")
	m.path = d.get("path", "")
	m.json_path = d.get("json_path", "")
	m.audio_path = d.get("audio_path", "")
	m.cover_path = d.get("cover_path", "")
	m.data = d.get("data", {})
	m.is_complete = d.get("is_complete", false)
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
		"data": data,
		"is_complete": is_complete,
	}
