## 收藏夹数据模型
## 存储收藏夹的元信息和其中包含的 MIDI chart_id 列表
extends Resource

class_name FavoriteListData

## 收藏夹唯一标识（时间戳+随机数生成的字符串）
var id: String

## 收藏夹名称（用户可自定义）
var name: String

## 收藏的 MIDI chart_id 列表
## chart_id 采用项目统一约定：file_hash 优先，否则使用 id
var midi_ids: Array[String] = []


func _init(p_id: String = "", p_name: String = "", p_midi_ids: Array[String] = []) -> void:
	id = p_id
	name = p_name
	midi_ids = p_midi_ids


## 序列化为字典，用于 JSON 持久化
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"midi_ids": midi_ids.duplicate()
	}


## 从字典反序列化
static func from_dict(d: Dictionary) -> FavoriteListData:
	var ids: Array[String] = []
	var raw_ids = d.get("midi_ids", [])
	for mid in raw_ids:
		ids.append(str(mid))
	return FavoriteListData.new(
		str(d.get("id", "")),
		str(d.get("name", "")),
		ids
	)
