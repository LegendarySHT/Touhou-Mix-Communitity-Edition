## MIDI 谱面数据模型
## 代表一个单独的MIDI谱面记录
class_name MidiData
extends Resource

## 唯一标识符
var id: String

## 谱面名称
var name: String

## 谱面描述
var description: String

## 谱面状态 (PENDING, APPROVED, INCLUDED, DEAD)
var status: String

## 作曲者名字
var artist_name: String

## 上传者名字
var uploader_name: String

## 上传时间戳
var uploaded_date: String

## 所属歌曲信息
var song_data: SongData

## 所属专辑信息
var album_data: AlbumData

## 统计数据 - 试玩数
var trial_count: int = 0

## 统计数据 - 下载数
var download_count: int = 0

## 统计数据 - 收藏数
var love_count: int = 0

## 统计数据 - 好评数
var up_count: int = 0

## 统计数据 - 差评数
var down_count: int = 0

## 统计数据 - 平均准确率
var avg_accuracy: float = 0.0

## 统计数据 - 通关人数
var pass_count: int = 0

## 统计数据 - 失败人数
var fail_count: int = 0

## 评级分布
var rank_distribution: Dictionary = {
	"S": 0,
	"A": 0,
	"B": 0,
	"C": 0,
	"D": 0,
	"F": 0
}

## 文件哈希
var file_hash: String = ""

## 从JSON数据构造MIDI数据
func from_json(json_data: Dictionary) -> void:
	id = json_data.get("_id", "")
	name = json_data.get("name", "")
	description = json_data.get("desc", "")
	status = json_data.get("status", "PENDING")
	artist_name = json_data.get("artistName", "")
	uploader_name = json_data.get("uploaderName", "")
	uploaded_date = json_data.get("uploadedDate", "")
	
	# 处理两种格式的字段名
	trial_count = json_data.get("trialCount", 0)
	download_count = json_data.get("downloadCount", 0)
	love_count = json_data.get("loveCount", 0)
	up_count = json_data.get("upCount", 0)
	down_count = json_data.get("downCount", 0)
	
	# 平均准确率可能有不同字段名
	avg_accuracy = json_data.get("avgAccuracy", 0.0)
	if avg_accuracy == 0.0:
		avg_accuracy = json_data.get("avgAccuracy", 0.0)
	
	pass_count = json_data.get("passCount", 0)
	fail_count = json_data.get("failCount", 0)
	file_hash = json_data.get("hash", "")
	
	# 处理评级分布
	rank_distribution["S"] = json_data.get("sCount", 0)
	rank_distribution["A"] = json_data.get("aCount", 0)
	rank_distribution["B"] = json_data.get("bCount", 0)
	rank_distribution["C"] = json_data.get("cCount", 0)
	rank_distribution["D"] = json_data.get("dCount", 0)
	rank_distribution["F"] = json_data.get("fCount", 0)

## 转换为字典格式（用于导出或缓存）
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"status": status,
		"artist_name": artist_name,
		"uploader_name": uploader_name,
		"uploaded_date": uploaded_date,
		"trial_count": trial_count,
		"download_count": download_count,
		"love_count": love_count,
		"up_count": up_count,
		"down_count": down_count,
		"avg_accuracy": avg_accuracy,
		"pass_count": pass_count,
		"fail_count": fail_count,
		"rank_distribution": rank_distribution,
		"file_hash": file_hash
	}
