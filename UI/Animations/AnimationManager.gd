## 动画管理器
## 统一管理项目中的动画和Tween，避免重复创建和内存泄漏
extends Node

class_name AnimationManager

## 单例实例
static var instance: AnimationManager

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
# signal scene_transition_fin

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
	add_to_group("singleton")

	# 连接场景退出信号
	var UI: UIStateManager = UiStatMGR.instance
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
func animate_list_item_horizontal(target: Node,range_left:int, range_right:int, excluded_index: int, horizon_delta: int, tween_id: String = "") -> Tween:
	var tween = _create_tween(tween_id)
	tween.set_ease(EASING_STANDARD)
	tween.set_trans(Tween.TRANS_CUBIC)

	range_left = range_left if range_left >= 0 else 0
	range_right = range_right if range_right <= target.get_node("VBox").get_child_count() else target.get_node("VBox").get_child_count()

	var time=0.15
	tween.set_parallel(true)
	for i in range(range_left, range_right):
		if i != excluded_index:
			var tag = target.get_node("VBox").get_child(i)
			time = time + 0.15 if time < 0.3 else 0.3
			tween.tween_property(tag,"theme_override_constants/margin_left",horizon_delta,time)

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
		if target.visible:
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


############################## 页面切换动画 #######################################

## 记录所有组件的状态
var ui_exist = {
	"Album_List" : true, # 程序启动时专辑列表存在
	"Song_List" : false, # 程序启动时歌曲列表不存在
	"Sorted_List" : false, # 程序启动时排序列表不存在
	"Midi_Info_View" : false, # 程序启动时MIDI信息视图不存在
	"Right_Part" : false, # 程序启动时右侧部分(按钮，立绘和头像区域)不存在
	"Back_Button": false, # False为显示商店按钮
	"Store_View": false,
	"Track_List": false, # 音轨界面的那个列表
}

## 记录每个页面存在哪些组件
var ui_part = {
	UIStateManager.UIState.ALBUM_VIEW: ["Album_List", "Right_Part"],
	UIStateManager.UIState.SONG_VIEW: ["Song_List", "Right_Part", "Back_Button"],
	UIStateManager.UIState.SORTED_VIEW: ["Sorted_List", "Right_Part", "Back_Button"],
	UIStateManager.UIState.MIDI_VIEW: ["Midi_Info_View", "Back_Button"],
	UIStateManager.UIState.STORE_VIEW: ["Store_View", "Back_Button"],
	UIStateManager.UIState.TRACK_VIEW: ["Track_List", "Back_Button"],
}

var ALBUMLIST="/root/Main/Album/AlbumList"
var SONGLIST="/root/Main/Song/SongList"
var _SS="/root/Main/SS/SS"

var tan15 = tan(deg_to_rad(15))

## 页面组件退出动画
func _scene_transition_exit(old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	# 商店界面进入时无需退出其它组件
	if new_state == UIStateManager.UIState.STORE_VIEW:
		_scene_transition_enter(old_state, new_state)
		ui_exist["Store_View"] = true
		return

	for key in ui_exist.keys():
		if ui_exist[key] and (key in ui_part[old_state]) and (key not in ui_part[new_state]):
			animate_ui_out(key, old_state, new_state)
			ui_exist[key] = false

func _scene_transition_enter(old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	for key in ui_exist.keys():
		if not ui_exist[key] and key in ui_part[new_state]:
			animate_ui_in(key, old_state)
			ui_exist[key] = true

func animate_ui_out(ui_name: String, old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	print("组件退出动画: %s" % ui_name)
	var tween_id = "%s_out" % ui_name
	var tween : Tween
	
	# 播放动画的组件
	var SS = get_node_or_null(_SS)
	var album_list:AlbumView = get_node_or_null(ALBUMLIST)
	var song_list:SongView = get_node_or_null(SONGLIST)

	match ui_name:	
		"Album_List":
			var sIndex = album_list.selected_item
			
			if new_state == UIStateManager.UIState.SONG_VIEW:
				var polygon=Polygon2D.new()
				var copy=album_list.container.get_child(sIndex).duplicate(true)

				polygon.skew=deg_to_rad(15)
				copy.name="SS"
				polygon.add_child(copy)
				polygon.name="SS"
				copy=polygon

				copy.position=album_list.container.get_child(sIndex).global_position

				# 设置节点
				var button=copy.get_node("SS/PC/Polygon2D/AlbumButton")
				button.button_group=null
				button.toggle_mode=false
				get_node("/root/Main").add_child(copy)

			var tindex = sIndex if new_state!= UIStateManager.UIState.SORTED_VIEW else -1
			tween = animate_list_item_horizontal(album_list, sIndex-4, sIndex+5, tindex, -1200, tween_id)
			tween.finished.connect(func() -> void:
				album_list.visible=false
			)
		"Song_List":
			if new_state == UIStateManager.UIState.ALBUM_VIEW:
				animate_position(SS, Vector2(0, SS.global_position.y), 0.15, "SSPosition")
			else:
				animate_fade_out(SS, 0.15, "SSPosition")
			
			# 歌曲列表收起
			animate_fade_out(song_list, 0.25, "SongListFadeOut")
			tween = animate_position(song_list, Vector2(song_list.position.x, 2*song_list.position.y), 0.25, tween_id)

		"Sorted_List":
			var sort_midi_list = get_node("/root/Main/SortedMidi")

			tween = animate_position(sort_midi_list, Vector2(-1500, sort_midi_list.position.y), 0.25, tween_id)
			tween.finished.connect(func() -> void:
				sort_midi_list.visible=false
			)
		"Midi_Info_View":
			var info_ui = get_node_or_null("/root/Main/InfoUI")
			
			tween = animate_fade_out(info_ui, 0.3, tween_id)
			
			tween.finished.connect(func() -> void:
				if info_ui.get_node_or_null("OptionWindow/Option/Rank"):
					info_ui.get_node("OptionWindow/Option/Rank").button_pressed=true
			)
		"Right_Part":
			animate_position(get_node("/root/Main/Menu_Bar"), Vector2(1305+900*tan15, 15-900), 0.25, "MenuBarPosition")
			animate_position(get_node("/root/Main/Player_Info/Charactor"), Vector2(0,950), 0.15, "CharactorPosition")
			animate_position(get_node("/root/Main/Player_Info"), Vector2(-44.393+650,257.71), 0.5, "PlayerInfoPosition")
		
		"Back_Button":
			EventBus.instance.storeButtonSwitch.emit(false)

		"Store_View":
			var store_node = get_node("/root/Main/Store")
			# var top_bar = store_node.get_node("Top_bar")
			# top_bar.position.y = -500
			# animate_position(top_bar, Vector2.ZERO, 0.25, tween_id)

			# var bottom = store_node.get_node("Bottom")
			# bottom.position.y = bottom.position.y + 500
			# animate_position(bottom, Vector2(bottom.position.x, bottom.position.y - 500), 0.25, tween_id)

			tween = animate_fade_out(store_node, 0.35, tween_id)
		"Track_List":
			var track_list = get_node("/root/Main/TrackView")
			tween = animate_fade_out(track_list, 0.35, tween_id)
			animate_position(track_list, Vector2(track_list.position.x-1080*tan15, 1080), 0.25, "track_pos")
			

	# 发射结束信号
	if tween:
		tween.finished.connect(func() -> void:
			# scene_transition_fin.emit()
			_scene_transition_enter(old_state, new_state)
		)

func animate_ui_in(ui_name: String, old_state: UIStateManager.UIState) -> void:
	print("组件进入动画: %s" % ui_name)
	var tween_id = "%s_in" % ui_name
	var tween : Tween

	# 播放动画的组件
	var SS = get_node_or_null(_SS)
	var album_list:AlbumView = get_node_or_null(ALBUMLIST)
	var song_list:SongView = get_node_or_null(SONGLIST)

	match ui_name:
		"Album_List":
			album_list.visible=true
			song_list.visible=false
			
			var sIndex = album_list.selected_item
			
			album_list.get_node("VBox").get_child(sIndex).modulate = Color(1, 1, 1, 1)
			var tindex = sIndex if old_state != UIStateManager.UIState.SORTED_VIEW else -1
			tween = animate_list_item_horizontal(album_list, sIndex-4, sIndex+5, tindex, 0, tween_id)
			
			# 从Song_List回来时会触发下面的
			if SS:
				SS.get_parent().queue_free()
			
			for i in song_list.get_child(0).get_children():
				if i:
					i.queue_free()
		"Song_List":
			if old_state == UIStateManager.UIState.ALBUM_VIEW:
				animate_position(SS, Vector2(0, -SS.global_position.y), 0.15, "SSPosition")
			elif SS:
				animate_fade_in(SS, 0.15, "SSPosition")

			song_list.visible=true
			song_list.position=Vector2(285,-679)
			animate_position(song_list, Vector2(song_list.position.x, 440), 0.15, tween_id)
			tween = animate_fade_in(song_list, 0.4, "SongListFadeIn")

			# 不要问为什么在播放动画的地方做初始化
			var button=SS.get_node("PC/Polygon2D/AlbumButton")
			var ui: UIStateManager = UiStatMGR.instance
			button.pressed.connect(func() -> void:
				ui.change_state(ui.UIState.ALBUM_VIEW))
		"Sorted_List":
			var sort_midi_list = get_node("/root/Main/SortedMidi")
			sort_midi_list.visible = true
			# EventBus.instance.storeButtonSwitch.emit(true)

			animate_position(sort_midi_list, Vector2(0, sort_midi_list.position.y), 0.25, tween_id)
		"Midi_Info_View":
			EvtBus.instance.storeButtonSwitch.emit(true)
			
			var info_ui = get_node_or_null("/root/Main/InfoUI")

			animate_fade_in(info_ui, 0.1, "InfoUIFadeIn")

			info_ui.position = Vector2(130+500*tan15,-500)
			tween = animate_position(info_ui, Vector2(130,50), 0.5, tween_id)
		"Right_Part":
			animate_position(get_node("/root/Main/Menu_Bar"), Vector2(1305, 15), 0.25, "MenuBarPosition")
			animate_position(get_node("/root/Main/Player_Info/Charactor"), Vector2.ZERO, 0.15, "CharactorPosition")
			animate_position(get_node("/root/Main/Player_Info"), Vector2(-44.393, 257.71), 0.5, "PlayerInfoPosition")
		"Back_Button":
			EventBus.instance.storeButtonSwitch.emit(true)
		"Store_View":
			var store_node = get_node("/root/Main/Store")
			var top_bar = store_node.get_node("Top_bar")
			top_bar.position.y = -500
			animate_position(top_bar, Vector2.ZERO, 0.25, "top_bar_in")

			var bottom = store_node.get_node("Bottom")
			bottom.position.y = bottom.position.y + 500
			animate_position(bottom, Vector2(bottom.position.x, bottom.position.y - 500), 0.25, "bottom_in")

			tween = animate_fade_in(store_node, 0.45, tween_id)
		"Track_List":
			var track_list = get_node("/root/Main/TrackView")
			track_list.get_node("Track/TrackList").scroll_vertical = 300
			tween = animate_fade_in(track_list, 0.45, tween_id)
			animate_position(track_list, Vector2.ZERO, 0.25, "track_pos")

	# 播放完毕
	if tween:
		tween.finished.connect(func() -> void:
			pass
		)
