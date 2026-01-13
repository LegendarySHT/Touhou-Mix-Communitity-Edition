extends HBoxContainer
var Status =0
var Data=0
var DataPTR=[Global.download,Global.favor,Global.like,Global.played]
var select=0 #1表示按data筛选，2表示按时间筛选

func _on_status_pressed() -> void:
	Status=(Status+1)%5
	if Status==0:
		get_node("Status").texture_normal=load("res://icon/Sort/Status/All.png")  #取消选中
		Global.SortStatus=0
		return
		
	elif Status==1:
		get_node("Status").texture_normal=load("res://icon/Sort/Status/pending.png")
	elif Status==2:
		get_node("Status").texture_normal=load("res://icon/Sort/Status/Approved.png")
	elif Status==3:
		get_node("Status").texture_normal=load("res://icon/Sort/Status/Included.png")
	elif Status==4:
		get_node("Status").texture_normal=load("res://icon/Sort/Status/Dead.png")
	
	Global.SortStatus=Status


func _on_data_toggled(toggled_on: bool) -> void:
	if toggled_on:
		if select!=1:
			select=1
			create_tween().tween_property(get_node("SelectData"),"self_modulate",Color("ffffffdd"),0.25).set_trans(Tween.TRANS_SINE)
			
		else:
			Data=(Data+1)%4
			if Data==0:
				get_node("Data").texture_normal=load("res://icon/Sort/Data/Download.png")
				Global.pn=["p1","n1"]
			elif Data==1:
				get_node("Data").texture_normal=load("res://icon/Sort/Data/Favor.png")
				Global.pn=["p2","n2"]
			elif Data==2:
				get_node("Data").texture_normal=load("res://icon/Sort/Data/Like.png")
				Global.pn=["p3","n3"]
			elif Data==3:
				get_node("Data").texture_normal=load("res://icon/Sort/Data/Played.png")
				Global.pn=["p4","n4"]
		Global.SortHeadPTR=DataPTR[Data]
	else:
		create_tween().tween_property(get_node("SelectData"),"self_modulate",Color("ffffff00"),0.25).set_trans(Tween.TRANS_SINE)


func _on_time_toggled(toggled_on: bool) -> void:
	if toggled_on:
		if select==2:
			Global.StartSort=1
		select=2
		Global.SortHeadPTR=Global.create_time
		Global.pn=["p5","n5"]
		create_tween().tween_property(get_node("SelectTime"),"self_modulate",Color("ffffffdd"),0.25).set_trans(Tween.TRANS_SINE)
		print("wait1")
		
		print("筛选：按创建时间")
	else:
		create_tween().tween_property(get_node("SelectTime"),"self_modulate",Color("ffffff00"),0.25).set_trans(Tween.TRANS_SINE)


func _on_ordering_pressed() -> void:
	if Global.Sort==1:
		print("筛选：升序")
		get_node("Ordering").texture_normal=load("res://icon/Sort/Ordering/Ascent.png")
		Global.Sort=2
	elif Global.Sort==2:
		print("筛选：降序")
		get_node("Ordering").texture_normal=load("res://icon/Sort/Ordering/Descent.png")
		Global.Sort=1
	print("wait2")
	Global.StartSort=1
