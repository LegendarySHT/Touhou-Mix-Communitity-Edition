## MIDI 简介配置解析器
## 从谱面简介文本中提取推荐启用音轨、音频偏移等信息
## 支持全角/半角标点，支持多种写法格式
class_name MidiDescriptionParser
extends RefCounted


## 解析描述文本，返回配置字典
## 返回格式:
##   {
##     "recommended_tracks": Array[int],  # 推荐启用的轨道索引（已选取第一个难度或直接推荐）
##     "audio_offset_ms": int,            # 音频偏移（毫秒），-1 表示简介中未提及
##     "difficulties": Array              # 所有识别到的难度配置（预留），元素: {"name": String, "tracks": Array[int]}
##   }
static func parse(description: String) -> Dictionary:
	var result: Dictionary = {
		"recommended_tracks": [],
		"audio_offset_ms": -1,
		"difficulties": [],
	}

	if description == null or description.is_empty():
		return result

	# 解析音频偏移
	result["audio_offset_ms"] = _parse_audio_offset(description)

	# 解析音轨推荐：优先直接推荐，其次难度推荐
	var direct_tracks := _parse_direct_recommendation(description)
	if not direct_tracks.is_empty():
		result["recommended_tracks"] = direct_tracks
	else:
		var difficulties := _parse_difficulty_recommendations(description)
		result["difficulties"] = difficulties
		if not difficulties.is_empty():
			# 多个难度时只选用第一个，其余预留
			result["recommended_tracks"] = difficulties[0]["tracks"]

	return result


## 解析音频偏移（毫秒），未找到返回 -1
## 支持写法:
##   音频偏移：0        → 0ms
##   音频偏移：0.05     → 50ms
##   参考音频偏移：0秒   → 0ms
##   参考音频偏移：0.05秒（因设备而异） → 50ms
## 简介中的数值按秒处理，转换为毫秒
static func _parse_audio_offset(description: String) -> int:
	var regex := RegEx.new()
	# 匹配 "音频偏移" 或 "参考音频偏移"，后接全角/半角冒号，再接数字（可带小数和负号），可选"秒"
	regex.compile("(?:参考)?音频偏移[：:]\\s*(-?[0-9]+(?:\\.[0-9]+)?)\\s*秒?")
	var match := regex.search(description)
	if match == null:
		return -1
	var value_str := match.get_string(1)
	var value_float := float(value_str)
	# 简介中的偏移值按秒处理，转换为毫秒（四舍五入）
	return int(round(value_float * 1000.0))


## 解析直接推荐（"推荐启用音轨：..."），返回轨道索引数组
## 支持写法:
##   推荐启用音轨：6, 9, 10, 11, 12, 13, 14, 15, 16
##   推荐启用音轨：3，4，5
##   推荐启用音轨：0
static func _parse_direct_recommendation(description: String) -> Array[int]:
	var regex := RegEx.new()
	# 匹配 "推荐启用音轨" 后接全角/半角冒号，捕获本行剩余内容（. 默认不匹配换行）
	regex.compile("推荐启用音轨[：:]\\s*(.+)")
	var match := regex.search(description)
	if match == null:
		return []
	var content := match.get_string(1)
	# 截取到首个换行（防止捕获到后续行的内容）
	var newline_idx := content.find("\n")
	if newline_idx >= 0:
		content = content.substr(0, newline_idx)
	return _extract_track_numbers(content)


## 解析基于难度的推荐（"XX版：...Track..."），返回难度数组
## 支持写法:
##   普通版：开启Track1.
##   困难版：开启Track1,2.
##   标准版：开启Track2，Track10，Track11，Track12。
##   简易版：选用Lunatic 开启Track8，Track10，Track12。
##   简单版：Track3,6,12,16,19,22,27,33,34          (无"开启"关键字，仅 Track 列表)
##   普通版：Track3,6,7,9,12,16,19,20,22,27,33
## 按文本出现顺序返回所有难度，调用方只取第一个
## "开启"为可选关键字：当存在时从其后提取数字，否则从冒号后整段提取
static func _parse_difficulty_recommendations(description: String) -> Array:
	var difficulties: Array = []
	var regex := RegEx.new()
	# 逐行匹配 "XXX版：" 开头，后接任意内容
	regex.compile("^(.+?版)[：:]\\s*(.*)$")

	for line in description.split("\n"):
		var line_stripped := line.strip_edges()
		if line_stripped.is_empty():
			continue
		var match := regex.search(line_stripped)
		if match == null:
			continue
		var name := match.get_string(1).strip_edges()
		var rest := match.get_string(2)
		# "开启" 为可选关键字：存在时仅取其后内容，避免误把前缀词数字当轨道号
		# 不存在时直接从 rest 起始提取（支持 "简单版：Track3,6,12" 这类省略写法）
		var track_content := rest
		var kai_idx := rest.find("开启")
		if kai_idx >= 0:
			track_content = rest.substr(kai_idx + 2)
		var tracks := _extract_track_numbers(track_content)
		if not tracks.is_empty():
			difficulties.append({"name": name, "tracks": tracks})

	return difficulties


## 从文本中提取所有轨道编号（连续数字串）
## 容忍任意分隔符（全角/半角逗号、空格、"Track"前缀、句点等）
static func _extract_track_numbers(content: String) -> Array[int]:
	var tracks: Array[int] = []
	var regex := RegEx.new()
	regex.compile("\\d+")
	for match in regex.search_all(content):
		var num := int(match.get_string(0))
		if num not in tracks:
			tracks.append(num)
	return tracks
