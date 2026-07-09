class_name SkinMetadata
extends RefCounted

## 皮肤元数据 Model

var name: String = ""
var path: String = ""              ## 皮肤文件夹路径
var is_builtin: bool = false       ## 是否内置皮肤
var is_complete: bool = true       ## 是否完整（保留字段，当前恒为 true）
var config: Dictionary = {}        ## 皮肤配置（原 skin_config Dictionary）

static func from_dict(d: Dictionary) -> SkinMetadata:
	var m = SkinMetadata.new()
	m.name = d.get("name", "")
	m.path = d.get("path", "")
	m.is_builtin = d.get("is_builtin", false)
	m.is_complete = d.get("is_complete", true)
	m.config = d.get("config", {})
	return m

func to_dict() -> Dictionary:
	return {
		"name": name,
		"path": path,
		"is_builtin": is_builtin,
		"is_complete": is_complete,
		"config": config,
	}
