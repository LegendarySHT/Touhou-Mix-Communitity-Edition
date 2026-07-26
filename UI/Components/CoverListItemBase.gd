## 含封面视差效果的列表项基类
## 继承自 ListItemBase，为含 cover_texture 的子类提供统一的视差移动
extends ListItemBase
class_name CoverListItemBase

## 封面纹理节点（子类在 _ready 中赋值，因节点路径各不相同）
var cover_texture: TextureRect = null

## 上次计算的封面偏移（避免重复赋值）
var _last_cover_offset: float = 0.0

## 是否启用视差（子类可禁用，如 StoreMidiListItem）
var _parallax_enabled: bool = true

## 额外动画 tween（子类可赋值，如 AlbumListItem 的 expand_tween），存在时强制更新视差
var _extra_motion_tween: Tween = null

func _process(_delta: float) -> void:
	if not _parallax_enabled or cover_texture == null or parent_node == null:
		return
	# 仅在滚动、吸附动画或额外动画期间才更新
	if not parent_node.is_scrolling() and _extra_motion_tween == null:
		return
	# 视区剔除
	var item_top := global_position.y
	var item_bottom := item_top + size.y
	var parent_ctrl := parent_node as Control
	var view_top: float = parent_ctrl.global_position.y
	var view_bottom: float = view_top + parent_ctrl.size.y
	if item_bottom < view_top or item_top > view_bottom:
		return
	var new_offset: float = -(global_position.y / max(parent_ctrl.size.y, 1.0)) * max(cover_texture.size.y - size.y, 0.0)
	if not is_equal_approx(new_offset, _last_cover_offset):
		cover_texture.offset_transform_position.y = new_offset
		_last_cover_offset = new_offset
