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
signal scene_transition_fin

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
}

## 记录每个页面存在哪些组件
var ui_part = {
	UIStateManager.UIState.ALBUM_VIEW: ["Album_List", "Right_Part"],
	UIStateManager.UIState.SONG_VIEW: ["Song_List", "Right_Part"],
	UIStateManager.UIState.SORTED_VIEW: ["Sorted_List", "Right_Part"],
	UIStateManager.UIState.MIDI_VIEW: ["Midi_Info_View"],
}

var ALBUMLIST="/root/Main/Album/AlbumList"
var SONGLIST="/root/Main/Song/SongList"
var _SS="/root/Main/SS/SS"

## 页面组件退出动画
func _scene_transition_exit(old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	# 发出状态进入和改变信号
	for key in ui_exist.keys():
		if ui_exist[key] and (key in ui_part[old_state]) and (key not in ui_part[new_state]):
			animate_ui_out(key, old_state, new_state)
			ui_exist[key] = false

func _scene_transition_enter(old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	# 发出状态进入和改变信号
	for key in ui_exist.keys():
		if not ui_exist[key] and key in ui_part[new_state]:
			animate_ui_in(key, old_state, new_state)
			ui_exist[key] = true

func animate_ui_out(ui_name: String, old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	print("组件退出动画: %s" % ui_name)
	var tween_id = "%s_out" % ui_name
	var tween : Tween
	
	# 播放动画的组件
	var SS = get_node_or_null(_SS)
	var album_list = get_node_or_null(ALBUMLIST)
	var song_list = get_node_or_null(SONGLIST)

	match ui_name:	
		"Album_List":
			if new_state == UIStateManager.UIState.SONG_VIEW:
				var polygon=Polygon2D.new()
				var copy=album_list.get_node("VBox").get_child(Global.album).duplicate(true)

				polygon.skew=deg_to_rad(15)
				copy.name="SS"
				polygon.add_child(copy)
				polygon.name="SS"
				copy=polygon

				copy.position=album_list.get_node("VBox").get_child(Global.album).global_position

				# 设置节点
				var button=copy.get_node("SS/PC/Polygon2D/AlbumButton")
				button.button_group=null
				button.toggle_mode=false
				get_node("/root/Main").add_child(copy)

			var tindex = Global.album if new_state!= UIStateManager.UIState.SORTED_VIEW else -1
			tween = animate_list_item_horizontal(album_list, Global.album-4, Global.album+5, tindex, -1200, tween_id)
			tween.finished.connect(func() -> void:
				album_list.visible=false
				album_list.get_node("VBox").get_child(Global.album).modulate = Color(1, 1, 1, 0)
			)
		"Song_List":
			if new_state == UIStateManager.UIState.ALBUM_VIEW:
				animate_position(SS, Vector2(0, SS.global_position.y), 0.15, "SSPosition")
			else:
				animate_fade_out(SS, 0.15, "SSPosition")
			
			# 歌曲列表收起
			animate_fade_out(song_list, 0.25, "SongListFadeOut")
			tween = animate_position(song_list, Vector2(song_list.position.x, 2*song_list.position.y), 0.25, tween_id)

			if new_state == UIStateManager.UIState.MIDI_VIEW:
				tween.finished.connect(func() -> void:
					SS.visible=false
				)
		"Sorted_List":
			var sort_midi_list = get_node("/root/Main/SortedMidi")
			
			song_list.storeButtonSwitch.emit(false)

			tween = animate_position(sort_midi_list, Vector2(-1500, sort_midi_list.position.y), 0.25, tween_id)
			tween.finished.connect(func() -> void:
				sort_midi_list.visible=false
			)
		"Midi_Info_View":
			var info_ui = get_node_or_null("/root/Main/InfoUI")
			
			tween = animate_modulate(info_ui, Color(1,1,1,0), 0.1, tween_id)
			
			tween.finished.connect(func() -> void:
				info_ui.visible=false
				if info_ui.get_node_or_null("OptionWindow/Option/Rank"):
					info_ui.get_node("OptionWindow/Option/Rank").button_pressed=true
				Global.song = -1
			)
		"Right_Part":
			animate_position(get_node("/root/Main/Menu_Bar"), Vector2(1305+53.58,-215-800), 0.25, "MenuBarPosition")
			animate_position(get_node("/root/Main/Player_Info/Charactor"), Vector2(0,950), 0.15, "CharactorPosition")
			animate_position(get_node("/root/Main/Player_Info"), Vector2(-44.393+650,257.71), 0.5, "PlayerInfoPosition")
			

	# 发射结束信号
	if tween:
		tween.finished.connect(func() -> void:
			# scene_transition_fin.emit()
			_scene_transition_enter(old_state, new_state)
		)

func animate_ui_in(ui_name: String, old_state: UIStateManager.UIState, new_state: UIStateManager.UIState) -> void:
	print("组件进入动画: %s" % ui_name)
	var tween_id = "%s_in" % ui_name
	var tween : Tween

	# 播放动画的组件
	var SS = get_node_or_null(_SS)
	var album_list = get_node_or_null(ALBUMLIST)
	var song_list = get_node_or_null(SONGLIST)

	match ui_name:
		"Album_List":
			album_list.visible=true
			album_list.get_node("VBox").get_child(Global.album).modulate = Color(1, 1, 1, 1)
			var tindex = Global.album if old_state != UIStateManager.UIState.SORTED_VIEW else -1
			tween = animate_list_item_horizontal(album_list, Global.album-4, Global.album+5, tindex, 0, tween_id)
			
			# 从Song_List回来时会触发下面的
			if SS:
				SS.get_parent().queue_free()
			
			song_list.initial=0
			song_list.visible=false
			for i in song_list.get_child(0).get_children():
				if i:
					i.queue_free()
		"Song_List":
			if old_state == UIStateManager.UIState.ALBUM_VIEW:
				animate_position(SS, Vector2(0, -SS.global_position.y), 0.15, "SSPosition")
			else:
				SS.visible=true
				animate_fade_in(SS, 0.15, "SSPosition")

			song_list.visible=true
			song_list.position=Vector2(285,-679)
			animate_position(song_list, Vector2(song_list.position.x, 440), 0.15, tween_id)
			tween = animate_fade_in(song_list, 1, "SongListFadeIn")

			# 不要问为什么在播放动画的地方做初始化
			var button=SS.get_node("PC/Polygon2D/AlbumButton")
			button.pressed.connect(song_list.back)
		"Sorted_List":
			var sort_midi_list = get_node("/root/Main/SortedMidi")
			sort_midi_list.visible = true
			song_list.storeButtonSwitch.emit(true)

			animate_position(sort_midi_list, Vector2(0, sort_midi_list.position.y), 0.25, tween_id)
		"Midi_Info_View":
			song_list.storeButtonSwitch.emit(true)
			
			var Main = get_node_or_null("/root/Main")

			var info_ui = Main.get_node_or_null("InfoUI")
			if not info_ui:
				var info_window = load("res://Scene/info_ui.tscn").instantiate()
				Main.add_child(info_window)
				info_ui = Main.get_node_or_null("InfoUI")
			
			info_ui.visible = true
			info_ui.modulate = Color(1,1,1,1)
		
			info_ui.position = Vector2(130+500*0.2679,-450)
			tween = animate_position(info_ui, Vector2(130,50), 0.5, tween_id)
		"Right_Part":
			animate_position(get_node("/root/Main/Menu_Bar"), Vector2(1305, 15), 0.25, "MenuBarPosition")
			animate_position(get_node("/root/Main/Player_Info/Charactor"), Vector2(0, 0), 0.15, "CharactorPosition")
			animate_position(get_node("/root/Main/Player_Info"), Vector2(-44.393, 257.71), 0.5, "PlayerInfoPosition")
	
	# 播放完毕
	if tween:
		tween.finished.connect(func() -> void:
			pass
		)
