extends ColorRect
var ShowBackButton=false

signal  switch_to_store

func _on_song_list_store_button_switch(showBackButton: bool):
	var tween =create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	ShowBackButton=showBackButton
	
	tween.set_parallel(true)
	if showBackButton:
		tween.tween_property(get_node("Store"),"position",Vector2(12,960),0.25)
		tween.tween_property(get_node("Back"),"position",Vector2(12,400),0.25)#
	else:
		tween.tween_property(get_node("Store"),"position",Vector2(12,410),0.25)#
		tween.tween_property(get_node("Back"),"position",Vector2(12,-50),0.25)
		


func _on_button_pressed() -> void:
	if ShowBackButton:
		get_node("/root/Main/Song/SongList").storeButtonSwitch.emit(false)
		if UiStatMGR.current_state == UiStatMGR.UIState.SORTED_VIEW:
			UiStatMGR.change_state(UiStatMGR.previous_state)
		else:
			UiStatMGR.change_state(UiStatMGR.UIState.SONG_VIEW)
	else:
		switch_to_store.emit()
