extends MarginContainer

signal snap_target(midi_node)

func _ready():
	get_node("MC/MC/status").text=get_meta("status")
	get_node("MC/VBox/MidiName").text=get_meta("name")
	get_node("MC/VBox/Author").text=get_meta("artistName")
	if get_meta("artistName")=="":
		get_node("MC/VBox/Author").text="Unknow"
	get_node("Button").set_meta("index",get_meta("index"))
	
func _on_button_toggled(toggled_on: bool):
	var tween =create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_parallel(true)
	
	var indicator=get_node("/root/Main/InfoUI/Right/Right/Indicator")
	if toggled_on:
		print("select: ",get_meta("name"))
		#歌曲框
		tween.tween_property(self,"custom_minimum_size",Vector2(900,500),0.5)
		tween.tween_property(get_node("MC"),"theme_override_constants/margin_bottom",120,0.15)
		#tween.tween_property(get_parent(),"theme_override_constants/separation",150,0.5)
		#文字
		tween.tween_property(get_node("MC/VBox/MidiName"),"theme_override_font_sizes/font_size",40,0.25)
		tween.tween_property(get_node("MC/VBox"),"theme_override_constants/separation",30,0.15)
		tween.tween_property(get_node("MC/VBox/Line2D"),"position",Vector2(-135,22),0.15)
#		#指示器
		tween.tween_property(indicator.get_child(get_meta("index")),"color",Color(0.129, 0.412, 0.702),0.15)
		tween.tween_property(indicator,"position",Vector2(186.9,214-(get_meta("index")+1)*20-get_meta("index")*9),0.35)
		print("move to: ",indicator.get_child(get_meta("index")).get_global_position().y)
		
		#读取数据
		var node=get_node("/root/Main/InfoUI/Status/Panel/GC")
		if node:
			print("Read: ",get_meta("trialCount"),get_meta("upCount"),get_meta("avgAccuracy"))
			node.get_node("Play/Label").text="%d"%get_meta("trialCount")
			node.get_node("UpCount/Label").text="%d"%get_meta("upCount")
			node.get_node("AvgAcc/Label").text="%.2f"%get_meta("avgAccuracy")
			snap_target.emit(self)
		#tween.finished.connect(_next)
	else:
		tween.tween_property(self,"custom_minimum_size",Vector2(900,150),0.5)

		tween.tween_property(get_node("MC"),"theme_override_constants/margin_bottom",10,0.15)
		#tween.tween_property(get_parent(),"theme_override_constants/separation",15,0.25)
		
		tween.tween_property(get_node("MC/VBox/MidiName"),"theme_override_font_sizes/font_size",30,0.5)
		tween.tween_property(get_node("MC/VBox"),"theme_override_constants/separation",0,0.5)
		tween.tween_property(get_node("MC/VBox/Line2D"),"position",Vector2(-135,-10),0.15)
		
		tween.tween_property(indicator.get_child(self.get_meta("index")),"color",Color(1, 1, 1),0.15)
		
		
#func _next():
	
	#get_parent().queue_sort();
	#await get_tree().process_frame
	
