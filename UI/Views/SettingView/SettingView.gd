extends Control
@onready var setting_list: SettingList = $Node2D/HBoxC/SettingList
@onready var short_cut_btn = $Node2D/HBoxC/ShortCut


func _ready() -> void:
	var idx: int = 0
	for btn:Button in short_cut_btn.get_children():
		btn.pressed.connect(_on_button_pressed.bind(idx))
		idx += 1

	# 设置按钮信号链接
	var setting_btn = get_node("/root/Main/LT_Btn/Button")
	if setting_btn:
		setting_btn.pressed.connect(
			func():
				if UIStateManager.instance.current_state != UIStateManager.UIState.SETTINGS_VIEW:
					UIStateManager.instance.change_state(UIStateManager.UIState.SETTINGS_VIEW)
				else:
					UIStateManager.instance.go_back()
		)

	# 样例
	# 这个配置应该从配置管理器获取，此处是个示例
	var settingData = {
	 "performing_mode": "0", "play_ready_animation": "0", "playback_speed_scaling": "1.5", "vibrate_on_touch": "0", "vibration_duration": "50", "use_system_stopwatch": "0", "lane_count": "12", "keyboard_mode": "0", "keyboard_mode_keys": "A,S,D,F,J,K,L,;", "flash_alpha": "0.8", "perfect_spark_preset": "0", "perfect_spark_scaling": "1.0", "great_spark_preset": "0", "great_spark_scaling": "1.0", "good_spark_preset": "0", "good_spark_scaling": "1.0", "bad_spark_preset": "0", "bad_spark_scaling": "1.0", "touch_judging_criteria": "3", "check_instant_blocks_when_finger_up": "1", "only_perfect_instant_blocks_before_judge": "0", "judge_line_position": "200", "block_judging_width": "100", "min_block_spacing": "50", "canvas_horizontal_padding": "100", "judge_time_offset": "0", "perfect_time": "0.05", "great_time": "0.1", "good_time": "0.15", "bad_time": "0.2", "instant_block_max_time": "0.5", "short_block_max_time": "1.0", "max_simultaneous_blocks": "3", "min_tap_interval": "0.2", "min_touch_cooldown_time": "0.2", "max_touch_move_speed": "500", "max_block_coalesce_time": "0.5", "randomize_block_color": "0", "sync_color_across_block_type": "0", "instant_block_color": "ff6b6bff", "short_block_color": "4ecdc4ff", "long_block_color": "45b7d1ff", "custom_block_skin_texture_filter_mode": "0", "block_skin_preset": "0", "cache_time": "2.0", "cache_easing_type": "0", "grace_time": "0.5", "grace_easing_type": "2", "custom_background_image_size_mode": "0", "block_size": "150", "background_image_preset": "0", "background_image_color": "ffffffff", "background_image_flash_color": "ffffff00", "background_dim_alpha": "0.5", "judge_line_thickness": "2", "generate_short_connect": "0", "generate_instant_connect": "0", "instant_connect_max_time": "0.5"
	}
	setting_list.load_settings(settingData)
	# print(_get_config())

# 左侧快速跳转按钮的事件
func _on_button_pressed(idx: int):
	var target_idx = idx*2
	var c_idx = 0

	var settingList: SettingList = get_node("Node2D/HBoxC/SettingList")
	for node in settingList.container.get_children():
		if node is Separator:
			if c_idx == target_idx:
				var tween = create_tween()
				tween.tween_property(settingList, "scroll_vertical", node.position.y, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				settingList.scroll_velocity = 0.0
			c_idx += 1

# 获取当前ui中的配置
func _get_config():
	var config = setting_list.get_all_settings_as_json()
	return config
