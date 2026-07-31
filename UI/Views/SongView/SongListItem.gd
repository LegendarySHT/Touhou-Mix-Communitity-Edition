## 歌曲列表项组件
## 继承自 CoverListItemBase，显示歌曲信息（含封面视差）
extends CoverListItemBase

const TextScrollHelper = preload("res://UI/Components/TextScrollHelper.gd")

## 引用节点（需要根据实际场景结构调整）
@onready var song_name_label: Label = $HBoxC/PN/NameBox/SongName
@onready var name_box: Control = $HBoxC/PN/NameBox
@onready var midi_count_label: Label = $HBoxC/SongCount
@onready var cover: TextureRect = $HBoxC/PN/cover

@onready var animation_manager: AnimationManager = AniMGR

## 歌曲数据
var song_data: SongData

## 文字滚动状态
var _name_scroll_state: TextScrollHelper.State = null

signal _init_fin

func _ready() -> void:
	# SongListItem 不使用视差滚动（封面静态显示）
	_parallax_enabled = false
	# 给基类 cover_texture 赋值，启用封面加载/释放机制
	cover_texture = $HBoxC/PN/cover
	await _init_fin

	song_name_label.text = " %s" % song_data.name if song_data.name else "Unknown"
	midi_count_label.text = "%d" % song_data.midi_ids.size()

	# 直接开始加载封面（不等列表构建完毕）
	# 命中 WeakRef 缓存时零开销同步应用；未命中则入 CoverLoader 异步队列，不阻塞主线程
	# 列表的 trigger_cover_chain 仍处理"释放后重载"场景（状态切换回视图时）与 path 暂不可用的重试
	start_cover_load()
	# 启动文字滚动动画（如名称过长）
	call_deferred("_setup_name_scroll")


## 启动/重算歌曲名称滚动动画
func _setup_name_scroll() -> void:
	if not is_instance_valid(song_name_label) or not is_instance_valid(name_box):
		return
	# 循环等待 NameBox 布局完成（最多 5 帧），确保 size 正确
	var max_wait := 5
	while name_box.size.y <= 10.0 and max_wait > 0:
		await get_tree().process_frame
		max_wait -= 1
	_name_scroll_state = TextScrollHelper.setup(
		song_name_label, name_box, song_name_label.text, _name_scroll_state
	)

## 从SongData初始化显示
func setup_with_song(parent: SongView, song: SongData, index: int, bg: ButtonGroup) -> void:
	song_data = song
	item_id = song.id
	item_type = "song"
	item_index = index

	button = self
	button.button_group = bg

	enable_selected_animation(button, parent)

	_init_fin.emit()

## 重写基类钩子：封面 texture 设置完成后应用 item_index 静态错位
## 不同歌曲项显示封面图的不同区域，避免所有歌曲显示同一部分
func _on_cover_texture_set() -> void:
	_apply_static_cover_offset(0)

## 应用基于 item_index 的静态错位
## 若布局未稳定（size 为 0），延迟到下一帧重试，最多 10 次后放弃（避免异常布局下无限重试）
func _apply_static_cover_offset(retry: int = 0) -> void:
	if not is_instance_valid(self) or not cover or not cover.texture:
		return
	if cover.size.y <= 0 or self.size.y <= 0:
		if retry < 10:
			# 布局未稳定，下一帧重试（不阻塞 start_cover_load 的 emit 传播）
			call_deferred("_apply_static_cover_offset", retry + 1)
		return
	var cover_h: int = int(max(cover.size.y - self.size.y, 1))
	cover.offset_transform_position.y = -(floori(self.size.y * item_index) % cover_h)

## 重写基类虚函数：返回歌曲封面 Texture2D
## 选择该歌曲下首个 MIDI 的封面，找不到由 FileSystemManager 返回默认封面
func _get_cover_texture() -> Texture2D:
	if not song_data:
		return null
	var fs_mgr := FileSystemManager.instance
	var data_mgr := DataMGR
	if not fs_mgr or not data_mgr:
		return null
	var midis := data_mgr.get_midis_by_song(song_data.id)
	if midis.is_empty():
		return null
	return fs_mgr.get_cover_by_midiData(midis[0])

## 重写基类虚函数：返回封面文件路径（主线程调用，供异步加载器使用）
## 路径查询在主线程完成，后台线程只负责读盘
func _resolve_cover_path() -> String:
	if not song_data:
		return ""
	var fs_mgr := FileSystemManager.instance
	var data_mgr := DataMGR
	if not fs_mgr or not data_mgr:
		return ""
	var midis := data_mgr.get_midis_by_song(song_data.id)
	if midis.is_empty():
		return ""
	return fs_mgr.get_cover_path_by_midiData(midis[0])
