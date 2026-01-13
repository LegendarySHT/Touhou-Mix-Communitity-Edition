## 歌曲数据模型
## 代表一首原曲，可能对应多个MIDI谱面
class_name SongData
extends Resource

## 唯一标识符
var id: String

## 歌曲名称（日文）
var name: String

## 歌曲英文名称（可选）
var name_en: String = ""

## 音轨序号
var track_number: int = 0

## 所属专辑
var album_id: String = ""

## 歌曲描述
var description: String = ""

## 该歌曲的MIDI谱面列表
var midi_ids: Array[String] = []

## 从JSON数据构造
func from_json(json_data: Dictionary) -> void:
	id = json_data.get("_id", "")
	name = json_data.get("name", "")
	name_en = json_data.get("nameEn", "")
	track_number = json_data.get("track", 0)
	album_id = json_data.get("albumId", "")
	description = json_data.get("description", "")

## 转换为字典格式
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"name_en": name_en,
		"track_number": track_number,
		"album_id": album_id,
		"description": description,
		"midi_ids": midi_ids
	}

## 添加MIDI谱面ID
func add_midi_id(midi_id: String) -> void:
	if not midi_id in midi_ids:
		midi_ids.append(midi_id)

## 移除MIDI谱面ID
func remove_midi_id(midi_id: String) -> void:
	midi_ids.erase(midi_id)

## 获取MIDI数量
func get_midi_count() -> int:
	return midi_ids.size()
