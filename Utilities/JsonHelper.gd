## JSON 辅助工具
## 提供 Dictionary 的安全字段访问
class_name JsonHelper
extends RefCounted

## 安全读取 Dictionary 字段，值为 null 或键不存在时返回默认值
## 合并自 DataManager.json_get 和 AlbumData.json_get
static func get_value(json: Dictionary, key: String, p_default: Variant) -> Variant:
	if not json or not json.has(key):
		return p_default
	var val = json[key]
	if val == null:
		return p_default
	return val
