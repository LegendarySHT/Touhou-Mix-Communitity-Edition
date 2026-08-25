## Chart JSON 规范化静态工具
## 将旧格式的6个字段（song/album/author + sourceSongName/sourceAlbumName/sourceArtistName）
## 合并为3个统一字段，并精简 song/album 对象只保留必要键
##
## 幂等：第二次调用已规范化的 JSON 必定返回 false
class_name ChartNormalizer


## 判断嵌套对象是否有实际数据（非 null 的 _id 或 name）
static func _has_meaningful_data(dict, id_key: String = "_id") -> bool:
	if not dict is Dictionary:
		return false
	var id_val = dict.get(id_key, null)
	var name_val = dict.get("name", null)
	return (id_val is String and not (id_val as String).is_empty()) or (name_val is String and not (name_val as String).is_empty())


## 安全获取非空字符串，空/非 String 时返回 fallback
static func _safe_str(val, fallback: String) -> String:
	if val is String and not (val as String).is_empty():
		return val as String
	return fallback


## 从 Dictionary 中安全提取 String，key 存在但值为 null 时也返回 fallback
static func _get_str(dict: Dictionary, key: String, fallback: String) -> String:
	var val = dict.get(key, null)
	if val is String and not (val as String).is_empty():
		return val as String
	return fallback


## 从 author 字段提取名称字符串（兼容 String / Dictionary / Array 三种格式）
static func _extract_author_name(author_val) -> String:
	if author_val is String:
		var s := author_val as String
		if not s.is_empty() and s != "Anonymous":
			return s
		return ""

	if author_val is Dictionary:
		var name_val = author_val.get("name", "")
		if name_val is String:
			var ns := name_val as String
			if not ns.is_empty() and ns != "Anonymous":
				return ns
		return ""

	if author_val is Array:
		var result := ""
		for item in (author_val as Array):
			var name_str := ""
			if item is Dictionary:
				var nv = item.get("name", "")
				if nv is String:
					name_str = nv as String
			elif item is String:
				name_str = item as String
			if not name_str.is_empty() and name_str != "Anonymous":
				if not result.is_empty():
					result += ", "
				result += name_str
		return result

	return ""


## 对已解析的 chart JSON 字典执行就地规范化
## 返回 true 表示有修改（调用方可决定是否写回磁盘）
static func normalize_chart_json(data: Dictionary) -> bool:
	var changed := false

	# ── song ──
	var song_from_source := _safe_str(data.get("sourceSongName", ""), "Unknown Song")

	if data.has("song") and _has_meaningful_data(data["song"]):
		# 嵌套 song 有实际数据 → 精简
		var song: Dictionary = data["song"]
		var sid := _get_str(song, "_id", "")
		if sid.is_empty():
			# 兼容旧格式：部分来源用 "id" 而非 "_id"（如旧版下载 JSON）
			sid = _get_str(song, "id", "")
			if not sid.is_empty():
				song["_id"] = sid
				changed = true
		if sid.is_empty():
			var sn := _get_str(song, "name", "Unknown Song")
			song["_id"] = "song_" + sn.sha256_text().substr(0, 16)
			changed = true
		for key in song.keys():
			if key not in ["_id", "name", "track", "author"]:
				song.erase(key)
				changed = true
	else:
		# 无实际数据或缺失 → 从 sourceSongName 重建
		data["song"] = {
			"_id": "song_" + song_from_source.sha256_text().substr(0, 16),
			"name": song_from_source,
			"track": 0
		}
		changed = true

	# ── album ──
	var album_from_source := _safe_str(data.get("sourceAlbumName", ""), "Unknown Album")

	if data.has("album") and _has_meaningful_data(data["album"]):
		var album: Dictionary = data["album"]
		var aid := _get_str(album, "_id", "")
		if aid.is_empty():
			# 兼容旧格式：部分来源用 "id" 而非 "_id"（如旧版下载 JSON）
			aid = _get_str(album, "id", "")
			if not aid.is_empty():
				album["_id"] = aid
				changed = true
		if aid.is_empty():
			var an := _get_str(album, "name", "Unknown Album")
			album["_id"] = "album_" + an.sha256_text().substr(0, 16)
			changed = true
		for key in album.keys():
			if key not in ["_id", "name", "abbr", "date"]:
				album.erase(key)
				changed = true
	else:
		data["album"] = {
			"_id": "album_" + album_from_source.sha256_text().substr(0, 16),
			"name": album_from_source,
			"abbr": "",
			"date": ""
		}
		changed = true

	# ── author ──
	# 统一落位到 song.author（白名单键之一），顶层不再保留 author
	# 取值优先级：sourceArtistName(旧) → 顶层 author(旧) → song.author(现) → 空
	var new_author := _safe_str(data.get("sourceArtistName", ""), "")
	if new_author.is_empty() and data.has("author"):
		new_author = _extract_author_name(data["author"])

	var song: Dictionary = data["song"]
	var existing_song_author := _safe_str(song.get("author", ""), "")
	if new_author.is_empty():
		new_author = existing_song_author

	# 旧格式顶层 author 迁移：已并入取值逻辑，此处直接移除顶层
	if data.has("author"):
		data.erase("author")
		changed = true

	if not song.has("author") or not song["author"] is String or song["author"] != new_author:
		song["author"] = new_author
		changed = true

	# ── 删除顶层冗余字段 ──
	var top_fields_to_remove := [
		"sourceArtistName",
		"sourceAlbumName",
		"sourceSongName",
		"authorId",
		"songId",
		"composer",
		"composerId",
		"id",
	]
	for field in top_fields_to_remove:
		if data.has(field):
			data.erase(field)
			changed = true

	return changed
