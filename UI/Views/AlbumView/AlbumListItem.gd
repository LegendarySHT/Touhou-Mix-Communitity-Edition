## 专辑列表项组件
## 继承自 CoverListItemBase，显示专辑信息
extends CoverListItemBase

const TextScrollHelper = preload("res://UI/Components/TextScrollHelper.gd")

## 引用节点路径
@onready var album_name_label: Label = $NameBox/AlbumName
@onready var name_box: Control = $NameBox
@onready var song_count_label: Label = $SongCount
# cover_texture 继承自 CoverListItemBase，在 _ready() 中赋值

## 专辑轻量投影数据（ChartDB.GetSortedAlbumItems 返回的字典）
var item_dict: Dictionary = {}

## 文字滚动状态
var _name_scroll_state: TextScrollHelper.State = null

## 展开动画补间
var expand_tween: Tween:
	set(t):
		expand_tween = t
		_extra_motion_tween = t

## 是否已 ready（复用时直接刷新显示，不再 emit _init_fin 等 _ready 续跑）
var _has_ready: bool = false

signal _init_fin

func _ready() -> void:
	cover_texture = $cover
	await _init_fin

	_refresh_labels()
	# 直接开始加载封面（不等列表构建完毕）
	# 命中 WeakRef 缓存时零开销同步应用；未命中则入 CoverLoader 异步队列，不阻塞主线程
	# 列表的 trigger_cover_chain 仍处理"释放后重载"场景（状态切换回视图时）与 path 暂不可用的重试
	start_cover_load()
	# 启动文字滚动动画（如名称过长）
	call_deferred("setup_name_scroll")
	_has_ready = true

## 从专辑轻量投影字典初始化显示（DB 返回，无完整 AlbumData）
## 新建节点（_has_ready=false）：emit _init_fin 触发 _ready 中的 await 继续
## 复用节点（_has_ready=true）：直接 _refresh_display 刷新数据
func setup_with_dict(parent: AlbumView, d: Dictionary, index:int, bg: ButtonGroup) -> void:
	item_dict = d
	item_id = String(d.get("id", ""))
	item_type = "album"
	item_index = index

	button = self
	button.button_group = bg

	enable_selected_animation(button, parent)

	if _has_ready:
		_refresh_display()
	else:
		_init_fin.emit()

## 更新名称/计数标签（新建与复用共用）
func _refresh_labels() -> void:
	if item_dict.is_empty():
		push_error("AlbumListItem: Missing album data")
		return
	album_name_label.text = " %s" % String(item_dict.get("name", "")) if item_dict.get("name", "") else "Unknown"
	song_count_label.text = "%d" % item_dict.get("song_count", 0)

## 复用刷新：重置展开/选中动画态 + 更新显示 + 重新加载封面
## 保留旧封面显示直到新封面加载完成（switch_cover_data 不清空 texture）
func _refresh_display() -> void:
	_refresh_labels()

	# 清理残留动画/选中态（展开动画改过尺寸/字号/NameBox 透明度，需复位到折叠默认）
	if expand_tween:
		expand_tween.kill()
		expand_tween = null
	if pulse_tween:
		pulse_tween.kill()
		pulse_tween = null
	if press_tween:
		press_tween.kill()
		press_tween = null
	offset_transform_scale = Vector2.ONE
	custom_minimum_size = Vector2(600, 150)
	album_name_label.add_theme_font_size_override("font_size", 25)
	name_box.self_modulate.a = 0.0
	button.set_pressed_no_signal(false)
	is_selected = false

	switch_cover_data()
	start_cover_load()
	call_deferred("setup_name_scroll")

## 重写基类虚函数：返回专辑封面 Texture2D
## 选择专辑下首个歌曲的首个 MIDI 的封面，否则由 FileSystemManager 返回默认封面
func _get_cover_texture() -> Texture2D:
	if item_dict.is_empty():
		return null
	var fs_mgr := FileSystemManager.instance
	if not fs_mgr:
		return null
	return fs_mgr._load_cover_with_cache(fs_mgr.default_cover_if_missing(ChartDB.GetAlbumCoverPath(String(item_dict.get("id", "")))))

## 重写基类虚函数：返回封面文件路径（主线程调用，供异步加载器使用）
## 路径查询在主线程完成，后台线程只负责读盘
func _resolve_cover_path() -> String:
	if item_dict.is_empty():
		return ""
	var fs_mgr := FileSystemManager.instance
	if not fs_mgr:
		return ""
	return fs_mgr.default_cover_if_missing(ChartDB.GetAlbumCoverPath(String(item_dict.get("id", ""))))

## 专辑按钮切换回调
func on_item_button_toggled(toggled_on: bool) -> void:
	if expand_tween:
		expand_tween.kill()
	
	expand_tween = create_tween()
	expand_tween.set_ease(Tween.EASE_OUT)
	expand_tween.set_trans(Tween.TRANS_SINE)
	expand_tween.set_parallel(true)
	
	var expa: int = 1 if toggled_on else 0
	expand_tween.tween_property(self,"custom_minimum_size",Vector2(600 + expa*350, 150 + 250*expa),0.15)
	expand_tween.tween_property(album_name_label,"theme_override_font_sizes/font_size",25 + 20*expa,0.15)
	expand_tween.tween_property(name_box, "self_modulate:a", float(expa), 0.15)

	if toggled_on:
		parent_node.selected_item = item_index
	
	expand_tween.finished.connect(func ():
		expand_tween.kill()
		expand_tween = null
		# 字号变化后重算滚动布局
		call_deferred("setup_name_scroll")
	)

	# 因为塞在tween里的话，节点在屏幕外似乎无法触发，所以就成下面这样了
	await get_tree().create_timer(0.15).timeout
	if toggled_on and parent_node.selected_item == item_index:
		parent_node.need_snap = true


## 启动/重算专辑名称滚动动画
func setup_name_scroll() -> void:
	if not is_instance_valid(album_name_label) or not is_instance_valid(name_box):
		return
	# 循环等待 NameBox 布局完成（最多 5 帧），确保 size 正确
	var max_wait := 5
	while name_box.size.y <= 10.0 and max_wait > 0:
		await get_tree().process_frame
		max_wait -= 1
	_name_scroll_state = TextScrollHelper.setup(
		album_name_label, name_box, album_name_label.text, _name_scroll_state
	)
