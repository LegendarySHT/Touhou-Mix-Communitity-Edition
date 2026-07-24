## 动画管理器
## 统一管理项目中的动画和Tween，避免重复创建和内存泄漏
extends Node

class_name AnimationManager

## 预定义的动画时长
const DURATION_QUICK = 0.2
const DURATION_NORMAL = 0.3
const DURATION_SLOW = 0.5

## 预定义的缓动方式
const EASING_STANDARD = Tween.EASE_OUT
const EASING_SMOOTH = Tween.EASE_IN_OUT
const EASING_SHARP = Tween.EASE_IN

## 所有活跃Tween的集合（用于统一管理）
var active_tweens: Dictionary[String, Tween] = {}

## Tween计数器（为每个Tween生成唯一ID）
var tween_counter: int = 0

# 场景退出信号
signal scene_transition_fin

var _current_transition_version: int = -1

func _ready() -> void:
	add_to_group("singleton")

	# 连接场景退出信号
	var UI: UIStateManager = UiStatMGR
	if UI:
		UI.state_changed.connect(_scene_transition_exit)
		#UI.state_entering.connect(_scene_transition_enter)

## 创建位置动画
func animate_position(target: Node, to_pos: Vector2, duration: float = DURATION_NORMAL, 
					  tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "position", to_pos, duration)
	return tween

## 列表项水平滑动动画
var out_item_idx: int = -1
func animate_list_item_horizontal(target: BaseScrollList, center_index: int, excluded_index: int, horizon_delta: int, tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)

	var screen_rect = get_viewport().get_visible_rect()
	var ctn:int = floori(screen_rect.size.y / 175) +2
	var container: Container = target.container

	var range_left = center_index - ctn
	var range_right = center_index + ctn
	range_left = range_left if range_left >= 0 else 0
	range_right = range_right if range_right <= container.get_child_count() else container.get_child_count()

	var time=0.08
	tween.set_parallel(true)
	for i in range(range_left, range_right):
		if i == excluded_index:
			continue

		var tag = container.get_child(i)
		if not tag.get_global_rect().intersects(screen_rect):
			pass
		time = time + 0.08 if time < 0.7 else 0.7
		tween.tween_property(tag,"offset_transform_position:x",horizon_delta,time).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

	return tween

## 创建透明度动画
func animate_modulate(target: Node, to_color: Color, duration: float = DURATION_NORMAL,
					  tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "modulate", to_color, duration)
	return tween

## 创建缩放动画
func animate_scale(target: Node, to_scale: Vector2, duration: float = DURATION_NORMAL,
				   tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "scale", to_scale, duration)
	return tween

## 创建旋转动画
func animate_rotation(target: Node, to_rotation: float, duration: float = DURATION_NORMAL,
					  tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "rotation", to_rotation, duration)
	return tween

## 创建大小动画（仅Control节点）
func animate_size(target: Control, to_size: Vector2, duration: float = DURATION_NORMAL,
				  tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "size", to_size, duration)
	return tween

## 创建淡入效果
func animate_fade_in(target: Node, duration: float = DURATION_NORMAL,
					 tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	if not target.visible:
		target.visible = true

	target.modulate.a = 0.0
	tween.tween_property(target, "modulate:a", 1.0, duration)
	return tween

## 创建淡出效果
func animate_fade_out(target: Node, duration: float = DURATION_NORMAL,
					  tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "modulate:a", 0.0, duration)
	tween.finished.connect(func() -> void:
		if target and target.visible:
			target.visible = false
	)
	return tween

## 创建菜单展开动画
func animate_menu_expand(target: Control, target_height: float, 
						duration: float = DURATION_NORMAL,
						tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_SMOOTH)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(target, "custom_minimum_size:y", target_height, duration)
	return tween

## 创建菜单收起动画
func animate_menu_collapse(target: Control, duration: float = DURATION_NORMAL,
						   tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_SMOOTH)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(target, "custom_minimum_size:y", 0, duration)
	return tween

## 创建弹跳动画
func animate_bounce(target: Node, from_pos: Vector2, to_pos: Vector2,
					duration: float = DURATION_NORMAL,
					tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BOUNCE)
	target.position = from_pos
	tween.tween_property(target, "position", to_pos, duration)
	return tween

## 创建脉冲效果
func animate_pulse(target: Node, min_scale: float = 0.9, max_scale: float = 1.0,
				   duration: float = DURATION_QUICK,
				   tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target, "scale", Vector2(max_scale, max_scale), duration / 2.0)
	tween.tween_property(target, "scale", Vector2(min_scale, min_scale), duration / 2.0)
	return tween

func animate_offset_to(target: Node, to_offset: Vector2, duration: float = DURATION_NORMAL,
					   tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	target.offset_transform_enabled = true
	tween.tween_property(target, "offset_transform_position", to_offset, duration)
	return tween

func animate_offset_back(target: Node, duration: float = DURATION_NORMAL,
						 tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)
	target.offset_transform_enabled = true
	tween.tween_property(target, "offset_transform_position", Vector2.ZERO, duration)
	return tween

## 延迟执行回调
func delay_call(callback: Callable, delay: float, tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.tween_callback(callback)
	if delay > 0:
		tween.set_delay(delay)
	return tween

## 创建序列动画（多个动画依次执行）
func create_sequence(tween_id: String = "") -> Tween:
	return _create_tween(tween_id)

## 获取或创建Tween（使用tween_id来保存和重用）
func _create_tween(tween_id: String = "") -> Tween:
	# 如果提供了ID且已存在，则杀死旧Tween
	if not tween_id.is_empty() and active_tweens.has(tween_id):
		active_tweens[tween_id].kill()
	
	# 生成唯一ID（如果未提供）
	if tween_id.is_empty():
		tween_id = "tween_%d" % tween_counter
		tween_counter += 1
	
	# 创建新Tween
	var tween = create_tween()
	active_tweens[tween_id] = tween
	
	# 连接Tween完成信号以清理
	tween.finished.connect(func() -> void:
		active_tweens.erase(tween_id)
	)
	
	return tween

## 停止特定ID的Tween
func stop_tween(tween_id: String) -> void:
	if active_tweens.has(tween_id):
		active_tweens[tween_id].kill()
		active_tweens.erase(tween_id)

## 停止所有Tween
func stop_all_tweens() -> void:
	for tween in active_tweens.values():
		if tween and tween.is_valid():
			tween.kill()
	active_tweens.clear()

## 暂停特定ID的Tween
func pause_tween(tween_id: String) -> void:
	if active_tweens.has(tween_id):
		active_tweens[tween_id].pause()

## 恢复特定ID的Tween
func resume_tween(tween_id: String) -> void:
	if active_tweens.has(tween_id):
		active_tweens[tween_id].play()

## 获取活跃Tween数量
func get_active_tween_count() -> int:
	return active_tweens.size()

## 销毁时清理所有Tween
func _exit_tree() -> void:
	stop_all_tweens()

func _kill_scene_transition_tweens() -> void:
	for key in ui_exist.keys():
		stop_tween("%s_out" % key)
		stop_tween("%s_in" % key)

	var secondary := [
		"SSPosition", "SongListFadeOut", "SongListFadeIn",
		"CharactorPosition", "PlayerInfoPosition", "MenuBarPosition",
		"top_bar_in", "bottom_in", "track_pos", "InfoUIFadeIn",
		"sv_bg", "sv_btns", "sv_info", "sv_chara", "sv_bottom",
		"sv_rank", "sv_score", "sv_score_fade", "sv_acc",
	]
	for tid in secondary:
		if active_tweens.has(tid):
			stop_tween(tid)

	var score_view := get_comp("Score_View")
	if is_instance_valid(score_view) and score_view.has_method("_kill_loop_ani"):
		score_view._kill_loop_ani()

	# 强制隐藏所有已标记为不存在的组件，防止动画被打断导致组件卡在屏幕上
	for key in ui_exist.keys():
		if not ui_exist[key]:
			var comp := get_comp(key)
			if is_instance_valid(comp):
				comp.visible = false
				if comp is CanvasItem:
					comp.modulate.a = 0.0


############################## 页面切换动画 #######################################

## 记录所有组件的状态
var ui_exist = {
	"Album_List" : true, 		# 程序启动时专辑列表存在
	"Player_Info": true,
	"Shortcut_Menu" : true, 
	"Song_List" : false, 		# 程序启动时歌曲列表不存在
	"Sorted_List" : false,  	# 程序启动时排序列表不存在
	"Midi_Info_View" : false, 	# 程序启动时MIDI信息视图不存在
	"Store_View": false,
	"Track_List": false, 		# 音轨界面的那个列表
	"Play_View": false,
	"Setting_View": false,
	"Score_View": false,
}

## 记录每个页面存在哪些组件
var ui_part = {
	UIStateManager.UIState.ALBUM_VIEW: ["Album_List", "Player_Info", "Shortcut_Menu"],
	UIStateManager.UIState.SONG_VIEW: ["Song_List", "Player_Info", "Shortcut_Menu"],
	UIStateManager.UIState.SORTED_VIEW: ["Sorted_List", "Player_Info", "Shortcut_Menu"],
	UIStateManager.UIState.MIDI_VIEW: ["Midi_Info_View"],
	UIStateManager.UIState.STORE_VIEW: ["Store_View"],
	UIStateManager.UIState.TRACK_VIEW: ["Track_List"],
	UIStateManager.UIState.SETTINGS_VIEW: ["Setting_View"],
	UIStateManager.UIState.PLAY_VIEW: ["Play_View"],
	UIStateManager.UIState.SCORE_VIEW: ["Score_View"],
}

var ui_path_map = {
	"Album_List" : "/root/Main/skew/C/AlbumList",
	"Song_List" : "/root/Main/skew/C/SongList",
	"Player_Info": "/root/Main/PlayerInfo",
	"Sorted_List" : "/root/Main/skew/C/SortedMidisList",
	"Shortcut_Menu" : "/root/Main/skew/C/ShortCutMenu",
	"Midi_Info_View" : "/root/Main/skew/C/InfoUI",
	"Store_View": "/root/Main/Store",
	"Track_List": "/root/Main/skew/C/TrackView",
	"Play_View": "/root/Main/PlayView",
	"Setting_View": "/root/Main/skew/C/SettingView",
	"Score_View": "/root/Main/ScoreView",
}

func get_comp(ui_part_name: String) -> Node:
	if not ui_path_map[ui_part_name]:
		return
	var node = get_node_or_null(ui_path_map[ui_part_name])
	if node:
		return node
	else:
		push_error("[AniMGR] COMP %s Not Found" % ui_part_name)
		return null

var _SS = "/root/Main/skew/SS"

var tan15 = tan(deg_to_rad(15))

## 页面组件退出动画
func _scene_transition_exit(old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	_current_transition_version = UiStatMGR.transition_version
	_kill_scene_transition_tweens()

	# 修复 ui_exist 并重置位置（包括被杀死补间破坏的子节点）
	for key in ui_part.get(old_state, []):
		var comp := get_comp(key)
		if not ui_exist.get(key, false):
			ui_exist[key] = true
			if is_instance_valid(comp):
				comp.visible = true
				if comp is CanvasItem:
					comp.modulate.a = 1.0
		# 无条件重置位置（即使 ui_exist 已为 true），防止补间被杀后位置损坏
		if is_instance_valid(comp) and comp.offset_transform_enabled:
			comp.offset_transform_position = Vector2.ZERO
		# 同时重置 Chara 子节点
		if key == "Player_Info" and is_instance_valid(comp):
			var chara := comp.get_node_or_null("Chara")
			if chara and chara.offset_transform_enabled:
				chara.offset_transform_position = Vector2.ZERO

	for key in ui_exist.keys():
		if ui_exist[key] and (key in ui_part[old_state]) and (key not in ui_part[new_state]):
			animate_ui_out(key, old_state, new_state)
			ui_exist[key] = false

func _scene_transition_enter(old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	if UiStatMGR.transition_version != _current_transition_version:
		return
	# 新组件：播放入场动画
	for key in ui_exist.keys():
		if not ui_exist[key] and key in ui_part.get(new_state, []):
			animate_ui_in(key, old_state)
			ui_exist[key] = true

func animate_ui_out(ui_name: String, old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	print("组件退出动画: %s" % ui_name)
	var tween_id = "%s_out" % ui_name
	var tween : Tween
	
	# 播放动画的组件
	var SS = get_node_or_null(_SS)
	var album_list:AlbumView = get_comp("Album_List")
	var song_list:SongView = get_comp("Song_List")
	var skew = get_node_or_null("/root/Main/skew")
	var ani_comp = get_comp(ui_name)

	match ui_name:
		"Album_List":
			var sIndex = album_list.selected_item
			if sIndex < 0:
				return
			var tindex = -1 # 目标状态不是歌曲列表时所有项都要播放退场动画

			if new_state == UIStateManager.UIState.SONG_VIEW:
				var sItem = album_list.container.get_child(sIndex)
				var old_SS := get_node_or_null(_SS)
				if is_instance_valid(old_SS):
					old_SS.queue_free()
				var copy=sItem.duplicate(true)
				copy.name="SS"

				copy.position = skew.to_local(sItem.global_position)

				# 设置节点
				var button: Button = copy.get_node("AlbumButton")
				button.button_group=null
				button.toggle_mode=false

				var sc = Shortcut.new()
				var event = InputEventKey.new()
				event.keycode = KEY_ESCAPE
				sc.events = [event]
				button.shortcut = sc

				tindex = sIndex
				sItem.modulate.a = 0.0
				
				create_tween().tween_property(button.get_theme_stylebox("normal"), "shadow_size", 24, 0.25)
				create_tween().tween_property(button.get_theme_stylebox("hover"), "shadow_size", 24, 0.25)
				skew.add_child(copy)

			animate_list_item_horizontal(album_list, sIndex, tindex, -1200, tween_id)
			out_item_idx = sIndex
			tween = animate_fade_out(album_list, 0.7, "AlbumListFadeOut")
		"Song_List":
			if new_state == UIStateManager.UIState.ALBUM_VIEW:
				animate_position(SS, skew.to_local(album_list.container.get_child(out_item_idx).global_position), 0.25, "SSPosition")
			else:
				animate_fade_out(SS, 0.15, "SSPosition")
			
			# 歌曲列表收起
			animate_fade_out(song_list, 0.25, "SongListFadeOut")
			tween = animate_offset_to(song_list, Vector2(0, song_list.size.y), 0.25, tween_id)

		"Sorted_List":
			tween = animate_offset_to(ani_comp, Vector2(-1500, 0), 0.25, tween_id)
			tween.finished.connect(func() -> void:
				ani_comp.visible=false
			)
		"Midi_Info_View":
			tween = animate_fade_out(ani_comp, 0.3, tween_id)
			
			tween.finished.connect(func() -> void:
				ani_comp.get_node("RightArea/OptionPanel/VBoxC/TabBtn/Rank").button_pressed=true
			)
		"Player_Info":
			var chara = ani_comp.get_node("Chara")
			if chara: animate_offset_to(chara, Vector2(0, chara.size.y), 0.35, "CharactorPosition")
			animate_offset_to(ani_comp, Vector2(900, 200), 0.55, "PlayerInfoPosition")
			
		"Shortcut_Menu":
			var t = animate_offset_to(ani_comp, Vector2(500*tan15, -500), 0.25, "MenuBarPosition")
			t.finished.connect(func() -> void:
				ani_comp.visible = false
			)
		"Store_View":
			tween = animate_fade_out(ani_comp, 0.35, tween_id)
		"Track_List":
			tween = animate_fade_out(ani_comp, 0.35, tween_id)
			animate_offset_to(ani_comp, Vector2(0, 1080), 0.25, "track_pos")
		"Play_View":
			tween = animate_fade_out(ani_comp, 0.45, tween_id)
		"Setting_View":
			if ani_comp.has_method("has_pending_changes") and ani_comp.has_pending_changes():
				_save_settings_on_exit(ani_comp)
			
			var btns = ani_comp.get_node("HBoxC/ShortCut")
			var setting_list = ani_comp.get_node("HBoxC/SettingList")
			tween = animate_offset_to(btns, Vector2(-500, 0), 0.35, "sv_btns")
			animate_offset_to(setting_list, Vector2(-1500, 0), 0.25, "sv_info")

			tween = animate_fade_out(ani_comp, 0.35, tween_id)
			if ani_comp.has_method("switch_page_instant"):
				ani_comp.switch_page_instant()
			else:
				ani_comp.switch_page()
		"Score_View":
			ani_comp.animate(false)
			if new_state!= UIStateManager.UIState.PLAY_VIEW:
				await get_tree().create_timer(0.7).timeout
			tween = animate_fade_out(ani_comp, 0.45, tween_id)

	# 发射结束信号
	if tween:
		var captured_version := _current_transition_version
		tween.finished.connect(func() -> void:
			if UiStatMGR.transition_version != captured_version:
				return
			_scene_transition_enter(old_state, new_state)
		)

## 保存设置配置（在 SettingView 退出时调用）
func _save_settings_on_exit(setting_view: Control) -> void:
	if not setting_view or not setting_view.has_method("save_config_to_file"):
		return
	
	# 调用 SettingView 的保存方法
	var success = setting_view.save_config_to_file()
	
	if success:
		print("[AnimationManager] Settings saved successfully")
		
		# 发出通配符信号，通知所有监听者配置已变化
		if EvtBus:
			EvtBus.settings_changed.emit("*", null)
	else:
		push_warning("[AnimationManager] Failed to save settings")

func animate_ui_in(ui_name: String, old_state: UIStateManager.UIState) -> void:
	print("组件进入动画: %s" % ui_name)
	var tween_id = "%s_in" % ui_name
	var tween : Tween

	# 播放动画的组件
	var SS = get_node_or_null(_SS)
	var album_list:AlbumView = get_comp("Album_List")
	var song_list:SongView = get_comp("Song_List")
	var skew = get_node_or_null("/root/Main/skew")
	var ani_comp = get_comp(ui_name)
	if is_instance_valid(ani_comp) and ani_comp is CanvasItem:
		ani_comp.visible = true
		ani_comp.modulate.a = 1.0

	match ui_name:
		"Album_List":
			animate_fade_in(album_list, 0.35, "AlbumListFadeIn")
			song_list.visible=false
			
			var sIndex = out_item_idx
			if sIndex < 0:
				return
			
			var vbox := album_list.get_node("VBox")
			if sIndex >= vbox.get_child_count():
				return
			
			vbox.get_child(sIndex).modulate = Color(1, 1, 1, 1)
			var tindex = sIndex if old_state == UIStateManager.UIState.SONG_VIEW else -1
			tween = animate_list_item_horizontal(album_list, sIndex, tindex, 0, tween_id)
			
			# 从Song_List回来时会触发下面的
			if SS:
				var button:Button = SS.get_node("AlbumButton")				
				await create_tween().tween_property(button.get_theme_stylebox("normal"), "shadow_size", 0, 0.2).finished
				await create_tween().tween_property(button.get_theme_stylebox("hover"), "shadow_size", 0, 0.2).finished
				SS.queue_free()
			
			song_list.clear_items.call_deferred()
		"Song_List":
			if old_state == UIStateManager.UIState.ALBUM_VIEW:
				animate_position(SS, skew.to_local(Vector2(280, 10)), 0.15, "SSPosition")
			elif SS:
				animate_fade_in(SS, 0.15, "SSPosition")

			song_list.visible=true
			song_list.offset_transform_position = Vector2(0, -1150)
			animate_offset_back(song_list, 0.15, tween_id)
			tween = animate_fade_in(song_list, 0.4, "SongListFadeIn")

			# 不要问为什么在播放动画的地方做初始化
			if SS:
				var button=SS.get_node("AlbumButton")
				var ui: UIStateManager = UiStatMGR
				button.pressed.connect(func() -> void:
					ui.change_state(ui.UIState.ALBUM_VIEW))
		"Sorted_List":
			ani_comp.visible = true

			animate_offset_back(ani_comp, 0.25, tween_id)
		"Midi_Info_View":
			animate_fade_in(ani_comp, 0.1, "InfoUIFadeIn")

			ani_comp.offset_transform_position = Vector2(0, -500)
			tween = animate_offset_back(ani_comp, 0.5, tween_id)
		"Player_Info":
			var chara: Node = ani_comp.get_node("Chara")
			ani_comp.offset_transform_position = Vector2(900, 200)
			if chara: chara.offset_transform_position = Vector2(0, chara.size.y)
			animate_offset_back(ani_comp, 0.35, "PlayerInfoPosition")
			if chara: animate_offset_back(chara, 0.55, "CharactorPosition")
		
		"Shortcut_Menu":
			ani_comp.visible = true
			ani_comp.offset_transform_position = Vector2(500*tan15, -500)
			animate_offset_back(ani_comp, 0.25, "MenuBarPosition")
		"Store_View":
			var top_bar = ani_comp.get_node("TopBar")
			top_bar.offset_transform_position = Vector2(0, -500)
			animate_offset_back(top_bar, 0.25, "top_bar_in")

			var bottom = ani_comp.get_node("Bottom")
			bottom.offset_transform_position = Vector2(0, 500)
			animate_offset_back(bottom, 0.25, "bottom_in")

			tween = animate_fade_in(ani_comp, 0.45, tween_id)
		"Track_List":
			ani_comp.scroll_vertical = 300
			tween = animate_fade_in(ani_comp, 0.45, tween_id)
			animate_offset_back(ani_comp, 0.25, "track_pos")
		"Play_View":
			tween = animate_fade_in(ani_comp, 0.45, tween_id)
		"Setting_View":
			var btns = ani_comp.get_node("HBoxC/ShortCut")
			var setting_list = ani_comp.get_node("HBoxC/SettingList")
			btns.offset_transform_position = Vector2(-500, 0)
			setting_list.offset_transform_position = Vector2(-1500, 0)
			tween = animate_offset_back(btns, 0.25, "sv_btns")
			animate_offset_back(setting_list, 0.35, "sv_info")
		"Score_View":
			tween = animate_fade_in(ani_comp, 0.45, tween_id)
			tween.finished.connect(func ():
				ani_comp.animate())

	# 播放完毕
	if tween:
		var captured_version := _current_transition_version
		tween.finished.connect(func() -> void:
			if UiStatMGR.transition_version != captured_version:
				return
			scene_transition_fin.emit()
		)
