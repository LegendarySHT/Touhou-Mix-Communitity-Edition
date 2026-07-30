## 含封面视差效果的列表项基类
## 继承自 ListItemBase，为含 cover_texture 的子类提供统一的视差移动与封面加载/释放
## 封面加载采用涟漪式：列表触发起点项 → 加载完 emit cover_loaded → 列表转发给相邻 pending 项
extends ListItemBase
class_name CoverListItemBase

## 本项封面加载完成信号（传 item_index，供列表转发给相邻项）
signal cover_loaded(idx: int)

## 封面纹理节点（子类在 _ready 中赋值，因节点路径各不相同）
var cover_texture: TextureRect = null

## 上次计算的封面偏移（避免重复赋值）
var _last_cover_offset: float = 0.0

## 是否启用视差（子类可禁用，如 StoreMidiListItem）
var _parallax_enabled: bool = true

## 额外动画 tween（子类可赋值，如 AlbumListItem 的 expand_tween），存在时强制更新视差
var _extra_motion_tween: Tween = null

## 封面是否已加载（控制 cover_texture.texture 是否有效）
var _cover_loaded: bool = false
## 是否待加载（release_cover 或 request_cover_load 后为 true，start_cover_load 消费后为 false）
## 列表触发涟漪时检查此标志决定是否启动加载
var _cover_load_pending: bool = false

## 子类重写：返回封面 Texture2D（实际加载逻辑）
## 默认返回 null，子类必须实现
func _get_cover_texture() -> Texture2D:
	return null

## 请求加载封面（仅标记 pending，实际加载由列表触发涟漪或相邻项传播）
## 子类 _ready 中调用，列表切回本视图时统一触发起点
func request_cover_load() -> void:
	if _cover_loaded:
		return
	_cover_load_pending = true

## 立即加载封面（同步，命中缓存零开销）
## 仅在本次确实从未加载→加载完成时 emit cover_loaded，控制涟漪传播速度 = 加载速度
## 已加载/加载失败时都不 emit，避免信号瞬间传遍失去分帧效果
## 注：不检查 _cover_load_pending——既然主动调用就是要加载
## pending 标志仅供列表 trigger_cover_chain 判断是否需要触发，不影响 start_cover_load 本身
func start_cover_load() -> void:
	if _cover_loaded:
		return  # 已加载：不重复加载，不 emit
	_cover_load_pending = false  # 消费 pending 标志（无论本次是否成功）
	if cover_texture == null:
		return  # 无 cover 节点：不 emit
	var tex := _get_cover_texture()
	if not tex:
		return  # 加载失败：不 emit，等下次 trigger_cover_chain 重试
	cover_texture.texture = tex
	_cover_loaded = true
	# 子类钩子：封面 texture 设置完成后做额外处理（如静态偏移）
	_on_cover_texture_set()
	# 视差项立即计算一次初始偏移：非滚动状态下 _process 不会触发重算，
	# 若不主动设置初始 offset，相邻项封面会停在 offset 0 显示同一区域
	if _parallax_enabled:
		_apply_parallax_offset()
		_last_cover_offset = NAN  # 强制下帧再算一次（避免布局未稳定时初始值偏差)
	# 仅本次确实加载完成才 emit，涟漪传播速度受加载速度节流，自然分帧
	cover_loaded.emit(item_index)

## 子类重写：封面 texture 设置完成后调用，可做额外处理（如 SongListItem 的 item_index 静态错位）
func _on_cover_texture_set() -> void:
	pass

## 计算并应用当前视差偏移（仅当 parent_node 已就绪时）
## 在 start_cover_load / _process 中复用，确保非滚动状态下封面也有正确的初始偏移
func _apply_parallax_offset() -> void:
	if not _parallax_enabled or cover_texture == null or parent_node == null:
		return
	if not _cover_loaded:
		return
	var parent_ctrl := parent_node as Control
	if parent_ctrl == null or parent_ctrl.size.y <= 0.0:
		return
	# 视区剔除
	var item_top := global_position.y
	var item_bottom := item_top + size.y
	var view_top: float = parent_ctrl.global_position.y
	var view_bottom: float = view_top + parent_ctrl.size.y
	if item_bottom < view_top or item_top > view_bottom:
		return
	var new_offset: float = -(global_position.y / max(parent_ctrl.size.y, 1.0)) * max(cover_texture.size.y - size.y, 0.0)
	if not is_equal_approx(new_offset, _last_cover_offset):
		cover_texture.offset_transform_position.y = new_offset
		_last_cover_offset = new_offset

## 释放封面（状态切换时调用）
## 将 cover_texture.texture 置空，标记 pending 等下次触发涟漪时重新加载
func release_cover() -> void:
	if cover_texture:
		cover_texture.texture = null
	_cover_loaded = false
	_cover_load_pending = true

func _process(_delta: float) -> void:
	if not _parallax_enabled or cover_texture == null or parent_node == null:
		return
	# 封面未加载时跳过视差计算（避免对空 texture 操作）
	if not _cover_loaded:
		return
	# 仅在滚动、吸附动画或额外动画期间才更新
	if not parent_node.is_scrolling() and _extra_motion_tween == null:
		return
	_apply_parallax_offset()
