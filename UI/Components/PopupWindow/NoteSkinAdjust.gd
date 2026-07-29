extends HBoxContainer

class_name NoteSkinAdjust

@onready var _note_preview_hboxc: HBoxContainer = $NotePreview/HBoxC
@onready var _note_block_node: TextureRect = $NotePreview/HBoxC/VBoxC/block
@onready var _note_slide_node: TextureRect = $NotePreview/HBoxC/VBoxC/slide
@onready var _note_long_node: Control = $NotePreview/HBoxC/long
@onready var _skin_option_btn: OptionButton = $VBoxC/OptionButton

func _ready() -> void:
	_skin_option_btn.item_selected.connect(_on_skin_option_selected)

## 由 PopupWindow.show_note_skin_adjust 调用：刷新选项 + 应用当前皮肤到预览 + 重置预览容器动画状态
func init_adjust() -> void:
	_refresh_skin_options()
	var current := ConfigManager.instance.get_string("Appearance", "block_skin_preset", "旧版2 [内置]")
	_apply_skin_to_preview(current)
	# 重置预览容器位置和透明度（防止上次切换动画残留）
	_note_preview_hboxc.offset_transform_position = Vector2.ZERO
	_note_preview_hboxc.modulate.a = 1.0

## 返回当前选中的皮肤名（供 PopupWindow.show_note_skin_adjust 返回）
func get_selected_skin() -> String:
	return _skin_option_btn.get_item_text(_skin_option_btn.selected)

# 创建完全透明的纹理用于缺失贴图回退
func _create_transparent_texture(width: int = 64, height: int = 64) -> Texture2D:
	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)

# 应用指定皮肤的贴图到 NotePreview 预览节点
# 复用 FlowArea.set_note_texture 的节点路径约定：
#   block/slide: 根 texture + core 子节点 texture
#   long: VBoxC/{head,head/core,body,body/core,tail,tail/core}
func _apply_skin_to_preview(skin_name: String) -> void:
	var skin_textures: Dictionary = {}
	skin_textures = SkinMGR.get_skin_textures(skin_name)

	var _transparent := _create_transparent_texture()
	# 纹理数组顺序与 FlowArea.load_note_skin 一致
	var tex_arr: Array = [
		skin_textures.get("short"),
		skin_textures.get("short_core"),
		skin_textures.get("instant"),
		skin_textures.get("instant_core"),
		skin_textures.get("long_b"),
		skin_textures.get("long_b_core"),
		skin_textures.get("long_f"),
		skin_textures.get("long_f_core"),
		skin_textures.get("long_t"),
		skin_textures.get("long_t_core")
	]

	# block
	_note_block_node.texture = tex_arr[0] if tex_arr[0] else _transparent
	_note_block_node.get_node("core").texture = tex_arr[1] if tex_arr[1] else _transparent

	# slide
	_note_slide_node.texture = tex_arr[2] if tex_arr[2] else _transparent
	_note_slide_node.get_node("core").texture = tex_arr[3] if tex_arr[3] else _transparent

	# long: head / body / tail
	_note_long_node.get_node("VBoxC/head").texture = tex_arr[4] if tex_arr[4] else _transparent
	_note_long_node.get_node("VBoxC/head/core").texture = tex_arr[5] if tex_arr[5] else _transparent
	_note_long_node.get_node("VBoxC/body").texture = tex_arr[6] if tex_arr[6] else _transparent
	_note_long_node.get_node("VBoxC/body/core").texture = tex_arr[7] if tex_arr[7] else _transparent
	_note_long_node.get_node("VBoxC/tail").texture = tex_arr[8] if tex_arr[8] else _transparent
	_note_long_node.get_node("VBoxC/tail/core").texture = tex_arr[9] if tex_arr[9] else _transparent

# 填充皮肤选项列表，选中当前配置的皮肤
func _refresh_skin_options() -> void:
	var skin_list: Array = SkinMGR.get_available_skins()
	if skin_list.is_empty():
		skin_list = ["旧版2 [内置]"]
	var current := ConfigManager.instance.get_string("Appearance", "block_skin_preset", "旧版2 [内置]")
	_skin_option_btn.clear()
	for skin in skin_list:
		_skin_option_btn.add_item(skin)
	var idx := skin_list.find(current)
	_skin_option_btn.select(maxi(0, idx))

# 选项切换：播放上移+淡出→换皮肤→从下方上移+淡入动画，并即时应用皮肤到 PlayView
# 注意：不能用 animate_fade_out/in，因为它们会设置 visible=false（fade_out 完成后）
# 和 modulate.a=0（fade_in 开头），会导致第二段动画期间节点不可见。
# 改用 create_sequence + tween_property 直接 tween modulate:a，避免 visible 副作用。
func _on_skin_option_selected(_index: int) -> void:
	var skin_name: String = _skin_option_btn.get_item_text(_skin_option_btn.selected)
	# 若有动画在跑，先 kill
	AniMGR.stop_tween("popup_skin_switch_up")
	AniMGR.stop_tween("popup_skin_switch_down")
	AniMGR.stop_tween("popup_skin_switch_fade_out")
	AniMGR.stop_tween("popup_skin_switch_fade_in")
	# 第一段：上移 + 淡出（并行）
	var move_up := AniMGR.animate_offset_to(_note_preview_hboxc, Vector2(0, -80), 0.25, "popup_skin_switch_up")
	var fade_out := AniMGR.create_sequence("popup_skin_switch_fade_out")
	fade_out.tween_property(_note_preview_hboxc, "modulate:a", 0.0, 0.25)
	await move_up.finished
	# 应用新皮肤到预览节点
	_apply_skin_to_preview(skin_name)
	# 通过 ConfigManager 即时触发 config_changed → PlayView 的 flow_area.load_note_skin()
	# （相当于把设置保存时进行的皮肤应用提前到这里）
	ConfigManager.instance.set_value_and_notify("Appearance", "block_skin_preset", skin_name)
	# 重置到下方位置（瞬间）
	_note_preview_hboxc.offset_transform_position = Vector2(0, 80)
	# 第二段：从下方上移 + 淡入（并行）
	AniMGR.animate_offset_to(_note_preview_hboxc, Vector2.ZERO, 0.25, "popup_skin_switch_down")
	var fade_in := AniMGR.create_sequence("popup_skin_switch_fade_in")
	fade_in.tween_property(_note_preview_hboxc, "modulate:a", 1.0, 0.25)
