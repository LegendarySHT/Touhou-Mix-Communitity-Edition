## 专辑数据模型
## 代表一个东方作品专辑
class_name AlbumData
extends Resource

## 唯一标识符
var id: String

## 专辑全名
var name: String

## 专辑缩写（如 TH02, TH03 等）
var abbreviation: String

## 发布日期
var release_date: String

## 专辑描述
var description: String = ""

## 封面图片URL
var cover_url: String = ""

## 该专辑的歌曲列表
var song_ids: Array[String] = []

## 该专辑的所有MIDI数量
var total_midi_count: int = 0

## 从JSON数据构造
func from_json(json_data: Dictionary) -> void:
	id = json_data.get("_id", "")
	name = json_data.get("name", "")
	abbreviation = json_data.get("abbr", "")
	release_date = json_data.get("date", "")
	description = json_data.get("description", "")
	cover_url = json_data.get("coverUrl", "")

## 转换为字典格式
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"abbreviation": abbreviation,
		"release_date": release_date,
		"description": description,
		"cover_url": cover_url,
		"song_ids": song_ids,
		"total_midi_count": total_midi_count
	}

## 添加歌曲ID
func add_song_id(song_id: String) -> void:
	if not song_id in song_ids:
		song_ids.append(song_id)

## 移除歌曲ID
func remove_song_id(song_id: String) -> void:
	song_ids.erase(song_id)

## 获取歌曲数量
func get_song_count() -> int:
	return song_ids.size()
