extends HBoxContainer
var SortByStatus: int = 0
var SortByData: int = 0
var Ascending: bool = true

var UI: UIStateManager

func _ready():
	UI = UIStateManager.instance

func _on_status_pressed() -> void:
	# Midi状态筛选
	var SE = SortEngine.instance
	SortByStatus=(SortByStatus+1)%5
	match SortByStatus:
		0: # 取消筛选（显示全部）
			get_node("Status").texture_normal=load("res://Resources/icon/Sort/Status/All.png")
			SE.set_sort_mode(SE.SortStatField.ALL)
		1: # 筛选pending状态
			get_node("Status").texture_normal=load("res://Resources/icon/Sort/Status/pending.png")
			SE.set_sort_mode(SE.SortStatField.PENDING)
		2: # 筛选approved状态
			get_node("Status").texture_normal=load("res://Resources/icon/Sort/Status/Approved.png")
			SE.set_sort_mode(SE.SortStatField.APPROVED)
		3: # 筛选included状态
			get_node("Status").texture_normal=load("res://Resources/icon/Sort/Status/Included.png")
			SE.set_sort_mode(SE.SortStatField.INCLUDED)
		4: # 筛选dead状态
			get_node("Status").texture_normal=load("res://Resources/icon/Sort/Status/Dead.png")
			SE.set_sort_mode(SE.SortStatField.DEAD)

	if UI.current_state!=UI.UIState.SORTED_VIEW:
		UI.change_state(UI.UIState.SORTED_VIEW)

# 数据筛选和下面的时间筛选是二选一的
func _on_data_toggled(toggled_on: bool) -> void:
	create_tween().tween_property(get_node("SelectData"),"self_modulate",Color(1, 1, 1,(1 if toggled_on else 0) * 0.87),0.25).set_trans(Tween.TRANS_SINE)
	var SE = SortEngine.instance
	if toggled_on:
		print("按数据筛选")
		SortByData = (SortByData + 1) % 6
		match SortByData:
			0: # 取消筛选（显示全部）
				get_node("Data").texture_normal=load("res://Resources/icon/Sort/Status/All.png")
				create_tween().tween_property(get_node("SelectData"),"self_modulate",Color(1, 1, 1, 0),0.25).set_trans(Tween.TRANS_SINE)
				SE.set_sort_mode(SE.current_sort_stat_field, SE.SortDataField.DEFAULT)
			1: # 筛选下载数
				get_node("Data").texture_normal=load("res://Resources/icon/Sort/Data/Download.png")
				SE.set_sort_mode(SE.current_sort_stat_field, SE.SortDataField.DOWNLOAD_COUNT)
			2: # 筛选收藏数
				get_node("Data").texture_normal=load("res://Resources/icon/Sort/Data/Favor.png")
				SE.set_sort_mode(SE.current_sort_stat_field, SE.SortDataField.LOVE_COUNT)
			3: # 筛选点赞数
				get_node("Data").texture_normal=load("res://Resources/icon/Sort/Data/Up.png")
				SE.set_sort_mode(SE.current_sort_stat_field, SE.SortDataField.UP_COUNT)
			4: # 筛选游玩数
				get_node("Data").texture_normal=load("res://Resources/icon/Sort/Data/Played.png")
				SE.set_sort_mode(SE.current_sort_stat_field, SE.SortDataField.TRIAL_COUNT)
			5: # 筛选上传时间
				get_node("Data").texture_normal=load("res://Resources/icon/Sort/Data/CreateTime.png")
				SE.set_sort_mode(SE.current_sort_stat_field, SE.SortDataField.UPLOADED_DATE)
		
		if UI.current_state!=UI.UIState.SORTED_VIEW:
			UI.change_state(UI.UIState.SORTED_VIEW)


# func _on_time_toggled(toggled_on: bool) -> void:
# 	create_tween().tween_property(get_node("SelectTime"),"self_modulate",Color(1, 1, 1,(1 if toggled_on else 0) * 0.87),0.25).set_trans(Tween.TRANS_SINE)
# 	if toggled_on:
# 		# if select==2:
# 		# 	Global.StartSort=1
# 		# select=2
# 		#Global.SortHeadPTR=Global.create_time
# 		#Global.pn=["p5","n5"]
# 		# create_tween().tween_property(get_node("SelectTime"),"self_modulate",Color("ffffffdd"),0.25).set_trans(Tween.TRANS_SINE)
# 		# print("wait1")
		
# 		print("筛选：按创建时间")
	# else:
	# 	create_tween().tween_property(get_node("SelectTime"),"self_modulate",Color("ffffff00"),0.25).set_trans(Tween.TRANS_SINE)


func _on_ordering_pressed() -> void:
	Ascending = not Ascending
	var SE = SortEngine.instance
	if Ascending:
		print("筛选：升序")
		get_node("Ordering").texture_normal=load("res://Resources/icon/Sort/Ordering/Ascent.png")
		SE.set_sort_mode(SE.current_sort_stat_field, SE.current_sort_field, SE.SortDirection.ASCENDING)
	else:
		print("筛选：降序")
		get_node("Ordering").texture_normal=load("res://Resources/icon/Sort/Ordering/Descent.png")
		SE.set_sort_mode(SE.current_sort_stat_field, SE.current_sort_field, SE.SortDirection.DESCENDING)

	if UI.current_state!=UI.UIState.SORTED_VIEW:
		UI.change_state(UI.UIState.SORTED_VIEW)
